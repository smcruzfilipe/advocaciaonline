require "ipaddr"
require "json"
require "net/http"
require "openssl"
require "resolv"
require "tempfile"
require "time"
require "timeout"
require "uri"
require_relative "errors"

module Processador
  class Http
    IPV4_RESERVED = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
      172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 192.168.0.0/16
      198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
    ].map { |range| IPAddr.new(range).freeze }.freeze
    IPV6_GLOBAL = IPAddr.new("2000::/3").freeze
    IPV6_RESERVED = %w[2001::/23 2001:db8::/32 2002::/16 3fff::/20].map {
      |range| IPAddr.new(range).freeze
    }.freeze

    # The last response's delay also accompanies validation errors raised by a source.
    attr_reader :retry_after
    attr_accessor :on_retry_after

    def initialize(open_timeout: 10, read_timeout: 60, write_timeout: 10, test_origin: nil)
      [open_timeout, read_timeout, write_timeout].each do |value|
        unless value.is_a?(Numeric) && value.real? && value.finite? && value.positive?
          raise ArgumentError, "HTTP timeouts must be positive finite seconds"
        end
      end
      @open_timeout = open_timeout
      @read_timeout = read_timeout
      @write_timeout = write_timeout
      @test_origin = parse_test_origin(test_origin) if test_origin
    end

    def retry_wait_remaining
      return 0 unless @retry_not_before

      [@retry_not_before - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max
    end

    def get_json(url)
      body = +""
      transfer(url, accept: "application/json") { |chunk| body << chunk }
      payload = JSON.parse(body)
      source_error("DJEN JSON root is not an object") unless payload.is_a?(Hash)
      payload
    rescue JSON::ParserError, EncodingError
      source_error("DJEN returned invalid JSON")
    end

    def download(url)
      raise ArgumentError, "A download consumer is required" unless block_given?

      # https://docs.ruby-lang.org/en/4.0/Tempfile.html#method-c-create
      Tempfile.create("processador-download-") do |file|
        file.binmode
        transfer(url, accept: "application/octet-stream") { |chunk| file.write(chunk) }
        file.flush
        yield file.path
      end
    end

    private

    def transfer(url, accept:)
      @retry_after = nil
      uri = parse_url(url)
      test_request = @test_origin == origin(uri)
      unless test_request || (uri.scheme == "https" && uri.port == 443)
        source_error("DJEN URL must use public HTTPS")
      end
      addresses = Timeout.timeout(@open_timeout) { Resolv.getaddresses(uri.hostname) }.uniq
      if addresses.empty? || (!test_request && !addresses.all? { |address| public_address?(address) })
        source_error("DJEN URL does not resolve exclusively to public addresses")
      end

      # Pin the validated address while retaining the hostname for TLS/SNI and Host.
      # https://docs.ruby-lang.org/en/4.0/Net/HTTP.html#method-i-ipaddr-3D
      connection = Net::HTTP.new(uri.hostname, uri.port, nil)
      connection.ipaddr = addresses.first
      connection.use_ssl = uri.scheme == "https"
      connection.verify_mode = OpenSSL::SSL::VERIFY_PEER
      connection.verify_hostname = true
      connection.open_timeout = @open_timeout
      connection.read_timeout = @read_timeout
      connection.write_timeout = @write_timeout
      connection.max_retries = 0
      connection.ignore_eof = false
      request = Net::HTTP::Get.new(uri.request_uri)
      request["Accept"] = accept
      request["Accept-Encoding"] = "identity"
      connection.start do |http|
        http.request(request) do |response|
          @retry_after = parse_retry_after(response["Retry-After"])
          @retry_not_before = @retry_after && Process.clock_gettime(Process::CLOCK_MONOTONIC) + @retry_after
          @on_retry_after&.call(@retry_after) unless @retry_after.nil?
          source_error("DJEN returned an unsuccessful HTTP response") unless response.is_a?(Net::HTTPOK)
          encoding = response["Content-Encoding"]
          if encoding && encoding.strip.downcase != "identity"
            source_error("DJEN returned an unexpected content encoding")
          end
          expected_length = response.content_length
          bytes = 0
          response.read_body do |chunk|
            bytes += chunk.bytesize
            yield chunk
          end
          if expected_length && bytes != expected_length
            source_error("DJEN returned an incomplete HTTP body")
          end
        end
      end
    rescue SocketError, Resolv::ResolvError, Timeout::Error, EOFError, IOError,
        SystemCallError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse,
        Net::HTTPHeaderSyntaxError, ArgumentError
      source_error("DJEN HTTP transfer failed")
    end

    def parse_url(url)
      uri = URI.parse(url)
      unless uri.is_a?(URI::HTTP) && uri.hostname && !uri.hostname.empty? &&
          uri.userinfo.nil? && uri.fragment.nil?
        source_error("DJEN URL is invalid")
      end
      uri
    rescue URI::InvalidURIError, URI::InvalidComponentError, ArgumentError, TypeError
      source_error("DJEN URL is invalid")
    end

    def parse_test_origin(value)
      uri = URI.parse(value)
      unless uri.is_a?(URI::HTTP) && uri.hostname && !uri.hostname.empty? &&
          uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? &&
          ["", "/"].include?(uri.path)
        raise ArgumentError, "test_origin must be an exact HTTP origin"
      end
      origin(uri).freeze
    rescue URI::InvalidURIError, URI::InvalidComponentError, TypeError
      raise ArgumentError, "test_origin must be an exact HTTP origin", cause: nil
    end

    def origin(uri)
      [uri.scheme, uri.hostname.downcase, uri.port]
    end

    def public_address?(value)
      address = IPAddr.new(value)
      if address.ipv4?
        IPV4_RESERVED.none? { |range| range.include?(address) }
      else
        IPV6_GLOBAL.include?(address) && IPV6_RESERVED.none? { |range| range.include?(address) }
      end
    rescue IPAddr::InvalidAddressError
      false
    end

    def parse_retry_after(value)
      return nil unless value

      value = value.strip
      return value.to_i if /\A[0-9]+\z/.match?(value)

      # RFC 9110 §10.2.3 permits both delay-seconds and HTTP-date; never shorten it.
      # https://www.rfc-editor.org/rfc/rfc9110.html#name-retry-after
      [(Time.httpdate(value) - Time.now).ceil, 0].max
    rescue ArgumentError
      nil
    end

    def source_error(message)
      # Parser/network exceptions can contain publication text or signed URLs.
      raise SourceError.new(message, retry_after: @retry_after), cause: nil
    end
  end
end
