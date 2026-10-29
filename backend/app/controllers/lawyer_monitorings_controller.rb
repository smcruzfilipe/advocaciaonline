class LawyerMonitoringsController < ApplicationController
  before_action :require_authentication

  def show
    unless authenticated_context["tenant_id"]
      return api_error("onboarding_required", "Cadastre seu perfil profissional para continuar.", :not_found)
    end

    payload = DatabaseContext.with_session(session_token) do
      context = authorize_session!("consultar_monitoramentos")
      lawyer = Lawyer.find_by(tenant_id: context.fetch("tenant_id"))
      if lawyer
        oabs = lawyer.oab_registrations.order(primary: :desc, uf: :asc, number: :asc).pluck(:number, :uf)
        { id: lawyer.id, tenant_id: lawyer.tenant_id, full_name: lawyer.full_name,
          oabs: oabs.map { |number, uf| { number: number, uf: uf } } }
      end
    end
    return api_error("onboarding_required", "Cadastre seu perfil profissional para continuar.", :not_found) unless payload

    render json: payload
  end
end
