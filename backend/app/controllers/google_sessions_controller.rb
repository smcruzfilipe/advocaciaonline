class GoogleSessionsController < ApplicationController
  def new
    # Cross-site initiation is refused where Fetch Metadata is available. The
    # callback is intentionally cross-site and is instead bound by state + cookie.
    if request.headers["Sec-Fetch-Site"] == "cross-site"
      return api_error("invalid_origin", "Inicie o login nesta aplicação.", :forbidden)
    end
    bucket = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, request.remote_ip)
    attempt = OidcAttempt.start(bucket: bucket)
    unless attempt
      response.headers["Retry-After"] = "900"
      return api_error("rate_limited", "Aguarde alguns minutos antes de tentar entrar novamente.", :too_many_requests)
    end
    cookies[OIDC_COOKIE] = cookie_options(expires: 10.minutes.from_now).merge(value: attempt.fetch(:browser))
    redirect_to GoogleOidc.new.authorization_url(**attempt.except(:browser)), allow_other_host: true
  end

  def create
    attempt = OidcAttempt.consume(browser: cookies[OIDC_COOKIE], state: params[:state])
    cookies.delete(OIDC_COOKIE, **cookie_options(expires: Time.at(0)))
    raise GoogleOidc::AuthenticationFailed unless attempt && params[:error].nil?
    verified = GoogleOidc.new.exchange(code: params[:code], nonce: attempt.fetch("nonce"), verifier: attempt.fetch("verifier"))
    token = SecureRandom.urlsafe_base64(32)
    csrf = SecureRandom.urlsafe_base64(32)
    ApplicationRecord.transaction do
      IdentityStore.authenticate(**verified, token: token, csrf: csrf)
      IdentityStore.revoke(session_token)
    end
    context = IdentityStore.context(token)
    raise GoogleOidc::AuthenticationFailed unless context
    cookies[SESSION_COOKIE] = cookie_options(expires: 12.hours.from_now).merge(value: token)
    render json: { authenticated: true, onboarded: context.fetch("tenant_id").present?, csrf_token: csrf }
  rescue GoogleOidc::AuthenticationFailed, IdentityStore::AuthenticationRejected
    api_error("google_login_failed", "Não foi possível entrar com o Google. Tente novamente.", :unauthorized)
  end
end
