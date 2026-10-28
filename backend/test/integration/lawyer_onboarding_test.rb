require "test_helper"

class LawyerOnboardingTest < ActiveSupport::TestCase
  test "persists complete profile and derives separate tenants despite same office" do
    first_token, = authenticated_session
    second_token, = authenticated_session
    first = LawyerOnboarding.call(token: first_token, input: profile_payload)
    second = LawyerOnboarding.call(token: second_token, input: profile_payload.except("secondary_oabs"))
    assert_not_equal first.tenant_id, second.tenant_id
    DatabaseContext.with_session(first_token) do
      profile = Lawyer.find(first.id)
      assert_equal "Ana de Ávila", profile.full_name
      assert_equal "Ávila Advocacia", profile.office_name
      assert_equal [["001234-A", "SP", true], ["00a-B", "RJ", false]],
        profile.oab_registrations.order(primary: :desc).pluck(:number, :uf, :primary)
    end
    DatabaseContext.with_session(second_token) { assert_equal 1, OabRegistration.count }
  end

  test "validation failure creates no tenant profile or identity association" do
    token, = authenticated_session
    input = profile_payload.merge("secondary_oabs" => [{ "number" => "001234-A", "uf" => "SP" }])
    assert_raises(LawyerOnboarding::InvalidProfile) { LawyerOnboarding.call(token: token, input: input) }
    assert_nil IdentityStore.context(token).fetch("tenant_id")
    DatabaseContext.with_session(token) { assert_equal 0, Tenant.count }
  end

  test "database failure rolls back tenant claim and all profile rows" do
    token, = authenticated_session
    OabRegistration.stub(:create!, ->(*) { raise ActiveRecord::RecordInvalid.new(OabRegistration.new) }) do
      assert_raises(ActiveRecord::RecordInvalid) { LawyerOnboarding.call(token: token, input: profile_payload) }
    end
    assert_nil IdentityStore.context(token).fetch("tenant_id")
    DatabaseContext.with_session(token) { assert_equal 0, Tenant.count }
  end

  test "second onboarding conflicts without replacing profile" do
    token, = authenticated_session
    LawyerOnboarding.call(token: token, input: profile_payload)
    assert_raises(LawyerOnboarding::AlreadyOnboarded) { LawyerOnboarding.call(token: token, input: profile_payload) }
    DatabaseContext.with_session(token) { assert_equal 1, Lawyer.count }
  end

  test "client identity and tenant cannot replace session proof" do
    token, = authenticated_session
    assert_raises(LawyerOnboarding::InvalidProfile) do
      LawyerOnboarding.call(token: token, input: profile_payload.merge("tenant_id" => SecureRandom.uuid))
    end
    assert_raises(LawyerOnboarding::Unauthenticated) do
      LawyerOnboarding.call(token: SecureRandom.urlsafe_base64(32), input: profile_payload)
    end
  end
end
