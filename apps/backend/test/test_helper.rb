ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

class ActiveSupport::TestCase
  self.use_transactional_tests = true

  def with_fixture_database
    raise "Refusing fixtures outside test" unless Rails.env.test?
    PG.connect(ENV.fetch("MIGRATION_DATABASE_URL")) do |db|
      target = db.exec("SELECT current_database(), inet_server_addr()::text, inet_server_port()").first
      runtime = ApplicationRecord.connection.select_rows("SELECT current_database(), inet_server_addr()::text, inet_server_port()").first
      unless db.user == "advocacia_migrator" && target.values == runtime.map { |value| value&.to_s } &&
          target.fetch("current_database").match?(/\Aadvocacia_test(?:_|\z)/)
        raise "Refusing fixtures on different or non-test databases"
      end
      yield db
    end
  end

  def fixture_identity(email:, password:, secret:, verified:)
    with_fixture_database do |db|
      db.transaction do
        id = db.exec_params(
          "INSERT INTO app_private.identities(verified_email, email_verified_at) VALUES ($1, CASE WHEN $2::boolean THEN clock_timestamp() END) RETURNING id",
          [email.downcase, verified]
        ).getvalue(0, 0)
        db.exec_params(
          "INSERT INTO app_private.password_credentials(identity_id, password_hash, totp_secret) VALUES ($1, $2, $3)",
          [id, PasswordAuthentication.password_hash(password), PasswordAuthentication.encrypt(secret)]
        )
        id
      end
    end
  end

  def grant_fixture_owner(identity_id)
    with_fixture_database do |db|
      db.exec_params("INSERT INTO app_private.first_access_grants(identity_id) VALUES ($1) ON CONFLICT DO NOTHING", [identity_id])
    end
  end

  def authenticated_session(subject: SecureRandom.uuid, email: nil, owner: false)
    email = (email || "#{subject}@example.test").downcase
    row = IdentityStore.call("password_lookup", email)
    unless row
      fixture_identity(email: email, password: "test-password-#{subject}", secret: PasswordAuthentication.new_secret, verified: true)
      row = IdentityStore.call("password_lookup", email)
    end
    grant_fixture_owner(row.fetch("identity_id")) if owner
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
