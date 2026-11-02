require "net/http"
require "openssl"
require "uri"
require_relative "errors"

module STF
  class Http
    Response = Data.define(:body, :url)

    ALLOWED_HOSTS = %w[portal.stf.jus.br digital.stf.jus.br].freeze
    MAX_REDIRECTS = 5
    MAX_BYTES = 10 * 1024 * 1024
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 30
    WRITE_TIMEOUT = 10

    def initialize(before_request: nil)
      @before_request = before_request
    end

    def get(url)
      uri = allowed_uri(url)
      redirects = 0

      loop do
        @before_request&.call
        response, body = request(uri)

        case response
        when Net::HTTPSuccess
          return Response.new(body: body, url: uri.to_s)
        when Net::HTTPMovedPermanently, Net::HTTPFound, Net::HTTPSeeOther,
             Net::HTTPTemporaryRedirect, Net::HTTPPermanentRedirect
          raise InvalidSource, "limite de redirecionamentos STF excedido" if redirects >= MAX_REDIRECTS
          location = response["location"]
          raise InvalidSource, "redirecionamento STF sem destino" if location.nil? || location.empty?

          begin
            uri = allowed_uri(URI.join(uri.to_s, location).to_s)
          rescue URI::InvalidURIError, URI::BadURIError
            raise InvalidSource, "destino de redirecionamento STF inválido"
          end
          redirects += 1
        else
          raise SourceUnavailable, "fonte STF retornou HTTP #{response.code}"
        end
      end
    end

    private

    def allowed_uri(url)
      uri = URI.parse(url.to_s)
      unless uri.is_a?(URI::HTTPS) && ALLOWED_HOSTS.include?(uri.host&.downcase) &&
             uri.port == 443 && uri.userinfo.nil?
        raise InvalidSource, "endereço STF não permitido"
      end
      uri
    rescue URI::InvalidURIError
      raise InvalidSource, "endereço STF inválido"
    end

    def request(uri)
      connection = Net::HTTP.new(uri.host, uri.port, nil)
      connection.use_ssl = true
      connection.verify_mode = OpenSSL::SSL::VERIFY_PEER
      connection.open_timeout = OPEN_TIMEOUT
      connection.read_timeout = READ_TIMEOUT
      connection.write_timeout = WRITE_TIMEOUT
      connection.max_retries = 0
      request = Net::HTTP::Get.new(uri.request_uri, "Accept-Encoding" => "identity")
      result = nil
      body = +"".b

      connection.request(request) do |response|
        result = response
        encoding = response["content-encoding"]
        raise InvalidSource, "codificação HTTP STF não suportada" if encoding && encoding.downcase != "identity"
        if response.content_length && response.content_length > MAX_BYTES
          raise InvalidSource, "resposta STF excede o limite de tamanho"
        end
        response.read_body do |chunk|
          raise InvalidSource, "resposta STF excede o limite de tamanho" if body.bytesize + chunk.bytesize > MAX_BYTES
          body << chunk
        end
      end
      [result, body]
    rescue Timeout::Error, SocketError, IOError, SystemCallError, EOFError,
           OpenSSL::SSL::SSLError, Net::ProtocolError, Net::HTTPBadResponse,
           Net::HTTPHeaderSyntaxError => error
      raise SourceUnavailable, "falha de comunicação com STF: #{error.class}"
    end
  end
end
