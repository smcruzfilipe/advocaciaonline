require "test_helper"
require "mail"

class PasswordResetMailerTest < ActiveSupport::TestCase
  setup do
    # Initialize Mail's lazy default transport before replacing the SMTP factory.
    Mail.new
    @smtp = { "host" => "smtp.example.test", "port" => 587, "username" => "user",
      "password" => "smtp-secret", "from" => "service@example.test" }
  end

  test "reset mail requires STARTTLS and carries the token only in a fragment" do
    token = SecureRandom.urlsafe_base64(32)
    message = capture do
      PasswordResetMailer.deliver!(email: "Person@example.test", token: token)
    end
    link = "#{AppSettings.origin}/reset-password#token=#{token}"
    assert_equal "multipart/alternative", message.mime_type
    assert_includes message.text_part.decoded, link
    action = Nokogiri::HTML(message.html_part.decoded).css("a").find { |anchor| anchor.text.strip == "Definir nova senha" }
    assert_not_nil action
    assert_equal link, action["href"]
    refute_includes message.header.to_s, token
    refute_includes message.text_part.decoded, "?token="
  end

  test "password change confirmation contains the original notice and a login action" do
    message = capture do
      PasswordResetMailer.deliver_changed!(email: "person@example.test")
    end

    assert_equal "multipart/alternative", message.mime_type
    assert_equal "Sua senha foi alterada no Advocacia Online", message.subject
    assert_includes message.text_part.decoded, "A senha da sua conta no Advocacia Online foi alterada."
    assert_includes message.text_part.decoded, "#{AppSettings.origin}/reset-password"
    html = Nokogiri::HTML(message.html_part.decoded)
    assert_includes html.text, "Confirmação de alteração de senha"
    assert_includes html.text, "Senha alterada"
    action = html.css("a").find { |anchor| anchor.text.strip == "Ir para o login" }
    assert_not_nil action
    assert_equal "#{AppSettings.origin}/login", action["href"]
  end


  test "transport failures strip SMTP text and cause for both mail types" do
    token = SecureRandom.urlsafe_base64(32)
    transport = Object.new
    transport.define_singleton_method(:deliver!) { |_| raise "SMTP content #{token} smtp-secret" }
    AppSettings.stub(:smtp, @smtp) do
      Mail::SMTP.stub(:new, transport) do
        [-> { PasswordResetMailer.deliver!(email: "person@example.test", token: token) },
          -> { PasswordResetMailer.deliver_changed!(email: "person@example.test") }].each do |operation|
          error = assert_raises(PasswordResetMailer::DeliveryFailed, &operation)
          refute_includes error.message, token
          refute_includes error.message, "smtp-secret"
          assert_nil error.cause
        end
      end
    end
  end

  test "malformed token and recipient never reach SMTP" do
    Mail::SMTP.stub(:new, ->(*) { flunk "Invalid input reached SMTP" }) do
      assert_raises(PasswordResetMailer::DeliveryFailed) do
        PasswordResetMailer.deliver!(email: "person@example.test", token: "bad")
      end
      AppSettings.stub(:smtp, @smtp) do
        assert_raises(PasswordResetMailer::DeliveryFailed) do
          PasswordResetMailer.deliver!(email: "person@example.test\r\nBcc: other@example.test", token: SecureRandom.urlsafe_base64(32))
        end
      end
    end
  end

  private

  def capture
    captured = nil
    transport = Object.new
    transport.define_singleton_method(:deliver!) { |message| captured = message }
    factory = lambda do |settings|
      assert_equal :always, settings.fetch(:enable_starttls)
      transport
    end
    AppSettings.stub(:smtp, @smtp) do
      Mail::SMTP.stub(:new, factory) { yield }
    end
    captured
  end
end
