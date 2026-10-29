class CourtCatalogsController < ApplicationController
  before_action :require_authentication

  def index
    DatabaseContext.with_session(session_token) do
      context = ApplicationRecord.connection.uncached { IdentityStore.context(session_token) }
      raise AuthorizationDenied unless context.is_a?(Hash) && context["identity_id"].present?
    end
    render json: { courts: CourtCatalog.fetch }
  rescue CourtCatalog::Unavailable
    api_error("court_catalog_unavailable", "O catálogo de tribunais está indisponível. Tente novamente mais tarde.", :service_unavailable)
  end
end
