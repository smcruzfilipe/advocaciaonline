require "test_helper"

class PasswordResetHttpTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    https!
    host! URI(AppSettings.origin).host
    @previous_ingress = ENV["AUTH_INGRESS_SECRET"]
    ENV["AUTH_INGRESS_SECRET"] = "reset-test-ingress-" + "x" * 32
    @headers = { "Origin" => AppSettings.origin, "X-Advocacia-Ingress-Secret" => ENV.fetch("AUTH_INGRESS_SECRET"),
      "X-Advocacia-Client-IP" => "2001:db8:#{SecureRandom.hex(2)}:#{SecureRandom.hex(2)}::1" }
    @email = "reset-http-#{SecureRandom.hex(12)}@example.test"
    @password = "senha longa anterior"
    @new_password = "senha nova escolhida"
    fixture_identity(email: @email, password: @password, secret: PasswordAuthentication.new_secret, verified: true)
  end

  teardown do
    ENV["AUTH_INGRESS_SECRET"] = @previous_ingress
  end

  test "known and unknown addresses get identical responses without exposing account existence" do
    sent = []
    PasswordResetMailer.stub(:deliver!, ->(**args) { sent << args }) do
      request_reset(@email.upcase)
      assert_response :accepted
      body = response.body
      refute_includes response.headers["Set-Cookie"].to_s, "advocacia"
      request_reset("absent-#{@email}")
      assert_response :accepted
      assert_equal body, response.body
    end
    assert_nil IdentityStore.call("confirm_password_reset", IdentityStore.digest(sent.last.fetch(:token)),
      PasswordAuthentication.password_hash(@new_password)).fetch("email")
  end

  test "new password must pass policy and confirmation does not authenticate or enroll TOTP" do
    token = capture_reset
    ["a" * 11, "a" * 129, [], nil].each do |password|
      confirm_reset(token, password)
      assert_response :unprocessable_entity
      assert_equal "invalid_input", response.parsed_body.dig("error", "code")
    end
    changed = []
    PasswordResetMailer.stub(:deliver_changed!, ->(**args) { changed << args.fetch(:email) }) do
      confirm_reset(token, @new_password)
      assert_response :no_content
      assert_empty response.body
      assert_nil response.headers["Set-Cookie"]
    end
    assert_equal [@email], changed
    get "/api/session"
    refute response.parsed_body.fetch("authenticated")
    post "/api/auth/login", params: { email: @email, password: @password }, as: :json, headers: @headers
    assert_response :unauthorized
    post "/api/auth/login", params: { email: @email, password: @new_password }, as: :json, headers: @headers
    assert_response :ok
    assert_equal "totp_setup", response.parsed_body.fetch("next")
    get "/api/session"
    refute response.parsed_body.fetch("authenticated")
    confirm_reset(token, @new_password)
    assert_response :unprocessable_entity
    assert_equal "password_reset_invalid", response.parsed_body.dig("error", "code")
  end

  test "malformed and absent tokens use the reset invalid error" do
    [nil, "", "bad", [], SecureRandom.urlsafe_base64(32)].each do |token|
      confirm_reset(token, @new_password)
      assert_response :unprocessable_entity
      assert_equal "password_reset_invalid", response.parsed_body.dig("error", "code")
    end
  end

  test "SMTP failure is explicit identical for unknown accounts and cancels only that issued link" do
    tokens = []
    failure = lambda do |**args|
      tokens << args.fetch(:token)
      raise PasswordResetMailer::DeliveryFailed, "safe delivery failure"
    end
    PasswordResetMailer.stub(:deliver!, failure) do
      request_reset(@email)
      assert_response :service_unavailable
      body = response.body
      request_reset("absent-#{@email}")
      assert_response :service_unavailable
      assert_equal body, response.body
      assert_equal "email_delivery_failed", response.parsed_body.dig("error", "code")
    end
    tokens.each do |token|
      confirm_reset(token, @new_password)
      assert_response :unprocessable_entity
    end
  end

  test "notification failure does not undo the committed password change" do
    token = capture_reset
    PasswordResetMailer.stub(:deliver_changed!, ->(**_) { raise PasswordResetMailer::DeliveryFailed, "safe failure" }) do
      confirm_reset(token, @new_password)
      assert_response :no_content
    end
    credential = IdentityStore.call("password_lookup", @email)
    assert PasswordAuthentication.valid_password?(@new_password, credential.fetch("password_hash"))
    confirm_reset(token, @new_password)
    assert_response :unprocessable_entity
  end

  test "both reset endpoints enforce existing origin JSON and trusted ingress rules" do
    [@headers.except("X-Advocacia-Ingress-Secret"), @headers.merge("Origin" => "https://attacker.test"),
      @headers.merge("X-Advocacia-Client-IP" => "127.0.0.1, 198.51.100.1")].each do |headers|
      post "/api/auth/password-reset", params: { email: @email }, as: :json, headers: headers
      assert_response :forbidden
      post "/api/auth/password-reset/confirm", params: { token: SecureRandom.urlsafe_base64(32), password: @new_password }, as: :json, headers: headers
      assert_response :forbidden
    end
    post "/api/auth/password-reset", params: { email: @email }, headers: @headers
    assert_response :forbidden
  end

  test "request applies shared per-account limits even across trusted client IPs" do
    PasswordResetMailer.stub(:deliver!, ->(**_) {}) do
      20.times do |index|
        request_reset(@email, headers: @headers.merge("X-Advocacia-Client-IP" => "2001:db8:#{SecureRandom.hex(2)}::#{index + 1}"))
        assert_response :accepted
      end
      request_reset(@email, headers: @headers.merge("X-Advocacia-Client-IP" => "2001:db8:ffff::1"))
      assert_response :too_many_requests
      assert_equal "900", response.headers["Retry-After"]
    end
  end

  test "confirmation applies the existing IP limit before processing unknown tokens" do
    20.times do
      confirm_reset(SecureRandom.urlsafe_base64(32), @new_password)
      assert_response :unprocessable_entity
    end
    confirm_reset(SecureRandom.urlsafe_base64(32), @new_password)
    assert_response :too_many_requests
  end

  private

  def request_reset(email, headers: @headers)
    post "/api/auth/password-reset", params: { email: email }, as: :json, headers: headers
  end

  def capture_reset
    token = nil
    PasswordResetMailer.stub(:deliver!, ->(**args) { token = args.fetch(:token) }) do
      request_reset(@email)
      assert_response :accepted
    end
    token
  end

  def confirm_reset(token, password)
    post "/api/auth/password-reset/confirm", params: { token: token, password: password }, as: :json, headers: @headers
  end
end
