require "minitest/autorun"
require "date"
require "time"
require_relative "../lib/stf/andamentos"

class AndamentosTest < Minitest::Test
  PROCESSO = { "incidente" => 7051926, "cnj" => "0803599-58.2023.4.05.8300", "classe" => "RE", "identificacao" => "RE 1519008" }.freeze
  DATA = Date.new(2026, 5, 5)
  CAPTURA = Time.iso8601("2026-05-05T12:00:00-03:00")

  class Http
    attr_reader :url
    def initialize(body) = @body = body
    def get(url)
      @url = url
      @body.b
    end
  end

  def item(date:, title:, observation: "", judge: "", links: "")
    <<~HTML
      <li><div class="andamento-item"><div class="andamento-detalhe">
        <div class="andamento-data">#{date}</div><h5 class="andamento-nome">#{title}</h5>
        <div class="hint-msg">Explicação genérica <a href="https://example.test/hint">https://example.test/hint</a></div>
        <div class="andamento-docs">#{links}</div>
        <span class="andamento-julgador">#{judge}</span><div class="col-md-9 p-0">#{observation}</div>
      </div></div></li>
    HTML
  end

  def fetch(items)
    http = Http.new("<div class='processo-andamentos m-t-8'><ul>#{items}</ul></div>")
    [STF::Andamentos.new(http: http).fetch(process: PROCESSO, date: DATA, captured_at: CAPTURA), http.url]
  end

  def test_preserves_item_scoped_links_text_metadata_and_multiplicity
    one = item(date: "05/05/2026", title: "Juntada &amp; análise", judge: "Min. Relator", observation: "Divulgado em 04/05/2026. https://digital.stf.jus.br/publico/publicacao/922824", links: '<a href="downloadPeca.asp?id=1&amp;ext=.pdf">Peça &amp; decisão</a><a href="https://externo.example/a">Outro</a><a href="javascript:alert(1)">Inseguro</a>')
    other = item(date: "04/05/2026", title: "Antigo", links: '<a href="downloadPeca.asp?id=1&amp;ext=.pdf">Peça</a>')
    results, url = fetch(one + one + other)
    assert_equal 2, results.size
    assert_equal results[0], results[1]
    result = results.first
    assert_equal "https://portal.stf.jus.br/processos/abaAndamentos.asp?incidente=7051926&imprimir=", url
    assert_equal "https://portal.stf.jus.br/processos/detalhe.asp?incidente=7051926", result.fetch("link")
    assert_equal "STF", result.fetch("siglaTribunal")
    assert_equal PROCESSO.fetch("cnj"), result.fetch("numero_processo")
    assert_equal "RE", result.fetch("nomeClasse")
    assert_equal "Juntada & análise\nMin. Relator\nDivulgado em 04/05/2026. https://digital.stf.jus.br/publico/publicacao/922824", result.fetch("texto")
    detail = result.fetch("stf")
    assert_equal 7051926, detail.fetch("incidente")
    assert_equal "RE 1519008", detail.fetch("identificacao")
    assert_equal "2026-05-05", detail.fetch("data_andamento")
    assert_equal "Juntada & análise", detail.fetch("titulo")
    assert_equal "Min. Relator", detail.fetch("julgador")
    assert_equal "Divulgado em 04/05/2026. https://digital.stf.jus.br/publico/publicacao/922824", detail.fetch("observacao")
    assert_equal url, detail.fetch("url_coleta")
    assert_equal CAPTURA.iso8601, detail.fetch("capturado_em")
    assert_equal [
      { "url" => "https://portal.stf.jus.br/processos/downloadPeca.asp?id=1&ext=.pdf", "rotulo" => "Peça & decisão", "referencia_original" => "downloadPeca.asp?id=1&ext=.pdf" },
      { "url" => "https://externo.example/a", "rotulo" => "Outro", "referencia_original" => "https://externo.example/a" },
      { "url" => "https://digital.stf.jus.br/publico/publicacao/922824", "rotulo" => nil, "referencia_original" => "https://digital.stf.jus.br/publico/publicacao/922824" }
    ], detail.fetch("links")
  end

  def test_shared_piece_remains_attached_to_each_event_and_urls_in_text_are_scoped
    first = item(date: "05/05/2026", title: "Primeiro", links: '<a href="downloadPeca.asp?id=42">Peça</a> Texto https://example.test/outro.')
    second = item(date: "05/05/2026", title: "Segundo", links: '<a href="downloadPeca.asp?id=42">Peça</a>')
    items, = fetch(first + second)
    assert_equal ["Primeiro", "Segundo"], items.map { |entry| entry.dig("stf", "titulo") }
    assert_equal ["https://portal.stf.jus.br/processos/downloadPeca.asp?id=42", "https://example.test/outro"], items[0].dig("stf", "links").map { |link| link.fetch("url") }
    assert_equal ["https://portal.stf.jus.br/processos/downloadPeca.asp?id=42"], items[1].dig("stf", "links").map { |link| link.fetch("url") }
  end

  def test_textual_urls_preserve_balanced_parentheses_and_original_punctuation
    results, = fetch(item(date: "05/05/2026", title: "Peça", observation: "Peça https://example.test/documento_(1). Outro (https://example.test/outro)."))
    assert_equal [
      { "url" => "https://example.test/documento_(1)", "rotulo" => nil, "referencia_original" => "https://example.test/documento_(1)." },
      { "url" => "https://example.test/outro", "rotulo" => nil, "referencia_original" => "https://example.test/outro)." }
    ], results.first.dig("stf", "links")
  end

  def test_unicode_anchor_and_text_urls_are_encoded_without_losing_original_references
    anchor = "https://example.test/decisão.pdf?nome=ação#página%202"
    textual = "https://example.test/peça_(1)"
    results, = fetch(item(date: "05/05/2026", title: "Peça", observation: textual, links: "<a href='#{anchor}'>Decisão</a>"))
    assert_equal [
      { "url" => "https://example.test/decis%C3%A3o.pdf?nome=a%C3%A7%C3%A3o#p%C3%A1gina%202", "rotulo" => "Decisão", "referencia_original" => anchor },
      { "url" => "https://example.test/pe%C3%A7a_(1)", "rotulo" => nil, "referencia_original" => textual }
    ], results.first.dig("stf", "links")
  end

  def test_optional_fields_and_empty_day
    results, = fetch(item(date: "05/05/2026", title: "Protocolo"))
    assert_nil results.first.dig("stf", "julgador")
    assert_nil results.first.dig("stf", "observacao")
    assert_equal "Protocolo", results.first.fetch("texto")
    assert_equal [], fetch("").first
    assert_equal [], fetch(item(date: "04/05/2026", title: "Antigo")).first
  end

  def test_decodes_declared_legacy_html_and_rejects_undeclared_invalid_bytes
    html = "<meta charset='ISO-8859-1'><div class='processo-andamentos'><ul>#{item(date: '05/05/2026', title: 'Decisão')}</ul></div>".encode("ISO-8859-1")
    result = STF::Andamentos.new(http: Http.new(html)).fetch(process: PROCESSO, date: DATA, captured_at: CAPTURA)
    assert_equal "Decisão", result.first.dig("stf", "titulo")
    assert_raises(STF::InvalidSource) do
      STF::Andamentos.new(http: Http.new("\xFF".b)).fetch(process: PROCESSO, date: DATA, captured_at: CAPTURA)
    end
  end

  def test_rejects_truncated_list_or_container_even_after_complete_items
    movement = item(date: "05/05/2026", title: "Protocolo")
    inner_list = item(date: "05/05/2026", title: "Protocolo", observation: "<ul><li>Detalhe</li></ul>")
    [
      "<div class='processo-andamentos'><ul>",
      "<div class='processo-andamentos'><ul>#{movement}",
      "<div class='processo-andamentos'><ul>#{movement}</ul>",
      "<div class='processo-andamentos'><ul></ul>",
      "<div class='processo-andamentos'><ul></div>",
      "<div class='processo-andamentos'><ul>#{movement}</div>",
      "<div class='processo-andamentos'><ul>#{inner_list}</div>",
      "<div class='processo-andamentos'><ul>#{movement}</u",
      "<div class='processo-andamentos'><ul><li><div class='andamento-item'><div class='andamento-data'>05/05/2026</div><div class='andamento-nome'>Título</div></ul></div>",
      "<div class='processo-andamentos'><ul><li><div class='andamento-item'><div class='andamento-data'>05/05/2026</div><div class='andamento-nome'>Título</div></li></ul></div>"
    ].each do |html|
      assert_raises(STF::InvalidSource, html) do
        STF::Andamentos.new(http: Http.new(html)).fetch(process: PROCESSO, date: DATA, captured_at: CAPTURA)
      end
    end
  end

  def test_accepts_complete_empty_list_with_padding_and_unrelated_legacy_errors
    html = "\n \n<div class='processo-andamentos' data-x='1' data-x='2'><ul></ul></div>\n "
    assert_equal [], STF::Andamentos.new(http: Http.new(html)).fetch(process: PROCESSO, date: DATA, captured_at: CAPTURA)
  end

  def test_preserves_complete_outer_list_with_nested_list
    movement = item(date: "05/05/2026", title: "Protocolo", observation: "<ul><li>Detalhe</li></ul>", links: '<a href="downloadPeca.asp?id=1">Peça</a>')
    results, = fetch(movement + movement)
    assert_equal 2, results.size
    assert_equal results.first, results.last
    assert_equal "https://portal.stf.jus.br/processos/downloadPeca.asp?id=1", results.first.dig("stf", "links", 0, "url")
  end

  def test_rejects_invalid_or_incomplete_source_instead_of_silent_empty_results
    ["<html><form>Login</form></html>", "<div class='processo-andamentos'></div>",
      "<div class='processo-andamentos'><ul><li>truncado</li></ul></div>",
      "<div class='processo-andamentos'><ul>#{item(date: '31/02/2026', title: 'Inválido')}</ul></div>",
      "<div class='processo-andamentos'><ul>#{item(date: '04/05/2026', title: '')}</ul></div>"].each do |html|
      assert_raises(STF::InvalidSource) { STF::Andamentos.new(http: Http.new(html)).fetch(process: PROCESSO, date: DATA, captured_at: CAPTURA) }
    end
  end
end
