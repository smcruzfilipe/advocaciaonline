class PartyMonitoringsController < ApplicationController
  class InvalidInput < StandardError; end

  before_action :require_authentication
  before_action :require_onboarding
  before_action :verify_csrf, only: [:create, :update]
  before_action :require_json, only: [:create, :update]

  rescue_from InvalidInput, ActiveRecord::RecordInvalid do
    api_error("invalid_party", "Informe um nome não vazio, tribunais disponíveis e uma situação válida.", :unprocessable_entity)
  end
  rescue_from ActiveRecord::RecordNotUnique do
    api_error("duplicate_party", "Esta parte já está cadastrada. Edite ou reative o monitoramento existente.", :conflict)
  end
  rescue_from ActiveRecord::RecordNotFound do
    api_error("monitoring_not_found", "Monitoramento não encontrado.", :not_found)
  end
  rescue_from CourtCatalog::Unavailable do
    api_error("court_catalog_unavailable", "Não foi possível consultar os tribunais. Tente novamente.", :service_unavailable)
  end

  def index
    parties = DatabaseContext.with_session(session_token) do
      party_monitorings.order(:created_at, :id).map { |party| serialize_party(party) }
    end
    render json: { parties: parties }
  end

  def show
    party = DatabaseContext.with_session(session_token) do
      serialize_party(party_monitorings.find(params[:id]))
    end
    render json: party
  end

  def create
    party = DatabaseContext.with_session(session_token) do
      record = PartyMonitoring.create!(input_attributes(creating: true).merge(
        tenant_id: authenticated_context.fetch("tenant_id")
      ))
      serialize_party(record)
    end
    render json: party, status: :created
  end

  def update
    party = DatabaseContext.with_session(session_token) do
      record = party_monitorings.find(params[:id])
      record.update!(input_attributes(creating: false))
      serialize_party(record)
    end
    render json: party
  end

  private

  def require_onboarding
    return if authenticated_context.fetch("tenant_id")

    api_error("onboarding_required", "Cadastre seu perfil profissional para continuar.", :not_found)
  end

  def require_json
    return if request.media_type == "application/json"

    api_error("invalid_content_type", "Envie os dados em JSON.", :unsupported_media_type)
  end

  def party_monitorings
    PartyMonitoring.where(tenant_id: authenticated_context.fetch("tenant_id"))
  end

  def input_attributes(creating:)
    input = request.request_parameters
    raise InvalidInput unless input.is_a?(Hash)

    attributes = {}
    if creating || input.key?("name")
      raise InvalidInput unless input["name"].is_a?(String)
      attributes[:name] = input.fetch("name")
    end
    attributes[:courts] = validated_courts(input["courts"]) if input.key?("courts")
    if !creating && input.key?("active")
      active = input["active"]
      raise InvalidInput unless active == true || active == false
      attributes[:active] = active
    end
    attributes
  end

  def validated_courts(courts)
    return if courts.nil?
    raise InvalidInput unless courts.is_a?(Array) && courts.any? && courts.all? { |code| code.is_a?(String) }

    selected = courts.uniq.sort
    offered = CourtCatalog.fetch.map { |court| court.fetch(:code) }
    raise InvalidInput unless (selected - offered).empty?

    selected
  end

  def serialize_party(party)
    party.attributes.slice("id", "tenant_id", "name", "courts", "active")
  end
end
