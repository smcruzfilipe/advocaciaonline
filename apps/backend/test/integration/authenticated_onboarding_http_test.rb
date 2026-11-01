require "test_helper"

class AuthenticatedOnboardingHttpTest < ActionDispatch::IntegrationTest
  setup do
    https!
    host! URI(AppSettings.origin).host
    @previous_ingress = ENV["AUTH_INGRESS_SECRET"]
    ENV["AUTH_INGRESS_SECRET"] = "test-ingress-secret-" + "x" * 32
    @email = "auth-#{SecureRandom.hex(12)}@example.test"
    @password = "uma senha longa de teste"
    @headers = { "Origin" => AppSettings.origin, "X-Advocacia-Ingress-Secret" => ENV.fetch("AUTH_INGRESS_SECRET"),
      "X-Advocacia-Client-IP" => "198.51.100.21" }
  end

  teardown do
    ENV["AUTH_INGRESS_SECRET"] = @previous_ingress
  end

  def register
    sent = []
    VerificationMailer.stub(:deliver!, ->(**args) { sent << args.fetch(:token) }) do
      post "/api/auth/register", params: { email: @email, password: @password }, as: :json, headers: @headers
    end
    assert_response :accepted
    sent.fetch(0)
  end

  def verify(token)
    post "/api/auth/verify-email", params: { token: token }, as: :json, headers: @headers
  end

  def login
    post "/api/auth/login", params: { email: @email, password: @password }, as: :json, headers: @headers
  end

  def finish(code)
    post "/api/auth/totp", params: { code: code }, as: :json, headers: @headers
  end

  def sign_in
    token = register
    verify(token)
    assert_response :ok
    login
    assert_equal "totp_setup", response.parsed_body.fetch("next")
    secret = response.parsed_body.fetch("secret")
    finish(PasswordAuthentication.code(secret, Time.now.to_i / 30))
    assert_response :ok
    secret
  end

  test "email verification and a valid TOTP are both required before onboarding" do
    verification = register
    login
    assert_response :unauthorized
    get "/api/session"
    assert_equal false, response.parsed_body.fetch("authenticated")
    verify(verification)
    assert_response :ok
    login
    assert_response :ok
    assert_equal "totp_setup", response.parsed_body.fetch("next")
    secret = response.parsed_body.fetch("secret")
    get "/api/session"
    assert_equal false, response.parsed_body.fetch("authenticated")
    finish("wrong")
    assert_response :unauthorized
    finish(PasswordAuthentication.code(secret, Time.now.to_i / 30))
    assert_response :ok
    assert response.parsed_body.fetch("authenticated")
    csrf = response.parsed_body.fetch("csrf_token")
    assert_includes response.headers["Set-Cookie"].to_s.downcase, "httponly"
    post "/api/onboarding", params: profile_payload, as: :json,
      headers: { "Origin" => AppSettings.origin, "X-CSRF-Token" => csrf }
    assert_response :created
    get "/api/session"
    assert_equal true, response.parsed_body.fetch("onboarded")
  end

  test "email token is browser bound, single use and does not create a session" do
    token = register
    other = ActionDispatch::Integration::Session.new(Rails.application)
    other.https!
    other.host! URI(AppSettings.origin).host
    other.post "/api/auth/verify-email", params: { token: token }, as: :json, headers: @headers
    assert_equal 422, other.response.status
    verify(token)
    assert_response :ok
    verify(token)
    assert_response :unprocessable_entity
    get "/api/session"
    assert_equal false, response.parsed_body.fetch("authenticated")
  end

  test "an unverified registration cannot reserve another person's email" do
    register
    other = ActionDispatch::Integration::Session.new(Rails.application)
    other.https!
    other.host! URI(AppSettings.origin).host
    sent = []
    VerificationMailer.stub(:deliver!, ->(**args) { sent << args.fetch(:token) }) do
      other.post "/api/auth/register", params: { email: @email, password: "outra senha segura" }, as: :json, headers: @headers
    end
    assert_equal 202, other.response.status
    other.post "/api/auth/verify-email", params: { token: sent.fetch(0) }, as: :json, headers: @headers
    assert_equal 200, other.response.status
    login
    assert_response :unauthorized
  end

  test "rate limiting applies to login attempts regardless of password" do
    20.times do
      post "/api/auth/login", params: { email: @email, password: @password }, as: :json, headers: @headers
      assert_response :unauthorized
    end
    login
    assert_response :too_many_requests
    assert_equal "900", response.headers["Retry-After"]
  end

  test "setup persists across login and a TOTP cannot be replayed" do
    verify(register)
    login
    secret = response.parsed_body.fetch("secret")
    login
    assert_equal secret, response.parsed_body.fetch("secret")
    code = PasswordAuthentication.code(secret, Time.now.to_i / 30)
    finish(code)
    assert_response :ok
    login
    assert_equal "totp", response.parsed_body.fetch("next")
    finish(code)
    assert_response :unauthorized
  end

  test "untrusted ingress and cross origin requests fail closed" do
    [@headers.except("X-Advocacia-Ingress-Secret"), @headers.merge("Origin" => "https://attacker.test"),
      @headers.merge("X-Advocacia-Client-IP" => "198.51.100.1, 127.0.0.1")].each do |headers|
      post "/api/auth/login", params: { email: @email, password: @password }, as: :json, headers: headers
      assert_response :forbidden
    end
  end

  test "onboarding still enforces CSRF and rejects invalid and duplicate profiles" do
    sign_in
    csrf = response.parsed_body.fetch("csrf_token")
    post "/api/onboarding", params: profile_payload, as: :json, headers: { "Origin" => AppSettings.origin }
    assert_response :forbidden
    headers = { "Origin" => AppSettings.origin, "X-CSRF-Token" => csrf }
    post "/api/onboarding", params: profile_payload.merge("full_name" => " "), as: :json, headers: headers
    assert_response :unprocessable_entity
    post "/api/onboarding", params: profile_payload, as: :json, headers: headers
    assert_response :created
    post "/api/onboarding", params: profile_payload, as: :json, headers: headers
    assert_response :conflict
  end
end
