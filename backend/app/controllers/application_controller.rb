class ApplicationController < ActionController::API
  include ActionController::Cookies

  SESSION_COOKIE = "__Host-advocacia_session".freeze
  OIDC_COOKIE = "__Host-advocacia_oidc".freeze
  before_action :prevent_caching
  rescue_from ActionDispatch::Http::Parameters::ParseError, ActionController::BadRequest do
    api_error("invalid_json", "Envie um objeto JSON válido.", :bad_request)
  end

  private

  def prevent_caching
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
  end

  def session_token
    value = cookies[SESSION_COOKIE]
    value if value.is_a?(String) && value.match?(/\A[A-Za-z0-9_-]{43}\z/)
  end

  def authenticated_context
    @authenticated_context ||= IdentityStore.context(session_token)
  end

  def require_authentication
    return if authenticated_context
    api_error("authentication_required", "Entre com sua conta Google para continuar.", :unauthorized)
  end

  def verify_csrf
    token = request.headers["X-CSRF-Token"]
    expected = authenticated_context&.fetch("csrf_token")
    return if request.headers["Origin"] == AppSettings.origin && token.is_a?(String) &&
      expected.is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(token, expected)
    api_error("invalid_csrf", "Sua sessão mudou. Atualize a página e tente novamente.", :forbidden)
  end

  def cookie_options(expires:)
    { secure: true, httponly: true, same_site: :lax, path: "/", expires: expires }
  end

  def api_error(code, message, status, details: nil)
    error = { code: code, message: message }
    error[:details] = details if details
    render json: { error: error }, status: status
  end
end
