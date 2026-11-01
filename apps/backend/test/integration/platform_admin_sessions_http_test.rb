require "test_helper"
require "ipaddr"

class PlatformAdminSessionsHttpTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    https!
    host! URI(AppSettings.origin).host
    @previous_ingress = ENV["AUTH_INGRESS_SECRET"]
    ENV["AUTH_INGRESS_SECRET"] = "admin-http-ingress-" + "x" * 32
    @headers = { "Origin" => AppSettings.origin, "X-Advocacia-Ingress-Secret" => ENV.fetch("AUTH_INGRESS_SECRET"),
      "X-Advocacia-Client-IP" => "2001:db8:#{SecureRandom.hex(2)}:#{SecureRandom.hex(2)}::1" }
    @buckets = []
    @identities = []
    @email = "admin-http-#{SecureRandom.hex(12)}@example.test"
    @password = "senha sintetica administrativa"
    @secret = PasswordAuthentication.new_secret
    @codes = PasswordAuthentication.new_recovery_codes
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    assert_equal "advocacia_migrator", @admin.exec("SELECT current_user").getvalue(0, 0)
    @admin.transaction do |db|
      @id = insert_identity(db, @email, @password, @secret)
      db.exec_params("INSERT INTO app_private.platform_administrator(identity_id) VALUES ($1)", [@id])
      @codes.each do |code|
        db.exec_params("INSERT INTO app_private.platform_recovery_codes(identity_id, code_hash) VALUES ($1, $2)",
          [@id, PasswordAuthentication.recovery_code_hash(code)])
      end
    end
  end

  teardown do
    if @admin
      @identities.each do |id|
        %w[platform_recovery_challenges platform_recovery_codes platform_administrator password_resets password_challenges sessions password_credentials].each do |table|
          @admin.exec_params("DELETE FROM app_private.#{table} WHERE identity_id = $1", [id])
        end
        @admin.exec_params("DELETE FROM app_private.identities WHERE id = $1", [id])
      end
      @buckets.uniq.each do |bucket|
        hash = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, bucket)
        @admin.exec_params("DELETE FROM app_private.auth_limits WHERE bucket_hash = $1", [hash])
      end
      @admin.close
    end
    ENV["AUTH_INGRESS_SECRET"] = @previous_ingress
  end

  test "password and TOTP login expose server resolved administration only in authenticated sessions and logout revokes it" do
    get "/api/session"
    assert_equal({ "authenticated" => false, "onboarded" => false }, response.parsed_body)
    login(@email, @password, extra: { platform_admin: true, role: "owner", tenant_id: SecureRandom.uuid })
    assert_response :ok
    assert_equal({ "next" => "totp" }, response.parsed_body)
    get "/api/session"
    assert_equal({ "authenticated" => false, "onboarded" => false }, response.parsed_body)
    finish_totp(@secret)
    assert_response :ok
    assert_equal true, response.parsed_body.fetch("platform_admin")
    assert_nil response.parsed_body.fetch("tenant_id")
    assert_no_factor_leak(response.body, @secret, *@codes)
    csrf = response.parsed_body.fetch("csrf_token")
    get "/api/session"
    assert_response :ok
    assert_equal true, response.parsed_body.fetch("platform_admin")
    assert_no_factor_leak(response.body, @secret, *@codes)
    delete "/api/session", headers: { "Origin" => AppSettings.origin, "X-CSRF-Token" => csrf }
    assert_response :no_content
    get "/api/session"
    assert_equal({ "authenticated" => false, "onboarded" => false }, response.parsed_body)
  end

  test "ordinary password and TOTP login cannot acquire administration from request fields" do
    email = "ordinary-#{SecureRandom.hex(12)}@example.test"
    secret = PasswordAuthentication.new_secret
    @admin.transaction { |db| insert_identity(db, email, @password, secret) }
    login(email, @password, extra: { platform_admin: true, role: "owner", tenant_id: SecureRandom.uuid })
    assert_response :ok
    finish_totp(secret, extra: { platform_admin: true, role: "owner" })
    assert_response :ok
    assert_equal false, response.parsed_body.fetch("platform_admin")
    get "/api/session"
    assert_equal false, response.parsed_body.fetch("platform_admin")

    assert_no_factor_leak(response.body, secret)
  end
  test "invalid TOTP and replay cannot create an authenticated session" do
    step = Time.now.to_i / 30
    login(@email, @password)
    assert_response :ok
    post "/api/auth/totp", params: { code: "not-a-code" }, as: :json, headers: @headers
    assert_response :unauthorized
    get "/api/session"
    assert_equal false, response.parsed_body.fetch("authenticated")
    finish_totp(@secret, step: step)
    assert_response :ok
    csrf = response.parsed_body.fetch("csrf_token")
    delete "/api/session", headers: { "Origin" => AppSettings.origin, "X-CSRF-Token" => csrf }
    assert_response :no_content
    login(@email, @password)
    assert_response :ok
    finish_totp(@secret, step: step)
    assert_response :unauthorized
    get "/api/session"
    assert_equal false, response.parsed_body.fetch("authenticated")
    finish_totp(@secret, step: step + 1)
    assert_response :ok
    assert_equal true, response.parsed_body.fetch("platform_admin")
  end

  test "recovery replaces factors only after confirmation without creating cookies or a session" do
    sign_in
    old_browser = open_session
    old_browser.https!
    old_browser.host! URI(AppSettings.origin).host
    old_browser.cookies[ApplicationController::SESSION_COOKIE] = cookies[ApplicationController::SESSION_COOKIE]
    pending = begin_recovery(headers: @headers.merge("X-CSRF-Token" => response.parsed_body.fetch("csrf_token")))
    assert_response :ok
    assert_nil response.headers["Set-Cookie"]
    assert_equal %w[challenge otpauth_uri secret], pending.keys.sort
    assert_includes pending.fetch("otpauth_uri"), pending.fetch("secret")
    assert_equal "0", active_sessions
    old_browser.get "/api/session"
    assert_equal false, old_browser.response.parsed_body.fetch("authenticated")
    post_recovery(@email, @password, @codes.first)
    assert_recovery_invalid
    confirm_recovery(pending.fetch("challenge"), "bad")
    assert_recovery_invalid
    confirm_recovery(pending.fetch("challenge"), totp(pending.fetch("secret")))
    assert_response :ok
    assert_nil response.headers["Set-Cookie"]
    new_codes = response.parsed_body.fetch("recovery_codes")
    assert_kind_of Array, new_codes
    assert_empty new_codes & @codes
    assert_equal "0", active_sessions
    get "/api/session"
    assert_equal({ "authenticated" => false, "onboarded" => false }, response.parsed_body)
    confirm_recovery(pending.fetch("challenge"), totp(pending.fetch("secret")))
    assert_recovery_invalid
    post_recovery(@email, @password, @codes.last)
    assert_recovery_invalid
    login(@email, @password)
    assert_response :ok
    assert_equal "totp", response.parsed_body.fetch("next")
    finish_totp(pending.fetch("secret"), step: Time.now.to_i / 30 + 1)
    assert_response :ok
    assert_equal true, response.parsed_body.fetch("platform_admin")
    assert_no_factor_leak(response.body, pending.fetch("secret"), *new_codes)
  end

  test "invalid missing malformed and wrong account factors use one indistinguishable error" do
    attempts = [
      [nil, @password, @codes.first], ["not-an-email", @password, @codes.first],
      [@email, nil, @codes.first], [@email, "short", @codes.first],
      [@email, @password, nil], [@email, @password, []], [@email, @password, "bad"],
      [@email, "senha incorreta longa", @codes.first],
      [@email, @password, SecureRandom.urlsafe_base64(32)],
      ["unknown-#{@email}", @password, @codes.first]
    ]
    expected = nil
    attempts.each do |email, password, code|
      post_recovery(email, password, code)
      expected ||= response.parsed_body
      assert_recovery_invalid(expected)
    end
    pending = begin_recovery
    assert_response :ok
    [[nil, "123456"], ["bad", "123456"], [SecureRandom.urlsafe_base64(32), "123456"],
      [pending.fetch("challenge"), nil], [pending.fetch("challenge"), []],
      [pending.fetch("challenge"), "not-a-code"]].each do |token, code|
      confirm_recovery(token, code)
      assert_recovery_invalid(expected)
    end
  end

  test "expired challenge is rejected and cannot authenticate" do
    pending = begin_recovery
    assert_response :ok
    @admin.exec_params("UPDATE app_private.platform_recovery_challenges SET expires_at = clock_timestamp() WHERE identity_id = $1", [@id])
    confirm_recovery(pending.fetch("challenge"), totp(pending.fetch("secret")))
    assert_recovery_invalid
    assert_equal "0", active_sessions
    get "/api/session"
    assert_equal false, response.parsed_body.fetch("authenticated")
  end

  test "recovery requires CSRF only for a valid session and stale cookies confer no session" do
    sign_in
    csrf = response.parsed_body.fetch("csrf_token")
    post_recovery(@email, @password, @codes.first)
    assert_response :forbidden
    post_recovery(@email, @password, @codes.first, headers: @headers.merge("X-CSRF-Token" => "wrong"))
    assert_response :forbidden
    pending = begin_recovery(headers: @headers.merge("X-CSRF-Token" => csrf))
    assert_response :ok
    # The recovery invalidated the old cookie, so confirmation needs no fictitious CSRF token.
    confirm_recovery(pending.fetch("challenge"), totp(pending.fetch("secret")))
    assert_response :ok
    assert_equal "0", active_sessions
  end

  test "confirmation also rejects missing or incorrect CSRF when another valid session exists" do
    pending = begin_recovery
    assert_response :ok
    # Provision a second ordinary identity and authenticate it after recovery starts.
    email = "ordinary-#{SecureRandom.hex(12)}@example.test"
    secret = PasswordAuthentication.new_secret
    @admin.transaction { |db| insert_identity(db, email, @password, secret) }
    login(email, @password)
    finish_totp(secret)
    assert_response :ok
    csrf = response.parsed_body.fetch("csrf_token")
    confirm_recovery(pending.fetch("challenge"), totp(pending.fetch("secret")))
    assert_response :forbidden
    confirm_recovery(pending.fetch("challenge"), totp(pending.fetch("secret")), headers: @headers.merge("X-CSRF-Token" => "wrong"))
    assert_response :forbidden
    confirm_recovery(pending.fetch("challenge"), totp(pending.fetch("secret")), headers: @headers.merge("X-CSRF-Token" => csrf))
    assert_response :ok
  end

  test "both endpoints enforce origin JSON trusted ingress and client IP" do
    bad_headers = [@headers.except("Origin"), @headers.merge("Origin" => "https://attacker.test"),
      @headers.except("X-Advocacia-Ingress-Secret"), @headers.merge("X-Advocacia-Ingress-Secret" => "invalid"),
      @headers.merge("X-Advocacia-Client-IP" => "127.0.0.1, 198.51.100.1")]
    bad_headers.each do |headers|
      post_recovery(@email, @password, @codes.first, headers: headers)
      assert_response :forbidden
      confirm_recovery(SecureRandom.urlsafe_base64(32), "123456", headers: headers)
      assert_response :forbidden
    end
    post "/api/admin/auth/recovery", params: { email: @email, password: @password, recovery_code: @codes.first }, headers: @headers
    assert_response :forbidden
    post "/api/admin/auth/recovery/confirm", params: { token: SecureRandom.urlsafe_base64(32), code: "123456" }, headers: @headers
    assert_response :forbidden
  end

  test "recovery account limit is shared across distinct trusted IPs" do
    21.times do |index|
      headers = @headers.merge("X-Advocacia-Client-IP" => "2001:db8:#{SecureRandom.hex(2)}::#{index + 1}")
      post_recovery(@email, "senha incorreta longa", @codes.first, headers: headers)
      if index < 20
        assert_recovery_invalid
      else
        assert_response :too_many_requests
        assert_equal "900", response.headers["Retry-After"]
      end
    end
  end

  test "confirmation uses the real shared IP limit for invalid tokens" do
    21.times do |index|
      confirm_recovery(SecureRandom.urlsafe_base64(32), "123456")
      if index < 20
        assert_recovery_invalid
      else
        assert_response :too_many_requests
        assert_equal "900", response.headers["Retry-After"]
      end
    end
  end

  test "request parameter logging filters both recovery code and confirmation token" do
    recovery_code = SecureRandom.urlsafe_base64(32)
    post_recovery(@email, @password, recovery_code)
    assert_equal "[FILTERED]", request.filtered_parameters.fetch("recovery_code")
    refute_includes request.filtered_parameters.inspect, recovery_code
    token = SecureRandom.urlsafe_base64(32)
    confirm_recovery(token, "123456")
    assert_equal "[FILTERED]", request.filtered_parameters.fetch("token")
    refute_includes request.filtered_parameters.inspect, token
  end

  test "password reset revokes the admin session but preserves the confirmed authenticator" do
    sign_in
    token = nil
    PasswordResetMailer.stub(:deliver!, ->(**args) { token = args.fetch(:token) }) do
      track(@headers, @email)
      post "/api/auth/password-reset", params: { email: @email }, as: :json, headers: @headers
      assert_response :accepted
    end
    @buckets << "reset:#{IdentityStore.digest(token)}"
    PasswordResetMailer.stub(:deliver_changed!, ->(**_) {}) do
      post "/api/auth/password-reset/confirm", params: { token: token, password: "nova senha sintetica segura" }, as: :json, headers: @headers
      assert_response :no_content
    end
    get "/api/session"
    assert_equal({ "authenticated" => false, "onboarded" => false }, response.parsed_body)
    login(@email, "nova senha sintetica segura")
    assert_response :ok
    assert_equal "totp", response.parsed_body.fetch("next")
    finish_totp(@secret, step: Time.now.to_i / 30 + 1)
    assert_response :ok
    assert_equal true, response.parsed_body.fetch("platform_admin")
    assert_no_factor_leak(response.body, @secret, *@codes)
  end

  private

  def insert_identity(db, email, password, secret)
    id = db.exec_params("INSERT INTO app_private.identities(verified_email,email_verified_at) VALUES ($1,clock_timestamp()) RETURNING id", [email]).getvalue(0, 0)
    @identities << id
    db.exec_params("INSERT INTO app_private.password_credentials(identity_id, password_hash, totp_secret, totp_confirmed) VALUES ($1, $2, $3, true)",
      [id, PasswordAuthentication.password_hash(password), PasswordAuthentication.encrypt(secret)])
    id
  end

  def track(headers, email = nil)
    ip = headers["X-Advocacia-Client-IP"]
    @buckets << "ip:#{IPAddr.new(ip)}" if ip && !ip.include?(",")
    @buckets << "account:#{email.downcase}" if email.is_a?(String) && email.include?("@")
  end

  def post_recovery(email, password, code, headers: @headers)
    track(headers, email)
    post "/api/admin/auth/recovery", params: { email: email, password: password, recovery_code: code }, as: :json, headers: headers
  end

  def begin_recovery(headers: @headers)
    post_recovery(@email, @password, @codes.first, headers: headers)
    response.parsed_body
  end

  def confirm_recovery(token, code, headers: @headers)
    track(headers)
    post "/api/admin/auth/recovery/confirm", params: { token: token, code: code }, as: :json, headers: headers
  end

  def login(email, password, extra: {})
    track(@headers, email)
    post "/api/auth/login", params: { email: email, password: password }.merge(extra), as: :json, headers: @headers
    challenge = cookies[ApplicationController::AUTH_COOKIE]
    @buckets << "challenge:#{IdentityStore.digest(challenge)}" if challenge
  end

  def finish_totp(secret, step: Time.now.to_i / 30, extra: {})
    track(@headers)
    post "/api/auth/totp", params: { code: totp(secret, step: step) }.merge(extra), as: :json, headers: @headers
  end

  def sign_in
    login(@email, @password)
    assert_response :ok
    assert_equal "totp", response.parsed_body.fetch("next")
    finish_totp(@secret)
    assert_response :ok
    assert_equal true, response.parsed_body.fetch("platform_admin")
  end

  def totp(secret, step: Time.now.to_i / 30)
    PasswordAuthentication.code(secret, step)
  end

  def active_sessions
    @admin.exec_params("SELECT count(*) FROM app_private.sessions WHERE identity_id = $1 AND revoked_at IS NULL AND expires_at > clock_timestamp()", [@id]).getvalue(0, 0)
  end

  def assert_recovery_invalid(expected = nil)
    assert_response :unprocessable_entity
    body = response.parsed_body
    assert_equal "admin_recovery_invalid", body.dig("error", "code")
    assert_kind_of String, body.dig("error", "message")
    assert_equal expected, body if expected
  end

  def assert_no_factor_leak(body, *secrets)
    secrets.each { |secret| refute_includes body, secret }
  end
end
