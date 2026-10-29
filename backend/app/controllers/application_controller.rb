class ApplicationController < ActionController::API
  include ActionController::Cookies

  SESSION_COOKIE = "__Host-advocacia_session".freeze
  OIDC_COOKIE = "__Host-advocacia_oidc".freeze
  class AuthorizationDenied < StandardError; end

  before_action :prevent_caching
  rescue_from ActionDispatch::Http::Parameters::ParseError, ActionController::BadRequest do
    api_error("invalid_json", "Envie um objeto JSON válido.", :bad_request)
  end
  rescue_from AuthorizationDenied do
    api_error("permission_denied", "Você não tem permissão para realizar esta operação.", :forbidden)
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

  # Call only inside DatabaseContext.with_session, next to the protected query.
  # Authentication/CSRF callbacks may have observed a now-revoked membership.
  def authorize_session!(*operations, owner_only: false)
    connection = ApplicationRecord.connection
    locked_tenant = connection.uncached { connection.select_value("SELECT app_private.lock_authorization(false)") }
    context = connection.uncached { IdentityStore.context(session_token) }
    unless context.is_a?(Hash) && context["identity_id"].present? &&
      context["tenant_id"].present? && context["membership_id"].present? &&
      context["tenant_id"] == locked_tenant && %w[owner member].include?(context["role"])
      raise AuthorizationDenied
    end

    return block_given? ? yield(context, []) : context if context["role"] == "owner"
    raise AuthorizationDenied if owner_only || operations.empty?

    rules = connection.uncached { connection.select_value("SELECT app_private.session_group_rules()") }
    groups = rules.is_a?(String) ? JSON.parse(rules) : rules
    raise AuthorizationDenied unless groups.is_a?(Array)

    permitted = operations.all? do |operation|
      AuthorizationPolicy.allowed?(owner: false, groups: groups, operation: operation)
    end
    raise AuthorizationDenied unless permitted

    block_given? ? yield(context, groups) : context
  rescue ActiveRecord::StatementInvalid => error
    state = error.cause.result&.error_field(PG::Result::PG_DIAG_SQLSTATE) if error.cause.is_a?(PG::Error)
    raise unless %w[28000 42501].include?(state)

    raise AuthorizationDenied, cause: nil
  end

  def monitoring_update_operations(attributes)
    operations = []
    operations << "editar_monitoramento" if (attributes.keys - [:active]).any? ||
      attributes.empty? || attributes[:active] == true
    operations << "desativar_monitoramento" if attributes[:active] == false
    operations
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
