require "ipaddr"

class PasswordAuthController < ApplicationController
  REGISTRATION_COOKIE = "__Host-advocacia_registration".freeze

  before_action :check_origin_and_ingress
  before_action :limit_ip

  def register
    email = normalized_email
    password = valid_password_input
    return invalid_input unless email && password
    return unless limit("account:#{email}")
    token = SecureRandom.urlsafe_base64(32)
    browser = cookies[REGISTRATION_COOKIE]
    browser = SecureRandom.urlsafe_base64(32) unless valid_token?(browser)
    row = IdentityStore.call("register_password", IdentityStore.digest(token), IdentityStore.digest(browser), email,
      PasswordAuthentication.password_hash(password), PasswordAuthentication.encrypt(PasswordAuthentication.new_secret))
    cookies[REGISTRATION_COOKIE] = cookie_options(expires: 24.hours.from_now).merge(value: browser)
    VerificationMailer.deliver!(email: email, token: token) if row.fetch("created")
    render json: { message: "Se o endereço puder ser cadastrado, enviaremos um e-mail de confirmação." }, status: :accepted
  rescue VerificationMailer::DeliveryFailed
    api_error("email_delivery_failed", "Não foi possível enviar o e-mail de confirmação. Tente novamente.", :service_unavailable)
  end

  def verify_email
    token = request.request_parameters["token"]
    browser = cookies[REGISTRATION_COOKIE]
    return invalid_input unless valid_token?(token) && valid_token?(browser)
    row = IdentityStore.call("verify_password_email", IdentityStore.digest(token), IdentityStore.digest(browser))
    return api_error("verification_invalid", "O link é inválido ou expirou.", :unprocessable_entity) unless row.fetch("verified")
    cookies.delete(REGISTRATION_COOKIE, **cookie_options(expires: Time.at(0)))
    render json: { verified: true }
  end

  def password_reset
    email = normalized_email
    return invalid_input unless email
    return unless limit("account:#{email}")
    token = SecureRandom.urlsafe_base64(32)
    IdentityStore.call("request_password_reset", email, IdentityStore.digest(token))
    # Use the same transport for every valid address: SMTP timing/failure must
    # not reveal whether a confirmed identity exists.
    PasswordResetMailer.deliver!(email: email, token: token)
    render json: { message: "Se houver uma conta para este endereço, você receberá as instruções para redefinir a senha." }, status: :accepted
  rescue PasswordResetMailer::DeliveryFailed
    IdentityStore.call("cancel_password_reset", IdentityStore.digest(token))
    api_error("email_delivery_failed", "Não foi possível enviar as instruções. Tente novamente.", :service_unavailable)
  end

  def confirm_password_reset
    token = request.request_parameters["token"]
    return reset_invalid unless valid_token?(token)
    password = valid_password_input
    return invalid_input unless password
    return unless limit("reset:#{IdentityStore.digest(token)}")
    result = IdentityStore.call("confirm_password_reset", IdentityStore.digest(token), PasswordAuthentication.password_hash(password))
    return reset_invalid unless result.fetch("changed")
    begin
      PasswordResetMailer.deliver_changed!(email: result.fetch("email"))
    rescue PasswordResetMailer::DeliveryFailed
      # The committed password change must not be reported as failed. Never log
      # SMTP exceptions: servers may echo message content or credentials.
      Rails.logger.error("password_reset_notification_delivery_failed")
    end
    head :no_content
  end

  def login
    email = normalized_email
    password = valid_password_input
    return invalid_input unless email && password
    return unless limit("account:#{email}")
    row = IdentityStore.call("password_lookup", email)
    valid = PasswordAuthentication.valid_password?(password, row && row.fetch("password_hash"))
    return rejected unless row && valid
    challenge = SecureRandom.urlsafe_base64(32)
    result = IdentityStore.call("create_password_challenge", row.fetch("identity_id"), IdentityStore.digest(challenge), row.fetch("password_hash"))
    return rejected unless result.fetch("created")
    cookies[AUTH_COOKIE] = cookie_options(expires: 10.minutes.from_now).merge(value: challenge)
    if row.fetch("totp_confirmed")
      render json: { next: "totp" }
    else
      secret = PasswordAuthentication.decrypt(row.fetch("totp_secret"))
      render json: { next: "totp_setup", secret: secret, otpauth_uri: PasswordAuthentication.uri(email, secret) }
    end
  end

  def totp
    challenge = cookies[AUTH_COOKIE]
    return rejected unless valid_token?(challenge)
    return unless limit("challenge:#{IdentityStore.digest(challenge)}")
    row = IdentityStore.call("password_challenge", IdentityStore.digest(challenge))
    return rejected unless row
    secret = PasswordAuthentication.decrypt(row.fetch("totp_secret"))
    step = PasswordAuthentication.matching_step(secret, request.request_parameters["code"])
    return rejected unless step
    token = SecureRandom.urlsafe_base64(32)
    csrf = SecureRandom.urlsafe_base64(32)
    result = IdentityStore.call("finish_password_challenge", IdentityStore.digest(challenge), step.to_s,
      IdentityStore.digest(token), csrf, session_token ? IdentityStore.digest(session_token) : "")
    return rejected unless result.fetch("created")
    cookies.delete(AUTH_COOKIE, **cookie_options(expires: Time.at(0)))
    cookies[SESSION_COOKIE] = cookie_options(expires: 12.hours.from_now).merge(value: token)
    context = IdentityStore.session_identity(token)
    selected = IdentityStore.context(token)
    memberships = IdentityStore.memberships(token)
    render json: { authenticated: true, onboarded: selected&.fetch("tenant_id").present?,
      csrf_token: context.fetch("csrf_token"), membership_id: selected&.fetch("membership_id"),
      tenant_id: selected&.fetch("tenant_id"), role: selected&.fetch("role"),
      selection_required: memberships.any? && selected&.fetch("tenant_id").blank?, memberships: memberships }
  end

  private

  def check_origin_and_ingress
    unless request.headers["Origin"] == AppSettings.origin && request.media_type == "application/json"
      return api_error("invalid_origin", "Use esta aplicação para continuar.", :forbidden)
    end
    expected = ENV["AUTH_INGRESS_SECRET"]
    supplied = request.headers["X-Advocacia-Ingress-Secret"]
    ip = request.headers["X-Advocacia-Client-IP"]
    unless expected.is_a?(String) && expected.bytesize >= 32 && supplied.is_a?(String) &&
        supplied.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(expected, supplied) &&
        ip.is_a?(String) && ip.bytesize <= 45 && !ip.include?("/")
      return api_error("invalid_ingress", "Não foi possível validar a origem da solicitação.", :forbidden)
    end
    @client_ip = IPAddr.new(ip).to_s
  rescue IPAddr::InvalidAddressError
    api_error("invalid_ingress", "Não foi possível validar a origem da solicitação.", :forbidden)
  end

  def limit_ip
    limit("ip:#{@client_ip}")
  end

  def limit(value)
    bucket = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, value)
    return true if IdentityStore.call("auth_limit", bucket).fetch("accepted")
    response.headers["Retry-After"] = "900"
    api_error("rate_limited", "Aguarde alguns minutos antes de tentar novamente.", :too_many_requests)
    false
  end

  def normalized_email
    TeamInvitationMailer.normalize_recipient!(request.request_parameters["email"])
  rescue ArgumentError
    nil
  end

  def valid_password_input
    value = request.request_parameters["password"]
    value if value.is_a?(String) && value.valid_encoding? && value.length.between?(12, 128) && value.bytesize <= 512
  end

  def valid_token?(value)
    value.is_a?(String) && value.match?(/\A[A-Za-z0-9_-]{43}\z/)
  end

  def invalid_input
    api_error("invalid_input", "Confira os dados informados.", :unprocessable_entity)
  end

  def reset_invalid
    api_error("password_reset_invalid", "O link é inválido ou expirou. Solicite uma nova redefinição de senha.", :unprocessable_entity)
  end

  def rejected
    api_error("authentication_failed", "Não foi possível autenticar. Confira os dados e tente novamente.", :unauthorized)
  end
end
