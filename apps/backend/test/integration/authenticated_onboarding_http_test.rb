require "test_helper"

class AuthenticatedOnboardingHttpTest < ActionDispatch::IntegrationTest
  setup do
    https!
    host! URI(AppSettings.origin).host
    Rails.cache.clear
    @key = OpenSSL::PKey::RSA.generate(2048)
    @jwk = JWT::JWK.new(@key, kid: "http-test-key", use: "sig", alg: "RS256")
    @subject = SecureRandom.uuid
  end

  def begin_login
    get "/auth/google"
    assert_response :redirect
    URI.decode_www_form(URI(response.location).query).to_h
  end

  def finish_login(query, email_verified: true)
    payload = { "iss" => GoogleOidc::ISSUER, "sub" => @subject,
      "aud" => AppSettings.google_client_id, "iat" => Time.now.to_i, "exp" => Time.now.to_i + 300,
      "nonce" => query.fetch("nonce"), "email" => "lawyer@example.test", "email_verified" => email_verified }
    id_token = JWT.encode(payload, @key, "RS256", kid: "http-test-key")
    client = GoogleOidc.new
    transport = lambda do |url, form: nil|
      if url == GoogleOidc::TOKEN_ENDPOINT
        assert_equal "authorization_code", form.fetch(:grant_type)
        assert_equal query.fetch("code_challenge"), Base64.urlsafe_encode64(Digest::SHA256.digest(form.fetch(:code_verifier)), padding: false)
        { "id_token" => id_token }
      else
        assert_equal GoogleOidc::JWKS_ENDPOINT, url
        { "keys" => [@jwk.export.transform_keys(&:to_s)] }
      end
    end
    client.stub(:request_json, transport) do
      GoogleOidc.stub(:new, client) do
        get "/auth/google/callback", params: { state: query.fetch("state"), code: "test-only-authorization-code" }
      end
    end
  end

  def csrf
    get "/api/session"
    response.parsed_body.fetch("csrf_token")
  end

  test "unauthenticated identity claims never authorize onboarding" do
    get "/api/session"
    assert_equal({ "authenticated" => false, "onboarded" => false }, response.parsed_body)
    post "/api/onboarding", params: { tenant_id: SecureRandom.uuid, subject: "someone" }, as: :json
    assert_response :unauthorized
  end

  test "real signed token callback returns backend-only JSON and completes onboarding" do
    query = begin_login
    finish_login(query)
    assert_response :ok
    assert_equal "application/json", response.media_type
    assert_nil response.headers["Location"]
    assert_equal true, response.parsed_body.fetch("authenticated")
    assert_equal false, response.parsed_body.fetch("onboarded")
    assert_match(/\A[A-Za-z0-9_-]{43}\z/, response.parsed_body.fetch("csrf_token"))
    cookie = response.headers["Set-Cookie"].to_s
    assert_includes cookie.downcase, "secure"
    assert_includes cookie.downcase, "httponly"
    assert_includes cookie.downcase, "samesite=lax"
    refute_match(/domain=/i, cookie)
    token = csrf
    assert_equal true, response.parsed_body.fetch("authenticated")
    assert_equal false, response.parsed_body.fetch("onboarded")
    assert_equal "no-store", response.headers["Cache-Control"]
    post "/api/onboarding", params: profile_payload, as: :json,
      headers: { "Origin" => AppSettings.origin, "X-CSRF-Token" => token }
    assert_response :created
    assert_equal "001234-A", response.parsed_body.dig("profile", "primary_oab", "number")
    assert_equal true, response.parsed_body.fetch("onboarded")
    get "/api/session"
    assert_equal true, response.parsed_body.fetch("onboarded")
  end

  test "missing wrong cross-session and cross-origin CSRF fail closed" do
    finish_login(begin_login)
    token = csrf
    [{ "Origin" => AppSettings.origin },
     { "Origin" => AppSettings.origin, "X-CSRF-Token" => SecureRandom.urlsafe_base64(32) },
     { "Origin" => "https://attacker.test", "X-CSRF-Token" => token },
     { "X-CSRF-Token" => token }].each do |headers|
      post "/api/onboarding", params: profile_payload, as: :json, headers: headers
      assert_response :forbidden
      assert_equal "invalid_csrf", response.parsed_body.dig("error", "code")
    end
  end

  test "unverified Google email and replayed state create no new authenticated session" do
    query = begin_login
    finish_login(query, email_verified: false)
    assert_response :unauthorized
    assert_equal "application/json", response.media_type
    assert_nil response.headers["Location"]
    assert_equal "google_login_failed", response.parsed_body.dig("error", "code")
    get "/api/session"
    assert_equal false, response.parsed_body.fetch("authenticated")
    finish_login(query)
    assert_response :unauthorized
    assert_equal "application/json", response.media_type
    assert_nil response.headers["Location"]
    assert_equal "google_login_failed", response.parsed_body.dig("error", "code")
    get "/api/session"
    assert_equal false, response.parsed_body.fetch("authenticated")
  end

  test "login state from another browser is not accepted" do
    query = begin_login
    other = ActionDispatch::Integration::Session.new(Rails.application)
    other.https!
    other.host! URI(AppSettings.origin).host
    other.get "/auth/google/callback", params: { state: query.fetch("state"), code: "stolen" }
    assert_equal 401, other.response.status
    assert_equal "application/json", other.response.media_type
    assert_nil other.response.headers["Location"]
    assert_equal "google_login_failed", other.response.parsed_body.dig("error", "code")
    other.get "/api/session"
    assert_equal false, other.response.parsed_body.fetch("authenticated")
    finish_login(query)
    assert_response :ok
    assert_equal true, response.parsed_body.fetch("authenticated")
  end

  test "new login rotates and invalidates the old server-side session" do
    finish_login(begin_login)
    old_token = cookies[ApplicationController::SESSION_COOKIE]
    old_csrf = csrf
    finish_login(begin_login)
    assert_not_equal old_token, cookies[ApplicationController::SESSION_COOKIE]
    assert_nil IdentityStore.context(old_token)
    assert_not_equal old_csrf, csrf
  end

  test "invalid profile returns field details and completed profile cannot be replaced" do
    finish_login(begin_login)
    token = csrf
    headers = { "Origin" => AppSettings.origin, "X-CSRF-Token" => token }
    post "/api/onboarding", params: profile_payload.merge("full_name" => " "), as: :json, headers: headers
    assert_response :unprocessable_entity
    assert response.parsed_body.dig("error", "details", "full_name").any?
    post "/api/onboarding", params: profile_payload, as: :json, headers: headers
    assert_response :created
    post "/api/onboarding", params: profile_payload, as: :json, headers: headers
    assert_response :conflict
  end
end
