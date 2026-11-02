require "test_helper"
require "mail"
require "net/smtp"

class VerificationMailerTest < ActiveSupport::TestCase
  class CapturingSmtp < Net::SMTP
    attr_reader :message
    attr_accessor :delivery_error

    def initialize
      super("smtp.example.test", 587)
    end

    def start(*)
      yield self
    end

    def sendmail(source, *)
      raise delivery_error if delivery_error
      @message = Mail.read_from_string(source)
    end
  end

  test "delivers a usable verification fragment without exposing it in headers and requires TLS" do
    smtp = { "host" => "smtp.example.test", "port" => 587, "username" => "user",
      "password" => "secret", "from" => "service@example.test" }
    token = SecureRandom.urlsafe_base64(32)
    transport = CapturingSmtp.new
    AppSettings.stub(:smtp, smtp) do
      Net::SMTP.stub(:new, transport) { VerificationMailer.deliver!(email: "person@example.test", token: token) }
    end
    assert_equal ["person@example.test"], transport.message.to
    assert_equal "multipart/alternative", transport.message.mime_type
    link = URI(transport.message.text_part.decoded.lines.map(&:strip).find { |line| line.start_with?("https://") })
    assert_equal "#{AppSettings.origin}/verify-email", "#{link.scheme}://#{link.host}#{link.port == 443 ? '' : ":#{link.port}"}#{link.path}"
    assert_nil link.query
    assert_equal({ "token" => token }, URI.decode_www_form(link.fragment).to_h)
    action = Nokogiri::HTML(transport.message.html_part.decoded).css("a").find { |anchor| anchor.text.strip == "Confirmar meu e-mail" }
    assert_not_nil action
    assert_equal link.to_s, action["href"]
    refute_includes transport.message.header.to_s, token
    assert transport.starttls_always?
    assert transport.tls_verify
  end

  test "delivery failures do not expose SMTP response or token" do
    smtp = { "host" => "smtp.example.test", "port" => 587, "username" => "user",
      "password" => "secret", "from" => "service@example.test" }
    token = SecureRandom.urlsafe_base64(32)
    transport = CapturingSmtp.new
    transport.delivery_error = RuntimeError.new("SMTP leaked #{token}")
    AppSettings.stub(:smtp, smtp) do
      Net::SMTP.stub(:new, transport) do
        error = assert_raises(VerificationMailer::DeliveryFailed) do
          VerificationMailer.deliver!(email: "person@example.test", token: token)
        end
        refute_includes error.message, token
        assert_nil error.cause
      end
    end
  end
end
