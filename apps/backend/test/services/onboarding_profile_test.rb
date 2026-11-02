require "test_helper"

class OnboardingProfileTest < ActiveSupport::TestCase
  test "normalizes display whitespace without changing OAB tokens" do
    profile = OnboardingProfile.new(profile_payload)
    assert profile.valid?
    assert_equal "Ana de Ávila", profile.full_name
    assert_equal "Ávila Advocacia", profile.office_name
    assert_equal [{ number: "001234-A", uf: "SP", primary: true },
                  { number: "00a-B", uf: "RJ", primary: false }], profile.registrations
  end

  test "secondary registrations and office are optional" do
    input = profile_payload.except("office_name", "secondary_oabs")
    profile = OnboardingProfile.new(input)
    assert profile.valid?
    assert_nil profile.office_name
    assert_equal 1, profile.registrations.size
  end

  test "rejects duplicate number and normalized UF including primary" do
    input = profile_payload.merge("secondary_oabs" => [{ "number" => "001234-A", "uf" => "sp" }])
    profile = OnboardingProfile.new(input)
    assert_not profile.valid?
    assert profile.errors[:secondary_oabs].any?
  end

  test "accepts all 27 UFs and preserves literal case punctuation and internal spaces" do
    OabRegistration::UFS.each do |uf|
      profile = OnboardingProfile.new(profile_payload.merge("primary_oab" => { "number" => " 00a. A-b ", "uf" => uf }))
      assert profile.valid?, uf
      assert_equal "00a. A-b", profile.registrations.first[:number]
    end
  end

  test "rejects missing primary blank name invalid UF and malformed shapes" do
    [profile_payload.except("primary_oab"), profile_payload.merge("full_name" => " \t\n"),
     profile_payload.merge("primary_oab" => { "number" => "001", "uf" => "XX" }),
     profile_payload.merge("primary_oab" => { "number" => 123, "uf" => "SP" }),
     profile_payload.merge("secondary_oabs" => {}), profile_payload.merge("full_name" => []),
     profile_payload.merge("tenant_id" => SecureRandom.uuid), profile_payload.merge("subject" => "victim")].each do |input|
      assert_not OnboardingProfile.new(input).valid?, input.inspect
    end
  end
end
