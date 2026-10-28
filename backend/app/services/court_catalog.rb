require "json"
require "net/http"
require "openssl"

class CourtCatalog
  class Unavailable < StandardError; end

  ENDPOINT = URI("https://comunicaapi.pje.jus.br/api/v1/comunicacao/tribunal").freeze

  def self.fetch
    catalog = JSON.parse(request_body)
    raise Unavailable unless catalog.is_a?(Array)

    # The OpenAPI describes a flat list; the live endpoint groups institutions by UF.
    # https://comunicaapi.pje.jus.br/swagger/djen.yml
    institutions = if catalog.all? { |entry| entry.is_a?(Hash) && entry.key?("instituicoes") }
      catalog.flat_map do |group|
        entries = group["instituicoes"]
        raise Unavailable unless entries.is_a?(Array)
        entries
      end
    else
      catalog
    end

    courts = {}
    institutions.each do |institution|
      raise Unavailable unless institution.is_a?(Hash)
      code = institution["sigla"]
      name = institution["nome"]
      raise Unavailable unless code.is_a?(String) && !code.strip.empty? &&
        name.is_a?(String) && !name.strip.empty?

      if courts.key?(code)
        raise Unavailable unless courts.fetch(code).fetch(:name) == name
      else
        courts[code] = { code: code, name: name }
      end
    end
    courts.values.sort_by { |court| court.fetch(:code) }
  rescue JSON::ParserError
    raise Unavailable
  end

  def self.request_body
    request = Net::HTTP::Get.new(ENDPOINT)
    request["Accept"] = "application/json"
    body = +""
    Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_PEER,
      open_timeout: 5, read_timeout: 10, write_timeout: 5, max_retries: 0) do |http|
      http.request(request) do |response|
        raise Unavailable unless response.is_a?(Net::HTTPSuccess)
        response.read_body do |chunk|
          raise Unavailable if body.bytesize + chunk.bytesize > 1_048_576
          body << chunk
        end
      end
    end
    body
  rescue SocketError, Timeout::Error, EOFError, IOError, SystemCallError,
      OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError
    raise Unavailable
  end
  private_class_method :request_body
end
