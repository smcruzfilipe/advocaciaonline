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
    assert_includes message.body.decoded, "#{AppSettings.origin}/reset-password#token=#{token}"
    refute_includes message.header.to_s, token
    refute_includes message.body.decoded, "?token="
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
