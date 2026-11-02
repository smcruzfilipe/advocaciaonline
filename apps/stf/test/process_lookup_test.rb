require "minitest/autorun"
require "uri"
require_relative "../lib/stf/process_lookup"
require_relative "../lib/stf/discovery"
require_relative "../lib/stf/http"

class ProcessLookupTest < Minitest::Test
  CNJ = "0188263-19.2026.1.00.0000".freeze
  EXPECTED = { "incidente" => 7728350, "cnj" => "01882631920261000000", "classe" => "Rcl", "identificacao" => "Rcl 101463", "publicidade" => "Público" }.freeze
  DETAIL = <<~HTML.freeze
    <div class="processo-titulo"><input id="incidente" value="7728350">
    <input id="classe-numero-processo" value="Rcl 101463"></div>
    <div class="processo-rotulo">Número Único: 0188263-19.2026.1.00.0000</div>
  HTML
  PARTIES = <<~HTML.freeze
    <div id="todas-partes">
      <div class="processo-partes"><div class="detalhe-parte">RECLTE.(S)</div><div class="nome-parte">COMPANHIA RIOGRANDENSE DE SANEAMENTO - CORSAN</div></div>
      <div class="processo-partes"><div class="detalhe-parte">ADV.(A/S)</div><div class="nome-parte">BENÔNI CANELLAS ROSSI (86573/DF)</div></div>
      <div class="processo-partes"><div class="detalhe-parte">RECLDO.(A/S)</div><div class="nome-parte">SEM REPRESENTAÇÃO NOS AUTOS</div></div>
      <div class="processo-partes"><div class="detalhe-parte">BENEF.(A/S)</div><div class="nome-parte">ROBERTO FERREIRA DA SILVA</div></div>
    </div>
    <div id="partes-resumidas"><div class="processo-partes">Não pesquisar</div></div>
  HTML

  class Http
    attr_reader :urls
    def initialize(detail: DETAIL, parties: PARTIES)
      @detail, @parties, @urls = detail, parties, []
    end
    def get(url)
      @urls << url
      STF::Http::Response.new(body: (url.include?("abaPartes.asp") ? @parties : @detail).b, url: url)
    end
  end

  class Discovery
    attr_reader :calls
    def initialize(statuses)
      @statuses, @calls = statuses, []
    end
    def find_status(name:, incidente:, cnj:)
      @calls << [name, incidente, cnj]
      @statuses[name]
    end
  end

  class JsonPages
    attr_reader :queries

    def initialize(cnjs, publicity: "Público")
      @cnjs, @publicity, @queries = cnjs, publicity, []
    end

    def get(url)
      query = URI.decode_www_form(URI(url).query).to_h
      @queries << query
      cnj = @cnjs.fetch(query.fetch("pagina").to_i - 1)
      body = JSON.generate("partes" => [{ "pessoaNome" => "ROBERTO FERREIRA DA SILVA",
                                          "processoId" => 7728350, "processoIdentificacao" => "Rcl 101463",
                                          "processoNumeroUnico" => cnj, "processoEmTramitacao" => "Sim",
                                          "processoPublicidade" => @publicity }],
                           "totalDePaginas" => @cnjs.size, "totalDeRegistros" => @cnjs.size)
      STF::Http::Response.new(body: body, url: url)
    end
  end

  def status(state, cnj: EXPECTED.fetch("cnj"))
    { state: state, cnj: cnj }
  end

  def test_cnj_resolves_detail_and_stops_after_beneficiary_confirmation
    http = Http.new
    discovery = Discovery.new("ROBERTO FERREIRA DA SILVA" => status(:active),
                              "COMPANHIA RIOGRANDENSE DE SANEAMENTO - CORSAN" => status(:restricted))
    result = STF::ProcessLookup.new(http: http, discovery: discovery).resolve("number" => "01882631920261000000")
    assert_equal EXPECTED, result
    assert_equal "01882631920261000000", URI.decode_www_form(URI(http.urls.first).query).to_h.fetch("numeroUnico")
    assert_equal "https://portal.stf.jus.br/processos/abaPartes.asp?incidente=7728350", http.urls.last
    assert_equal [["ROBERTO FERREIRA DA SILVA", 7728350, EXPECTED.fetch("cnj")]], discovery.calls
  end

  def test_masked_input_matches_unmasked_detail_and_returns_canonical_cnj
    detail = DETAIL.sub(CNJ, "01882631920261000000")
    discovery = Discovery.new("ROBERTO FERREIRA DA SILVA" => status(:active))
    assert_equal EXPECTED, STF::ProcessLookup.new(http: Http.new(detail: detail), discovery: discovery).resolve("number" => CNJ)
    assert_equal EXPECTED.fetch("cnj"), discovery.calls.last.last
  end

  def test_class_and_number_resolve_and_explicit_inactive_is_not_eligible
    http = Http.new
    discovery = Discovery.new("ROBERTO FERREIRA DA SILVA" => status(:inactive),
                              "COMPANHIA RIOGRANDENSE DE SANEAMENTO - CORSAN" => status(:active))
    result = STF::ProcessLookup.new(http: http, discovery: discovery).resolve("classe" => "Rcl", "numeroProcesso" => "101463")
    assert_nil result
    assert_equal({ "classe" => "Rcl", "numeroProcesso" => "101463" }, URI.decode_www_form(URI(http.urls.first).query).to_h)
    assert_equal ["ROBERTO FERREIRA DA SILVA"], discovery.calls.map(&:first)
  end

  def test_unknown_status_tries_next_real_party_without_querying_advocate
    discovery = Discovery.new("COMPANHIA RIOGRANDENSE DE SANEAMENTO - CORSAN" => status(:active))
    assert_equal EXPECTED, STF::ProcessLookup.new(http: Http.new, discovery: discovery).resolve("number" => CNJ)
    assert_equal ["ROBERTO FERREIRA DA SILVA", "COMPANHIA RIOGRANDENSE DE SANEAMENTO - CORSAN"], discovery.calls.map(&:first)
  end

  def test_parties_keep_original_order_when_no_beneficiary_exists
    parties = PARTIES.sub("BENEF.(A/S)", "INTERESSADO")
    discovery = Discovery.new("COMPANHIA RIOGRANDENSE DE SANEAMENTO - CORSAN" => status(:active))
    assert_equal EXPECTED, STF::ProcessLookup.new(http: Http.new(parties: parties), discovery: discovery).resolve("number" => CNJ)
    assert_equal ["COMPANHIA RIOGRANDENSE DE SANEAMENTO - CORSAN"], discovery.calls.map(&:first)
  end

  def test_decodes_declared_legacy_detail_and_parties
    detail = ("<meta charset='ISO-8859-1'>" + DETAIL).encode("ISO-8859-1")
    parties = ("<meta charset='ISO-8859-1'>" + PARTIES).encode("ISO-8859-1")
    discovery = Discovery.new("ROBERTO FERREIRA DA SILVA" => status(:active))
    assert_equal EXPECTED, STF::ProcessLookup.new(http: Http.new(detail: detail, parties: parties), discovery: discovery).resolve("number" => CNJ)
    assert_equal "ROBERTO FERREIRA DA SILVA", discovery.calls.first.first
  end

  def test_unknown_status_and_missing_or_malformed_source_fail
    [Http.new, Http.new(detail: "<html>Login</html>"), Http.new(parties: "<html>Login</html>"),
      Http.new(parties: '<div id="todas-partes"><div class="processo-partes"><div class="nome-parte">X</div></div></div>')].each do |http|
      assert_raises(STF::InvalidSource) { STF::ProcessLookup.new(http: http, discovery: Discovery.new({})).resolve("number" => CNJ) }
    end
  end

  def test_rejects_conflicting_identification_and_incomplete_cnj
    http = Http.new
    lookup = STF::ProcessLookup.new(http: http, discovery: Discovery.new("ROBERTO FERREIRA DA SILVA" => status(:active)))
    assert_raises(STF::InvalidSource) { lookup.resolve("number" => "01882631920261000001") }
    assert_equal 1, http.urls.size
    assert_raises(STF::InvalidSource) { lookup.resolve("number" => CNJ, "classe" => "RE", "numeroProcesso" => "1") }
    assert_raises(STF::InvalidSource) { lookup.resolve("number" => "123") }
    assert_raises(STF::InvalidSource) { lookup.resolve("classe" => "Rcl") }
  end

  def test_class_number_without_detail_cnj_uses_json_cnj
    detail = DETAIL.sub(/<div class="processo-rotulo">.*?<\/div>/, "")
    discovery = Discovery.new("ROBERTO FERREIRA DA SILVA" => status(:active))
    result = STF::ProcessLookup.new(http: Http.new(detail: detail), discovery: discovery).resolve("classe" => "Rcl", "numeroProcesso" => "101463")
    assert_equal EXPECTED, result
    assert_nil discovery.calls.last.last
  end

  def test_real_discovery_completes_pagination_before_enriching_missing_detail_cnj
    detail = DETAIL.sub(/<div class="processo-rotulo">.*?<\/div>/, "")
    json = JsonPages.new([nil, CNJ])
    lookup = STF::ProcessLookup.new(http: Http.new(detail: detail), discovery: STF::Discovery.new(http: json))
    assert_equal EXPECTED, lookup.resolve("classe" => "Rcl", "numeroProcesso" => "101463")
    assert_equal ["1", "2"], json.queries.map { |query| query.fetch("pagina") }
    assert_equal ["ROBERTO FERREIRA DA SILVA"], json.queries.map { |query| query.fetch("nome") }.uniq
  end

  def test_real_discovery_rejects_conflicting_cnj_on_later_page
    json = JsonPages.new([CNJ, "01882631920261000001"])
    lookup = STF::ProcessLookup.new(http: Http.new, discovery: STF::Discovery.new(http: json))
    assert_raises(STF::InvalidSource) { lookup.resolve("number" => CNJ) }
    assert_equal ["1", "2"], json.queries.map { |query| query.fetch("pagina") }
  end

  def test_class_number_preserves_genuinely_absent_cnj
    detail = DETAIL.sub(/<div class="processo-rotulo">.*?<\/div>/, "")
    discovery = Discovery.new("ROBERTO FERREIRA DA SILVA" => status(:active, cnj: nil))
    result = STF::ProcessLookup.new(http: Http.new(detail: detail), discovery: discovery).resolve("classe" => "Rcl", "numeroProcesso" => "101463")
    assert_equal EXPECTED.merge("cnj" => nil), result
  end

  def test_input_cnj_without_detail_cnj_requires_matching_json_cnj
    detail = DETAIL.sub(/<div class="processo-rotulo">.*?<\/div>/, "")
    discovery = Discovery.new("ROBERTO FERREIRA DA SILVA" => status(:active))
    assert_equal EXPECTED, STF::ProcessLookup.new(http: Http.new(detail: detail), discovery: discovery).resolve("number" => CNJ)
    assert_equal EXPECTED.fetch("cnj"), discovery.calls.first.last

    [nil, status(:active, cnj: nil)].each do |unconfirmed|
      discovery = Discovery.new("ROBERTO FERREIRA DA SILVA" => unconfirmed)
      assert_raises(STF::InvalidSource) do
        STF::ProcessLookup.new(http: Http.new(detail: detail), discovery: discovery).resolve("number" => CNJ)
      end
    end
  end

  def test_json_cnj_conflict_is_an_error_for_input_and_detail
    [DETAIL, DETAIL.sub(/<div class="processo-rotulo">.*?<\/div>/, "")].each do |detail|
      discovery = Discovery.new("ROBERTO FERREIRA DA SILVA" => status(:active, cnj: "01882631920261000001"))
      assert_raises(STF::InvalidSource) do
        STF::ProcessLookup.new(http: Http.new(detail: detail), discovery: discovery).resolve("number" => CNJ)
      end
    end
    discovery = Discovery.new("ROBERTO FERREIRA DA SILVA" => status(:active, cnj: "01882631920261000001"))
    assert_raises(STF::InvalidSource) do
      STF::ProcessLookup.new(http: Http.new, discovery: discovery).resolve("classe" => "Rcl", "numeroProcesso" => "101463")
    end
  end

  def test_restricted_status_is_ineligible_even_when_detail_is_accessible
    discovery = Discovery.new("ROBERTO FERREIRA DA SILVA" => status(:restricted, cnj: nil),
                              "COMPANHIA RIOGRANDENSE DE SANEAMENTO - CORSAN" => status(:active))
    assert_nil STF::ProcessLookup.new(http: Http.new, discovery: discovery).resolve("number" => CNJ)
    assert_equal ["ROBERTO FERREIRA DA SILVA"], discovery.calls.map(&:first)
  end

  def test_restricted_json_without_cnj_cannot_confirm_input_missing_from_detail
    detail = DETAIL.sub(/<div class="processo-rotulo">.*?<\/div>/, "")
    [nil, "********"].each do |masked_cnj|
      json = JsonPages.new([masked_cnj], publicity: "Sigiloso")
      lookup = STF::ProcessLookup.new(http: Http.new(detail: detail), discovery: STF::Discovery.new(http: json))
      assert_raises(STF::InvalidSource) { lookup.resolve("number" => CNJ) }
    end
  end

  def test_restricted_json_allows_ineligibility_when_identity_is_confirmed
    detail_without_cnj = DETAIL.sub(/<div class="processo-rotulo">.*?<\/div>/, "")
    [
      [DETAIL, nil, { "number" => CNJ }],
      [detail_without_cnj, CNJ, { "number" => CNJ }],
      [detail_without_cnj, nil, { "classe" => "Rcl", "numeroProcesso" => "101463" }]
    ].each do |detail, json_cnj, criteria|
      json = JsonPages.new([json_cnj], publicity: "Sigiloso")
      lookup = STF::ProcessLookup.new(http: Http.new(detail: detail), discovery: STF::Discovery.new(http: json))
      assert_nil lookup.resolve(criteria)
    end
  end

  def test_restricted_json_with_conflicting_cnj_is_rejected
    detail = DETAIL.sub(/<div class="processo-rotulo">.*?<\/div>/, "")
    json = JsonPages.new(["01882631920261000001"], publicity: "Sigiloso")
    lookup = STF::ProcessLookup.new(http: Http.new(detail: detail), discovery: STF::Discovery.new(http: json))
    assert_raises(STF::InvalidSource) { lookup.resolve("number" => CNJ) }
  end

  def test_unconfirmed_restricted_party_cannot_be_overridden_by_later_public_identity
    detail = DETAIL.sub(/<div class="processo-rotulo">.*?<\/div>/, "")
    discovery = Discovery.new("ROBERTO FERREIRA DA SILVA" => status(:restricted, cnj: nil),
                              "COMPANHIA RIOGRANDENSE DE SANEAMENTO - CORSAN" => status(:active))
    lookup = STF::ProcessLookup.new(http: Http.new(detail: detail), discovery: discovery)
    assert_raises(STF::InvalidSource) { lookup.resolve("number" => CNJ) }
  end

  def test_old_or_malformed_discovery_status_is_rejected
    [:active, { state: :active }, { state: :active, cnj: CNJ }, { state: :unknown, cnj: nil }].each do |invalid|
      discovery = Discovery.new("ROBERTO FERREIRA DA SILVA" => invalid)
      assert_raises(STF::InvalidSource) { STF::ProcessLookup.new(http: Http.new, discovery: discovery).resolve("number" => CNJ) }
    end
  end

  def test_nonempty_malformed_cnj_in_detail_is_rejected_for_class_lookup
    detail = DETAIL.sub(CNJ, "123")
    assert_raises(STF::InvalidSource) do
      STF::ProcessLookup.new(http: Http.new(detail: detail), discovery: Discovery.new({})).resolve("classe" => "Rcl", "numeroProcesso" => "101463")
    end
  end
end
