require "test_helper"

class TenantMembershipsTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  def create_owner
    token, = authenticated_session
    LawyerOnboarding.call(token: token, input: profile_payload)
    token
  end

  def invited_member(owner, email:, subject: SecureRandom.uuid)
    invitation = nil
    TeamInvitationMailer.stub(:deliver!, ->(**arguments) { invitation = arguments.fetch(:token) }) do
      credential = IdentityStore.create_credential(token: owner, email: email, validity_days: nil, smtp: {})
      token = SecureRandom.urlsafe_base64(32)
      IdentityStore.authenticate(subject: subject, email: email, token: token, csrf: SecureRandom.urlsafe_base64(32))
      IdentityStore.accept_invitation(token: token, invitation_token: invitation)
      return [token, credential, subject]
    end
  end

  test "one identity can accept memberships in two tenants and must select a verified membership" do
    owner_a = create_owner
    owner_b = create_owner
    member, membership_a, subject = invited_member(owner_a, email: "member@example.test")
    invitation = nil
    membership_b = nil
    TeamInvitationMailer.stub(:deliver!, ->(**arguments) { invitation = arguments.fetch(:token) }) do
      membership_b = IdentityStore.create_credential(token: owner_b, email: "member@example.test", validity_days: nil, smtp: {})
    end
    IdentityStore.accept_invitation(token: member, invitation_token: invitation)
    assert_equal 2, IdentityStore.memberships(member).length
    IdentityStore.select_membership(token: member, membership_id: membership_a.fetch("id"))
    DatabaseContext.with_session(member) do
      assert_equal [membership_a.fetch("tenant_id")], Lawyer.pluck(:tenant_id)
    end
    IdentityStore.select_membership(token: member, membership_id: membership_b.fetch("id"))
    DatabaseContext.with_session(member) do
      assert_equal [membership_b.fetch("tenant_id")], Lawyer.pluck(:tenant_id)
    end
    fresh = SecureRandom.urlsafe_base64(32)
    IdentityStore.authenticate(subject: subject, email: "member@example.test", token: fresh, csrf: SecureRandom.urlsafe_base64(32))
    assert_nil IdentityStore.context(fresh).fetch("tenant_id")
    DatabaseContext.with_session(fresh) { assert_empty Lawyer.pluck(:id) }
  end

  test "client membership and tenant identifiers never establish association" do
    owner_a = create_owner
    owner_b = create_owner
    membership_b = IdentityStore.context(owner_b).fetch("membership_id")
    original = IdentityStore.context(owner_a)
    assert_raises(IdentityStore::AccessDenied) do
      IdentityStore.select_membership(token: owner_a, membership_id: membership_b)
    end
    assert_equal original, IdentityStore.context(owner_a)
    DatabaseContext.with_session(owner_a) do
      assert_equal [original.fetch("tenant_id")], Lawyer.pluck(:tenant_id)
    end
  end

  test "onboarding preserves one owner membership without expiration" do
    owner = create_owner
    context = IdentityStore.context(owner)
    assert_equal "owner", context.fetch("role")
    assert_equal 1, IdentityStore.memberships(owner).length
    assert_raises(LawyerOnboarding::AlreadyOnboarded) { LawyerOnboarding.call(token: owner, input: profile_payload) }
    assert_equal context, IdentityStore.context(owner)
  end
end
