require "date"
require "uri"
require_relative "errors"

module Processador
  class Fallback
    def initialize(http:, base_url: "https://comunicaapi.pje.jus.br/api/v1")
      @http = http
      @endpoint = URI.parse(base_url)
      unless @endpoint.is_a?(URI::HTTP) && @endpoint.hostname && !@endpoint.hostname.empty? &&
          @endpoint.userinfo.nil? && @endpoint.query.nil? && @endpoint.fragment.nil?
        raise SourceError, "DJEN fallback base URL is invalid", cause: nil
      end
      @endpoint.path = "#{@endpoint.path.delete_suffix("/")}/comunicacao"
      @endpoint.freeze
    rescue URI::InvalidURIError, URI::InvalidComponentError, ArgumentError, TypeError
      raise SourceError, "DJEN fallback base URL is invalid", cause: nil
    end

    def each(court:, date:, medium:, before_request: nil)
      return enum_for(__method__, court: court, date: date, medium: medium, before_request: before_request) unless block_given?

      unless court.is_a?(String) && !court.strip.empty? && date.instance_of?(Date) && medium == "D"
        raise SourceError, "DJEN collection requires a court, execution date and D medium", cause: nil
      end
      page = 1
      loop do
        url = @endpoint.dup
        url.query = URI.encode_www_form(
          siglaTribunal: court,
          meio: medium,
          dataDisponibilizacaoInicio: date.iso8601,
          dataDisponibilizacaoFim: date.iso8601,
          pagina: page,
          itensPorPagina: 100
        )
        before_request&.call
        payload = @http.get_json(url.to_s)
        unless payload.is_a?(Hash) && payload["status"] == "success" &&
            payload["items"].is_a?(Array) && payload["items"].all? { |item| item.is_a?(Hash) }
          delay = @http.retry_after if @http.respond_to?(:retry_after)
          raise SourceError.new("DJEN fallback returned an invalid page", retry_after: delay), cause: nil
        end
        items = payload.fetch("items")
        break if items.empty?

        items.each { |item| yield item }
        page += 1
      end
      self
    end
  end
end
