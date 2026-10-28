class OnboardingsController < ApplicationController
  before_action :require_authentication
  before_action :verify_csrf, only: :create

  def show
    payload = DatabaseContext.with_session(session_token) do
      lawyer = Lawyer.first
      { tenant_id: lawyer.tenant_id, profile: serialize_profile(lawyer) } if lawyer
    end
    return api_error("onboarding_required", "Cadastre seu perfil profissional para continuar.", :not_found) unless payload
    render json: payload
  end

  def create
    return api_error("invalid_content_type", "Envie os dados em JSON.", :unsupported_media_type) unless request.media_type == "application/json"
    lawyer = LawyerOnboarding.call(token: session_token, input: request.request_parameters)
    profile = DatabaseContext.with_session(session_token) { serialize_profile(lawyer) }
    render json: { authenticated: true, onboarded: true,
      csrf_token: authenticated_context.fetch("csrf_token"), profile: profile }, status: :created
  rescue LawyerOnboarding::InvalidProfile => error
    api_error("invalid_profile", error.message, :unprocessable_entity, details: error.details)
  rescue LawyerOnboarding::AlreadyOnboarded
    api_error("already_onboarded", "Seu perfil profissional já foi cadastrado.", :conflict)
  rescue LawyerOnboarding::Unauthenticated
    api_error("authentication_required", "Entre com sua conta Google para continuar.", :unauthorized)
  end

  private

  def serialize_profile(lawyer)
    registrations = lawyer.oab_registrations.order(primary: :desc).to_a
    { full_name: lawyer.full_name, office_name: lawyer.office_name,
      primary_oab: registrations.find(&:primary).attributes.slice("number", "uf"),
      secondary_oabs: registrations.reject(&:primary).map { |oab| oab.attributes.slice("number", "uf") } }
  end
end
