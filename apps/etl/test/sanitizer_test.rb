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
end
