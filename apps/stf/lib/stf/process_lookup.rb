require "nokogiri"
require "uri"
require_relative "errors"

module STF
  class ProcessLookup
    PORTAL = "https://portal.stf.jus.br/processos".freeze
    CNJ = /\A(?:[0-9]{20}|[0-9]{7}-[0-9]{2}\.[0-9]{4}\.[0-9]\.[0-9]{2}\.[0-9]{4})\z/.freeze

    def initialize(http:, discovery:)
      @http = http
      @discovery = discovery
    end

    def resolve(criteria)
      number = criteria["number"]
      classe = criteria["classe"]
      source_number = criteria["numeroProcesso"]
      if number && (!number.is_a?(String) || !CNJ.match?(number))
        raise InvalidSource, "Número CNJ inválido"
      end
      if classe || source_number
        unless classe.is_a?(String) && !classe.strip.empty? && source_number.is_a?(String) && /\A[0-9]+\z/.match?(source_number)
          raise InvalidSource, "Identificação STF incompleta"
        end
      end
      raise InvalidSource, "Identificação do processo ausente" unless number || classe

      query = number ? { numeroUnico: number.delete("-.") } : { classe: classe, numeroProcesso: source_number }
      detail = Nokogiri::HTML(html_text(@http.get("#{PORTAL}/listarProcessos.asp?#{URI.encode_www_form(query)}")), nil, "UTF-8")
      incidente_text = detail.at_css("#incidente")&.[]("value")
      identificacao = clean(detail.at_css("#classe-numero-processo")&.[]("value"))
      match = identificacao&.match(/\A(.+?)\s+([0-9]+)\z/)
      cnj_text = detail.css(".processo-rotulo").map { |node| clean(node.text) }.find { |text| text&.match?(/\ANúmero Único\s*:/i) }
      cnj = clean(cnj_text&.sub(/\ANúmero Único\s*:\s*/i, ""))
      unless incidente_text&.match?(/\A[1-9][0-9]*\z/) && match && (cnj.nil? || CNJ.match?(cnj))
        raise InvalidSource, "Detalhe de processo inválido ou incompleto"
      end
      if number && (cnj.nil? || number.delete("-.") != cnj.delete("-."))
        raise InvalidSource, "Número CNJ divergente"
      end
      cnj = cnj&.delete("-.")
      if classe && (classe.strip.casecmp?(match[1]) == false || source_number.to_i != match[2].to_i)
        raise InvalidSource, "Identificação STF divergente"
      end

      process = { "incidente" => incidente_text.to_i, "cnj" => cnj, "classe" => match[1],
                  "identificacao" => identificacao, "publicidade" => "Público" }
      parties = Nokogiri::HTML.fragment(html_text(@http.get("#{PORTAL}/abaPartes.asp?incidente=#{process.fetch('incidente')}")))
      container = parties.at_css("#todas-partes")
      raise InvalidSource, "Aba de partes inválida" unless container

      names = container.css(".processo-partes").filter_map do |row|
        role = clean(row.at_css(".detalhe-parte")&.text)
        name = clean(row.at_css(".nome-parte")&.text)
        raise InvalidSource, "Parte incompleta" unless role && name
        name unless role.match?(/\AADV/i) || name.casecmp?("SEM REPRESENTAÇÃO NOS AUTOS")
      end.uniq
      active = inactive = false
      names.each do |name|
        case @discovery.find_status(name: name, incidente: process.fetch("incidente"), cnj: cnj)
        when :active then active = true
        when :inactive then inactive = true
        when :restricted then return nil
        when nil then next
        else raise InvalidSource, "Situação de processo desconhecida"
        end
      end
      return process if active
      return nil if inactive

      raise InvalidSource, "Situação do processo não comprovada"
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
  end
end
