require "test_helper"

class TeamRegistrationHttpTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    https!
    host! URI(AppSettings.origin).host
    @previous_ingress = ENV["AUTH_INGRESS_SECRET"]
    ENV["AUTH_INGRESS_SECRET"] = "team-registration-http-" + "x" * 32
    @headers = { "Origin" => AppSettings.origin, "X-Advocacia-Ingress-Secret" => ENV.fetch("AUTH_INGRESS_SECRET"),
      "X-Advocacia-Client-IP" => "2001:db8:#{SecureRandom.hex(2)}:#{SecureRandom.hex(2)}::1" }
    @email = "team-http-#{SecureRandom.hex(12)}@example.test"
    @password = "senha de equipe suficientemente longa"
    owner, = authenticated_session(owner: true)
    LawyerOnboarding.call(token: owner, input: profile_payload)
    TeamInvitationMailer.stub(:deliver!, ->(**args) { @invitation = args.fetch(:token) }) do
      @member = IdentityStore.create_credential(token: owner, email: @email, validity_days: nil, smtp: {})
    end
  end

  teardown do
    ENV["AUTH_INGRESS_SECRET"] = @previous_ingress
  end

  test "invited account needs mailbox verification and TOTP before accepting the invitation" do
    sent = []
    VerificationMailer.stub(:deliver!, ->(**args) { sent << args.fetch(:token) }) do
      register(token: SecureRandom.urlsafe_base64(32), email: @email)
      assert_response :accepted
      assert_empty sent
      register(token: @invitation, email: "other-#{@email}")
      assert_response :accepted
      assert_empty sent
      register(token: @invitation, email: @email)
      assert_response :accepted
    end
    assert_equal 1, sent.length
    post "/api/auth/login", params: { email: @email, password: @password }, as: :json, headers: @headers
    assert_response :unauthorized
    post "/api/auth/verify-email", params: { token: sent.fetch(0) }, as: :json, headers: @headers
    assert_response :ok
    post "/api/auth/login", params: { email: @email, password: @password }, as: :json, headers: @headers
    assert_response :ok
    assert_equal "totp_setup", response.parsed_body.fetch("next")
    secret = response.parsed_body.fetch("secret")
    post "/api/auth/totp", params: { code: PasswordAuthentication.code(secret, Time.now.to_i / 30) }, as: :json, headers: @headers
    assert_response :ok
    assert_equal false, response.parsed_body.fetch("can_create_tenant")
    csrf = response.parsed_body.fetch("csrf_token")
    post "/api/team/invitations/accept", params: { token: @invitation }, as: :json,
      headers: { "Origin" => AppSettings.origin, "X-CSRF-Token" => csrf }
    assert_response :success
    assert_equal @member.fetch("id"), response.parsed_body.fetch("membership").fetch("membership_id")
    get "/api/session"
    assert_equal "member", response.parsed_body.fetch("role")
    assert_equal false, response.parsed_body.fetch("can_create_tenant")
    post "/api/onboarding", params: profile_payload, as: :json,
      headers: { "Origin" => AppSettings.origin, "X-CSRF-Token" => csrf }
    assert_response :forbidden
    identity = IdentityStore.session_identity(cookies[ApplicationController::SESSION_COOKIE]).fetch("identity_id")
    grant_fixture_owner(identity)
    get "/api/session"
    assert_equal "member", response.parsed_body.fetch("role")
    assert_equal true, response.parsed_body.fetch("can_create_tenant")
    post "/api/onboarding", params: profile_payload, as: :json,
      headers: { "Origin" => AppSettings.origin, "X-CSRF-Token" => csrf }
    assert_response :created
    get "/api/session"
    assert_equal "owner", response.parsed_body.fetch("role")
    assert_equal false, response.parsed_body.fetch("can_create_tenant")
    patch "/api/session/membership", params: { membership_id: @member.fetch("id") }, as: :json,
      headers: { "Origin" => AppSettings.origin, "X-CSRF-Token" => csrf }
    assert_response :ok
    get "/api/session"
    assert_equal "member", response.parsed_body.fetch("role")
    assert_equal false, response.parsed_body.fetch("can_create_tenant")
  end

  test "existing unverified lawyer confirms the invited mailbox without changing password or TOTP" do
    session, csrf = authenticated_session(email: @email)
    before = IdentityStore.call("password_lookup", @email)
    with_fixture_database do |db|
      db.exec_params("UPDATE app_private.identities SET email_verified_at=NULL WHERE id=$1", [before.fetch("identity_id")])
    end
    cookies[ApplicationController::SESSION_COOKIE] = session
    headers = @headers.merge("X-CSRF-Token" => csrf)
    post "/api/team/invitations/accept", params: { token: @invitation }, as: :json, headers: headers
    assert_response :unprocessable_entity
    sent = []
    VerificationMailer.stub(:deliver!, ->(**args) { sent << args.fetch(:token) }) do
      post "/api/auth/team-register", params: { token: @invitation, email: @email }, as: :json, headers: @headers
      assert_response :forbidden
      post "/api/auth/team-register", params: { token: @invitation, email: @email }, as: :json, headers: headers
      assert_response :accepted
    end
    post "/api/auth/verify-email", params: { token: sent.fetch(0) }, as: :json, headers: headers
    assert_response :ok
    assert_equal before, IdentityStore.call("password_lookup", @email)
    post "/api/team/invitations/accept", params: { token: @invitation }, as: :json, headers: headers
    assert_response :success
    assert_equal @member.fetch("id"), response.parsed_body.fetch("membership").fetch("membership_id")
  end

  private

  def register(token:, email:)
    post "/api/auth/team-register", params: { token: token, email: email, password: @password,
      password_confirmation: @password }, as: :json, headers: @headers
  end
end
