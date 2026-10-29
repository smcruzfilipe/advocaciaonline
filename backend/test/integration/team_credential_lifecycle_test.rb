require "test_helper"

class TeamCredentialLifecycleTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @owner, = authenticated_session
    LawyerOnboarding.call(token: @owner, input: profile_payload)
    @email = "member-#{SecureRandom.hex(6)}@example.test"
  end

  def administer
    connection = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    yield connection
  ensure
    connection&.close
  end

  def create_credential(days)
    TeamInvitationMailer.stub(:deliver!, ->(**arguments) { @invitation = arguments.fetch(:token) }) do
      IdentityStore.create_credential(token: @owner, email: @email, validity_days: days, smtp: {})
    end
  end

  def accept_credential
    member = SecureRandom.urlsafe_base64(32)
    IdentityStore.authenticate(subject: SecureRandom.uuid, email: @email, token: member,
      csrf: SecureRandom.urlsafe_base64(32))
    IdentityStore.accept_invitation(token: member, invitation_token: @invitation)
    member
  end

  test "validity is explicit and a positive integer or unlimited" do
    [0, -1, 1.5, "2", true, {}, []].each do |days|
      assert_raises(IdentityStore::InvalidInput) { create_credential(days) }
    end
    credential = create_credential(nil)
    assert_nil credential.fetch("validity_days")
    assert_nil credential.fetch("expires_at")
    member = accept_credential
    assert_equal credential.fetch("id"), IdentityStore.context(member).fetch("membership_id")
  end

  test "days are exact twenty-four hour periods from issuance rather than acceptance" do
    credential = create_credential(2)
    assert_in_delta 172_800, credential.fetch("expires_at") - credential.fetch("credential_started_at"), 0.000001
    started = credential.fetch("credential_started_at")
    expiry = credential.fetch("expires_at")
    member = accept_credential
    listed = IdentityStore.team_credentials(@owner).find { |row| row.fetch("id") == credential.fetch("id") }
    assert_equal started, listed.fetch("credential_started_at")
    assert_equal expiry, listed.fetch("expires_at")
    assert_equal "member", IdentityStore.context(member).fetch("role")
  end

  test "changing the next validity does not change the effective deadline and renewal starts anew" do
    credential = create_credential(2)
    member = accept_credential
    changed = IdentityStore.change_validity(token: @owner, membership_id: credential.fetch("id"), validity_days: 3)
    assert_equal credential.fetch("expires_at"), changed.fetch("expires_at")
    assert_equal credential.fetch("credential_started_at"), changed.fetch("credential_started_at")
    administer do |connection|
      connection.exec_params("UPDATE app_private.tenant_memberships SET expires_at = statement_timestamp() WHERE id = $1", [credential.fetch("id")])
    end
    assert_nil IdentityStore.context(member)
    DatabaseContext.with_session(member) { assert_empty Lawyer.pluck(:id) }
    renewed = IdentityStore.renew_credential(token: @owner, membership_id: credential.fetch("id"))
    assert_operator renewed.fetch("credential_started_at"), :>, credential.fetch("credential_started_at")
    assert_in_delta 259_200, renewed.fetch("expires_at") - renewed.fetch("credential_started_at"), 0.000001
    assert_equal credential.fetch("id"), IdentityStore.context(member).fetch("membership_id")
  end

  test "revocation immediately invalidates active sessions and only a new credential restores access" do
    credential = create_credential(nil)
    member = accept_credential
    revoked = IdentityStore.revoke_credential(token: @owner, membership_id: credential.fetch("id"))
    assert_not_nil revoked.fetch("revoked_at")
    assert_nil IdentityStore.context(member)
    DatabaseContext.with_session(member) { assert_empty Lawyer.pluck(:id) }
    assert_raises(IdentityStore::Conflict) do
      IdentityStore.renew_credential(token: @owner, membership_id: credential.fetch("id"))
    end
    replacement = create_credential(nil)
    refute_equal credential.fetch("id"), replacement.fetch("id")
    IdentityStore.accept_invitation(token: member, invitation_token: @invitation)
    assert_equal replacement.fetch("id"), IdentityStore.context(member).fetch("membership_id")
  end

  test "only owner can administer and another tenant cannot mutate a known credential" do
    credential = create_credential(nil)
    member = accept_credential
    assert_raises(IdentityStore::AccessDenied) { IdentityStore.team_credentials(member) }
    assert_raises(IdentityStore::AccessDenied) { IdentityStore.revoke_credential(token: member, membership_id: credential.fetch("id")) }
    other, = authenticated_session
    LawyerOnboarding.call(token: other, input: profile_payload)
    assert_raises(IdentityStore::NotFound) { IdentityStore.revoke_credential(token: other, membership_id: credential.fetch("id")) }
    assert_empty IdentityStore.team_credentials(other)
    assert_not_nil IdentityStore.context(member)
    assert_raises(IdentityStore::NotFound) do
      IdentityStore.renew_credential(token: @owner, membership_id: IdentityStore.context(@owner).fetch("membership_id"))
    end
  end

  test "private bootstrap tables do not expose memberships or invitation hashes to runtime" do
    %w[tenant_memberships team_invitations].each do |table|
      assert_raises(ActiveRecord::StatementInvalid) do
        ApplicationRecord.connection.execute("SELECT * FROM app_private.#{table}")
      end
      flags = ApplicationRecord.connection.select_one("SELECT relrowsecurity, relforcerowsecurity FROM pg_class WHERE oid = 'app_private.#{table}'::regclass")
      assert flags.fetch("relrowsecurity")
      assert flags.fetch("relforcerowsecurity")
    end
  end

  def wait_for_advisory(connection, pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      waiting = connection.exec_params("SELECT EXISTS (SELECT 1 FROM pg_locks WHERE pid = $1 AND locktype = 'advisory' AND NOT granted)", [pid]).getvalue(0, 0)
      return if waiting == "t"
      flunk "Expected authorization lock wait" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.01
    end
  end

  test "authorization lock revalidates expiry after waiting for an exclusive tenant change" do
    credential = create_credential(2)
    member = accept_credential
    tenant = credential.fetch("tenant_id")
    ready = Queue.new
    worker = nil
    administer do |connection|
      connection.exec("BEGIN")
      connection.exec_params("SELECT pg_advisory_xact_lock(hashtextextended('authorization:' || $1, 0))", [tenant])
      worker = Thread.new do
        ApplicationRecord.connection_pool.with_connection do |runtime|
          begin
            DatabaseContext.with_session(member) do
              ready << runtime.select_value("SELECT pg_backend_pid()")
              runtime.select_value("SELECT app_private.lock_authorization(false)")
            end
          rescue ActiveRecord::StatementInvalid => error
            error.cause.result.error_field(PG::Result::PG_DIAG_SQLSTATE)
          end
        end
      end
      wait_for_advisory(connection, ready.pop)
      connection.exec_params("UPDATE app_private.tenant_memberships SET expires_at = clock_timestamp() WHERE id = $1", [credential.fetch("id")])
      connection.exec("COMMIT")
      assert_equal "42501", worker.value
    end
    assert_nil IdentityStore.context(member)
  ensure
    worker&.join(5)
  end

  test "logout waits for a protected transaction and invalidates subsequent operations" do
    create_credential(nil)
    member = accept_credential
    entered = Queue.new
    release = Queue.new
    revoking = Queue.new
    protected = Thread.new do
      ApplicationRecord.connection_pool.with_connection do |runtime|
        DatabaseContext.with_session(member) do
          runtime.select_value("SELECT app_private.lock_authorization(false)")
          entered << true
          release.pop
        end
      end
    end
    entered.pop
    logout = Thread.new do
      ApplicationRecord.connection_pool.with_connection do |runtime|
        revoking << runtime.select_value("SELECT pg_backend_pid()")
        IdentityStore.revoke(member)
      end
    end
    administer { |connection| wait_for_advisory(connection, revoking.pop) }
    release << true
    protected.value
    logout.value
    assert_nil IdentityStore.context(member)
    assert_nil IdentityStore.session_identity(member)
  ensure
    release << true if release
    protected&.join(5)
    logout&.join(5)
  end
end
