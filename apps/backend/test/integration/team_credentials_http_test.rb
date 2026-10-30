require "test_helper"

class TeamCredentialsHttpTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    https!
    host! URI(AppSettings.origin).host
    @owner, @csrf = authenticated_session
    LawyerOnboarding.call(token: @owner, input: profile_payload)
    cookies[ApplicationController::SESSION_COOKIE] = @owner
    @email = "http-member-#{SecureRandom.hex(6)}@example.test"
    @sent = []
  end

  def headers(csrf = @csrf)
    { "Origin" => AppSettings.origin, "X-CSRF-Token" => csrf }
  end

  def deliver
    TeamInvitationMailer.stub(:deliver!, ->(**arguments) { @sent << arguments }) do
      AppSettings.stub(:smtp, {}) { yield }
    end
  end

  def create_credential(days = nil)
    deliver do
      post "/api/team/credentials", params: { email: @email, validity_days: days, group_ids: [] },
        as: :json, headers: headers
    end
    assert_response :created
    response.parsed_body.fetch("credential")
  end

  def member_session
    token = SecureRandom.urlsafe_base64(32)
    csrf = SecureRandom.urlsafe_base64(32)
    IdentityStore.authenticate(subject: SecureRandom.uuid, email: @email, token: token, csrf: csrf)
    [token, csrf]
  end

  test "creation requires explicit validity and supports lifecycle without exposing invitation secrets" do
    deliver do
      post "/api/team/credentials", params: { email: @email }, as: :json, headers: headers
    end
    assert_response :unprocessable_entity
    credential = create_credential(2)
    assert_equal 2, credential.fetch("validity_days")
    assert_equal IdentityStore.context(@owner).fetch("tenant_id"), credential.fetch("tenant_id")
    refute_includes response.body, @sent.last.fetch(:token)
    refute_includes response.body, IdentityStore.digest(@sent.last.fetch(:token))
    get "/api/team/credentials", params: { tenant_id: SecureRandom.uuid }
    assert_response :ok
    assert_equal [credential.fetch("id")], response.parsed_body.fetch("credentials").map { |row| row.fetch("id") }
    patch "/api/team/credentials/#{credential.fetch('id')}", params: { validity_days: nil }, as: :json, headers: headers
    assert_response :ok
    assert_equal credential.fetch("expires_at"), response.parsed_body.dig("credential", "expires_at")
    post "/api/team/credentials/#{credential.fetch('id')}/renewal", as: :json, headers: headers
    assert_response :ok
    assert_nil response.parsed_body.dig("credential", "expires_at")
    delete "/api/team/credentials/#{credential.fetch('id')}", as: :json, headers: headers
    assert_response :ok
    post "/api/team/credentials/#{credential.fetch('id')}/renewal", as: :json, headers: headers
    assert_response :conflict
  end

  test "recipient validation matches SMTP before any credential is persisted" do
    ["josé@example.com", "equipe@exámple.com", "Nome <equipe@example.test>",
      "equipe@example.test\r\nBcc: other@example.test"].each do |email|
      deliver do
        post "/api/team/credentials", params: { email: email, validity_days: nil }, as: :json, headers: headers
      end
      assert_response :unprocessable_entity
      assert_equal "invalid_credential", response.parsed_body.dig("error", "code")
      assert_empty @sent
      assert_empty IdentityStore.team_credentials(@owner)
    end
  end

  test "all identity mutations enforce login origin and cross-session CSRF" do
    credential = create_credential
    urls = [[:post, "/api/team/credentials"], [:patch, "/api/team/credentials/#{credential.fetch('id')}"],
      [:post, "/api/team/credentials/#{credential.fetch('id')}/renewal"],
      [:post, "/api/team/credentials/#{credential.fetch('id')}/invitation"],
      [:delete, "/api/team/credentials/#{credential.fetch('id')}"],
      [:patch, "/api/session/membership"], [:delete, "/api/session"], [:post, "/api/team/invitations/accept"]]
    urls.each do |verb, url|
      public_send(verb, url, params: {}, as: :json)
      assert_response :forbidden
      public_send(verb, url, params: {}, as: :json,
        headers: { "Origin" => "https://attacker.test", "X-CSRF-Token" => @csrf })
      assert_response :forbidden
    end
    cookies.delete(ApplicationController::SESSION_COOKIE)
    get "/api/team/credentials"
    assert_response :unauthorized
    post "/api/team/invitations/accept", params: { token: @sent.last.fetch(:token) }, as: :json, headers: headers
    assert_response :unauthorized
  end

  test "acceptance uses Google email and JSON body token rather than URL claims" do
    credential = create_credential
    member, csrf = member_session
    cookies[ApplicationController::SESSION_COOKIE] = member
    post "/api/team/invitations/accept?token=#{"A" * 43}", params: {}, as: :json, headers: headers(csrf)
    assert_response :unprocessable_entity
    assert_nil IdentityStore.context(member).fetch("tenant_id")
    post "/api/team/invitations/accept", params: { token: @sent.last.fetch(:token), tenant_id: SecureRandom.uuid },
      as: :json, headers: headers(csrf)
    assert_response :ok
    assert_equal credential.fetch("id"), response.parsed_body.dig("membership", "membership_id")
    assert_equal credential.fetch("tenant_id"), IdentityStore.context(member).fetch("tenant_id")
    get "/api/team/credentials"
    assert_response :forbidden
    post "/api/team/invitations/accept", params: { token: @sent.last.fetch(:token) }, as: :json, headers: headers(csrf)
    assert_response :unprocessable_entity
  end

  test "selection is verified and expired active membership cannot access a protected endpoint" do
    credential = create_credential(1)
    member, csrf = member_session
    IdentityStore.accept_invitation(token: member, invitation_token: @sent.last.fetch(:token))
    cookies[ApplicationController::SESSION_COOKIE] = member
    patch "/api/session/membership", params: { membership_id: IdentityStore.context(@owner).fetch("membership_id") },
      as: :json, headers: headers(csrf)
    assert_response :forbidden
    assert_equal credential.fetch("id"), IdentityStore.context(member).fetch("membership_id")
    connection = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    begin
      connection.exec_params("UPDATE app_private.tenant_memberships SET expires_at = statement_timestamp() WHERE id = $1", [credential.fetch("id")])
    ensure
      connection.close
    end
    get "/api/onboarding"
    assert_response :unauthorized
    get "/api/session"
    assert_response :ok
    assert_equal true, response.parsed_body.fetch("authenticated")
    assert_nil response.parsed_body.fetch("tenant_id")
    assert_empty response.parsed_body.fetch("memberships")
    delete "/api/session", as: :json, headers: headers(csrf)
    assert_response :no_content
    assert_nil IdentityStore.session_identity(member)
  end

  test "SMTP failure reports uncertain delivery and preserves a credential for explicit reissue" do
    TeamInvitationMailer.stub(:deliver!, ->(**) { raise TeamInvitationMailer::DeliveryFailed, "SMTP delivery failed" }) do
      AppSettings.stub(:smtp, {}) do
        post "/api/team/credentials", params: { email: @email, validity_days: 2 }, as: :json, headers: headers
      end
    end
    assert_response :bad_gateway
    assert_equal "invitation_delivery_failed", response.parsed_body.dig("error", "code")
    assert_includes response.parsed_body.dig("error", "message"), "reemita"
    assert_equal 1, IdentityStore.team_credentials(@owner).length
    credential = IdentityStore.team_credentials(@owner).first
    deliver do
      post "/api/team/credentials/#{credential.fetch('id')}/invitation", as: :json, headers: headers
    end
    assert_response :ok
    assert_equal credential.fetch("id"), response.parsed_body.dig("credential", "id")
    assert_equal credential.fetch("expires_at").as_json, response.parsed_body.dig("credential", "expires_at")
    assert_equal credential.fetch("credential_started_at").as_json, response.parsed_body.dig("credential", "credential_started_at")
  end

  test "invalid group rolls back membership creation before sending" do
    deliver do
      post "/api/team/credentials", params: { email: @email, validity_days: nil, group_ids: [SecureRandom.uuid] },
        as: :json, headers: headers
    end
    assert_response :not_found
    assert_empty @sent
    assert_empty IdentityStore.team_credentials(@owner)
  end
end
