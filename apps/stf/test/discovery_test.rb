require "minitest/autorun"
require "json"
require "uri"
require_relative "../lib/stf/discovery"

class DiscoveryTest < Minitest::Test
  class FakeHTTP
    attr_reader :requests

    def initialize(pages)
      @pages = pages
      @requests = []
    end

    def get(url)
      uri = URI(url)
      params = URI.decode_www_form(uri.query).to_h
      @requests << [uri, params]
      response = @pages.fetch([params["processosEmTramitacao"], params.fetch("pagina").to_i])
      raise response if response.is_a?(Exception)
      response.is_a?(String) ? response : JSON.generate(response)
    end
  end

  def row(id: 7728350, name: "ROBERTO FERREIRA DA SILVA", cnj: "0188263-19.2026.1.00.0000", status: "Sim", identification: "Rcl 101463", publicity: "Público")
    { "pessoaNome" => name, "processoId" => id, "processoIdentificacao" => identification,
      "processoNumeroUnico" => cnj, "processoEmTramitacao" => status, "processoPublicidade" => publicity }
  end

  def page(rows, pages: 1, total: rows.size)
    { "partes" => rows, "totalDePaginas" => pages, "totalDeRegistros" => total }
  end

  def test_search_follows_all_pages_filters_exact_canonical_name_and_active_status
    http = FakeHTTP.new({
      [nil, 1] => page([row, row(id: 10, name: "ROBERTO FERREIRA DA SILVA JUNIOR")], pages: 2, total: 4),
      [nil, 2] => page([row(id: 11, status: "Não"), row(id: 12, name: "Róberto  Ferreira da Silva", identification: "RE 1519008")], pages: 2, total: 4)
    })
    result = STF::Discovery.new(http: http).search(name: "  Roberto Ferreira da SILVA ", type: "ADVOGADO")

    assert_equal [7728350, 12], result.map { |process| process.fetch("incidente") }
    assert_equal({ "incidente" => 7728350, "cnj" => "0188263-19.2026.1.00.0000", "classe" => "Rcl", "identificacao" => "Rcl 101463", "publicidade" => "Público" }, result.first)
    assert_equal ["1", "2"], http.requests.map { |_, params| params["pagina"] }
    http.requests.each do |uri, params|
      assert_equal "https://digital.stf.jus.br/integracoes-processos/api/public/partes/processos", "#{uri.scheme}://#{uri.host}#{uri.path}"
      assert_equal "20", params["processosPorPagina"]
      assert_equal "ADVOGADO", params["tipoPesquisa"]
      refute params.key?("processosEmTramitacao")
    end
  end

  def test_party_search_encodes_name_and_requests_active_filter
    http = FakeHTTP.new({ ["sim", 1] => page([row]) })
    result = STF::Discovery.new(http: http).search(name: "Roberto Ferreira da Silva", type: "PARTE")
    assert_equal 1, result.size
    assert_equal "Roberto Ferreira da Silva", http.requests.first.last["nome"]
    assert_equal "PARTE", http.requests.first.last["tipoPesquisa"]
    assert_equal "sim", http.requests.first.last["processosEmTramitacao"]
  end

  def test_search_returns_empty_only_for_valid_empty_response
    http = FakeHTTP.new({ [nil, 1] => page([], pages: 0) })
    assert_empty STF::Discovery.new(http: http).search(name: "Pessoa", type: "ADVOGADO")
  end

  def test_search_does_not_cap_the_number_of_pages
    pages = (1..501).to_h do |number|
      [[nil, number], page([row(id: number)], pages: 501, total: 501)]
    end
    http = FakeHTTP.new(pages)
    result = STF::Discovery.new(http: http).search(name: "Roberto Ferreira da Silva", type: "ADVOGADO")
    assert_equal 501, result.length
    assert_equal "501", http.requests.last.last["pagina"]
  end

  def test_search_preserves_punctuation_in_canonical_names_and_deduplicates_processes
    http = FakeHTTP.new({ [nil, 1] => page([row, row, row(id: 10, name: "ROBERTO FERREIRA DA SILVA JR.")]) })
    result = STF::Discovery.new(http: http).search(name: "Roberto Ferreira da Silva", type: "ADVOGADO")
    assert_equal [7728350], result.map { |process| process.fetch("incidente") }
  end

  def test_late_http_error_is_not_a_partial_success
    error = STF::SourceUnavailable.new("indisponível")
    http = FakeHTTP.new({ [nil, 1] => page([row], pages: 2, total: 2), [nil, 2] => error })
    assert_raises(STF::SourceUnavailable) { STF::Discovery.new(http: http).search(name: "Roberto Ferreira da Silva", type: "ADVOGADO") }
  end

  def test_rejects_repeated_pages_even_if_association_ids_change
    http = FakeHTTP.new({
      [nil, 1] => page([row.merge("id" => 1)], pages: 2, total: 2),
      [nil, 2] => page([row.merge("id" => 2)], pages: 2, total: 2)
    })
    assert_raises(STF::InvalidSource) { STF::Discovery.new(http: http).search(name: "Roberto Ferreira da Silva", type: "ADVOGADO") }
  end

  def test_rejects_bad_json_bad_records_and_inconsistent_pagination
    invalid_pages = [
      "<html>erro</html>",
      { "partes" => [], "totalDePaginas" => "1", "totalDeRegistros" => 0 },
      page([row.merge("processoId" => nil)]),
      page([row.merge("processoEmTramitacao" => "talvez")]),
      page([], pages: 1, total: 1)
    ]
    invalid_pages.each do |response|
      http = FakeHTTP.new({ [nil, 1] => response })
      assert_raises(STF::InvalidSource) { STF::Discovery.new(http: http).search(name: "Pessoa", type: "ADVOGADO") }
    end
    http = FakeHTTP.new({ [nil, 1] => page([row], pages: 2, total: 2), [nil, 2] => page([row(id: 9)], pages: 3, total: 2) })
    assert_raises(STF::InvalidSource) { STF::Discovery.new(http: http).search(name: "Pessoa", type: "ADVOGADO") }
  end

  def test_find_status_confirms_active_by_name_id_and_cnj_on_later_page
    http = FakeHTTP.new({
      ["sim", 1] => page([row(id: 1)], pages: 2, total: 2),
      ["sim", 2] => page([row], pages: 2, total: 2)
    })
    assert_equal :active, STF::Discovery.new(http: http).find_status(name: "Roberto Ferreira da Silva", incidente: 7728350, cnj: "01882631920261000000")
    assert_equal ["1", "2"], http.requests.map { |_, params| params["pagina"] }
  end

  def test_find_status_confirms_inactive_only_from_explicit_negative
    http = FakeHTTP.new({ ["sim", 1] => page([row(status: "Não")]) })
    assert_equal :inactive, STF::Discovery.new(http: http).find_status(name: "Roberto Ferreira da Silva", incidente: 7728350, cnj: "0188263-19.2026.1.00.0000")
    assert_equal ["sim"], http.requests.map { |_, params| params["processosEmTramitacao"] }
  end

  def test_find_status_checks_archived_processes_after_active_search
    http = FakeHTTP.new({
      ["sim", 1] => page([], pages: 0),
      ["nao", 1] => page([row(status: "Não")])
    })
    assert_equal :inactive, STF::Discovery.new(http: http).find_status(
      name: "Roberto Ferreira da Silva", incidente: 7728350, cnj: "0188263-19.2026.1.00.0000")
  end

  def test_find_status_requires_complete_pages_even_after_an_active_match
    http = FakeHTTP.new({
      ["sim", 1] => page([row], pages: 2, total: 2),
      ["sim", 2] => STF::SourceUnavailable.new("late failure")
    })
    assert_raises(STF::SourceUnavailable) do
      STF::Discovery.new(http: http).find_status(
        name: "Roberto Ferreira da Silva", incidente: 7728350, cnj: "0188263-19.2026.1.00.0000")
    end
  end

  def test_find_status_absence_wrong_name_id_or_cnj_does_not_prove_inactive
    http = FakeHTTP.new({
      ["sim", 1] => page([row(id: 1), row(cnj: "0000000-00.2026.1.00.0000"), row(name: "OUTRA PESSOA")]),
      ["nao", 1] => page([], pages: 0)
    })
    assert_nil STF::Discovery.new(http: http).find_status(name: "Roberto Ferreira da Silva", incidente: 7728350, cnj: "0188263-19.2026.1.00.0000")
  end

  def test_find_status_does_not_turn_late_failure_into_unknown_or_inactive
    error = STF::SourceUnavailable.new("indisponível")
    http = FakeHTTP.new({ ["sim", 1] => page([row(id: 1)], pages: 2, total: 2), ["sim", 2] => error })
    assert_raises(STF::SourceUnavailable) { STF::Discovery.new(http: http).find_status(name: "Roberto Ferreira da Silva", incidente: 7728350, cnj: "0188263-19.2026.1.00.0000") }
  end

  def test_search_filters_masked_restricted_and_inactive_before_validating_consumed_fields
    http = FakeHTTP.new({
      [nil, 1] => page([row(publicity: "Sigiloso", cnj: "***", identification: nil),
                        row(id: 2, status: "Não", cnj: nil, identification: nil),
                        row(id: 3, cnj: "", identification: "RE 1519008")])
    })
    assert_equal [{ "incidente" => 3, "cnj" => nil, "classe" => "RE",
                   "identificacao" => "RE 1519008", "publicidade" => "Público" }],
                 STF::Discovery.new(http: http).search(name: "Roberto Ferreira da Silva", type: "ADVOGADO")
  end

  def test_unknown_publicity_and_malformed_present_cnj_fail
    [row(publicity: nil), row(publicity: "desconhecido"), row(cnj: "123")].each do |record|
      http = FakeHTTP.new({ [nil, 1] => page([record]) })
      assert_raises(STF::InvalidSource) { STF::Discovery.new(http: http).search(name: "Roberto Ferreira da Silva", type: "ADVOGADO") }
    end
  end

  def test_status_restricted_masked
    http = FakeHTTP.new({ ["sim", 1] => page([row(publicity: "Privado", cnj: "***", identification: nil)]) })
    assert_equal :restricted, STF::Discovery.new(http: http).find_status(name: "Roberto Ferreira da Silva", incidente: 7728350, cnj: nil)
  end

  def test_known_cnj_is_not_confirmed_by_missing_or_different_source_cnj
    [nil, "0000001-00.2026.1.00.0000"].each do |cnj|
      http = FakeHTTP.new({ ["sim", 1] => page([row(cnj: cnj)]), ["nao", 1] => page([]) })
      assert_nil STF::Discovery.new(http: http).find_status(name: "Roberto Ferreira da Silva", incidente: 7728350, cnj: "01882631920261000000")
    end
  end
  def test_status_accepts_public_without_detail_cnj_but_rejects_malformed_present_cnj
    http = FakeHTTP.new({ ["sim", 1] => page([row(publicity: "PUBLICO")]) })
    assert_equal :active, STF::Discovery.new(http: http).find_status(name: "Roberto Ferreira da Silva", incidente: 7728350, cnj: nil)
    http = FakeHTTP.new({ ["sim", 1] => page([row(cnj: "123")]) })
    assert_raises(STF::InvalidSource) do
      STF::Discovery.new(http: http).find_status(name: "Roberto Ferreira da Silva", incidente: 7728350, cnj: nil)
    end
  end


  def test_restricted_match_still_checks_all_pages
    http = FakeHTTP.new({ ["sim", 1] => page([row(publicity: "Sigiloso", cnj: nil, identification: nil)], pages: 2, total: 2),
                          ["sim", 2] => STF::SourceUnavailable.new("late failure") })
    assert_raises(STF::SourceUnavailable) do
      STF::Discovery.new(http: http).find_status(name: "Roberto Ferreira da Silva", incidente: 7728350, cnj: nil)
    end
  end

end
