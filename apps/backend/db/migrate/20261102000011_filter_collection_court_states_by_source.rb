class FilterCollectionCourtStatesBySource < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DROP FUNCTION app_private.collection_court_states(uuid);
      CREATE FUNCTION app_private.collection_court_states(p_run_id uuid, p_source text)
      RETURNS TABLE(run_id uuid, court text, state text, job_count bigint,
        succeeded_count bigint, failed_count bigint, pending_count bigint,
        matched_count bigint, pending_identity_count bigint)
      LANGUAGE sql STABLE SECURITY INVOKER SET search_path = pg_catalog, pg_temp AS $fn$
        WITH work AS (
          SELECT job.id, job.run_id, job.court,
            CASE WHEN execution.state = 'succeeded' AND result.job_id IS NOT NULL THEN 'succeeded'
              WHEN execution.state = 'failed' THEN 'failed' ELSE 'pending' END AS state
          FROM public.collection_jobs AS job
          JOIN public.collection_job_executions AS execution
            ON execution.job_id = job.id AND execution.tenant_id = job.tenant_id
          LEFT JOIN public.collection_job_results AS result
            ON result.job_id = job.id AND result.tenant_id = job.tenant_id
          WHERE job.run_id = p_run_id AND (p_source IS NULL OR job.source = p_source)
        ), summaries AS (
          SELECT work.run_id, work.court, count(*) AS job_count,
            count(*) FILTER (WHERE work.state = 'succeeded') AS succeeded_count,
            count(*) FILTER (WHERE work.state = 'failed') AS failed_count,
            count(*) FILTER (WHERE work.state = 'pending') AS pending_count
          FROM work GROUP BY work.run_id, work.court
        ), publications AS (
          SELECT work.run_id, work.court, count(DISTINCT communication.id) AS matched_count,
            count(DISTINCT communication.id) FILTER (WHERE communication.identity_status = 'pending') AS pending_identity_count
          FROM work
          JOIN public.collection_communication_links AS link ON link.job_id = work.id
          JOIN public.collection_communications AS communication
            ON communication.id = link.communication_id AND communication.tenant_id = link.tenant_id
          GROUP BY work.run_id, work.court
        )
        SELECT summary.run_id, summary.court, CASE
          WHEN summary.succeeded_count = summary.job_count THEN 'succeeded'
          WHEN summary.succeeded_count > 0 THEN 'partial'
          WHEN summary.pending_count > 0 THEN 'running'
          ELSE 'failed' END,
          summary.job_count, summary.succeeded_count, summary.failed_count, summary.pending_count,
          CASE WHEN summary.succeeded_count = summary.job_count THEN COALESCE(publications.matched_count, 0) END,
          CASE WHEN summary.succeeded_count = summary.job_count THEN COALESCE(publications.pending_identity_count, 0) END
        FROM summaries AS summary LEFT JOIN publications
          ON publications.run_id = summary.run_id AND publications.court = summary.court
        ORDER BY summary.court
      $fn$;
      REVOKE ALL ON FUNCTION app_private.collection_court_states(uuid,text)
        FROM PUBLIC, advocacia_runtime, advocacia_despachante, advocacia_processador;
      GRANT EXECUTE ON FUNCTION app_private.collection_court_states(uuid,text) TO advocacia_runtime;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Collection state callers require a source filter"
  end
end
