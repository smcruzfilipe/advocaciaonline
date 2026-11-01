require "test_helper"
require "net/smtp"

class VerificationMailerTest < ActiveSupport::TestCase
  test "sends a single-use fragment link using required STARTTLS" do
    smtp = { "host" => "smtp.example.test", "port" => 587, "username" => "user",
      "password" => "secret", "from" => "service@example.test" }
    token = SecureRandom.urlsafe_base64(32)
    captured = nil
    transport = Object.new
    transport.define_singleton_method(:deliver!) { |message| captured = message }
    factory = lambda do |settings|
      assert_equal :always, settings.fetch(:enable_starttls)
      assert_equal "smtp.example.test", settings.fetch(:address)
      transport
    end
    AppSettings.stub(:smtp, smtp) do
      Mail::SMTP.stub(:new, factory) { VerificationMailer.deliver!(email: "person@example.test", token: token) }
    end
    assert_equal ["person@example.test"], captured.to
    assert_includes captured.body.decoded, "#{AppSettings.origin}/verify-email#token=#{token}"
    refute_includes captured.header.to_s, token
  end

  test "delivery failures do not expose SMTP response or token" do
    smtp = { "host" => "smtp.example.test", "port" => 587, "username" => "user",
      "password" => "secret", "from" => "service@example.test" }
    token = SecureRandom.urlsafe_base64(32)
    transport = Object.new
    transport.define_singleton_method(:deliver!) { |_| raise "SMTP leaked #{token}" }
    AppSettings.stub(:smtp, smtp) do
      Mail::SMTP.stub(:new, transport) do
        error = assert_raises(VerificationMailer::DeliveryFailed) do
          VerificationMailer.deliver!(email: "person@example.test", token: token)
        end
        refute_includes error.message, token
        assert_nil error.cause
      end
    end
  end
end
