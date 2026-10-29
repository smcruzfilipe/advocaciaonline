require "date"
require "digest"
require "json"
require "minitest/autorun"
require "tempfile"
require "tmpdir"
require "zip"
require_relative "../lib/processador/caderno"

class CadernoTest < Minitest::Test
  DATE = Date.new(2026, 10, 29)
  BASE_URL = "https://djen.example/api/v1"
  METADATA_URL = "#{BASE_URL}/caderno/TJSP/2026-10-29/D"
  PACKAGE_URL = "https://downloads.example/caderno.zip?token=nao-expor"
  LAWYER_NAME = "Guilherme Curcelli Guimarães"

  class ControlledHttp
    attr_reader :requests, :downloads, :retry_after

    def initialize(metadata:, package: nil, error: nil, download_directory: nil, retry_after: nil)
      @metadata = metadata
      @package = package
      @error = error
      @download_directory = download_directory
      @retry_after = retry_after
      @requests = []
      @downloads = []
    end

    def get_json(url)
      @requests << url
      raise @error if @error

      @metadata
    end

    def download(url)
      @downloads << url
      raise @package if @package.is_a?(Exception)
      raise "download inesperado" unless @package

      Tempfile.create(["caderno-test", ".zip"], @download_directory) do |file|
        file.binmode
        file.write(@package)
        file.flush
        yield file.path
      end
    end
  end

  def test_reads_every_json_and_publication_after_validating_the_complete_package
    publications = [publication(1), publication(2), publication(3)]
    package = zip_bytes([
      ["pagina-1.json", page(publications.first(2), count: 999)],
      ["subdiretorio/", ""],
      ["subdiretorio/pagina-2.json", page(publications.last(1), count: 999)],
      ["leia-me.txt", "arquivo auxiliar integro"]
    ])
    http = ControlledHttp.new(metadata: metadata(package, pages: 2, total: 3), package: package)

    actual = collect(http)

    assert_equal publications, actual
    assert_equal LAWYER_NAME, actual.first.fetch("destinatarioadvogados").first.fetch("advogado").fetch("nome")
    assert_equal [METADATA_URL], http.requests
    assert_equal [PACKAGE_URL], http.downloads
  end

  def test_missing_or_null_optional_metadata_does_not_invalidate_a_complete_package
    package = zip_bytes([["pagina.json", JSON.generate("items" => [publication(1)])]])
    [
      { "status" => "Processado", "url" => PACKAGE_URL },
      { "status" => "Processado", "url" => PACKAGE_URL, "hash" => nil, "numero_paginas" => nil, "total_comunicacoes" => nil }
    ].each do |response|
      assert_equal [publication(1)], collect(ControlledHttp.new(metadata: response, package: package))
    end
  end

  def test_accepts_uppercase_sha256_without_confusing_it_with_publication_hashes
    package = zip_bytes([["pagina.json", page([publication(1)])]])
    response = metadata(package, pages: 1, total: 1).merge("hash" => Digest::SHA256.hexdigest(package).upcase)

    assert_equal [publication(1)], collect(ControlledHttp.new(metadata: response, package: package))
  end

  def test_explicit_coherent_absence_succeeds_without_downloading
    [
      { "status" => "Sem comunicações" },
      { "status" => "Sem comunicações", "numero_paginas" => 0, "total_comunicacoes" => 0, "url" => nil, "hash" => nil }
    ].each do |response|
      http = ControlledHttp.new(metadata: response)

      assert_empty collect(http)
      assert_empty http.downloads
    end
  end

  def test_explicit_absence_cannot_hide_contradictory_metadata_or_publications
    package = zip_bytes([["pagina.json", page([publication(1)])]])
    [
      { "status" => "Sem comunicações", "numero_paginas" => 1 },
      { "status" => "Sem comunicações", "total_comunicacoes" => 1 },
      { "status" => "Sem comunicações", "hash" => "a" * 64 },
      metadata(package, pages: 1, total: 1).merge("status" => "Sem comunicações")
    ].each do |response|
      assert_rejected(response, package: package)
    end
  end

  def test_a_validated_package_with_no_items_is_also_a_legitimate_empty_result
    [
      [zip_bytes([]), 0],
      [zip_bytes([["pagina.json", page([], count: 741)]]), 1]
    ].each do |package, pages|
      assert_empty collect(ControlledHttp.new(metadata: metadata(package, pages: pages, total: 0), package: package))
    end
  end

  def test_explicit_absence_with_a_package_still_validates_that_package
    package = zip_bytes([["pagina.json", page([])]])
    response = metadata(package, pages: 1, total: 0).merge("status" => "Sem comunicações")

    assert_empty collect(ControlledHttp.new(metadata: response, package: package))
    assert_rejected(response, package: "isto nao e ZIP")
  end

  def test_pending_cancelled_unknown_and_missing_status_are_failures_not_zero
    [nil, "", "Não Processado", "Em processamento", "Cancelado", "success", 1].each do |status|
      assert_rejected({ "status" => status })
    end
    assert_rejected({})
    [nil, [], "Processado", 3].each { |response| assert_rejected(response) }
  end

  def test_processed_status_requires_the_official_url_field
    [nil, "", "  ", 17, [], {}].each do |url|
      assert_rejected({ "status" => "Processado", "url" => url })
    end
    assert_rejected({ "status" => "Processado", "download_url" => PACKAGE_URL })
  end

  def test_hash_mismatch_and_invalid_hash_metadata_are_failures_before_emission
    package = zip_bytes([["pagina.json", page([publication(1)])]])
    ["0" * 64, "", "nao-e-sha256", 123, []].each do |hash|
      assert_rejected(metadata(package, pages: 1, total: 1).merge("hash" => hash), package: package)
    end
  end

  def test_supplied_page_and_publication_totals_must_match_actual_items
    package = zip_bytes([
      ["pagina-1.json", page([publication(1), publication(2)], count: 9000)],
      ["pagina-2.json", page([publication(3)], count: 9000)]
    ])
    [
      { "numero_paginas" => 1 },
      { "numero_paginas" => 3 },
      { "total_comunicacoes" => 2 },
      { "total_comunicacoes" => 4 }
    ].each do |override|
      assert_rejected(metadata(package, pages: 2, total: 3).merge(override), package: package)
    end
  end

  def test_optional_counts_reject_wrong_types_instead_of_coercing_them
    package = zip_bytes([["pagina.json", page([])]])
    %w[numero_paginas total_comunicacoes].each do |key|
      ["0", 0.0, -1, false, [], {}].each do |value|
        assert_rejected(metadata(package, pages: 1, total: 0).merge(key => value), package: package)
        assert_rejected({ "status" => "Sem comunicações", key => value })
      end
    end
  end

  def test_a_malformed_later_json_never_leaks_earlier_valid_publications
    [
      "{json truncado",
      "[]",
      "null",
      "{}",
      JSON.generate("items" => nil),
      JSON.generate("items" => {}),
      JSON.generate("items" => [publication(2), "publicacao invalida"]),
      "{\"items\":[{\"texto\":\"\xff\"}]}".b,
    ].each do |invalid_page|
      package = zip_bytes([
        ["pagina-1.json", page([publication(1)])],
        ["pagina-2.json", invalid_page]
      ])
      assert_rejected({ "status" => "Processado", "url" => PACKAGE_URL }, package: package)
    end
  end

  def test_late_crc_corruption_is_rejected_even_when_json_still_parses
    package = zip_bytes([
      ["pagina-1.json", page([publication(1)])],
      ["pagina-2.json", page([publication(2)])]
    ], stored: true)
    corrupted = package.sub("publicacao-2", "publicacao-X")
    refute_equal package, corrupted

    assert_rejected(metadata(corrupted, pages: 2, total: 2), package: corrupted)
  end

  def test_crc_of_non_json_members_is_checked_before_emitting_publications
    package = zip_bytes([
      ["pagina.json", page([publication(1)])],
      ["anexo.txt", "anexo original"]
    ], stored: true)
    corrupted = package.sub("anexo original", "anexo alterado")
    refute_equal package, corrupted

    assert_rejected(metadata(corrupted, pages: 1, total: 1), package: corrupted)
  end

  def test_corrupt_late_local_header_does_not_pass_the_central_crc_check
    package = zip_bytes([
      ["pagina-1.json", page([publication(1)])],
      ["pagina-2.json", page([publication(2)])]
    ], stored: true)
    corrupted = package.dup
    crc_offset = corrupted.rindex("PK\x03\x04".b) + 14
    corrupted.setbyte(crc_offset, corrupted.getbyte(crc_offset) ^ 1)

    assert_rejected(metadata(corrupted, pages: 2, total: 2), package: corrupted)
  end

  def test_invalid_and_truncated_zips_are_not_empty_successes
    valid = zip_bytes([["pagina.json", page([publication(1)])]])
    ["", "nao e um zip", valid.byteslice(0, 100), valid.byteslice(0, valid.bytesize - 10)].each do |package|
      assert_rejected({ "status" => "Processado", "url" => PACKAGE_URL }, package: package)
    end
  end

  def test_missing_late_central_directory_entry_is_not_silently_ignored
    package = zip_bytes([
      ["pagina-1.json", page([publication(1)])],
      ["pagina-2.json", page([publication(2)])]
    ])
    corrupted = package.dup
    last_header = corrupted.rindex("PK\x01\x02".b)
    corrupted.setbyte(last_header, "Q".ord)

    assert_rejected({ "status" => "Processado", "url" => PACKAGE_URL }, package: corrupted)
  end

  def test_member_paths_are_never_extracted_to_the_filesystem
    Dir.mktmpdir("caderno-paths") do |directory|
      downloads = File.join(directory, "downloads")
      Dir.mkdir(downloads)
      package = zip_bytes([["../escaped.json", page([publication(1)])]])
      http = ControlledHttp.new(
        metadata: metadata(package, pages: 1, total: 1),
        package: package,
        download_directory: downloads
      )

      assert_equal [publication(1)], collect(http)
      refute File.exist?(File.join(directory, "escaped.json"))
      assert_empty Dir.children(downloads)
    end
  end


  def test_an_unsuccessful_metadata_status_preserves_the_http_retry_after
    http = ControlledHttp.new(metadata: { "status" => "Em processamento" }, retry_after: 600)

    error = assert_raises(Processador::SourceError) { collect(http) }

    assert_equal 600, error.retry_after
    assert_empty http.downloads
  end

  def test_download_failure_is_a_source_failure_and_not_zero
    error = Processador::SourceError.new("download_failed", retry_after: 60)
    http = ControlledHttp.new(metadata: { "status" => "Processado", "url" => PACKAGE_URL }, package: error)

    assert_same error, assert_raises(Processador::SourceError) { collect(http) }
  end

  def test_each_returns_a_lazy_enumerator_when_no_block_is_given
    package = zip_bytes([["pagina.json", page([publication(1)])]])
    http = ControlledHttp.new(metadata: metadata(package, pages: 1, total: 1), package: package)
    enumerator = Processador::Caderno.new(http: http, base_url: "#{BASE_URL}/").each(court: "TJSP", date: DATE, medium: "D")

    assert_empty http.requests
    assert_equal [publication(1)], enumerator.to_a
    assert_equal [METADATA_URL], http.requests
  end

  def test_consumer_exceptions_are_not_rewritten_as_source_errors
    package = zip_bytes([["pagina.json", page([publication(1)])]])
    http = ControlledHttp.new(metadata: metadata(package, pages: 1, total: 1), package: package)
    error = ArgumentError.new("erro do consumidor")

    actual = assert_raises(ArgumentError) do
      Processador::Caderno.new(http: http, base_url: BASE_URL).each(court: "TJSP", date: DATE, medium: "D") do |_item|
        raise error
      end
    end

    assert_same error, actual
  end

  private

  def publication(id)
    {
      "id" => id,
      "hash" => "publicacao-#{id}",
      "siglaTribunal" => "TJSP",
      "destinatarioadvogados" => [{ "advogado" => { "nome" => LAWYER_NAME, "numero_oab" => "12345", "uf_oab" => "SP" } }]
    }
  end

  def page(items, count: items.length)
    JSON.generate("count" => count, "items" => items)
  end

  def zip_bytes(entries, stored: false)
    Zip::OutputStream.write_buffer do |output|
      entries.each do |name, content|
        entry = Zip::Entry.new(
          "", name,
          time: Time.utc(2026, 10, 29, 12),
          compression_method: stored ? Zip::Entry::STORED : Zip::Entry::DEFLATED
        )
        output.put_next_entry(entry)
        output.write(content)
      end
    end.string
  end

  def metadata(package, pages:, total:)
    {
      "status" => "Processado",
      "url" => PACKAGE_URL,
      "hash" => Digest::SHA256.hexdigest(package),
      "numero_paginas" => pages,
      "total_comunicacoes" => total
    }
  end

  def collect(http)
    Processador::Caderno.new(http: http, base_url: BASE_URL).each(court: "TJSP", date: DATE, medium: "D").to_a
  end

  def assert_rejected(response, package: nil)
    http = ControlledHttp.new(metadata: response, package: package)
    emitted = []
    error = assert_raises(Processador::SourceError) do
      Processador::Caderno.new(http: http, base_url: BASE_URL).each(court: "TJSP", date: DATE, medium: "D") do |item|
        emitted << item
      end
    end
    assert_empty emitted
    refute_includes error.message, PACKAGE_URL
  end
end
