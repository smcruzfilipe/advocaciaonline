class ProcessMonitoringsController < ApplicationController
  class InvalidInput < StandardError
    attr_reader :details

    def initialize(field, message)
      @details = { field => [message] }
      super(message)
    end
  end

  before_action :require_authentication
  before_action :require_onboarding
  before_action :verify_csrf, only: %i[create update]
  before_action :require_json, only: %i[create update]

  rescue_from InvalidInput do |error|
    api_error("invalid_process", error.message, :unprocessable_entity, details: error.details)
  end
  rescue_from ActiveRecord::RecordInvalid do |error|
    api_error("invalid_process", "Confira os dados do processo.", :unprocessable_entity,
      details: error.record.errors.to_hash)
  end
  rescue_from ActiveRecord::RecordNotUnique do
    api_error("duplicate_process", "Este processo já está cadastrado. Edite ou reative o monitoramento existente.", :conflict)
  end
  rescue_from ActiveRecord::RecordNotFound do
    api_error("monitoring_not_found", "Monitoramento não encontrado.", :not_found)
  end
  rescue_from CourtCatalog::Unavailable do
    api_error("court_catalog_unavailable", "A lista de tribunais está indisponível. Tente novamente mais tarde.", :service_unavailable)
  end

  def index
    processes = DatabaseContext.with_session(session_token) do
      ProcessMonitoring.order(:id).map { |process| serialize_process(process) }
    end
    render json: { processes: processes }
  end

  def show
    process = DatabaseContext.with_session(session_token) do
      serialize_process(ProcessMonitoring.find(params[:id]))
    end
    render json: process
  end

  def create
    attributes = input_attributes(creating: true)
    process = DatabaseContext.with_session(session_token) do
      record = ProcessMonitoring.create!(attributes.merge(tenant_id: authenticated_context.fetch("tenant_id")))
      serialize_process(record)
    end
    render json: process, status: :created
  end

  def update
    process = DatabaseContext.with_session(session_token) do
      record = ProcessMonitoring.find(params[:id])
      record.update!(input_attributes(creating: false))
      serialize_process(record)
    end
    render json: process
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

  def input_attributes(creating:)
    input = request.request_parameters
    unless input.is_a?(Hash) && !input.key?("_json")
      raise InvalidInput.new(:base, "Envie um objeto JSON com os dados do processo.")
    end

    attributes = {}
    if creating || input.key?("number")
      number = ProcessMonitoring.canonical_number(input["number"])
      raise InvalidInput.new(:number, "Informe o número CNJ mascarado ou como 20 dígitos ASCII.") unless number
      attributes[:number] = number
    end
    if !creating && input.key?("active")
      active = input["active"]
      unless active == true || active == false
        raise InvalidInput.new(:active, "Informe verdadeiro ou falso para o estado do monitoramento.")
      end
      attributes[:active] = active
    end
    if input.key?("courts")
      selection = input["courts"]
      if selection.nil?
        attributes[:courts] = nil
      else
        unless selection.is_a?(Array) && selection.any? && selection.all? { |code| code.is_a?(String) }
          raise InvalidInput.new(:courts, "Selecione ao menos um código de tribunal disponível.")
        end
        courts = selection.uniq.sort
        available = CourtCatalog.fetch.map { |court| court.fetch(:code) }
        unless (courts - available).empty?
          raise InvalidInput.new(:courts, "Selecione somente códigos de tribunais disponíveis.")
        end
        attributes[:courts] = courts
      end
    end
    attributes
  end

  def serialize_process(process)
    { id: process.id, tenant_id: process.tenant_id, number: process.number,
      courts: process.courts, active: process.active }
  end
end
