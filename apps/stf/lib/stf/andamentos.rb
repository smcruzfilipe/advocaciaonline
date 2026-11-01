require "date"
require "time"
require "uri"
require "nokogiri"
require_relative "errors"

module STF
  class Andamentos
    PORTAL = "https://portal.stf.jus.br/processos".freeze

    def initialize(http:)
      @http = http
    end

    def fetch(process:, date:, captured_at:)
      incidente = process.fetch("incidente")
      url = "#{PORTAL}/abaAndamentos.asp?incidente=#{incidente}&imprimir="
      html = Nokogiri::HTML.fragment(html_text(@http.get(url)))
      list = html.at_css(".processo-andamentos > ul")
      raise InvalidSource, "Aba de andamentos inválida" unless list

      list.element_children.each do |child|
        raise InvalidSource, "Lista de andamentos incompleta" unless child.name == "li" && child.at_css(".andamento-item")
      end
      list.css(".andamento-item").filter_map do |item|
        data = clean(item.at_css(".andamento-data")&.text)
        titulo = clean(item.at_css(".andamento-nome")&.text)
        raise InvalidSource, "Andamento incompleto" unless data && titulo && data.match?(/\A[0-9]{2}\/[0-9]{2}\/[0-9]{4}\z/)
        begin
          movement_date = Date.strptime(data, "%d/%m/%Y")
        rescue Date::Error
          raise InvalidSource, "Data de andamento inválida"
        end
        next unless movement_date == date

        julgador = clean(item.at_css(".andamento-julgador")&.text)
        observacao = clean(item.at_css(".andamento-detalhe > .col-md-9.p-0")&.text)
        {
          "siglaTribunal" => "STF",
          "numero_processo" => process.fetch("cnj"),
          "nomeClasse" => process.fetch("classe"),
          "texto" => [titulo, julgador, observacao].compact.join("\n"),
          "link" => "#{PORTAL}/detalhe.asp?incidente=#{incidente}",
          "stf" => {
            "incidente" => incidente,
            "identificacao" => process.fetch("identificacao"),
            "data_andamento" => movement_date.iso8601,
            "titulo" => titulo,
            "julgador" => julgador,
            "observacao" => observacao,
            "url_coleta" => url,
            "capturado_em" => captured_at.iso8601,
            "links" => links(item, url)
          }
        }
      end
    end

    private

    def html_text(body)
      bytes = body.b
      charset = bytes[/<meta\b[^>]*charset\s*=\s*["']?\s*([a-z0-9._-]+)/i, 1] || "UTF-8"
      bytes.force_encoding(Encoding.find(charset))
      raise InvalidSource, "Codificação HTML STF inválida" unless bytes.valid_encoding?
      bytes.encode(Encoding::UTF_8)
    rescue ArgumentError, EncodingError
      raise InvalidSource, "Codificação HTML STF inválida"
    end

    def clean(value)
      text = value&.gsub(/[[:space:]\u00a0]+/, " ")&.strip
      text unless text.nil? || text.empty?
    end

    def links(item, base)
      result = []
      item.css("a[href]").each do |anchor|
        next if hint?(anchor)
        original = anchor["href"]
        url = absolute_url(base, original)
        result << { "url" => url, "rotulo" => clean(anchor.text), "referencia_original" => original } if url
      end
      item.xpath(".//text()[not(ancestor::a)]").each do |text|
        next if hint?(text) || text.ancestors.any? { |node| %w[script style svg].include?(node.name) }
        text.text.scan(%r{https?://[^\s<>"']+}i).each do |reference|
          reference = reference.sub(/[.,;:!?\)\]]+\z/, "")
          url = absolute_url(base, reference)
          result << { "url" => url, "rotulo" => nil, "referencia_original" => reference } if url
        end
      end
      result
    end

    def hint?(node)
      node.ancestors.any? { |ancestor| ancestor["class"].to_s.split.any? { |name| name.start_with?("hint-") } }
    end

    def absolute_url(base, reference)
      return if reference.nil? || reference.strip.empty?
      uri = URI.join(base, reference)
      uri.to_s if %w[http https].include?(uri.scheme&.downcase) && uri.host && !uri.host.empty?
    rescue URI::InvalidURIError
      nil
    end
  end
end
