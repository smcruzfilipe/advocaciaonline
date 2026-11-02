require "test_helper"

class AppSettingsTest < ActiveSupport::TestCase
  test "SMTP requires all settings and validates the port" do
    keys = %w[SMTP_HOST SMTP_PORT SMTP_USERNAME SMTP_PASSWORD SMTP_FROM]
    previous = keys.to_h { |key| [key, ENV[key]] }
    keys.each { |key| ENV.delete(key) }
    assert_raises(KeyError) { AppSettings.smtp }

    ENV.update("SMTP_HOST" => "smtp.example.test", "SMTP_PORT" => "587",
      "SMTP_USERNAME" => "user", "SMTP_PASSWORD" => "test-secret", "SMTP_FROM" => "sender@example.test")
    assert_equal 587, AppSettings.smtp.fetch("port")
    ENV["SMTP_PORT"] = "65536"
    assert_raises(ArgumentError) { AppSettings.smtp }
    ENV["SMTP_PORT"] = "abc"
    assert_raises(ArgumentError) { AppSettings.smtp }
    ENV["SMTP_PASSWORD"] = ""
    assert_raises(ArgumentError) { AppSettings.smtp }
  ensure
    previous&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
