require "test_helper"

class PlatformAdminProvisioningTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @operator = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    assert_equal "advocacia_migrator", @operator.exec("SELECT current_user").getvalue(0, 0)
    @operator.exec("BEGIN")
  end

  teardown do
    @operator.exec("ROLLBACK")
    @operator.close
  end

  test "operator provisions one administrator with hashed recovery codes without a session" do
    email = "platform-#{SecureRandom.hex(12)}@example.test"
    password = "synthetic administrator password"
    secret = PasswordAuthentication.new_secret
    codes = PasswordAuthentication.new_recovery_codes
    identity = @operator.exec_params(
      "INSERT INTO app_private.identities(verified_email) VALUES ($1) RETURNING id", [email]
    ).getvalue(0, 0)
    @operator.exec_params(
      "INSERT INTO app_private.password_credentials(identity_id,password_hash,totp_secret) VALUES ($1,$2,$3)",
      [identity, PasswordAuthentication.password_hash(password), PasswordAuthentication.encrypt(secret)]
    )
    @operator.exec_params("INSERT INTO app_private.platform_administrator(identity_id) VALUES ($1)", [identity])
    codes.each do |code|
      @operator.exec_params("INSERT INTO app_private.platform_recovery_codes(identity_id,code_hash) VALUES ($1,$2)",
        [identity, PasswordAuthentication.recovery_code_hash(code)])
    end

    credential = @operator.exec_params("SELECT * FROM app_private.password_credentials WHERE identity_id=$1", [identity]).first
    assert PasswordAuthentication.valid_password?(password, credential.fetch("password_hash"))
    assert_equal secret, PasswordAuthentication.decrypt(credential.fetch("totp_secret"))
    assert_equal "f", credential.fetch("totp_confirmed")
    stored = @operator.exec_params("SELECT code_hash FROM app_private.platform_recovery_codes WHERE identity_id=$1", [identity]).column_values(0)
    assert_equal codes.map { |code| PasswordAuthentication.recovery_code_hash(code) }.sort, stored.sort
    assert_empty stored & codes
    assert_equal "0", @operator.exec_params("SELECT count(*) FROM app_private.sessions WHERE identity_id=$1", [identity]).getvalue(0, 0)

    other = @operator.exec_params("INSERT INTO app_private.identities(verified_email) VALUES ($1) RETURNING id",
      ["second-#{email}"]).getvalue(0, 0)
    assert_raises(PG::UniqueViolation) do
      @operator.exec_params("INSERT INTO app_private.platform_administrator(identity_id) VALUES ($1)", [other])
    end
  end

  test "runtime cannot grant itself platform administration or inject recovery codes" do
    PG.connect(ENV.fetch("DATABASE_URL")) do |runtime|
      assert_equal "advocacia_runtime", runtime.exec("SELECT current_user").getvalue(0, 0)
      assert_raises(PG::InsufficientPrivilege) do
        runtime.exec_params("INSERT INTO app_private.platform_administrator(identity_id) VALUES ($1)", [SecureRandom.uuid])
      end
      assert_raises(PG::InsufficientPrivilege) do
        runtime.exec_params("INSERT INTO app_private.platform_recovery_codes(identity_id,code_hash) VALUES ($1,$2)",
          [SecureRandom.uuid, "a" * 64])
      end
    end
  end
end
