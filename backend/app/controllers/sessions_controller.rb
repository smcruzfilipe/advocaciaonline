class SessionsController < ApplicationController
  before_action :require_authentication, except: :show
  before_action :verify_csrf, except: :show

  def show
    context = authenticated_context
    unless context
      cookies.delete(SESSION_COOKIE, **cookie_options(expires: Time.at(0))) if cookies[SESSION_COOKIE]
      return render json: { authenticated: false, onboarded: false }
    end
    selected = IdentityStore.context(session_token)
    memberships = IdentityStore.memberships(session_token)
    render json: { authenticated: true, onboarded: selected&.fetch("tenant_id").present?,
      csrf_token: context.fetch("csrf_token"), membership_id: selected&.fetch("membership_id"),
      tenant_id: selected&.fetch("tenant_id"), role: selected&.fetch("role"),
      selection_required: memberships.any? && selected&.fetch("tenant_id").blank?,
      memberships: memberships }
  end

  def update
    selected = IdentityStore.select_membership(token: session_token,
      membership_id: request.request_parameters["membership_id"])
    render json: { membership_id: selected.fetch("membership_id"), tenant_id: selected.fetch("tenant_id"),
      role: selected.fetch("role") }
  rescue IdentityStore::InvalidInput
    api_error("invalid_membership", "Informe um vínculo válido.", :unprocessable_entity)
  rescue IdentityStore::AccessDenied
    api_error("membership_unavailable", "Este vínculo não está disponível para sua identidade.", :forbidden)
  end

  def destroy
    IdentityStore.revoke(session_token)
    cookies.delete(SESSION_COOKIE, **cookie_options(expires: Time.at(0)))
    head :no_content
  end

  private

  def authenticated_context
    @authenticated_context ||= IdentityStore.session_identity(session_token)
  end
end
