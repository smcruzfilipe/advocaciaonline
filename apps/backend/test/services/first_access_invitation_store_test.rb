require "test_helper"

class FirstAccessInvitationStoreTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    raise "Refusing to create invitation fixtures outside test" unless Rails.env.test?
    @operator = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    assert_equal "advocacia_migrator", @operator.exec("SELECT current_user").getvalue(0, 0)
    DatabaseContext.assert_runtime!(ApplicationRecord.connection)
    target = @operator.exec("SELECT current_database(), inet_server_addr()::text, inet_server_port()").first
    runtime = ApplicationRecord.connection.select_rows("SELECT current_database(), inet_server_addr()::text, inet_server_port()").first
    unless target.values == runtime.map { |value| value&.to_s } && target.fetch("current_database").match?(/\Aadvocacia_test(?:_|\z)/)
      raise "Refusing invitation fixtures on different or non-test databases"
    end
    raise "Refusing to replace an existing platform administrator" unless @operator.exec("SELECT 1 FROM app_private.platform_administrator LIMIT 1").ntuples.zero?
    @prefix = "first-access-test-#{SecureRandom.hex(12)}"
    @emails = []
    @identities = []
    @admin_email = email("admin")
    @admin_id, @admin_token = identity_session(@admin_email)
    @operator.exec_params("INSERT INTO app_private.platform_administrator(identity_id) VALUES ($1)", [@admin_id])
  end

  teardown do
    if @operator && @prefix
      @emails.each { |email| @operator.exec_params("DELETE FROM app_private.first_access_invitations WHERE email = $1", [email]) }
      @identities.each do |id|
        %w[first_access_grants platform_recovery_challenges platform_recovery_codes platform_administrator password_resets password_challenges sessions password_credentials].each do |table|
          @operator.exec_params("DELETE FROM app_private.#{table} WHERE identity_id = $1", [id])
        end
        @operator.exec_params("DELETE FROM app_private.identities WHERE id = $1", [id])
      end
    end
    @operator&.close
  end

  test "issue lists only metadata and link recovers the same encrypted bearer without extending expiry" do
    address = email("new")
    issued = FirstAccessInvitationStore.issue(token: @admin_token, email: "  #{address.upcase}  ")
    assert_equal %w[created_at email expires_at id], issued.keys.sort
    assert_equal address, issued.fetch("email")
    listed = FirstAccessInvitationStore.list(token: @admin_token).find { |row| row.fetch("id") == issued.fetch("id") }
    assert_equal issued, listed
    first = FirstAccessInvitationStore.link(token: @admin_token, id: issued.fetch("id"))
    second = FirstAccessInvitationStore.link(token: @admin_token, id: issued.fetch("id"))
    assert_equal [:expires_at, :link], first.keys.sort
    assert first == second
    assert_equal issued.fetch("expires_at"), first.fetch(:expires_at)
    bearer = first.fetch(:link).split("#token=", 2).last
    assert bearer.match?(/\A[A-Za-z0-9_-]{43}\z/)
    stored = @operator.exec_params("SELECT token_hash, token_ciphertext FROM app_private.first_access_invitations WHERE id = $1", [issued.fetch("id")]).first
    assert stored.fetch("token_hash") == IdentityStore.digest(bearer)
    refute stored.fetch("token_ciphertext").include?(bearer)
    inspected = FirstAccessInvitationStore.inspect_token(bearer: bearer)
    assert_equal address, inspected.fetch("email")
    assert_equal false, inspected.fetch("requires_login")
    refute inspected.keys.any? { |key| key.include?("token") }
    assert_raises(IdentityStore::Conflict) { FirstAccessInvitationStore.issue(token: @admin_token, email: address) }
  end

  test "reissue invalidates the old bearer and preparation and creates a distinct link" do
    issued, bearer = invitation("reissue")
    pending = FirstAccessInvitationStore.prepare(bearer: bearer, password: "synthetic password one", confirmation: "synthetic password one")
    replacement = FirstAccessInvitationStore.reissue(token: @admin_token, id: issued.fetch("id"))
    refute_equal issued.fetch("id"), replacement.fetch("id")
    assert_equal %w[created_at email expires_at id], replacement.keys.sort
    assert_raises(IdentityStore::NotFound) { FirstAccessInvitationStore.link(token: @admin_token, id: issued.fetch("id")) }
    assert_raises(IdentityStore::NotFound) { FirstAccessInvitationStore.inspect_token(bearer: bearer) }
    assert_raises(IdentityStore::NotFound) { FirstAccessInvitationStore.prepared(bearer: bearer, challenge: pending.fetch(:challenge)) }
    new_link = FirstAccessInvitationStore.link(token: @admin_token, id: replacement.fetch("id"))
    refute new_link.fetch(:link).end_with?(bearer)
  end

  test "preparation stores protected credentials only and restart invalidates the previous challenge" do
    issued, bearer = invitation("prepare")
    password = "synthetic password one"
    first = FirstAccessInvitationStore.prepare(bearer: bearer, password: password, confirmation: password)
    assert_equal [:challenge, :otpauth_uri, :secret], first.keys.sort
    assert first.fetch(:otpauth_uri).start_with?("otpauth://totp/")
    row = FirstAccessInvitationStore.prepared(bearer: bearer, challenge: first.fetch(:challenge))
    assert PasswordAuthentication.valid_password?(password, row.fetch("password_hash"))
    assert PasswordAuthentication.decrypt(row.fetch("totp_secret")) == first.fetch(:secret)
    refute row.fetch("password_hash").include?(password)
    assert_equal "0", @operator.exec_params("SELECT count(*) FROM app_private.identities WHERE verified_email=$1", [issued.fetch("email")]).getvalue(0, 0)
    assert IdentityStore.call("password_lookup", issued.fetch("email")).nil?
    reset = SecureRandom.urlsafe_base64(32)
    IdentityStore.call("request_password_reset", issued.fetch("email"), IdentityStore.digest(reset))
    refute IdentityStore.call("confirm_password_reset", IdentityStore.digest(reset), PasswordAuthentication.password_hash("another synthetic password")).fetch("changed")
    second = FirstAccessInvitationStore.prepare(bearer: bearer, password: "synthetic password two", confirmation: "synthetic password two")
    assert_raises(IdentityStore::NotFound) { FirstAccessInvitationStore.prepared(bearer: bearer, challenge: first.fetch(:challenge)) }
    assert FirstAccessInvitationStore.prepared(bearer: bearer, challenge: second.fetch(:challenge))
    @operator.exec_params("UPDATE app_private.first_access_preparations SET expires_at=clock_timestamp() WHERE invitation_id=$1", [issued.fetch("id")])
    assert_raises(IdentityStore::NotFound) { FirstAccessInvitationStore.prepared(bearer: bearer, challenge: second.fetch(:challenge)) }
    assert_equal "0", @operator.exec_params("SELECT count(*) FROM app_private.first_access_grants g JOIN app_private.identities i ON i.id=g.identity_id WHERE i.verified_email=$1", [issued.fetch("email")]).getvalue(0, 0)
  end

  test "invalid input, tampered ciphertext, and exact expiration are unavailable" do
    issued, bearer = invitation("invalid")
    [nil, "short", "a" * 42 + "!"].each do |bad|
      assert_raises(IdentityStore::NotFound) { FirstAccessInvitationStore.inspect_token(bearer: bad) }
    end
    ["too short", "a" * 129, "😀" * 129].each do |password|
      assert_raises(IdentityStore::InvalidInput) { FirstAccessInvitationStore.prepare(bearer: bearer, password: password, confirmation: password) }
    end
    assert_raises(IdentityStore::InvalidInput) { FirstAccessInvitationStore.prepare(bearer: bearer, password: "synthetic password", confirmation: "different password") }
    @operator.exec_params("UPDATE app_private.first_access_invitations SET token_ciphertext = $1 WHERE id = $2", ["invalid ciphertext", issued.fetch("id")])
    error = assert_raises(IdentityStore::NotFound) { FirstAccessInvitationStore.link(token: @admin_token, id: issued.fetch("id")) }
    refute_includes error.message, "invalid ciphertext"
    assert_nil error.cause
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key("first-access-link-encryption-v1", 32)
    ciphertext = ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm").encrypt_and_sign(SecureRandom.urlsafe_base64(32), purpose: "first-access-link-v1")
    @operator.exec_params("UPDATE app_private.first_access_invitations SET token_ciphertext = $1 WHERE id = $2", [ciphertext, issued.fetch("id")])
    assert_raises(IdentityStore::NotFound) { FirstAccessInvitationStore.link(token: @admin_token, id: issued.fetch("id")) }
    @operator.exec_params("UPDATE app_private.first_access_invitations SET expires_at = clock_timestamp() WHERE id = $1", [issued.fetch("id")])
    assert_raises(IdentityStore::NotFound) { FirstAccessInvitationStore.inspect_token(bearer: bearer) }
    assert_raises(IdentityStore::NotFound) { FirstAccessInvitationStore.link(token: @admin_token, id: issued.fetch("id")) }
  end

  test "admin operations require a current administrator and a top-level transaction" do
    issued, = invitation("authorization")
    _, ordinary = identity_session(email("ordinary"))
    [nil, SecureRandom.urlsafe_base64(32)].each do |token|
      assert_raises(IdentityStore::AuthenticationRejected) { FirstAccessInvitationStore.list(token: token) }
    end
    assert_raises(IdentityStore::AccessDenied) { FirstAccessInvitationStore.list(token: ordinary) }
    assert_raises(IdentityStore::AccessDenied) { FirstAccessInvitationStore.link(token: ordinary, id: issued.fetch("id")) }
    assert_raises(IdentityStore::AccessDenied) { FirstAccessInvitationStore.reissue(token: ordinary, id: issued.fetch("id")) }
    assert_raises(IdentityStore::AccessDenied) { FirstAccessInvitationStore.issue(token: ordinary, email: email("denied")) }
    ApplicationRecord.transaction do
      assert_raises(ActiveRecord::ActiveRecordError) { FirstAccessInvitationStore.issue(token: @admin_token, email: email("nested")) }
      assert_raises(ActiveRecord::ActiveRecordError) { FirstAccessInvitationStore.link(token: @admin_token, id: issued.fetch("id")) }
      assert_raises(ActiveRecord::ActiveRecordError) { FirstAccessInvitationStore.reissue(token: @admin_token, id: issued.fetch("id")) }
    end
  end

  test "consume requires the matching MFA session, supports rollback, and prevents replay" do
    address = email("existing")
    identity, session = identity_session(address)
    _, other = identity_session(email("other"))
    issued = FirstAccessInvitationStore.issue(token: @admin_token, email: address)
    bearer = FirstAccessInvitationStore.link(token: @admin_token, id: issued.fetch("id")).fetch(:link).split("#token=", 2).last
    assert_equal true, FirstAccessInvitationStore.inspect_token(bearer: bearer).fetch("requires_login")
    assert_raises(IdentityStore::NotFound) { FirstAccessInvitationStore.consume(bearer: bearer, session: other) }
    assert_raises(IdentityStore::AuthenticationRejected) { FirstAccessInvitationStore.consume(bearer: bearer, session: "") }
    ApplicationRecord.transaction do
      result = FirstAccessInvitationStore.consume(bearer: bearer, session: session)
      assert_equal identity, result.fetch("identity_id")
      raise ActiveRecord::Rollback
    end
    assert FirstAccessInvitationStore.inspect_token(bearer: bearer)
    assert_equal "0", @operator.exec_params("SELECT count(*) FROM app_private.first_access_grants WHERE identity_id=$1", [identity]).getvalue(0, 0)
    assert_equal identity, FirstAccessInvitationStore.consume(bearer: bearer, session: session).fetch("identity_id")
    assert_equal "1", @operator.exec_params("SELECT count(*) FROM app_private.first_access_grants WHERE identity_id=$1", [identity]).getvalue(0, 0)
    assert_raises(IdentityStore::NotFound) { FirstAccessInvitationStore.consume(bearer: bearer, session: session) }
  end

  test "concurrent consumption has one winner" do
    address = email("concurrent")
    identity, session = identity_session(address)
    issued = FirstAccessInvitationStore.issue(token: @admin_token, email: address)
    bearer = FirstAccessInvitationStore.link(token: @admin_token, id: issued.fetch("id")).fetch(:link).split("#token=", 2).last
    ready = Queue.new
    start = Queue.new
    workers = 2.times.map do
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            FirstAccessInvitationStore.consume(bearer: bearer, session: session)
            :consumed
          rescue IdentityStore::NotFound
            :unavailable
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    assert_equal [:consumed, :unavailable], workers.map(&:value).sort
    assert_equal "1", @operator.exec_params("SELECT count(*) FROM app_private.first_access_grants WHERE identity_id=$1", [identity]).getvalue(0, 0)
  end

  private

  def email(label)
    "#{@prefix}-#{label}@example.test".tap { |value| @emails << value }
  end

  def identity_session(address)
    id = @operator.exec_params("INSERT INTO app_private.identities(verified_email) VALUES ($1) RETURNING id", [address]).getvalue(0, 0)
    @identities << id
    secret = PasswordAuthentication.new_secret
    password_hash = PasswordAuthentication.password_hash("synthetic fixture password")
    @operator.exec_params("INSERT INTO app_private.password_credentials(identity_id,password_hash,totp_secret,totp_confirmed) VALUES ($1,$2,$3,true)", [id, password_hash, PasswordAuthentication.encrypt(secret)])
    challenge = SecureRandom.urlsafe_base64(32)
    token = SecureRandom.urlsafe_base64(32)
    assert IdentityStore.call("create_password_challenge", id, IdentityStore.digest(challenge), password_hash).fetch("created")
    step = Time.now.to_i / 30
    assert PasswordAuthentication.matching_step(secret, PasswordAuthentication.code(secret, step), now: step * 30)
    assert IdentityStore.call("finish_password_challenge", IdentityStore.digest(challenge), step.to_s, IdentityStore.digest(token), SecureRandom.urlsafe_base64(32), "").fetch("created")
    [id, token]
  end

  def invitation(label)
    issued = FirstAccessInvitationStore.issue(token: @admin_token, email: email(label))
    bearer = FirstAccessInvitationStore.link(token: @admin_token, id: issued.fetch("id")).fetch(:link).split("#token=", 2).last
    [issued, bearer]
  end
end
