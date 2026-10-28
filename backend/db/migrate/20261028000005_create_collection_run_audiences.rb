class CreateCollectionRunAudiences < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DO $guard$
      BEGIN
        IF current_user <> 'advocacia_migrator' THEN
          RAISE EXCEPTION 'Migrations require advocacia_migrator, never the web or planner role';
        END IF;
      END $guard$;
    SQL

    add_column :collection_runs, :audience_fixed, :boolean, null: false, default: false
    create_table :collection_run_audiences, id: false do |t|
      t.uuid :run_id, null: false
      t.references :tenant, type: :uuid, null: false, foreign_key: true, index: false
    end
    add_index :collection_run_audiences, [:run_id, :tenant_id], unique: true, name: "unique_collection_run_audience"
    add_index :collection_run_audiences, [:tenant_id, :run_id], name: "tenant_collection_run_audience"
    add_foreign_key :collection_run_audiences, :collection_runs, column: :run_id

    execute <<~SQL
      -- Only already persisted jobs prove historical participation. In particular,
      -- old no_work/failed executions must not be assigned to today's tenants.
      CREATE POLICY collection_audience_backfill ON public.collection_jobs
        FOR SELECT TO advocacia_migrator USING (true);
      INSERT INTO public.collection_run_audiences (run_id, tenant_id)
        SELECT DISTINCT run_id, tenant_id FROM public.collection_jobs;
      DROP POLICY collection_audience_backfill ON public.collection_jobs;

      ALTER TABLE public.collection_jobs ADD CONSTRAINT collection_job_audience
        FOREIGN KEY (run_id, tenant_id)
        REFERENCES public.collection_run_audiences (run_id, tenant_id);

      ALTER TABLE public.collection_run_audiences ENABLE ROW LEVEL SECURITY;
      ALTER TABLE public.collection_run_audiences FORCE ROW LEVEL SECURITY;
      CREATE POLICY tenant_isolation ON public.collection_run_audiences
        FOR SELECT TO advocacia_runtime, advocacia_migrator
        USING (tenant_id = (SELECT app_private.current_tenant_id()));
      CREATE POLICY collection_planner_read ON public.collection_run_audiences
        FOR SELECT TO advocacia_planner USING (true);
      CREATE POLICY collection_planner_insert ON public.collection_run_audiences
        FOR INSERT TO advocacia_planner WITH CHECK (true);
      REVOKE ALL ON public.collection_run_audiences FROM PUBLIC, advocacia_runtime, advocacia_planner;
      GRANT SELECT ON public.collection_run_audiences TO advocacia_runtime;
      GRANT SELECT, INSERT ON public.collection_run_audiences TO advocacia_planner;
      GRANT UPDATE (audience_fixed) ON public.collection_runs TO advocacia_planner;

      -- Runtime still cannot SELECT collection_runs. The fixed function is owned
      -- by migrator and both its join and the forced policy require tenant proof.
      CREATE POLICY collection_session_read ON public.collection_runs
        FOR SELECT TO advocacia_migrator USING (EXISTS (
          SELECT 1 FROM public.collection_run_audiences AS audience
          WHERE audience.run_id = collection_runs.id
            AND audience.tenant_id = (SELECT app_private.current_tenant_id())
        ));
      CREATE FUNCTION app_private.collection_runs_for_session()
      RETURNS TABLE(id uuid, collection_date date, slot integer, status text)
      LANGUAGE sql STABLE SECURITY DEFINER
      SET search_path = pg_catalog, public, pg_temp AS $fn$
        SELECT run.id, run.collection_date, run.slot, run.status
        FROM public.collection_runs AS run
        JOIN public.collection_run_audiences AS audience ON audience.run_id = run.id
        WHERE audience.tenant_id = (SELECT app_private.current_tenant_id())
      $fn$;
      REVOKE ALL ON FUNCTION app_private.collection_runs_for_session() FROM PUBLIC;
      GRANT EXECUTE ON FUNCTION app_private.collection_runs_for_session() TO advocacia_runtime;
    SQL
  end

  def down
    execute <<~SQL
      DROP FUNCTION app_private.collection_runs_for_session();
      DROP POLICY collection_session_read ON public.collection_runs;
      ALTER TABLE public.collection_jobs DROP CONSTRAINT collection_job_audience;
      REVOKE UPDATE (audience_fixed) ON public.collection_runs FROM advocacia_planner;
    SQL
    drop_table :collection_run_audiences
    remove_column :collection_runs, :audience_fixed
  end
end
