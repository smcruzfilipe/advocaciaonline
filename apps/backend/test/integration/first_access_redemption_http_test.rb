require "test_helper"
require "timeout"

class FirstAccessRedemptionHttpTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    https!
    host! URI(AppSettings.origin).host
    @previous_ingress = ENV["AUTH_INGRESS_SECRET"]
    ENV["AUTH_INGRESS_SECRET"] = "first-access-http-" + "x" * 32
    @headers = { "Origin" => AppSettings.origin, "X-Advocacia-Ingress-Secret" => ENV.fetch("AUTH_INGRESS_SECRET"),
      "X-Advocacia-Client-IP" => "2001:db8:#{SecureRandom.hex(2)}:#{SecureRandom.hex(2)}::1" }
    @db = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    @email = "redemption-#{SecureRandom.hex(12)}@example.test"
    @admin_email = "admin-#{@email}"
    @admin_id = @db.exec_params("INSERT INTO app_private.identities(verified_email, email_verified_at) VALUES ($1, clock_timestamp()) RETURNING id", [@admin_email]).getvalue(0, 0)
    @db.exec_params("INSERT INTO app_private.password_credentials(identity_id,password_hash,totp_secret,totp_confirmed) VALUES ($1,'hash','secret',true)", [@admin_id])
    @db.exec_params("INSERT INTO app_private.platform_administrator(identity_id) VALUES ($1)", [@admin_id])
    @admin_session = SecureRandom.urlsafe_base64(32)
    @db.exec_params("INSERT INTO app_private.sessions(session_hash,identity_id,csrf_token,expires_at) VALUES ($1,$2,'csrf',clock_timestamp()+interval '1 hour')", [IdentityStore.digest(@admin_session), @admin_id])
    invitation = FirstAccessInvitationStore.issue(token: @admin_session, email: @email)
    @invitation_id = invitation.fetch("id")
    link = FirstAccessInvitationStore.link(token: @admin_session, id: @invitation_id).fetch(:link)
    @token = URI.decode_www_form(URI(link).fragment).to_h.fetch("token")
    @password = "senha sintetica suficientemente longa"
  end

  teardown do
    if @db
      @db.exec_params("DELETE FROM app_private.first_access_invitations WHERE id=$1", [@invitation_id]) if @invitation_id
      [@email, @admin_email].each do |email|
        ids = @db.exec_params("SELECT id FROM app_private.identities WHERE verified_email=$1", [email]).column_values(0)
        ids.each do |id|
          %w[first_access_grants platform_administrator password_resets password_challenges sessions password_credentials].each do |table|
            @db.exec_params("DELETE FROM app_private.#{table} WHERE identity_id=$1", [id])
          end
          @db.exec_params("DELETE FROM app_private.identities WHERE id=$1", [id])
        end
      end
      @db.close
    end
    ENV["AUTH_INGRESS_SECRET"] = @previous_ingress
  end

  test "preparation does not create an account or reset eligibility and first TOTP creates an unverified authenticated identity" do
    post_auth "/api/auth/first-access/inspect", token: @token
    assert_response :ok
    assert_equal @email, response.parsed_body.fetch("email")
    assert_equal false, response.parsed_body.fetch("requires_login")
    post_auth "/api/auth/first-access", token: @token, password: @password, password_confirmation: @password
    assert_response :accepted
    pending = response.parsed_body
    assert_nil response.headers["Set-Cookie"]
    assert_equal "0", count_identities
    PasswordResetMailer.stub(:deliver!, ->(**_) {}) do
      post_auth "/api/auth/password-reset", email: @email
      assert_response :accepted
    end
    assert_equal "0", @db.exec_params("SELECT count(*) FROM app_private.password_resets r JOIN app_private.identities i ON i.id=r.identity_id WHERE i.verified_email=$1", [@email]).getvalue(0, 0)
    post_auth "/api/auth/first-access/confirm", token: @token, challenge: pending.fetch("challenge"), code: "bad"
    assert_response :unprocessable_entity
    assert_equal "0", count_identities
    used_step = Time.now.to_i / 30
    code = PasswordAuthentication.code(pending.fetch("secret"), used_step)
    post_auth "/api/auth/first-access/confirm", token: @token, challenge: pending.fetch("challenge"), code: code
    assert_response :ok
    assert_equal true, response.parsed_body.fetch("authenticated")
    assert_equal true, response.parsed_body.fetch("can_create_tenant")
    assert_equal false, response.parsed_body.fetch("onboarded")
    assert_includes response.headers["Set-Cookie"].to_s.downcase, "httponly"
    row = @db.exec_params(<<~SQL, [@email]).first
      SELECT i.email_verified_at, c.totp_confirmed, c.last_totp_step, g.identity_id
      FROM app_private.identities i JOIN app_private.password_credentials c ON c.identity_id=i.id
      JOIN app_private.first_access_grants g ON g.identity_id=i.id WHERE i.verified_email=$1
    SQL
    assert_nil row.fetch("email_verified_at")
    assert_equal "t", row.fetch("totp_confirmed")
    assert_equal used_step.to_s, row.fetch("last_totp_step")
    csrf = response.parsed_body.fetch("csrf_token")
    post "/api/auth/first-access/inspect", params: { token: @token }, as: :json, headers: @headers.merge("X-CSRF-Token" => csrf)
    assert_response :unprocessable_entity
    assert_equal "first_access_invalid", response.parsed_body.dig("error", "code")
    delete "/api/session", headers: { "Origin" => AppSettings.origin, "X-CSRF-Token" => csrf }
    assert_response :no_content
    post_auth "/api/auth/login", email: @email, password: @password
    assert_equal "totp", response.parsed_body.fetch("next")
    post_auth "/api/auth/totp", code: code
    assert_response :unauthorized
    post_auth "/api/auth/totp", code: PasswordAuthentication.code(pending.fetch("secret"), used_step + 1)
    assert_response :ok
    assert_equal true, response.parsed_body.fetch("can_create_tenant")
  end

  test "replacing preparation and expiry reject old challenge without creating an identity" do
    post_auth "/api/auth/first-access", token: @token, password: @password, password_confirmation: @password
    first = response.parsed_body
    post_auth "/api/auth/first-access", token: @token, password: @password, password_confirmation: @password
    second = response.parsed_body
    post_auth "/api/auth/first-access/confirm", token: @token, challenge: first.fetch("challenge"),
      code: PasswordAuthentication.code(first.fetch("secret"), Time.now.to_i / 30)
    assert_response :unprocessable_entity
    @db.exec_params("UPDATE app_private.first_access_invitations SET expires_at=clock_timestamp() WHERE id=$1", [@invitation_id])
    post_auth "/api/auth/first-access/confirm", token: @token, challenge: second.fetch("challenge"),
      code: PasswordAuthentication.code(second.fetch("secret"), Time.now.to_i / 30)
    assert_response :unprocessable_entity
    assert_equal "0", count_identities
    get "/api/session"
    assert_equal false, response.parsed_body.fetch("authenticated")
  end

  test "existing identity requires its own authenticated session and keeps its credentials unchanged" do
    secret = PasswordAuthentication.encrypt(PasswordAuthentication.new_secret)
    password_hash = PasswordAuthentication.password_hash(@password)
    id = @db.exec_params("INSERT INTO app_private.identities(verified_email) VALUES ($1) RETURNING id", [@email]).getvalue(0, 0)
    @db.exec_params("INSERT INTO app_private.password_credentials(identity_id,password_hash,totp_secret,totp_confirmed,last_totp_step) VALUES ($1,$2,$3,true,17)",
      [id, password_hash, secret])
    post_auth "/api/auth/first-access/inspect", token: @token
    assert_equal true, response.parsed_body.fetch("requires_login")
    post_auth "/api/auth/first-access", token: @token
    assert_response :unauthorized
    cookies[ApplicationController::SESSION_COOKIE] = @admin_session
    post "/api/auth/first-access", params: { token: @token }, as: :json, headers: @headers.merge("X-CSRF-Token" => "csrf")
    assert_response :unprocessable_entity
    assert_equal "first_access_invalid", response.parsed_body.dig("error", "code")
    own_session = SecureRandom.urlsafe_base64(32)
    @db.exec_params("INSERT INTO app_private.sessions(session_hash,identity_id,csrf_token,expires_at) VALUES ($1,$2,'own-csrf',clock_timestamp()+interval '1 hour')",
      [IdentityStore.digest(own_session), id])
    cookies[ApplicationController::SESSION_COOKIE] = own_session
    post "/api/auth/first-access", params: { token: @token }, as: :json, headers: @headers.merge("X-CSRF-Token" => "own-csrf")
    assert_response :ok
    assert_equal true, response.parsed_body.fetch("authenticated")
    assert_equal true, response.parsed_body.fetch("can_create_tenant")
    row = @db.exec_params("SELECT password_hash,totp_secret,last_totp_step FROM app_private.password_credentials WHERE identity_id=$1", [id]).first
    assert_equal password_hash, row.fetch("password_hash")
    assert_equal secret, row.fetch("totp_secret")
    assert_equal "17", row.fetch("last_totp_step")
    assert_equal "1", @db.exec_params("SELECT count(*) FROM app_private.first_access_grants WHERE identity_id=$1", [id]).getvalue(0, 0)
  end

  test "first access completion is atomic on rollback and concurrent confirmation has at most one winner" do
    bearer_hash = IdentityStore.digest(@token)
    challenge_hash = SecureRandom.hex(32)
    encrypted = PasswordAuthentication.encrypt(PasswordAuthentication.new_secret)
    IdentityStore.call("first_access_prepare", bearer_hash, challenge_hash, "hash", encrypted)
    runtime = PG.connect(ENV.fetch("DATABASE_URL"))
    args = [bearer_hash, challenge_hash, encrypted, (Time.now.to_i / 30).to_s, SecureRandom.hex(32), "csrf", ""]
    runtime.exec("BEGIN")
    assert_equal "t", runtime.exec_params("SELECT * FROM app_private.first_access_finish($1,$2,$3,$4,$5,$6,$7)", args).getvalue(0, 0)
    runtime.exec("ROLLBACK")
    assert_equal "0", count_identities
    ready, start = Queue.new, Queue.new
    workers = 2.times.map do
      Thread.new do
        PG.connect(ENV.fetch("DATABASE_URL")) do |db|
          db.exec("SET statement_timeout='10s'")
          ready << true
          start.pop
          local_args = args.dup
          local_args[4] = SecureRandom.hex(32)
          db.exec_params("SELECT * FROM app_private.first_access_finish($1,$2,$3,$4,$5,$6,$7)", local_args).getvalue(0, 0)
        end
      end
    end
    Timeout.timeout(15) do
      2.times { ready.pop }
      2.times { start << true }
      assert_equal %w[f t], workers.map(&:value).sort
    end
    assert_equal "1", count_identities
  ensure
    runtime&.exec("ROLLBACK") if runtime && runtime.transaction_status != PG::PQTRANS_IDLE
    runtime&.close
    2.times { start << true } if start
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end

  private

  def post_auth(path, params)
    post path, params: params, as: :json, headers: @headers
  end

  def count_identities
    @db.exec_params("SELECT count(*) FROM app_private.identities WHERE verified_email=$1", [@email]).getvalue(0, 0)
  end
end
