require "test_helper"

class PlatformAdminAuthorizationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    @runtime = PG.connect(ENV.fetch("DATABASE_URL"))
    assert_equal "advocacia_migrator", @admin.exec("SELECT current_user").getvalue(0, 0)
    assert_equal "advocacia_runtime", @runtime.exec("SELECT current_user").getvalue(0, 0)
    @email = "admin-#{SecureRandom.hex(12)}@example.test"
    @password = "senha sintetica de administradora"
    @password_hash = PasswordAuthentication.password_hash(@password)
    @secret = PasswordAuthentication.new_secret
    @codes = PasswordAuthentication.new_recovery_codes
    @identities = []
    @admin.transaction do |db|
      @id = insert_identity(db, @email)
      db.exec_params("INSERT INTO app_private.password_credentials(identity_id, password_hash, totp_secret, totp_confirmed) VALUES ($1, $2, $3, true)",
        [@id, @password_hash, PasswordAuthentication.encrypt(@secret)])
      db.exec_params("INSERT INTO app_private.platform_administrator(identity_id) VALUES ($1)", [@id])
      @codes.each do |code|
        db.exec_params("INSERT INTO app_private.platform_recovery_codes(identity_id, code_hash) VALUES ($1, $2)",
          [@id, PasswordAuthentication.recovery_code_hash(code)])
      end
    end
  end

  teardown do
    if @admin
      @identities&.each do |id|
        %w[platform_recovery_challenges platform_recovery_codes platform_administrator password_resets password_challenges sessions password_credentials].each do |table|
          @admin.exec_params("DELETE FROM app_private.#{table} WHERE identity_id = $1", [id])
        end
        @admin.exec_params("DELETE FROM app_private.identities WHERE id = $1", [id])
      end
    end
    @runtime&.close
    @admin&.close
  end

  test "runtime cannot assign or read the administrative capability" do
    assert_raises(PG::InsufficientPrivilege) { @runtime.exec("SELECT * FROM app_private.platform_administrator") }
    assert_raises(PG::InsufficientPrivilege) do
      @runtime.exec_params("INSERT INTO app_private.platform_administrator(identity_id) VALUES ($1)", [@id])
    end
    assert_raises(PG::InsufficientPrivilege) { @runtime.exec("SET ROLE advocacia_migrator") }
    assert_equal "f", call("platform_admin_for_session", IdentityStore.digest(SecureRandom.urlsafe_base64(32))).fetch("authorized")
  end

  test "unique capability holds under concurrent migrator transactions" do
    other = insert_identity(@admin, "other-#{SecureRandom.hex(12)}@example.test")
    @admin.exec_params("DELETE FROM app_private.platform_recovery_codes WHERE identity_id = $1", [@id])
    @admin.exec_params("DELETE FROM app_private.platform_administrator WHERE identity_id = $1", [@id])
    ready = Queue.new
    start = Queue.new
    workers = [@id, other].map do |identity|
      Thread.new do
        PG.connect(ENV.fetch("MIGRATION_DATABASE_URL")) do |db|
          db.exec("SET statement_timeout = '10s'")
          ready << true
          start.pop
          begin
            db.exec_params("INSERT INTO app_private.platform_administrator(identity_id) VALUES ($1)", [identity])
            :created
          rescue PG::UniqueViolation
            :conflict
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    assert_equal [:conflict, :created], workers.map(&:value).sort
    assert_equal "1", @admin.exec("SELECT count(*) FROM app_private.platform_administrator").getvalue(0, 0)
  end

  test "recovery consumes a code, blocks sessions and replaces factors only after valid TOTP" do
    old_session = login_session
    assert_equal "t", call("platform_admin_for_session", IdentityStore.digest(old_session)).fetch("authorized")
    assert_nil PasswordAuthentication.begin_platform_recovery(email: @email, password: "incorreta", recovery_code: @codes.first)
    assert_nil PasswordAuthentication.begin_platform_recovery(email: @email, password: @password, recovery_code: SecureRandom.urlsafe_base64(32))
    pending = PasswordAuthentication.begin_platform_recovery(email: @email, password: @password, recovery_code: @codes.first)
    assert pending
    assert_equal "f", call("platform_admin_for_session", IdentityStore.digest(old_session)).fetch("authorized")
    assert_equal "f", call("create_password_challenge", @id, digest_random, @password_hash).fetch("created")
    assert_nil PasswordAuthentication.begin_platform_recovery(email: @email, password: @password, recovery_code: @codes.first)
    assert_nil PasswordAuthentication.confirm_platform_recovery(challenge: pending.fetch(:challenge), code: "000000x")
    assert_equal "f", call("platform_admin_for_session", IdentityStore.digest(old_session)).fetch("authorized")
    code = PasswordAuthentication.code(pending.fetch(:secret), Time.now.to_i / 30)
    new_codes = PasswordAuthentication.confirm_platform_recovery(challenge: pending.fetch(:challenge), code: code)
    assert_nil PasswordAuthentication.confirm_platform_recovery(challenge: pending.fetch(:challenge), code: code)
    stored = @admin.exec_params("SELECT code_hash FROM app_private.platform_recovery_codes WHERE identity_id = $1", [@id]).column_values(0)
    assert_equal new_codes.map { |value| PasswordAuthentication.recovery_code_hash(value) }.sort, stored.sort
    assert_empty stored & @codes.map { |value| PasswordAuthentication.recovery_code_hash(value) }
    assert_equal "f", call("platform_admin_for_session", IdentityStore.digest(old_session)).fetch("authorized")
    assert_nil PasswordAuthentication.begin_platform_recovery(email: @email, password: @password, recovery_code: @codes.last)
    new_session = login_session(secret: pending.fetch(:secret), step: Time.now.to_i / 30 + 1)
    assert_equal "t", call("platform_admin_for_session", IdentityStore.digest(new_session)).fetch("authorized")
  end

  test "password reset keeps the confirmed TOTP and does not create a session" do
    old_session = login_session
    token = SecureRandom.urlsafe_base64(32)
    call("request_password_reset", @email, IdentityStore.digest(token))
    new_hash = PasswordAuthentication.password_hash("outra senha sintetica")
    assert_equal "t", call("confirm_password_reset", IdentityStore.digest(token), new_hash).fetch("changed")
    assert_equal "f", call("confirm_password_reset", IdentityStore.digest(token), new_hash).fetch("changed")
    row = @admin.exec_params("SELECT password_hash, totp_secret, totp_confirmed FROM app_private.password_credentials WHERE identity_id = $1", [@id]).first
    assert_equal new_hash, row.fetch("password_hash")
    assert_equal @secret, PasswordAuthentication.decrypt(row.fetch("totp_secret"))
    assert_equal "t", row.fetch("totp_confirmed")
    assert_equal "f", call("platform_admin_for_session", IdentityStore.digest(old_session)).fetch("authorized")
    assert_equal @codes.length.to_s, @admin.exec_params("SELECT count(*) FROM app_private.platform_recovery_codes WHERE identity_id = $1", [@id]).getvalue(0, 0)
  end

  test "concurrent use of a recovery code has only one winner" do
    ready = Queue.new
    start = Queue.new
    workers = 2.times.map do
      Thread.new do
        PG.connect(ENV.fetch("DATABASE_URL")) do |db|
          db.exec("SET statement_timeout = '10s'")
          secret = PasswordAuthentication.encrypt(PasswordAuthentication.new_secret)
          ready << true
          start.pop
          db.exec_params("SELECT started FROM app_private.platform_recovery_begin($1, $2, $3, $4, $5)",
            [@email, @password_hash, PasswordAuthentication.recovery_code_hash(@codes.first), digest_random, secret]).getvalue(0, 0)
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    assert_equal %w[f t], workers.map(&:value).sort
  end

  test "password reset cannot capture an unconfirmed administrative authenticator" do
    @admin.exec_params("UPDATE app_private.password_credentials SET totp_confirmed = false WHERE identity_id = $1", [@id])
    token = SecureRandom.urlsafe_base64(32)
    assert_equal "t", call("request_password_reset", @email, IdentityStore.digest(token)).fetch("accepted")
    assert_equal "f", call("confirm_password_reset", IdentityStore.digest(token), PasswordAuthentication.password_hash("outra senha sintetica")).fetch("changed")
    assert_equal @secret, PasswordAuthentication.decrypt(@admin.exec_params(
      "SELECT totp_secret FROM app_private.password_credentials WHERE identity_id = $1", [@id]).getvalue(0, 0))
  end

  test "reset during recovery invalidates the pending challenge but keeps the original MFA" do
    pending = PasswordAuthentication.begin_platform_recovery(email: @email, password: @password, recovery_code: @codes.first)
    token = SecureRandom.urlsafe_base64(32)
    call("request_password_reset", @email, IdentityStore.digest(token))
    assert_equal "t", call("confirm_password_reset", IdentityStore.digest(token), PasswordAuthentication.password_hash("outra senha sintetica")).fetch("changed")
    code = PasswordAuthentication.code(pending.fetch(:secret), Time.now.to_i / 30)
    assert_nil PasswordAuthentication.confirm_platform_recovery(challenge: pending.fetch(:challenge), code: code)
    row = @admin.exec_params("SELECT totp_secret, totp_confirmed FROM app_private.password_credentials WHERE identity_id = $1", [@id]).first
    assert_equal @secret, PasswordAuthentication.decrypt(row.fetch("totp_secret"))
    assert_equal "t", row.fetch("totp_confirmed")
  end

  test "expired recovery restores password and original authenticator without another recovery code" do
    pending = PasswordAuthentication.begin_platform_recovery(email: @email, password: @password, recovery_code: @codes.first)
    @admin.exec_params("DELETE FROM app_private.platform_recovery_codes WHERE identity_id=$1", [@id])
    @admin.exec_params("UPDATE app_private.platform_recovery_challenges SET expires_at=clock_timestamp() WHERE identity_id=$1", [@id])
    assert_nil PasswordAuthentication.confirm_platform_recovery(challenge: pending.fetch(:challenge),
      code: PasswordAuthentication.code(pending.fetch(:secret), Time.now.to_i / 30))
    session = login_session
    assert_equal "t", call("platform_admin_for_session", IdentityStore.digest(session)).fetch("authorized")
  end

  test "initial enrollment can be restarted with password and a recovery code without creating a session" do
    @admin.exec_params("UPDATE app_private.password_credentials SET totp_confirmed=false WHERE identity_id=$1", [@id])
    pending = PasswordAuthentication.begin_platform_recovery(email: @email, password: @password, recovery_code: @codes.first)
    assert pending
    assert_equal "f", call("create_password_challenge", @id, digest_random, @password_hash).fetch("created")
    replacement = PasswordAuthentication.confirm_platform_recovery(challenge: pending.fetch(:challenge),
      code: PasswordAuthentication.code(pending.fetch(:secret), Time.now.to_i / 30))
    assert replacement
    assert_equal "0", @admin.exec_params("SELECT count(*) FROM app_private.sessions WHERE identity_id=$1", [@id]).getvalue(0, 0)
  end

  private

  def insert_identity(db, email)
    id = db.exec_params("INSERT INTO app_private.identities(verified_email) VALUES ($1) RETURNING id", [email]).getvalue(0, 0)
    @identities << id
    id
  end

  def call(function, *values)
    placeholders = values.each_index.map { |index| "$#{index + 1}::text" }.join(", ")
    @runtime.exec_params("SELECT * FROM app_private.#{function}(#{placeholders})", values).first
  end

  def digest_random
    IdentityStore.digest(SecureRandom.urlsafe_base64(32))
  end

  def login_session(secret: @secret, step: Time.now.to_i / 30)
    challenge = digest_random
    assert_equal "t", call("create_password_challenge", @id, challenge, @password_hash).fetch("created")
    token = SecureRandom.urlsafe_base64(32)
    code = PasswordAuthentication.code(secret, step)
    assert_equal step, PasswordAuthentication.matching_step(secret, code, now: step * 30)
    assert_equal "t", call("finish_password_challenge", challenge, step.to_s, IdentityStore.digest(token), SecureRandom.urlsafe_base64(32), "").fetch("created")
    token
  end
end
