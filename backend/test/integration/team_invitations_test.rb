require "test_helper"
require "base64"

class TeamInvitationsTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @owner, = authenticated_session
    LawyerOnboarding.call(token: @owner, input: profile_payload)
    @email = "invited-#{SecureRandom.hex(6)}@example.test"
    @sent_tokens = []
  end

  def administer
    connection = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    yield connection
  ensure
    connection&.close
  end

  def deliver
    TeamInvitationMailer.stub(:deliver!, ->(**arguments) { @sent_tokens << arguments.fetch(:token) }) { yield }
  end

  def credential(days = nil)
    deliver { IdentityStore.create_credential(token: @owner, email: @email, validity_days: days, smtp: {}) }
  end

  def google_identity(email = @email)
    token = SecureRandom.urlsafe_base64(32)
    IdentityStore.authenticate(subject: SecureRandom.uuid, email: email, token: token, csrf: SecureRandom.urlsafe_base64(32))
    token
  end

  test "invitation stores only a 256-bit token digest and expires after twenty-four hours" do
    member = credential(2)
    raw_token = @sent_tokens.last
    assert_equal 32, Base64.urlsafe_decode64(raw_token).bytesize
    administer do |connection|
      row = connection.exec_params("SELECT token_hash, extract(epoch FROM expires_at - issued_at) AS duration FROM app_private.team_invitations WHERE membership_id = $1", [member.fetch("id")]).first
      assert_equal IdentityStore.digest(raw_token), row.fetch("token_hash")
      refute_equal raw_token, row.fetch("token_hash")
      assert_equal 86_400, row.fetch("duration").to_f
    end
    refute member.key?("token_hash")
    refute member.key?("token")
  end

  test "acceptance requires the invited verified Google email and is single use" do
    member = credential
    wrong = google_identity("wrong@example.test")
    assert_raises(IdentityStore::NotFound) { IdentityStore.accept_invitation(token: wrong, invitation_token: @sent_tokens.last) }
    assert_nil IdentityStore.context(wrong).fetch("tenant_id")
    right = google_identity(@email.upcase)
    accepted = IdentityStore.accept_invitation(token: right, invitation_token: @sent_tokens.last)
    assert_equal member.fetch("id"), accepted.fetch("membership_id")
    assert_equal member.fetch("tenant_id"), IdentityStore.context(right).fetch("tenant_id")
    assert_raises(IdentityStore::NotFound) { IdentityStore.accept_invitation(token: right, invitation_token: @sent_tokens.last) }
  end

  test "reissue atomically invalidates the old token without restarting credential validity" do
    member = credential(2)
    original = @sent_tokens.last
    reissued = deliver { IdentityStore.reissue_invitation(token: @owner, membership_id: member.fetch("id"), smtp: {}) }
    replacement = @sent_tokens.last
    refute_equal original, replacement
    assert_equal member.fetch("credential_started_at"), reissued.fetch("credential_started_at")
    assert_equal member.fetch("expires_at"), reissued.fetch("expires_at")
    invited = google_identity
    assert_raises(IdentityStore::NotFound) { IdentityStore.accept_invitation(token: invited, invitation_token: original) }
    assert_equal member.fetch("id"), IdentityStore.accept_invitation(token: invited, invitation_token: replacement).fetch("membership_id")
    assert_raises(IdentityStore::Conflict) { deliver { IdentityStore.reissue_invitation(token: @owner, membership_id: member.fetch("id"), smtp: {}) } }
  end

  test "invitation is bounded by credential expiry and revocation" do
    member = credential(1)
    administer do |connection|
      row = connection.exec_params("SELECT i.expires_at = m.expires_at AS bounded FROM app_private.team_invitations i JOIN app_private.tenant_memberships m ON m.id = i.membership_id WHERE m.id = $1", [member.fetch("id")]).first
      assert_equal "t", row.fetch("bounded")
    end
    invited = google_identity
    IdentityStore.revoke_credential(token: @owner, membership_id: member.fetch("id"))
    assert_raises(IdentityStore::NotFound) { IdentityStore.accept_invitation(token: invited, invitation_token: @sent_tokens.last) }
    assert_raises(IdentityStore::Conflict) { deliver { IdentityStore.reissue_invitation(token: @owner, membership_id: member.fetch("id"), smtp: {}) } }
  end

  test "an expired invitation is rejected even after the credential is renewed" do
    member = credential(2)
    administer do |connection|
      connection.exec_params("UPDATE app_private.team_invitations SET issued_at = statement_timestamp() - interval '24 hours', expires_at = statement_timestamp() WHERE membership_id = $1", [member.fetch("id")])
    end
    IdentityStore.renew_credential(token: @owner, membership_id: member.fetch("id"))
    invited = google_identity
    assert_raises(IdentityStore::NotFound) { IdentityStore.accept_invitation(token: invited, invitation_token: @sent_tokens.last) }
    deliver { IdentityStore.reissue_invitation(token: @owner, membership_id: member.fetch("id"), smtp: {}) }
    assert_equal member.fetch("id"), IdentityStore.accept_invitation(token: invited, invitation_token: @sent_tokens.last).fetch("membership_id")
  end

  test "delivery failure preserves committed creation and explicit reissue invalidates the uncertain link" do
    failure = ->(**arguments) do
      @sent_tokens << arguments.fetch(:token)
      raise TeamInvitationMailer::DeliveryFailed, "SMTP delivery failed"
    end
    TeamInvitationMailer.stub(:deliver!, failure) do
      assert_raises(TeamInvitationMailer::DeliveryFailed) do
        IdentityStore.create_credential(token: @owner, email: @email, validity_days: 2, smtp: {})
      end
    end
    assert_equal 1, IdentityStore.team_credentials(@owner).length
    member = IdentityStore.team_credentials(@owner).first
    uncertain = @sent_tokens.last
    reissued = deliver { IdentityStore.reissue_invitation(token: @owner, membership_id: member.fetch("id"), smtp: {}) }
    assert_equal member.fetch("credential_started_at"), reissued.fetch("credential_started_at")
    assert_equal member.fetch("expires_at"), reissued.fetch("expires_at")
    invited = google_identity
    assert_raises(IdentityStore::NotFound) { IdentityStore.accept_invitation(token: invited, invitation_token: uncertain) }
    assert_equal member.fetch("id"), IdentityStore.accept_invitation(token: invited, invitation_token: @sent_tokens.last).fetch("membership_id")
  end

  test "failed delivery after reissue leaves the old token invalid and permits another explicit reissue" do
    member = credential(2)
    original = @sent_tokens.last
    failure = ->(**arguments) do
      @sent_tokens << arguments.fetch(:token)
      raise TeamInvitationMailer::DeliveryFailed, "SMTP delivery failed"
    end
    TeamInvitationMailer.stub(:deliver!, failure) do
      assert_raises(TeamInvitationMailer::DeliveryFailed) do
        IdentityStore.reissue_invitation(token: @owner, membership_id: member.fetch("id"), smtp: {})
      end
    end
    uncertain = @sent_tokens.last
    invited = google_identity
    assert_raises(IdentityStore::NotFound) { IdentityStore.accept_invitation(token: invited, invitation_token: original) }
    reissued = deliver { IdentityStore.reissue_invitation(token: @owner, membership_id: member.fetch("id"), smtp: {}) }
    assert_equal member.fetch("credential_started_at"), reissued.fetch("credential_started_at")
    assert_equal member.fetch("expires_at"), reissued.fetch("expires_at")
    assert_raises(IdentityStore::NotFound) { IdentityStore.accept_invitation(token: invited, invitation_token: uncertain) }
    assert_equal member.fetch("id"), IdentityStore.accept_invitation(token: invited, invitation_token: @sent_tokens.last).fetch("membership_id")
  end

  test "invitation creation and reissue are committed before SMTP observes them" do
    observed = []
    transport = ->(**arguments) do
      assert_not ApplicationRecord.connection.transaction_open?
      administer do |connection|
        observed << connection.exec_params("SELECT membership_id FROM app_private.team_invitations WHERE token_hash = $1",
          [IdentityStore.digest(arguments.fetch(:token))]).first.fetch("membership_id")
      end
    end
    TeamInvitationMailer.stub(:deliver!, transport) do
      member = IdentityStore.create_credential(token: @owner, email: @email, validity_days: 2, smtp: {})
      IdentityStore.reissue_invitation(token: @owner, membership_id: member.fetch("id"), smtp: {})
      assert_equal [member.fetch("id"), member.fetch("id")], observed
    end
  end

  test "issuance rejects enclosing transactions rather than sending uncommitted invitations" do
    ApplicationRecord.transaction do
      assert_raises(ActiveRecord::ActiveRecordError) { credential }
    end
    assert_empty @sent_tokens
    assert_empty IdentityStore.team_credentials(@owner)
    member = credential
    original = @sent_tokens.last
    ApplicationRecord.transaction do
      assert_raises(ActiveRecord::ActiveRecordError) do
        deliver { IdentityStore.reissue_invitation(token: @owner, membership_id: member.fetch("id"), smtp: {}) }
      end
    end
    assert_equal [original], @sent_tokens
  end

  test "an expired pending credential cannot be accepted or reissued" do
    member = credential(2)
    administer do |connection|
      connection.exec_params("UPDATE app_private.tenant_memberships SET expires_at = statement_timestamp() WHERE id = $1", [member.fetch("id")])
    end
    invited = google_identity
    assert_raises(IdentityStore::NotFound) { IdentityStore.accept_invitation(token: invited, invitation_token: @sent_tokens.last) }
    assert_raises(IdentityStore::Conflict) do
      deliver { IdentityStore.reissue_invitation(token: @owner, membership_id: member.fetch("id"), smtp: {}) }
    end
    assert_nil IdentityStore.context(invited).fetch("tenant_id")
  end

  test "simultaneous acceptance consumes one token exactly once" do
    member = credential
    invited = google_identity
    invitation = @sent_tokens.last
    ready = Queue.new
    start = Queue.new
    threads = 2.times.map do
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            IdentityStore.accept_invitation(token: invited, invitation_token: invitation)
          rescue IdentityStore::NotFound => error
            error
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    results = threads.map(&:value)
    assert_equal 1, results.count { |result| result.is_a?(Hash) && result["membership_id"] == member.fetch("id") }
    assert_equal 1, results.count { |result| result.is_a?(IdentityStore::NotFound) }
  end
end
