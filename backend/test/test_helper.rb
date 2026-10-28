ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

class ActiveSupport::TestCase
  self.use_transactional_tests = true

  def authenticated_session(subject: SecureRandom.uuid)
    token = SecureRandom.urlsafe_base64(32)
    csrf = SecureRandom.urlsafe_base64(32)
    IdentityStore.authenticate(subject: subject, email: "lawyer@example.test", token: token, csrf: csrf)
    [token, csrf]
  end

  def profile_payload
    { "full_name" => "  Ana   de Ávila  ", "office_name" => "  Ávila Advocacia ",
      "primary_oab" => { "number" => " 001234-A ", "uf" => " sp " },
      "secondary_oabs" => [{ "number" => "00a-B", "uf" => "rj" }] }
  end
end
