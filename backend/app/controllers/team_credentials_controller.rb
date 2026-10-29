class TeamCredentialsController < ApplicationController
  before_action :require_authentication
  before_action :verify_csrf, except: :index

  rescue_from IdentityStore::AccessDenied do
    api_error("owner_required", "Somente o advogado titular administra credenciais da equipe.", :forbidden)
  end
  rescue_from IdentityStore::InvalidInput do
    api_error("invalid_credential", "Informe e-mail, grupos e validade explícita: null ou dias inteiros positivos.", :unprocessable_entity)
  end
  rescue_from IdentityStore::NotFound, AuthorizationGroupStore::NotFound do
    api_error("credential_not_found", "Credencial ou grupo não encontrado neste ambiente.", :not_found)
  end
  rescue_from IdentityStore::Conflict, AuthorizationGroupStore::Conflict do
    api_error("credential_conflict", "O estado atual da credencial não permite esta operação.", :conflict)
  end
  rescue_from AuthorizationGroupStore::InvalidInput do
    api_error("invalid_groups", "Informe grupos válidos deste ambiente.", :unprocessable_entity)
  end
  rescue_from AuthorizationGroupStore::Forbidden do
    api_error("owner_required", "Somente o advogado titular administra credenciais da equipe.", :forbidden)
  end
  rescue_from TeamInvitationMailer::DeliveryFailed do
    api_error("invitation_delivery_failed",
      "Convite registrado, mas não foi possível confirmar a entrega. Consulte as credenciais e reemita o convite para invalidar o link anterior.",
      :bad_gateway)
  end
  rescue_from KeyError, ArgumentError do
    api_error("invitation_configuration_error",
      "Convite registrado, mas o envio não está configurado corretamente. Corrija a configuração e reemita o convite para invalidar o link anterior.",
      :service_unavailable)
  end

  def index
    render json: { credentials: IdentityStore.team_credentials(session_token) }
  end

  def create
    input = request.request_parameters
    raise IdentityStore::InvalidInput unless input.key?("validity_days")
    credential = IdentityStore.create_credential(token: session_token, email: input["email"],
      validity_days: input["validity_days"], group_ids: input.fetch("group_ids", []))
    render json: { credential: credential }, status: :created
  end

  def update
    input = request.request_parameters
    raise IdentityStore::InvalidInput unless input.key?("validity_days")
    render json: { credential: IdentityStore.change_validity(token: session_token,
      membership_id: params[:id], validity_days: input["validity_days"]) }
  end

  def renew
    render json: { credential: IdentityStore.renew_credential(token: session_token, membership_id: params[:id]) }
  end

  def destroy
    render json: { credential: IdentityStore.revoke_credential(token: session_token, membership_id: params[:id]) }
  end

  def reissue
    render json: { credential: IdentityStore.reissue_invitation(token: session_token, membership_id: params[:id]) }
  end
end
