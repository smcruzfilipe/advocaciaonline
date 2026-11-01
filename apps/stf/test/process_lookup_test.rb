require "minitest/autorun"
require "uri"
require_relative "../lib/stf/process_lookup"

class ProcessLookupTest < Minitest::Test
  CNJ = "0188263-19.2026.1.00.0000".freeze
  EXPECTED = { "incidente" => 7728350, "cnj" => CNJ, "classe" => "Rcl", "identificacao" => "Rcl 101463", "publicidade" => "Público" }.freeze
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
      (url.include?("abaPartes.asp") ? @parties : @detail).b
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

  def test_cnj_resolves_detail_and_real_parties_until_positive_confirmation
    http = Http.new
    discovery = Discovery.new("ROBERTO FERREIRA DA SILVA" => :active)
    result = STF::ProcessLookup.new(http: http, discovery: discovery).resolve("number" => "01882631920261000000")
    assert_equal EXPECTED, result
    assert_equal "01882631920261000000", URI.decode_www_form(URI(http.urls.first).query).to_h.fetch("numeroUnico")
    assert_equal "https://portal.stf.jus.br/processos/abaPartes.asp?incidente=7728350", http.urls.last
    assert_equal [["COMPANHIA RIOGRANDENSE DE SANEAMENTO - CORSAN", 7728350, CNJ], ["ROBERTO FERREIRA DA SILVA", 7728350, CNJ]], discovery.calls
  end

  def test_class_and_number_resolve_and_explicit_inactive_is_not_eligible
    http = Http.new
    discovery = Discovery.new("ROBERTO FERREIRA DA SILVA" => :inactive)
    result = STF::ProcessLookup.new(http: http, discovery: discovery).resolve("classe" => "Rcl", "numeroProcesso" => "101463")
    assert_nil result
    assert_equal({ "classe" => "Rcl", "numeroProcesso" => "101463" }, URI.decode_www_form(URI(http.urls.first).query).to_h)
  end

  def test_an_explicit_inactive_record_does_not_prevent_a_later_active_confirmation
    discovery = Discovery.new("COMPANHIA RIOGRANDENSE DE SANEAMENTO - CORSAN" => :inactive, "ROBERTO FERREIRA DA SILVA" => :active)
    assert_equal EXPECTED, STF::ProcessLookup.new(http: Http.new, discovery: discovery).resolve("number" => CNJ)
  end

  def test_decodes_declared_legacy_detail_and_parties
    detail = ("<meta charset='ISO-8859-1'>" + DETAIL).encode("ISO-8859-1")
    parties = ("<meta charset='ISO-8859-1'>" + PARTIES).encode("ISO-8859-1")
    discovery = Discovery.new("ROBERTO FERREIRA DA SILVA" => :active)
    assert_equal EXPECTED, STF::ProcessLookup.new(http: Http.new(detail: detail, parties: parties), discovery: discovery).resolve("number" => CNJ)
    assert_equal "COMPANHIA RIOGRANDENSE DE SANEAMENTO - CORSAN", discovery.calls.first.first
  end

  def test_unknown_status_and_missing_or_malformed_source_fail
    [Http.new, Http.new(detail: "<html>Login</html>"), Http.new(parties: "<html>Login</html>"),
      Http.new(parties: '<div id="todas-partes"><div class="processo-partes"><div class="nome-parte">X</div></div></div>')].each do |http|
      assert_raises(STF::InvalidSource) { STF::ProcessLookup.new(http: http, discovery: Discovery.new({})).resolve("number" => CNJ) }
    end
  end

  def test_rejects_conflicting_identification_and_incomplete_cnj
    lookup = STF::ProcessLookup.new(http: Http.new, discovery: Discovery.new("ROBERTO FERREIRA DA SILVA" => :active))
    assert_raises(STF::InvalidSource) { lookup.resolve("number" => "01882631920261000001") }
    assert_raises(STF::InvalidSource) { lookup.resolve("number" => CNJ, "classe" => "RE", "numeroProcesso" => "1") }
    assert_raises(STF::InvalidSource) { lookup.resolve("number" => "123") }
    assert_raises(STF::InvalidSource) { lookup.resolve("classe" => "Rcl") }
  end
  def test_class_number_without_detail_cnj_can_be_confirmed_by_incidente
    detail = DETAIL.sub(/<div class="processo-rotulo">.*?<\/div>/, "")
    discovery = Discovery.new("ROBERTO FERREIRA DA SILVA" => :active)
    result = STF::ProcessLookup.new(http: Http.new(detail: detail), discovery: discovery).resolve("classe" => "Rcl", "numeroProcesso" => "101463")
    assert_equal EXPECTED.merge("cnj" => nil), result
    assert_nil discovery.calls.last.last
    assert_raises(STF::InvalidSource) do
      STF::ProcessLookup.new(http: Http.new(detail: detail), discovery: discovery).resolve("number" => CNJ)
    end
  end

  def test_restricted_status_is_ineligible_even_when_detail_is_accessible
    discovery = Discovery.new("COMPANHIA RIOGRANDENSE DE SANEAMENTO - CORSAN" => :restricted,
                              "ROBERTO FERREIRA DA SILVA" => :active)
    assert_nil STF::ProcessLookup.new(http: Http.new, discovery: discovery).resolve("number" => CNJ)
  end

  def test_nonempty_malformed_cnj_in_detail_is_rejected_for_class_lookup
    detail = DETAIL.sub(CNJ, "123")
    assert_raises(STF::InvalidSource) do
      STF::ProcessLookup.new(http: Http.new(detail: detail), discovery: Discovery.new({})).resolve("classe" => "Rcl", "numeroProcesso" => "101463")
    end
  end

end
