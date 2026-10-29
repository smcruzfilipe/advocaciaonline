class TeamInvitationsController < ApplicationController
  before_action :require_authentication
  before_action :verify_csrf

  def create
    accepted = IdentityStore.accept_invitation(token: session_token,
      invitation_token: request.request_parameters["token"])
    render json: { membership: accepted }
  rescue IdentityStore::InvalidInput
    api_error("invalid_invitation", "Envie o convite no corpo JSON da solicitação.", :unprocessable_entity)
  rescue IdentityStore::NotFound, IdentityStore::Conflict
    api_error("invitation_unavailable", "Convite inválido, vencido, já utilizado ou destinado a outra conta Google.", :unprocessable_entity)
  rescue IdentityStore::AuthenticationRejected
    api_error("authentication_required", "Entre com sua conta Google para continuar.", :unauthorized)
  end

  private

  # Invitation acceptance authenticates Google, not an existing tenant. Even a
  # session whose old membership expired may accept a new, independently valid one.
  def authenticated_context
    @authenticated_context ||= IdentityStore.session_identity(session_token)
  end
end
