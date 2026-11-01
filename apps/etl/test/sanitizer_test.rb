require "minitest/autorun"
require_relative "../lib/processador/sanitizer"

class SanitizerTest < Minitest::Test
  def test_converts_source_markup_to_readable_text_without_executable_content
    source = {
      "id" => 123,
      "hash" => "fixed-hash",
      "texto" => "<p>Guilherme&nbsp;Curcelli Guimarães &amp; partes<br><b>Intimação</b></p>" \
        "<script>alert('não executar')</script><style>body{display:none}</style>" \
        "<foo>Conteúdo legítimo</foo>"
    }
    result = Processador::Sanitizer.publication(source)
    assert_equal 123, result.fetch("id")
    assert_equal "fixed-hash", result.fetch("hash")
    assert_includes result.fetch("texto"), "Guilherme Curcelli Guimarães & partes"
    assert_includes result.fetch("texto"), "Intimação"
    assert_includes result.fetch("texto"), "Conteúdo legítimo"
    assert_match(/partes\s*\n\s*Intimação/, result.fetch("texto"))
    refute_match(/<\/?(?:p|b|foo|script|style)\b/i, result.fetch("texto"))
    refute_includes result.fetch("texto"), "não executar"
    refute_includes result.fetch("texto"), "display:none"
    assert_includes source.fetch("texto"), "<script>"
  end

  def test_preserves_only_safe_source_anchors_without_changing_plain_text
    url = "https://www.tjsp.jus.br/download/EPROC/ManuaisPublicoExterno/" \
      "1.1-EPROC_ADVOGADO-Primeiros_passos_no_sistema_eproc_04.04.25.pdf"
    source = { "texto" => "<p>Material de apoio disponível em: <a href= #{url} " \
      "onclick='alert(1)' target='_self'> EPROC_ADVOGADO-Primeiros_passos_no_sistema.PDF </a></p>" \
      "<script>roubar()</script><img src=x onerror='roubar()'>" }
    result = Processador::Sanitizer.publication(source)
    assert_includes result.fetch("texto"), "EPROC_ADVOGADO-Primeiros_passos_no_sistema.PDF"
    refute_includes result.fetch("texto"), "<a"
    parts = result.fetch("texto_parts")
    assert_equal result.fetch("texto"), parts.map { |part| part.fetch("text") }.join
    assert_equal [url], parts.filter_map { |part| part["href"] }
    assert_includes parts.find { |part| part["href"] }.fetch("text"), "EPROC_ADVOGADO-Primeiros_passos_no_sistema.PDF"
    refute_match(/onclick|target=|<script|<img|roubar/, parts.to_s)
  end

  def test_unsafe_and_relative_source_links_remain_inert_text
    %w[javascript:alert(1) data:text/html,test ftp://example.test/file
      https://user:pass@example.test/file //example.test/file /file].each do |url|
      result = Processador::Sanitizer.publication({ "texto" => "<p>Antes <a href='#{url}'>documento</a> depois</p>" })
      assert_equal "Antes documento depois", result.fetch("texto")
      refute result.key?("texto_parts"), url
    end
  end

  def test_link_boundaries_repeated_labels_entities_and_paragraphs_keep_their_positions
    source = { "texto" => "<p>mesmo <a href='https://example.test/one?x=1&amp;y=2'>mesmo</a></p>" \
      "<p><a href='https://example.test/two'><b>Segundo&nbsp;documento</b></a><br>fim</p>" }
    result = Processador::Sanitizer.publication(source)
    parts = result.fetch("texto_parts")
    assert_equal result.fetch("texto"), parts.map { |part| part.fetch("text") }.join
    assert_equal "mesmo ", parts.first.fetch("text")
    refute parts.first.key?("href")
    linked = parts.select { |part| part["href"] }
    assert_equal ["mesmo", "Segundo documento"], linked.map { |part| part.fetch("text") }
    assert_equal ["https://example.test/one?x=1&y=2", "https://example.test/two"], linked.map { |part| part.fetch("href") }
    assert_match(/mesmo\s*\n\s*Segundo documento\s*\n\s*fim/, result.fetch("texto"))
  end

  def test_anchor_at_text_boundaries_and_marker_like_source_text_are_not_lost
    result = Processador::Sanitizer.publication({
      "texto" => "<a href='https://example.test/manual'> documento </a> AO_PUBLICATION_LINK_0_START"
    })
    assert_equal "documento  AO_PUBLICATION_LINK_0_START", result.fetch("texto")
    assert_equal result.fetch("texto"), result.fetch("texto_parts").map { |part| part.fetch("text") }.join
    assert_equal "documento ", result.fetch("texto_parts").first.fetch("text")
  end

  def test_encoded_unsafe_links_and_source_supplied_metadata_cannot_create_anchors
    result = Processador::Sanitizer.publication({
      "texto" => "<a href='java&#x73;cript:alert(1)'>rótulo</a>",
      "texto_parts" => [{ "text" => "rótulo", "href" => "https://forged.test" }],
      "texto_plain" => "falso"
    })
    assert_equal "rótulo", result.fetch("texto")
    refute result.key?("texto_parts")
    refute result.key?("texto_plain")
  end

  def test_caderno_presentation_adds_only_derived_metadata_and_keeps_the_original_payload
    source = { "id" => 51, "hash" => "same", "texto" =>
      "<p>Manual <a href='https://example.test/manual.pdf' onclick='alert(1)'>PDF</a></p><script>secret()</script>" }
    result = Processador::Sanitizer.presentation(source)
    assert_equal source, result.reject { |key, _| %w[texto_parts texto_plain].include?(key) }
    assert_equal "Manual PDF", result.fetch("texto_plain")
    assert_equal [{ "text" => "Manual " }, { "text" => "PDF", "href" => "https://example.test/manual.pdf" }], result.fetch("texto_parts")
    refute_match(/secret|onclick|<p>/, result.fetch("texto_parts").to_s)
    plain = source.merge("texto" => "texto comum")
    assert_equal plain, Processador::Sanitizer.presentation(plain)
  end

  def test_decodes_entities_once_and_preserves_text_that_must_be_escaped_by_consumers
    source = { "texto" => "&lt;script&gt;exemplo&lt;/script&gt; &amp;#169; &#169;" }
    result = Processador::Sanitizer.publication(source)
    assert_equal "<script>exemplo</script> &#169; ©", result.fetch("texto")
  end

  def test_keeps_missing_or_non_string_text_and_source_identity_unchanged
    [ { "id" => 1 }, { "texto" => nil }, { "texto" => 123 } ].each do |source|
      assert_equal source, Processador::Sanitizer.publication(source)
    end
  end

  def test_non_text_publications_discard_forged_presentation_metadata_in_both_paths
    [{ "id" => 9 }, { "id" => 9, "texto" => nil }, { "id" => 9, "texto" => 123 }].each do |expected|
      source = expected.merge(
        "texto_parts" => [{ "text" => "conteúdo forjado", "href" => "https://forged.test/manual.pdf" }],
        "texto_plain" => "conteúdo forjado"
      )
      assert_equal expected, Processador::Sanitizer.presentation(source)
      assert_equal expected, Processador::Sanitizer.publication(source)
    end
  end
end
