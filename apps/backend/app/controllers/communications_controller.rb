class CommunicationsController < ApplicationController
  before_action :require_authentication
  before_action :require_onboarding

  def index
    courts = DatabaseContext.with_session(session_token) do
      result = authorize_session!(court_scoped: true) do |context, groups|
        CommunicationQuery.new(context: context, groups: groups).list
      end
      authorize_session!(court_scoped: true) { result }
    end
    render json: ActiveSupport::JSON.encode({ courts: courts }, escape_html_entities: true)
  end

  def show
    communication = DatabaseContext.with_session(session_token) do
      result = authorize_session!(court_scoped: true) do |context, groups|
        CommunicationQuery.new(context: context, groups: groups).find(params[:id])
      end
      authorize_session!(court_scoped: true) { result }
    end
    return api_error("communication_not_found", "Comunicação não encontrada.", :not_found) unless communication

    # JSON encoding is not HTML sanitization: clients must render the decoded
    # source strings as text, never as executable markup.
    # https://api.rubyonrails.org/v8.1.4/classes/ActiveSupport/JSON.html#method-c-encode
    render json: ActiveSupport::JSON.encode(communication, escape_html_entities: true)
  end

  private

  def require_onboarding
    return if authenticated_context.fetch("tenant_id")

    api_error("onboarding_required", "Cadastre seu perfil profissional para continuar.", :not_found)
  end
end
