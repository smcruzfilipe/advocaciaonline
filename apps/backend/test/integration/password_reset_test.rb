require "test_helper"
require "timeout"

class PasswordResetTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    assert_equal "advocacia_migrator", @admin.exec("SELECT current_user").getvalue(0, 0)
    @admin.exec("SET lock_timeout = '5s'; SET statement_timeout = '10s'")
    @email = "reset-#{SecureRandom.hex(12)}@example.test"
    @password = "senha anterior segura"
    @new_password = "minha nova senha segura"
    @secret = PasswordAuthentication.new_secret
    verification = IdentityStore.digest(SecureRandom.urlsafe_base64(32))
    IdentityStore.call("register_password", verification, verification, @email,
      PasswordAuthentication.password_hash(@password), PasswordAuthentication.encrypt(@secret))
    assert IdentityStore.call("verify_password_email", verification, verification).fetch("verified")
    @credential = IdentityStore.call("password_lookup", @email)
    @identity = @credential.fetch("identity_id")
  end

  teardown do
    @admin.close
  end

  test "reset preserves pending TOTP enrollment and requires a second factor" do
    before = credential
    token = issue
    assert confirm(token).fetch("changed")
    after = credential
    assert_equal before.except("password_hash"), after.except("password_hash")
    refute after.fetch("totp_confirmed")
    refute PasswordAuthentication.valid_password?(@password, after.fetch("password_hash"))
    assert PasswordAuthentication.valid_password?(@new_password, after.fetch("password_hash"))
    assert_equal "0", @admin.exec_params("SELECT count(*) FROM app_private.sessions WHERE identity_id = $1", [@identity]).getvalue(0, 0)
    challenge = new_challenge
    assert finish(challenge, Time.now.to_i / 30).fetch("created")
    assert credential.fetch("totp_confirmed")
  end

  test "reset revokes every session and challenge while preserving enrollment replay counter and profile" do
    first = new_challenge
    step = Time.now.to_i / 30
    session = SecureRandom.urlsafe_base64(32)
    assert finish(first, step, session: session).fetch("created")
    second_session, = authenticated_session(email: @email)
    LawyerOnboarding.call(token: session, input: profile_payload)
    context = IdentityStore.context(session)
    memberships = IdentityStore.memberships(session)
    stale = new_challenge
    before = credential
    token = issue
    assert confirm(token).fetch("changed")
    assert_equal before.except("password_hash"), credential.except("password_hash")
    assert_nil IdentityStore.session_identity(session)
    assert_nil IdentityStore.session_identity(second_session)
    assert_nil IdentityStore.call("password_challenge", IdentityStore.digest(stale))
    refute finish(stale, before.fetch("last_totp_step") + 1).fetch("created")
    fresh = new_challenge
    refute finish(fresh, before.fetch("last_totp_step")).fetch("created")
    new_session = SecureRandom.urlsafe_base64(32)
    assert finish(fresh, before.fetch("last_totp_step") + 1, session: new_session).fetch("created")
    assert_equal context.except("csrf_token"), IdentityStore.context(new_session).except("csrf_token")
    assert_equal memberships, IdentityStore.memberships(new_session)
  end

  test "tokens are hashed expire at their deadline rotate and can be used only once" do
    old = issue
    current = issue
    refute confirm(old).fetch("changed")
    stored = @admin.exec_params("SELECT * FROM app_private.password_resets WHERE identity_id = $1", [@identity]).first
    assert_equal IdentityStore.digest(current), stored.fetch("token_hash")
    refute_includes stored.values.join, current
    @admin.exec_params("UPDATE app_private.password_resets SET expires_at = clock_timestamp() WHERE identity_id = $1", [@identity])
    refute confirm(current).fetch("changed")
    fresh = issue
    assert confirm(fresh).fetch("changed")
    refute confirm(fresh).fetch("changed")
    assert_equal "0", @admin.exec_params("SELECT count(*) FROM app_private.password_resets WHERE identity_id = $1", [@identity]).getvalue(0, 0)
  end

  test "disabled unknown and unverified identities do not receive a usable token" do
    absent = SecureRandom.urlsafe_base64(32)
    assert IdentityStore.call("request_password_reset", "absent-#{@email}", IdentityStore.digest(absent)).fetch("accepted")
    refute confirm(absent).fetch("changed")
    pending = IdentityStore.digest(SecureRandom.urlsafe_base64(32))
    pending_email = "pending-#{@email}"
    IdentityStore.call("register_password", pending, pending, pending_email,
      PasswordAuthentication.password_hash(@password), PasswordAuthentication.encrypt(@secret))
    assert IdentityStore.call("request_password_reset", pending_email, IdentityStore.digest(absent)).fetch("accepted")
    refute confirm(absent).fetch("changed")
    token = issue
    @admin.exec_params("UPDATE app_private.identities SET disabled_at = clock_timestamp() WHERE id = $1", [@identity])
    refute confirm(token).fetch("changed")
    assert IdentityStore.call("request_password_reset", @email, IdentityStore.digest(absent)).fetch("accepted")
    refute confirm(absent).fetch("changed")
  end

  test "failed delivery invalidation cannot invalidate a newer request" do
    old = issue
    fresh = issue
    IdentityStore.call("cancel_password_reset", IdentityStore.digest(old))
    assert confirm(fresh).fetch("changed")
    canceled = issue
    IdentityStore.call("cancel_password_reset", IdentityStore.digest(canceled))
    refute confirm(canceled).fetch("changed")
  end

  test "concurrent confirmations have exactly one winner" do
    token = issue
    ready, start = Queue.new, Queue.new
    workers = 2.times.map do
      Thread.new do
        PG.connect(ENV.fetch("DATABASE_URL")) do |connection|
          connection.exec("SET statement_timeout = '10s'")
          ready << true
          start.pop
          connection.exec_params("SELECT * FROM app_private.confirm_password_reset($1, $2)",
            [IdentityStore.digest(token), PasswordAuthentication.password_hash(@new_password)]).first.fetch("changed")
        end
      end
    end
    Timeout.timeout(15) do
      2.times { ready.pop }
      2.times { start << true }
      assert_equal ["f", "t"], workers.map(&:value).sort
    end
  ensure
    2.times { start << true }
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end

  test "password verified before reset cannot create a challenge after reset commits" do
    token = issue
    result = while_credential_locked(
      "SELECT * FROM app_private.create_password_challenge($1, $2, $3)",
      [@identity, IdentityStore.digest(SecureRandom.urlsafe_base64(32)), @credential.fetch("password_hash")]
    ) do
      assert_equal "t", admin_confirm(token).fetch("changed")
    end
    assert_equal "f", result.fetch("created")
  end

  test "challenge validated before reset cannot mint a session after reset commits" do
    challenge = new_challenge
    token = issue
    session = SecureRandom.urlsafe_base64(32)
    result = while_credential_locked(
      "SELECT * FROM app_private.finish_password_challenge($1, $2, $3, $4, $5)",
      [IdentityStore.digest(challenge), (Time.now.to_i / 30).to_s, IdentityStore.digest(session), "csrf", ""]
    ) do
      assert_equal "t", admin_confirm(token).fetch("changed")
    end
    assert_equal "f", result.fetch("created")
    assert_nil IdentityStore.session_identity(session)
  end

  test "reset waiting for a finishing login revokes the session minted before it commits" do
    challenge = new_challenge
    token = issue
    session = SecureRandom.urlsafe_base64(32)
    step = Time.now.to_i / 30
    result = while_credential_locked(
      "SELECT * FROM app_private.confirm_password_reset($1, $2)",
      [IdentityStore.digest(token), PasswordAuthentication.password_hash(@new_password)]
    ) do
      finished = @admin.exec_params(
        "SELECT * FROM app_private.finish_password_challenge($1, $2, $3, $4, $5)",
        [IdentityStore.digest(challenge), step.to_s, IdentityStore.digest(session), "csrf", ""]
      ).first
      assert_equal "t", finished.fetch("created")
    end
    assert_equal "t", result.fetch("changed")
    assert_nil IdentityStore.session_identity(session)
    assert credential.fetch("totp_confirmed")
    assert_equal step, credential.fetch("last_totp_step")
  end

  test "runtime has only narrow function execution and cannot access private reset or credential tables" do
    %w[password_resets password_credentials password_challenges identities sessions].each do |table|
      %w[SELECT INSERT UPDATE DELETE].each do |privilege|
        refute ApplicationRecord.connection.select_value(
          "SELECT has_table_privilege(current_user, 'app_private.#{table}', '#{privilege}')")
      end
    end
    refute ApplicationRecord.connection.select_value(<<~SQL)
      SELECT EXISTS (
        SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
        WHERE p.oid = 'app_private.confirm_password_reset(text,text)'::regprocedure
          AND a.grantee = 0 AND a.privilege_type = 'EXECUTE'
      )
    SQL
    assert_nil @admin.exec("SELECT to_regprocedure('app_private.create_password_challenge(text,text)')").getvalue(0, 0)
  end

  private

  def credential
    row = @admin.exec_params("SELECT * FROM app_private.password_credentials WHERE identity_id = $1", [@identity]).first
    row.merge("totp_confirmed" => row.fetch("totp_confirmed") == "t", "last_totp_step" => row.fetch("last_totp_step").to_i)
  end

  def issue
    token = SecureRandom.urlsafe_base64(32)
    assert IdentityStore.call("request_password_reset", @email, IdentityStore.digest(token)).fetch("accepted")
    token
  end

  def confirm(token)
    IdentityStore.call("confirm_password_reset", IdentityStore.digest(token), PasswordAuthentication.password_hash(@new_password))
  end

  def admin_confirm(token)
    @admin.exec_params("SELECT * FROM app_private.confirm_password_reset($1, $2)",
      [IdentityStore.digest(token), PasswordAuthentication.password_hash(@new_password)]).first
  end

  def new_challenge
    challenge = SecureRandom.urlsafe_base64(32)
    row = IdentityStore.call("password_lookup", @email)
    assert IdentityStore.call("create_password_challenge", @identity, IdentityStore.digest(challenge), row.fetch("password_hash")).fetch("created")
    challenge
  end

  def finish(challenge, step, session: SecureRandom.urlsafe_base64(32))
    IdentityStore.call("finish_password_challenge", IdentityStore.digest(challenge), step.to_s,
      IdentityStore.digest(session), SecureRandom.urlsafe_base64(32), "")
  end

  def while_credential_locked(sql, values)
    pid = Queue.new
    @admin.exec("BEGIN")
    @admin.exec_params("SELECT identity_id FROM app_private.password_credentials WHERE identity_id = $1 FOR UPDATE", [@identity])
    worker = Thread.new do
      Thread.current.report_on_exception = false
      PG.connect(ENV.fetch("DATABASE_URL")) do |connection|
        connection.exec("SET statement_timeout = '10s'")
        pid << connection.backend_pid
        connection.exec_params(sql, values).first
      end
    end
    Timeout.timeout(15) do
      blocked_pid = pid.pop
      loop do
        break if @admin.exec_params("SELECT $1::integer = ANY(pg_blocking_pids($2::integer))",
          [@admin.backend_pid, blocked_pid]).getvalue(0, 0) == "t"
        Thread.pass
      end
      yield
      @admin.exec("COMMIT")
      worker.value
    end
  ensure
    @admin.exec("ROLLBACK") unless @admin.transaction_status == PG::PQTRANS_IDLE
    worker&.kill if worker&.alive?
    worker&.join
  end
end
