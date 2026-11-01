class PlatformAdminInvitationsController < ApplicationController
  before_action :require_platform_administration
  before_action :check_origin
  before_action :verify_csrf, only: [:create, :reissue]
  before_action :require_json, only: [:create, :reissue]

  rescue_from IdentityStore::AuthenticationRejected do
    api_error("authentication_required", "Entre na sua conta para continuar.", :unauthorized)
  end
  rescue_from IdentityStore::AccessDenied do
    api_error("permission_denied", "Você não tem permissão para realizar esta operação.", :forbidden)
  end
  rescue_from IdentityStore::InvalidInput do
    api_error("invalid_invitation", "Informe um e-mail válido e confira os dados do convite.", :unprocessable_entity)
  end
  rescue_from IdentityStore::NotFound do
    invitation_not_found
  end
  rescue_from IdentityStore::Conflict do
    api_error("invitation_conflict", "Não foi possível emitir o convite. Se já houver cadastro, use o login. Um convite ativo só pode ser substituído por reemissão explícita.", :conflict)
  end

  def index
    render json: { invitations: FirstAccessInvitationStore.list(token: session_token) }
  end

  def create
    render json: FirstAccessInvitationStore.issue(token: session_token,
      email: request.request_parameters["email"]), status: :created
  end

  def link
    return invitation_not_found unless valid_identifier?
    render json: FirstAccessInvitationStore.link(token: session_token, id: params[:id])
  end

  def reissue
    return invitation_not_found unless valid_identifier?
    render json: FirstAccessInvitationStore.reissue(token: session_token, id: params[:id]), status: :created
  end

  private

  def check_origin
    origin = request.headers["Origin"]
    return if origin == AppSettings.origin ||
      (request.get? && origin.nil? && request.headers["Sec-Fetch-Site"] == "same-origin")
    api_error("invalid_origin", "Use esta aplicação para continuar.", :forbidden)
  end

  def require_json
    return if request.media_type == "application/json"
    api_error("invalid_json", "Envie um objeto JSON válido.", :unprocessable_entity)
  end

  def valid_identifier?
    params[:id].is_a?(String) && IdentityStore::UUID.match?(params[:id])
  end

  def invitation_not_found
    api_error("invitation_not_found", "Convite ativo não encontrado.", :not_found)
  end
end
