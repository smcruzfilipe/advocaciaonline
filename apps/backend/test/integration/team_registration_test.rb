require "test_helper"

class TeamRegistrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @email = "team-registration-#{SecureRandom.hex(10)}@example.test"
    @verification = SecureRandom.urlsafe_base64(32)
    @browser = SecureRandom.urlsafe_base64(32)
    owner, = authenticated_session(owner: true)
    LawyerOnboarding.call(token: owner, input: profile_payload)
    TeamInvitationMailer.stub(:deliver!, ->(**args) { @invitation = args.fetch(:token) }) do
      member = IdentityStore.create_credential(token: owner, email: @email, validity_days: nil, smtp: {})
      @membership = member.fetch("id")
    end
  end

  def administer
    db = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    yield db
  ensure
    db&.close
  end

  def digest(value)
    IdentityStore.digest(value)
  end

  def register(invitation: @invitation, email: @email, session: nil, verification: @verification)
    IdentityStore.call("register_team_password", digest(invitation), digest(verification), digest(@browser), email,
      "password-hash", "encrypted-totp", session && digest(session)).fetch("created")
  end

  def verify(session: nil, browser: @browser, verification: @verification)
    IdentityStore.call("verify_team_email", digest(verification), digest(browser), session && digest(session)).fetch("verified")
  end

  test "registration requires the current invitation and matching email and creates no identity before mailbox proof" do
    refute register(invitation: SecureRandom.urlsafe_base64(32))
    refute register(email: "wrong@example.test")
    assert register
    assert_nil IdentityStore.call("password_lookup", @email)
    refute verify(browser: SecureRandom.urlsafe_base64(32))
    assert_nil IdentityStore.call("password_lookup", @email)
    assert verify
    refute verify
    credential = IdentityStore.call("password_lookup", @email)
    assert_equal "password-hash", credential.fetch("password_hash")
    assert_equal "encrypted-totp", credential.fetch("totp_secret")
    refute credential.fetch("totp_confirmed")
    administer do |db|
      row = db.exec_params(<<~SQL, [@email, @membership]).first
        SELECT i.email_verified_at IS NOT NULL AS verified, t.consumed_at IS NULL AS unconsumed
        FROM app_private.identities i CROSS JOIN app_private.team_invitations t
        WHERE i.verified_email = $1 AND t.membership_id = $2
      SQL
      assert_equal "t", row.fetch("verified")
      assert_equal "t", row.fetch("unconsumed")
    end
  end

  test "replacement, revocation and expiration invalidate pending mailbox proofs" do
    assert register
    administer do |db|
      db.exec_params("UPDATE app_private.team_invitations SET token_hash = $1 WHERE membership_id = $2",
        [digest(SecureRandom.urlsafe_base64(32)), @membership])
    end
    refute verify
    assert_nil IdentityStore.call("password_lookup", @email)

    administer do |db|
      db.exec_params("UPDATE app_private.team_invitations SET token_hash = $1 WHERE membership_id = $2", [digest(@invitation), @membership])
      db.exec_params("UPDATE app_private.tenant_memberships SET revoked_at = clock_timestamp() WHERE id = $1", [@membership])
    end
    refute verify
    refute register(verification: SecureRandom.urlsafe_base64(32))
    administer do |db|
      db.exec_params("UPDATE app_private.tenant_memberships SET revoked_at = NULL WHERE id = $1", [@membership])
      db.exec_params(<<~SQL, [@membership])
        UPDATE app_private.team_invitations SET issued_at = clock_timestamp() - interval '24 hours',
          expires_at = clock_timestamp() - interval '1 second' WHERE membership_id = $1
      SQL
    end
    refute verify
    refute register(verification: SecureRandom.urlsafe_base64(32))
    assert_nil IdentityStore.call("password_lookup", @email)
  end

  test "existing account must authenticate at registration and verification without changing credentials" do
    session, = authenticated_session(email: @email)
    other, = authenticated_session
    before = IdentityStore.call("password_lookup", @email)
    administer do |db|
      db.exec_params("UPDATE app_private.identities SET email_verified_at = NULL WHERE id = $1", [before.fetch("identity_id")])
    end
    assert_raises(IdentityStore::NotFound) { IdentityStore.accept_invitation(token: session, invitation_token: @invitation) }
    refute register
    refute register(session: other)
    assert register(session: session)
    refute verify
    refute verify(session: other)
    assert verify(session: session)
    refute verify(session: session)
    assert_equal before, IdentityStore.call("password_lookup", @email)
    assert_equal @membership, IdentityStore.accept_invitation(token: session, invitation_token: @invitation).fetch("membership_id")
    assert_raises(IdentityStore::NotFound) { IdentityStore.accept_invitation(token: session, invitation_token: @invitation) }
  end

  test "a revoked session cannot confirm an existing account's mailbox" do
    session, = authenticated_session(email: @email)
    assert register(session: session)
    IdentityStore.revoke(session)
    refute verify(session: session)
  end

  test "an identity created after preparation cannot have its credentials replaced" do
    assert register
    session, = authenticated_session(email: @email)
    credential = IdentityStore.call("password_lookup", @email)
    refute verify(session: session)
    assert_equal credential, IdentityStore.call("password_lookup", @email)
  end

  test "concurrent mailbox confirmations create only one identity" do
    assert register
    ready = Queue.new
    start = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          verify
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    assert_equal [false, true], threads.map(&:value).sort_by { |value| value ? 1 : 0 }
    assert IdentityStore.call("password_lookup", @email)
  end

  test "runtime cannot invoke obsolete public registration functions" do
    connection = ApplicationRecord.connection
    %w[register_password(text,text,text,text,text) verify_password_email(text,text)].each do |signature|
      assert_nil connection.select_value("SELECT to_regprocedure('app_private.#{signature}')")
    end
  end
end
