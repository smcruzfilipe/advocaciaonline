class EscreventeController < ApplicationController
  before_action :require_authentication
  before_action :require_onboarding

  def events
    events = for_visible_run do |connection, binds|
      connection.exec_query(<<~SQL, "Tenant collection events", binds).to_a
        SELECT events.id, events.job_id, events.event_type, events.recorded_at,
          jobs.entity_type, jobs.entity_id, jobs.source, jobs.court, jobs.medium
        FROM public.collection_events AS events
        JOIN public.collection_jobs AS jobs ON jobs.id = events.job_id
        WHERE jobs.run_id = $1::uuid
        ORDER BY events.recorded_at, events.id
      SQL
    end
    return run_not_found unless events

    render json: { events: events }
  end

  def execution
    jobs = for_visible_run do |connection, binds|
      connection.exec_query(<<~SQL, "Tenant collection execution states", binds).to_a
        SELECT jobs.id AS job_id, jobs.court, jobs.medium,
          COALESCE(executions.state, 'pending') AS state
        FROM public.collection_jobs AS jobs
        LEFT JOIN public.collection_job_executions AS executions ON executions.job_id = jobs.id
        WHERE jobs.run_id = $1::uuid
        ORDER BY jobs.id
      SQL
    end
    return run_not_found unless jobs

    render json: { jobs: jobs }
  end

  private

  def for_visible_run
    run_id = params[:id]
    return unless run_id.is_a?(String) && run_id.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i)

    DatabaseContext.with_session(session_token) do
      connection = ApplicationRecord.connection
      binds = [ActiveRecord::Relation::QueryAttribute.new("run_id", run_id, ActiveRecord::Type::String.new)]
      visible = connection.exec_query(<<~SQL, "Tenant collection visibility", binds).any?
        SELECT id FROM app_private.collection_runs_for_session() WHERE id = $1::uuid
      SQL
      next unless visible

      yield connection, binds
    end
  end

  def require_onboarding
    return if authenticated_context.fetch("tenant_id")
    api_error("onboarding_required", "Cadastre seu perfil profissional para continuar.", :not_found)
  end

  def run_not_found
    api_error("collection_run_not_found", "Execução de coleta não encontrada.", :not_found)
  end
end
