class CourtCatalogsController < ApplicationController
  before_action :require_authentication

  def index
    render json: { courts: CourtCatalog.fetch }
  rescue CourtCatalog::Unavailable
    api_error("court_catalog_unavailable", "O catálogo de tribunais está indisponível. Tente novamente mais tarde.", :service_unavailable)
  end
end
