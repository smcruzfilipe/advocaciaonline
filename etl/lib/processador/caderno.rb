require "digest"
require "json"
require "uri"
require "zip"
require "zlib"
require_relative "errors"

module Processador
  class Caderno
    CHUNK_SIZE = 64 * 1024
    STATUSES = ["Processado", "Sem comunicações"].freeze

    def initialize(http:, base_url:)
      @http = http
      @base_url = base_url.delete_suffix("/")
    end

    def each(court:, date:, medium:, before_request: nil)
      return enum_for(__method__, court: court, date: date, medium: medium, before_request: before_request) unless block_given?

      path = [court, date.iso8601, medium].map { |part| URI.encode_www_form_component(part) }.join("/")
      before_request&.call
      metadata = @http.get_json("#{@base_url}/caderno/#{path}")
      source_read { validate_metadata(metadata) }
      url = metadata["url"]

      if metadata["status"] == "Sem comunicações" && (url.nil? || url == "")
        validate_absence(metadata)
        return
      end
      unless url.is_a?(String) && !url.strip.empty?
        source_failure("caderno_missing_url")
      end

      before_request&.call
      @http.download(url) do |download|
        source_read { validate_hash(download, metadata["hash"]) }
        archive = source_read { Zip::File.open(download) }
        begin
          source_read { validate_archive(archive, download, metadata) }

          # Http owns a private, complete tempfile for this block. Re-read one
          # JSON at a time only after every member and aggregate is validated.
          archive.each do |entry|
            next unless json_entry?(entry)

            items = source_read { parse_items(entry.get_input_stream(&:read)) }
            items.each { |item| yield item }
          end
        ensure
          source_read { archive.close }
        end
      end
      nil
    end

    private

    def source_failure(code)
      retry_after = @http.retry_after if @http.respond_to?(:retry_after)
      raise SourceError.new(code, retry_after: retry_after), cause: nil
    end

    def validate_metadata(metadata)
      unless metadata.is_a?(Hash) && STATUSES.include?(metadata["status"])
        source_failure("caderno_invalid_status")
      end

      %w[numero_paginas total_comunicacoes].each do |key|
        value = metadata[key]
        unless value.nil? || (value.is_a?(Integer) && value >= 0)
          source_failure("caderno_invalid_count")
        end
      end
      hash = metadata["hash"]
      unless hash.nil? || (hash.is_a?(String) && hash.match?(/\A[0-9a-fA-F]{64}\z/))
        source_failure("caderno_invalid_hash")
      end
    end

    def validate_absence(metadata)
      if metadata["hash"] || %w[numero_paginas total_comunicacoes].any? { |key| metadata[key] && metadata[key] != 0 }
        source_failure("caderno_contradictory_absence")
      end
    end

    def validate_hash(path, expected)
      return if expected.nil?
      return if Digest::SHA256.file(path).hexdigest == expected.downcase

      source_failure("caderno_hash_mismatch")
    end

    def validate_archive(archive, path, metadata)
      # rubyzip can stop at a malformed central-directory member or replace a
      # duplicate name. Never silently validate the remaining subset.
      unless archive.size == Zip::File.count_entries(path)
        source_failure("caderno_incomplete_directory")
      end

      pages = 0
      total = 0
      File.open(path, "rb") do |input|
        archive.each do |entry|
          validate_local_header(input, entry)
          json = json_entry?(entry)
          contents = read_entry(entry, keep: json)
          next unless json

          pages += 1
          total += parse_items(contents).length
        end
      end
      if (!metadata["numero_paginas"].nil? && metadata["numero_paginas"] != pages) ||
          (!metadata["total_comunicacoes"].nil? && metadata["total_comunicacoes"] != total)
        source_failure("caderno_count_mismatch")
      end
      if metadata["status"] == "Sem comunicações" && total != 0
        source_failure("caderno_contradictory_absence")
      end
    end

    def validate_local_header(input, entry)
      input.seek(entry.local_header_offset)
      local = Zip::Entry.read_local_entry(input)
      unless local && local.name == entry.name && local.gp_flags == entry.gp_flags &&
          local.compression_method == entry.compression_method
        source_failure("caderno_invalid_local_header")
      end

      descriptor = (entry.gp_flags & 8) != 0
      %i[crc size compressed_size].each do |field|
        value = local.public_send(field)
        unless value == entry.public_send(field) || (descriptor && value == 0)
          source_failure("caderno_inconsistent_local_header")
        end
      end
      if input.pos + entry.compressed_size > input.stat.size
        source_failure("caderno_truncated_member")
      end
    end

    def read_entry(entry, keep:)
      if entry.directory?
        unless entry.size == 0 && entry.crc == 0
          source_failure("caderno_invalid_directory")
        end
        return
      end
      unless entry.file? && !entry.encrypted?
        source_failure("caderno_unsupported_member")
      end

      contents = +"".b if keep
      size = 0
      crc = 0
      buffer = +"".b
      entry.get_input_stream do |stream|
        while stream.read(CHUNK_SIZE, buffer)
          size += buffer.bytesize
          source_failure("caderno_member_size_mismatch") if size > entry.size

          crc = Zlib.crc32(buffer, crc)
          contents << buffer if keep
        end
      end
      unless size == entry.size && crc == entry.crc
        source_failure("caderno_member_integrity_mismatch")
      end
      contents
    end

    def json_entry?(entry)
      entry.file? && entry.name.downcase.end_with?(".json")
    end

    def parse_items(contents)
      contents.force_encoding(Encoding::UTF_8)
      source_failure("caderno_invalid_json_encoding") unless contents.valid_encoding?

      document = JSON.parse(contents)
      unless document.is_a?(Hash) && document["items"].is_a?(Array) && document["items"].all? { |item| item.is_a?(Hash) }
        source_failure("caderno_invalid_json_structure")
      end
      # count has no documented completeness semantics; only actual items and
      # optional package metadata determine the publication total.
      document["items"]
    end

    def source_read
      yield
    rescue SourceError
      raise
    rescue StandardError
      # Keep ZIP member names, temporary paths and untrusted parser details out
      # of persisted failure reasons. Consumer code is never inside this block.
      source_failure("caderno_invalid_package")
    end
  end
end
