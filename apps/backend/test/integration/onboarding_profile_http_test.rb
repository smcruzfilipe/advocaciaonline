require "test_helper"

class OnboardingProfileHttpTest < ActionDispatch::IntegrationTest
  setup do
    https!
    host! URI(AppSettings.origin).host
  end

  test "reads the authenticated lawyer profile OABs and own tenant without trusting query identity" do
    first_token, = authenticated_session
    second_token, = authenticated_session
    first = LawyerOnboarding.call(token: first_token, input: profile_payload)
    second_input = profile_payload.merge("full_name" => "Bruno Lima",
      "primary_oab" => { "number" => "000777-B", "uf" => "MG" }, "secondary_oabs" => [])
    second = LawyerOnboarding.call(token: second_token, input: second_input)
    assert_not_equal first.tenant_id, second.tenant_id

    cookies[ApplicationController::SESSION_COOKIE] = first_token
    get "/api/onboarding"
    assert_response :ok
    assert_equal "application/json", response.media_type
    assert_equal "no-store", response.headers["Cache-Control"]
    first_body = response.parsed_body
    assert_equal first.tenant_id, first_body.fetch("tenant_id")
    assert_equal({ "full_name" => "Ana de Ávila", "office_name" => "Ávila Advocacia",
      "primary_oab" => { "number" => "001234-A", "uf" => "SP" },
      "secondary_oabs" => [{ "number" => "00a-B", "uf" => "RJ" }] }, first_body.fetch("profile"))

    get "/api/onboarding", params: { tenant_id: second.tenant_id, subject: "another-google-user" }
    assert_response :ok
    assert_equal first_body, response.parsed_body

    cookies[ApplicationController::SESSION_COOKIE] = second_token
    get "/api/onboarding", params: { tenant_id: first.tenant_id }
    assert_response :ok
    assert_equal second.tenant_id, response.parsed_body.fetch("tenant_id")
    assert_equal "Bruno Lima", response.parsed_body.dig("profile", "full_name")
    assert_equal({ "number" => "000777-B", "uf" => "MG" }, response.parsed_body.dig("profile", "primary_oab"))
    assert_equal [], response.parsed_body.dig("profile", "secondary_oabs")
  end

  test "profile read without a valid server-side session is denied" do
    get "/api/onboarding", params: { tenant_id: SecureRandom.uuid, subject: "claimed-identity" }
    assert_response :unauthorized
    assert_equal "authentication_required", response.parsed_body.dig("error", "code")

    token, = authenticated_session
    LawyerOnboarding.call(token: token, input: profile_payload)
    cookies[ApplicationController::SESSION_COOKIE] = token
    IdentityStore.revoke(token)
    get "/api/onboarding"
    assert_response :unauthorized
    assert_equal "authentication_required", response.parsed_body.dig("error", "code")
  end

  test "authenticated lawyer without onboarding has no invented profile or tenant" do
    token, = authenticated_session
    cookies[ApplicationController::SESSION_COOKIE] = token
    get "/api/onboarding"
    assert_response :not_found
    assert_equal "onboarding_required", response.parsed_body.dig("error", "code")
    assert_nil IdentityStore.context(token).fetch("tenant_id")
  end
end
