ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

class ActiveSupport::TestCase
  self.use_transactional_tests = true

  def authenticated_session(subject: SecureRandom.uuid, email: nil)
    email ||= "#{subject}@example.test"
    email = email.downcase
    password = "test-password-#{subject}"
    row = IdentityStore.call("password_lookup", email)
    unless row
      verification = SecureRandom.urlsafe_base64(32)
      IdentityStore.call("register_password", IdentityStore.digest(verification), IdentityStore.digest(verification), email,
        PasswordAuthentication.password_hash(password), PasswordAuthentication.encrypt(PasswordAuthentication.new_secret))
      raise "verification failed" unless IdentityStore.call("verify_password_email", IdentityStore.digest(verification), IdentityStore.digest(verification)).fetch("verified")
      row = IdentityStore.call("password_lookup", email)
    end
    challenge = SecureRandom.urlsafe_base64(32)
    IdentityStore.call("create_password_challenge", row.fetch("identity_id"), IdentityStore.digest(challenge), row.fetch("password_hash"))
    token = SecureRandom.urlsafe_base64(32)
    csrf = SecureRandom.urlsafe_base64(32)
    @test_totp_step = [@test_totp_step.to_i + 1, (Time.now.to_f * 1_000_000).to_i].max
    result = IdentityStore.call("finish_password_challenge", IdentityStore.digest(challenge),
      @test_totp_step.to_s, IdentityStore.digest(token), csrf, "")
    raise "authentication failed" unless result.fetch("created")
    [token, csrf]
  end

  def profile_payload
    { "full_name" => "  Ana   de Ávila  ", "office_name" => "  Ávila Advocacia ",
      "primary_oab" => { "number" => " 001234-A ", "uf" => " sp " },
      "secondary_oabs" => [{ "number" => "00a-B", "uf" => "rj" }] }
  end
end
