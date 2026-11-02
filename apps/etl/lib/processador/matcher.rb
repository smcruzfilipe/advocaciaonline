# frozen_string_literal: true

module Processador
  module Matcher
    UFS = %w[AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO].freeze
    CANONICAL_NUMBER = /\A[0-9]{20}\z/.freeze
    MASKED_NUMBER = /\A[0-9]{7}-[0-9]{2}\.[0-9]{4}\.[0-9]\.[0-9]{2}\.[0-9]{4}\z/.freeze

    class << self
      # criteria is the JSON snapshot from collection_jobs, not a live profile lookup.
      def match?(entity_type:, criteria:, publication:)
        return false unless criteria.is_a?(Hash) && publication.is_a?(Hash)

        case entity_type
        when "lawyer" then lawyer_match?(criteria, publication)
        when "party" then party_match?(criteria, publication)
        when "process"
          number = canonical_number(criteria["number"])
          !number.nil? && number == canonical_number(publication["numero_processo"])
        else false
        end
      end

      private

      def lawyer_match?(criteria, publication)
        recipients = publication["destinatarioadvogados"]
        return false unless recipients.is_a?(Array)

        name = canonical_name(criteria["name"])
        registrations = criteria["oabs"]
        oabs = if registrations.is_a?(Array)
          registrations.filter_map do |registration|
            canonical_oab(registration["number"], registration["uf"]) if registration.is_a?(Hash)
          end
        else
          []
        end

        recipients.any? do |recipient|
          next false unless recipient.is_a?(Hash)

          lawyer = recipient["advogado"]
          next false unless lawyer.is_a?(Hash)

          (name && name == canonical_name(lawyer["nome"])) ||
            oabs.include?(canonical_oab(lawyer["numero_oab"], lawyer["uf_oab"]))
        end
      end

      def party_match?(criteria, publication)
        name = canonical_name(criteria["name"])
        recipients = publication["destinatarios"]
        return false unless name && recipients.is_a?(Array)

        recipients.any? do |recipient|
          recipient.is_a?(Hash) && name == canonical_name(recipient["nome"])
        end
      end

      def canonical_name(value)
        return unless value.is_a?(String)

        # Same canonical normalization as PartyMonitoring; punctuation stays significant.
        # https://docs.ruby-lang.org/en/4.0/String.html#method-i-unicode_normalize
        # https://docs.ruby-lang.org/en/4.0/language/case_mapping_rdoc.html
        name = value.gsub(/[[:space:]]+/, " ").strip.unicode_normalize(:nfd).gsub(/\p{M}/, "").downcase(:fold)
        name unless name.empty?
      end

      def canonical_oab(number, uf)
        return unless number.is_a?(String) && uf.is_a?(String)

        number = trim(number)
        uf = trim(uf).upcase
        [number, uf] unless number.empty? || !UFS.include?(uf)
      end

      def trim(value)
        value.gsub(/\A[[:space:]]+|[[:space:]]+\z/, "")
      end

      def canonical_number(value)
        return unless value.is_a?(String)
        return value if CANONICAL_NUMBER.match?(value)

        value.delete("-.") if MASKED_NUMBER.match?(value)
      end
    end
  end
end
