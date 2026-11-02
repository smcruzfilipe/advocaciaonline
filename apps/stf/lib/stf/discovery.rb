require "json"
require "uri"
require_relative "errors"

module STF
  class Discovery
    ENDPOINT = "https://digital.stf.jus.br/integracoes-processos/api/public/partes/processos".freeze
    CNJ = /\A(?:[0-9]{20}|[0-9]{7}-[0-9]{2}\.[0-9]{4}\.[0-9]\.[0-9]{2}\.[0-9]{4})\z/.freeze
    PAGE_SIZE = 20

    def initialize(http:)
      @http = http
    end

    def search(name:, type:)
      validate_name!(name)
      raise ArgumentError, "Tipo de pesquisa inválido" unless %w[ADVOGADO PARTE].include?(type)

      matches = {}
      each_record(name: name, type: type, active: type == "PARTE" ? "sim" : nil) do |record|
        next unless canonical_name(record.fetch("pessoaNome")) == canonical_name(name)
        next unless record.fetch("processoEmTramitacao") == "Sim"
        next unless publicity(record) == :public

        process = process_from(record)
        id = process.fetch("incidente")
        if (previous = matches[id])
          if previous.merge("cnj" => process["cnj"]) != process ||
             (previous["cnj"] && process["cnj"] && previous["cnj"] != process["cnj"])
            raise InvalidSource, "Dados contraditórios para processo STF"
          end
          process["cnj"] ||= previous["cnj"]
        end
        matches[id] = process
      end
      matches.values
    end

    def find_status(name:, incidente:, cnj:)
      validate_name!(name)
      raise ArgumentError, "Incidente inválido" unless incidente.is_a?(Integer) && incidente.positive?
      raise ArgumentError, "CNJ inválido" unless cnj.nil? || (cnj.is_a?(String) && CNJ.match?(cnj))

      expected_name = canonical_name(name)
      expected_cnj = cnj&.delete("-.")
      found = nil
      %w[sim nao].each do |filter|
        each_record(name: name, type: "PARTE", active: filter) do |record|
          next unless canonical_name(record.fetch("pessoaNome")) == expected_name
          next unless record.fetch("processoId") == incidente

          restricted = publicity(record) == :restricted
          raw_cnj = record["processoNumeroUnico"]
          record_cnj = if restricted && !(raw_cnj.is_a?(String) && CNJ.match?(raw_cnj))
                         nil
                       else
                         optional_cnj(record)
                       end
          status = restricted ? :restricted : (record.fetch("processoEmTramitacao") == "Sim" ? :active : :inactive)
          if expected_cnj && record_cnj && expected_cnj != record_cnj
            raise InvalidSource, "CNJ divergente para processo STF"
          end
          if found && found[:state] != status
            raise InvalidSource, "Situações contraditórias para processo STF"
          end
          if found && found[:cnj] && record_cnj && found[:cnj] != record_cnj
            raise InvalidSource, "CNJs contraditórios para processo STF"
          end
          found = { state: status, cnj: found&.fetch(:cnj) || record_cnj }
        end
        return found if found && (found[:state] == :restricted || expected_cnj.nil? || found[:cnj])
      end
      nil
    end

    private

    def each_record(name:, type:, active:)
      number = 1
      expected_pages = expected_total = nil
      count = 0
      seen_pages = {}

      loop do
        params = { nome: name, processosPorPagina: PAGE_SIZE, pagina: number, tipoPesquisa: type }
        params[:processosEmTramitacao] = active if active
        response = JSON.parse(@http.get("#{ENDPOINT}?#{URI.encode_www_form(params)}"))
        unless response.is_a?(Hash) && response["partes"].is_a?(Array) &&
               response["totalDePaginas"].is_a?(Integer) && response["totalDePaginas"] >= 0 &&
               response["totalDeRegistros"].is_a?(Integer) && response["totalDeRegistros"] >= 0
          raise InvalidSource, "Resposta de descoberta STF inválida"
        end

        pages = response.fetch("totalDePaginas")
        total = response.fetch("totalDeRegistros")
        rows = response.fetch("partes")
        if (number == 1 && ((pages.zero? && total.positive?) || (pages > 1 && total.zero?))) ||
           (expected_pages && (pages != expected_pages || total != expected_total)) ||
           rows.size > PAGE_SIZE || (total.positive? && rows.empty?)
          raise InvalidSource, "Paginação STF inconsistente"
        end
        expected_pages ||= pages
        expected_total ||= total
        count += rows.size
        raise InvalidSource, "Contagem STF inconsistente" if count > total

        rows.each { |record| validate_record!(record) }
        unless rows.empty?
          # Association ids are not stable process identities; compare the actual observed rows.
          fingerprint = rows.map do |record|
            JSON.generate([record["pessoaNome"], record["processoId"], record["processoIdentificacao"],
                           record["processoNumeroUnico"], record["processoEmTramitacao"], record["processoPublicidade"]])
          end.sort
          raise InvalidSource, "Página STF repetida" if seen_pages.key?(fingerprint)
          seen_pages[fingerprint] = true
        end
        rows.each { |record| yield record }

        break if number >= pages
        number += 1
      end
      raise InvalidSource, "Contagem STF inconsistente" unless count == expected_total
    rescue JSON::ParserError, EncodingError
      raise InvalidSource, "JSON de descoberta STF inválido"
    end

    def validate_record!(record)
      unless record.is_a?(Hash) && record["pessoaNome"].is_a?(String) && !record["pessoaNome"].strip.empty? &&
             record["processoId"].is_a?(Integer) && record["processoId"].positive? &&
             %w[Sim Não].include?(record["processoEmTramitacao"])
        raise InvalidSource, "Registro de descoberta STF inválido"
      end
      publicity(record)
    end

    def publicity(record)
      value = record["processoPublicidade"]
      normalized = canonical_name(value) if value.is_a?(String)
      return :public if normalized == "publico"
      return :restricted if ["privado", "sigiloso", "sigilo", "restrito", "nao publico", "segredo de justica"].include?(normalized)

      raise InvalidSource, "Publicidade de processo STF desconhecida"
    end

    def optional_cnj(record)
      cnj = record["processoNumeroUnico"]
      return nil if cnj.nil? || (cnj.is_a?(String) && cnj.strip.empty?)
      raise InvalidSource, "CNJ de processo STF inválido" unless cnj.is_a?(String) && CNJ.match?(cnj)

      cnj.delete("-.")
    end

    def process_from(record)
      identification = record["processoIdentificacao"]
      unless identification.is_a?(String) && /\A\s*\S(?:.*?\S)?\s+[0-9][0-9.]*\s*\z/.match?(identification)
        raise InvalidSource, "Identificação de processo STF inválida"
      end
      identification = identification.strip
      { "incidente" => record.fetch("processoId"), "cnj" => optional_cnj(record),
        "classe" => identification.sub(/\s+[0-9][0-9.]*\z/, ""), "identificacao" => identification,
        "publicidade" => "Público" }
    end

    def validate_name!(name)
      raise ArgumentError, "Nome inválido" unless name.is_a?(String) && !name.strip.empty?
    end

    def canonical_name(name)
      name.gsub(/[[:space:]]+/, " ").strip.unicode_normalize(:nfd).gsub(/\p{M}/, "").downcase(:fold)
    end
  end
end
