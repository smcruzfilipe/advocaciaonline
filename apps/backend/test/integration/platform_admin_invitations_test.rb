require "test_helper"
require "pg"

class PlatformAdminInvitationsTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    @operator = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    raise "Use a disposable test database" unless @operator.db.start_with?("advocacia_test")
    raise "Platform administrator already provisioned" if @operator.exec("SELECT 1 FROM app_private.platform_administrator").ntuples.positive?
    @identities = []
    @token, @csrf = authenticated_session
    @admin = remember_identity(@token)
    @operator.exec_params("INSERT INTO app_private.platform_administrator(identity_id) VALUES ($1)", [@admin])
    @email = "http-pa05-#{SecureRandom.hex(8)}@example.test"
    https!
    host! "example.test"
    cookies[ApplicationController::SESSION_COOKIE] = @token
    @headers = { "Origin" => AppSettings.origin, "X-CSRF-Token" => @csrf }
  end

  teardown do
    if @operator
      @operator.exec_params("DELETE FROM app_private.first_access_invitations WHERE email = $1", [@email]) if @email
      Array(@identities).each do |id|
        %w[first_access_grants platform_administrator sessions password_challenges password_credentials].each do |table|
          @operator.exec_params("DELETE FROM app_private.#{table} WHERE identity_id = $1", [id])
        end
        @operator.exec_params("DELETE FROM app_private.identities WHERE id = $1", [id])
      end
      @operator.close
    end
  end

  test "issue and list expose metadata only while explicit copy keeps the same link and expiry" do
    issue(email: " #{@email.upcase} ")
    assert_response :created
    invitation = response.parsed_body
    assert_equal @email, invitation.fetch("email")
    refute_match(/token|cipher|password|secret|link/, response.body)
    id = invitation.fetch("id")
    get "/api/admin/invitations", headers: @headers
    assert_response :ok
    assert_includes response.parsed_body.fetch("invitations"), invitation
    refute_match(/token|cipher|password|secret|link/, response.body)
    get "/api/admin/invitations/#{id}/link", headers: @headers
    assert_response :ok
    first = response.parsed_body
    assert_match(%r{\Ahttps://example\.test/primeiro-acesso#token=[A-Za-z0-9_-]{43}\z}, first.fetch("link"))
    assert_equal "no-store", response.headers["Cache-Control"]
    get "/api/admin/invitations/#{id}/link", headers: @headers
    assert_response :ok
    assert_equal first, response.parsed_body
    assert_equal invitation.fetch("expires_at"), first.fetch("expires_at")
  end

  test "duplicate issue conflicts and only explicit reissue replaces the old invitation" do
    issue
    assert_response :created
    first = response.parsed_body
    get "/api/admin/invitations/#{first.fetch('id')}/link", headers: @headers
    old_link = response.parsed_body.fetch("link")
    issue
    assert_response :conflict
    get "/api/admin/invitations/#{first.fetch('id')}/link", headers: @headers
    assert_equal old_link, response.parsed_body.fetch("link")
    post "/api/admin/invitations/#{first.fetch('id')}/reissue", params: {}, headers: @headers, as: :json
    assert_response :created
    replacement = response.parsed_body
    refute_equal first.fetch("id"), replacement.fetch("id")
    refute_match(/token|cipher|password|secret|link/, response.body)
    get "/api/admin/invitations/#{first.fetch('id')}/link", headers: @headers
    assert_response :not_found
    get "/api/admin/invitations/#{replacement.fetch('id')}/link", headers: @headers
    assert_response :ok
    refute_equal old_link, response.parsed_body.fetch("link")
  end

  test "missing and expired invitations never return a link" do
    get "/api/admin/invitations/#{SecureRandom.uuid}/link", headers: @headers
    assert_response :not_found
    get "/api/admin/invitations/not-a-uuid/link", headers: @headers
    assert_response :not_found
    issue
    assert_response :created
    id = response.parsed_body.fetch("id")
    @operator.exec_params("WITH t AS (SELECT clock_timestamp() AS now) UPDATE app_private.first_access_invitations i SET created_at = t.now - interval '25 hours', expires_at = t.now - interval '1 hour' FROM t WHERE i.id = $1", [id])
    get "/api/admin/invitations/#{id}/link", headers: @headers
    assert_response :not_found
    refute_includes response.body, "#token="
    assert_equal "0", @operator.exec_params("SELECT count(*) FROM app_private.first_access_invitations WHERE id = $1", [id]).getvalue(0, 0)
    post "/api/admin/invitations/#{id}/reissue", params: {}, headers: @headers, as: :json
    assert_response :not_found
  end

  test "ordinary users cannot acquire administration through client flags" do
    token, csrf = authenticated_session
    remember_identity(token)
    cookies[ApplicationController::SESSION_COOKIE] = token
    get "/api/admin/invitations", headers: @headers
    assert_response :forbidden
    post "/api/admin/invitations", params: { email: @email, platform_admin: true, role: "owner" },
      headers: @headers.merge("X-CSRF-Token" => csrf), as: :json
    assert_response :forbidden
    assert_equal "0", @operator.exec_params("SELECT count(*) FROM app_private.first_access_invitations WHERE email = $1", [@email]).getvalue(0, 0)
  end

  test "missing or revoked common sessions are denied" do
    cookies.delete(ApplicationController::SESSION_COOKIE)
    get "/api/admin/invitations", headers: @headers
    assert_response :unauthorized
    cookies[ApplicationController::SESSION_COOKIE] = @token
    IdentityStore.call("revoke_session", IdentityStore.digest(@token))
    get "/api/admin/invitations", headers: @headers
    assert_response :unauthorized
  end

  test "origin CSRF and invalid input never issue an invitation" do
    issue(headers: @headers.merge("Origin" => "https://evil.test"))
    assert_response :forbidden
    issue(headers: @headers.except("X-CSRF-Token"))
    assert_response :forbidden
    issue(email: "not-an-email")
    assert_response :unprocessable_entity
    get "/api/admin/invitations", headers: @headers.merge("Origin" => "https://evil.test", "Sec-Fetch-Site" => "same-origin")
    assert_response :forbidden
    get "/api/admin/invitations", headers: { "Sec-Fetch-Site" => "same-origin" }
    assert_response :ok
    assert_empty response.parsed_body.fetch("invitations")
  end

  test "explicit email sends the same active invitation without changing its expiry" do
    issue
    assert_response :created
    invitation = response.parsed_body
    id = invitation.fetch("id")
    get "/api/admin/invitations/#{id}/link", headers: @headers
    original = response.parsed_body
    deliveries = []
    FirstAccessInvitationMailer.stub(:deliver!, ->(**args) { deliveries << args }) do
      2.times do
        post "/api/admin/invitations/#{id}/email", params: {}, headers: @headers, as: :json
        assert_response :ok
        assert_equal({ "accepted" => true, "message" => "Mensagem aceita pelo servidor SMTP; isso não confirma entrega na caixa postal." }, response.parsed_body)
        refute_includes response.body, original.fetch("link")
      end
    end
    assert_equal [{ email: @email, link: original.fetch("link") }] * 2, deliveries
    get "/api/admin/invitations/#{id}/link", headers: @headers
    assert_equal original, response.parsed_body
    assert_equal invitation.fetch("expires_at"), original.fetch("expires_at")
  end

  test "failed or uncertain email leaves the original link available for copying" do
    issue
    assert_response :created
    invitation = response.parsed_body
    id = invitation.fetch("id")
    get "/api/admin/invitations/#{id}/link", headers: @headers
    original = response.parsed_body
    [FirstAccessInvitationMailer::DeliveryFailed, FirstAccessInvitationMailer::DeliveryUnknown].each do |failure|
      FirstAccessInvitationMailer.stub(:deliver!, ->(**) { raise failure, "secret #{@email} #{original.fetch('link')}" }) do
        post "/api/admin/invitations/#{id}/email", params: {}, headers: @headers, as: :json
      end
      assert_response :service_unavailable
      assert_equal "invitation_email_failed", response.parsed_body.fetch("error").fetch("code")
      refute_includes response.body, original.fetch("link")
      refute_includes response.body, @email
      if failure == FirstAccessInvitationMailer::DeliveryUnknown
        assert_match(/desconhecido/i, response.parsed_body.fetch("error").fetch("message"))
      end
      get "/api/admin/invitations/#{id}/link", headers: @headers
      assert_response :ok
      assert_equal original, response.parsed_body
    end
  end

  test "email requires administrator origin csrf and an active invitation" do
    issue
    assert_response :created
    id = response.parsed_body.fetch("id")
    FirstAccessInvitationMailer.stub(:deliver!, ->(**) { flunk "unauthorized or inactive invitation was sent" }) do
      post "/api/admin/invitations/#{id}/email", params: {}, headers: @headers.merge("Origin" => "https://evil.test"), as: :json
      assert_response :forbidden
      post "/api/admin/invitations/#{id}/email", params: {}, headers: @headers.except("X-CSRF-Token"), as: :json
      assert_response :forbidden
      post "/api/admin/invitations/#{SecureRandom.uuid}/email", params: {}, headers: @headers, as: :json
      assert_response :not_found
      post "/api/admin/invitations/not-a-uuid/email", params: {}, headers: @headers, as: :json
      assert_response :not_found
      token, csrf = authenticated_session
      remember_identity(token)
      cookies[ApplicationController::SESSION_COOKIE] = token
      post "/api/admin/invitations/#{id}/email", params: {}, headers: @headers.merge("X-CSRF-Token" => csrf), as: :json
      assert_response :forbidden
      cookies.delete(ApplicationController::SESSION_COOKIE)
      post "/api/admin/invitations/#{id}/email", params: {}, headers: @headers, as: :json
      assert_response :unauthorized
      cookies[ApplicationController::SESSION_COOKIE] = @token
      @operator.exec_params("WITH t AS (SELECT clock_timestamp() AS now) UPDATE app_private.first_access_invitations i SET created_at = t.now - interval '25 hours', expires_at = t.now - interval '1 hour' FROM t WHERE i.id = $1", [id])
      post "/api/admin/invitations/#{id}/email", params: {}, headers: @headers, as: :json
      assert_response :not_found
    end
  end

  test "email revalidates the administrator session at link retrieval" do
    issue
    assert_response :created
    id = response.parsed_body.fetch("id")
    list = FirstAccessInvitationStore.method(:list)
    revoke_after_list = lambda do |token:|
      invitations = list.call(token: token)
      IdentityStore.call("revoke_session", IdentityStore.digest(token))
      invitations
    end
    FirstAccessInvitationStore.stub(:list, revoke_after_list) do
      FirstAccessInvitationMailer.stub(:deliver!, ->(**) { flunk "revoked session sent an invitation" }) do
        post "/api/admin/invitations/#{id}/email", params: {}, headers: @headers, as: :json
      end
    end
    assert_response :unauthorized
  end

  test "reissuing invalidates the prior invitation for email too" do
    issue
    assert_response :created
    id = response.parsed_body.fetch("id")
    post "/api/admin/invitations/#{id}/reissue", params: {}, headers: @headers, as: :json
    assert_response :created
    FirstAccessInvitationMailer.stub(:deliver!, ->(**) { flunk "replaced invitation was sent" }) do
      post "/api/admin/invitations/#{id}/email", params: {}, headers: @headers, as: :json
    end
    assert_response :not_found
  end

  private

  def remember_identity(token)
    id = IdentityStore.session_identity(token).fetch("identity_id")
    @identities << id
    id
  end

  def issue(email: @email, headers: @headers)
    post "/api/admin/invitations", params: { email: email }, headers: headers, as: :json
  end
end
