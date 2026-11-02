require "test_helper"
require "mail"
require "nokogiri"

class EmailTemplateTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "plain text and HTML preserve the same actionable fragment through MIME encoding" do
    url = "https://example.test/invite/accept#token=opaque%2Bvalue%2Fpart%3F%26%3D"
    text = "Você recebeu um convite.\n\n#{url}\n\nUso único; válido por 24 horas.\n"
    message = Mail.new(from: "service@example.test", to: "person@example.test", subject: "Convite")
    EmailTemplate.apply(message, text: text, title: "Convite para sua equipe",
      action_label: "Aceitar convite e entrar", action_url: url)

    decoded = Mail.read_from_string(message.encoded)
    assert_equal "multipart/alternative", decoded.mime_type
    assert_equal ["text/plain", "text/html"], decoded.parts.map(&:mime_type)
    assert_equal text, decoded.text_part.decoded.force_encoding("UTF-8").gsub("\r\n", "\n")
    html = Nokogiri::HTML(decoded.html_part.decoded.force_encoding("UTF-8"))
    assert_equal [url, url], html.css("a").map { |link| link["href"] }
    assert_equal "Aceitar convite e entrar", html.css("a").first.text.strip
    assert_includes html.text, "Uso único; válido por 24 horas."
    assert_equal "pt-BR", html.at_css("html")["lang"]
    refute_includes decoded.header.to_s, "opaque"
  end

  test "dynamic copy and URL attributes cannot inject HTML or additional recipients" do
    url = "https://example.test/reset-password#token=one&extra=\" onmouseover=\"alert(1)"
    text = "<img src=x onerror=alert(1)> & equipe\n\n#{url}\n\nNão compartilhe este link."
    message = Mail.new(from: "service@example.test", to: "person@example.test")
    EmailTemplate.apply(message, text: text, title: "<script>alert(1)</script>",
      action_label: "<b>Entrar</b>", action_url: url, status: "<img src=x>")

    html = Nokogiri::HTML(message.html_part.decoded)
    assert_empty html.css("script,img,iframe,form")
    assert_empty html.css("[onmouseover],[onerror]")
    assert_equal [url, url], html.css("a").map { |link| link["href"] }
    assert_includes html.text, "<img src=x onerror=alert(1)> & equipe"
    assert_includes html.text, "<script>alert(1)</script>"
    assert_equal ["person@example.test"], message.to
  end

  test "a confirmation with no standalone URL still provides a login action" do
    url = "https://example.test/login"
    text = "A senha foi alterada.\n\nSeu autenticador foi preservado."
    message = Mail.new
    EmailTemplate.apply(message, text: text, title: "Confirmação de alteração de senha",
      action_label: "Ir para o login", action_url: url, status: "Senha alterada")

    html = Nokogiri::HTML(message.html_part.decoded)
    assert_equal url, html.at_css("a")["href"]
    assert_includes html.text, "Seu autenticador foi preservado."
    assert_includes html.text, "Senha alterada"
    assert_equal text, message.text_part.decoded
  end
end
