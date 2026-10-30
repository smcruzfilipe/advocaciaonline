class DashboardController < ApplicationController
  before_action :require_authentication
  before_action :require_onboarding

  def show
    snapshot = DatabaseContext.with_session(session_token) do
      result = authorize_session!(court_scoped: true) do |context, groups|
        DashboardSnapshot.call(context: context, groups: groups)
      end
      # Membership can expire naturally while the aggregate is being read even
      # though policy changes and revocation serialize on the authorization lock.
      authorize_session!(court_scoped: true) { |_context, _groups| result }
    end
    render json: snapshot
  end

  private

  def require_onboarding
    return if authenticated_context.fetch("tenant_id")

    api_error("onboarding_required", "Cadastre seu perfil profissional para continuar.", :not_found)
  end
end
