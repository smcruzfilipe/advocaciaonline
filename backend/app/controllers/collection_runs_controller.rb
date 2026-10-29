class CollectionRunsController < ApplicationController
  before_action :require_authentication
  before_action :require_onboarding

  def index
    runs = DatabaseContext.with_session(session_token) do
      authorize_session!(owner_only: true)
      ApplicationRecord.connection.select_all(<<~SQL).to_a
        SELECT id, collection_date::text AS collection_date, slot, status
        FROM app_private.collection_runs_for_session()
      SQL
    end
    render json: { runs: runs }
  end

  def jobs
    run_id = params[:id]

    jobs = DatabaseContext.with_session(session_token) do
      authorize_session!(owner_only: true)
      next unless run_id.is_a?(String) && run_id.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i)

      connection = ApplicationRecord.connection
      binds = [ActiveRecord::Relation::QueryAttribute.new("run_id", run_id, ActiveRecord::Type::String.new)]
      visible = connection.exec_query(<<~SQL, "Tenant collection execution", binds).any?
        SELECT id FROM app_private.collection_runs_for_session() WHERE id = $1::uuid
      SQL
      next unless visible

      connection.exec_query(<<~SQL, "Tenant collection jobs", binds).map do |job|
        SELECT id, entity_type, entity_id, source, court, medium, criteria::text AS criteria, status
        FROM public.collection_jobs WHERE run_id = $1::uuid
      SQL
        job.merge("criteria" => JSON.parse(job.fetch("criteria")))
      end
    end
    return run_not_found unless jobs

    render json: { jobs: jobs }
  end

  private

  def require_onboarding
    return if authenticated_context.fetch("tenant_id")
    api_error("onboarding_required", "Cadastre seu perfil profissional para continuar.", :not_found)
  end

  def run_not_found
    api_error("collection_run_not_found", "Execução de coleta não encontrada.", :not_found)
  end
end
