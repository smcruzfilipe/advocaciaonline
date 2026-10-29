class CreateCollectionPlanning < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DO $guard$
      BEGIN
        IF current_user <> 'advocacia_migrator' THEN
          RAISE EXCEPTION 'Migrations require advocacia_migrator, never the web or despachante role';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'advocacia_despachante'
          AND rolcanlogin AND NOT rolsuper AND NOT rolbypassrls AND NOT rolcreaterole
          AND NOT rolcreatedb AND NOT rolreplication)
          OR EXISTS (SELECT 1 FROM pg_auth_members WHERE member = 'advocacia_despachante'::regrole)
          OR pg_has_role('advocacia_runtime', 'advocacia_despachante', 'MEMBER') THEN
          RAISE EXCEPTION 'Provision an isolated, non-bypass despachante login first';
        END IF;
      END $guard$;
    SQL

    create_table :collection_runs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.date :collection_date, null: false
      t.integer :slot, null: false
      t.text :status, null: false
      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
      t.boolean :audience_fixed, null: false, default: false
    end
    add_index :collection_runs, [:collection_date, :slot], unique: true, name: "unique_collection_date_slot"
    add_check_constraint :collection_runs, "slot IN (1, 2)", name: "collection_run_slot"
    add_check_constraint :collection_runs,
      "status IN ('planned', 'no_work', 'planning_failed', 'interrupted')", name: "collection_run_status"

    create_table :collection_run_audiences, id: false do |t|
      t.uuid :run_id, null: false
      t.references :tenant, type: :uuid, null: false, foreign_key: true, index: false
    end
    add_index :collection_run_audiences, [:run_id, :tenant_id], unique: true, name: "unique_collection_run_audience"
    add_index :collection_run_audiences, [:tenant_id, :run_id], name: "tenant_collection_run_audience"
    add_foreign_key :collection_run_audiences, :collection_runs, column: :run_id

    # Generated keys cannot be supplied independently of the frozen entity_type/entity_id.
    # https://guides.rubyonrails.org/v8.1/active_record_postgresql.html#generated-columns
    create_table :collection_jobs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :run_id, null: false
      t.references :tenant, type: :uuid, null: false, foreign_key: true, index: false
      t.text :entity_type, null: false
      t.uuid :entity_id, null: false
      t.text :source, null: false
      t.text :court, null: false
      t.text :medium, null: false
      t.jsonb :criteria, null: false
      t.text :status, null: false, default: "pending"
      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
      t.virtual :lawyer_id, type: :uuid, as: "CASE WHEN entity_type = 'lawyer' THEN entity_id END", stored: true
      t.virtual :party_monitoring_id, type: :uuid, as: "CASE WHEN entity_type = 'party' THEN entity_id END", stored: true
      t.virtual :process_monitoring_id, type: :uuid, as: "CASE WHEN entity_type = 'process' THEN entity_id END", stored: true
    end
    add_foreign_key :collection_jobs, :collection_runs, column: :run_id
    add_index :collection_jobs, [:tenant_id, :run_id]
    add_index :collection_jobs, [:tenant_id, :id], unique: true, name: "unique_collection_job_tenant_identity"
    add_index :collection_jobs, [:run_id, :tenant_id, :entity_type, :entity_id, :court, :medium],
      unique: true, name: "unique_collection_work"
    add_check_constraint :collection_jobs, "entity_type IN ('lawyer', 'party', 'process')", name: "collection_job_entity"
    add_check_constraint :collection_jobs, "source = 'DJEN'", name: "collection_job_source"
    add_check_constraint :collection_jobs, "court ~ '[^[:space:]]'", name: "collection_job_court"
    add_check_constraint :collection_jobs, "medium IN ('D', 'E')", name: "collection_job_medium"
    add_check_constraint :collection_jobs, "jsonb_typeof(criteria) = 'object'", name: "collection_job_criteria"
    add_check_constraint :collection_jobs, "status = 'pending'", name: "collection_job_status"

    # MATCH SIMPLE skips the two inapplicable NULL keys, while the applicable FK includes tenant_id.
    # https://www.postgresql.org/docs/18/ddl-constraints.html#DDL-CONSTRAINTS-FK
    execute <<~SQL
      ALTER TABLE public.collection_jobs
        ADD CONSTRAINT collection_job_lawyer_same_tenant
          FOREIGN KEY (tenant_id, lawyer_id) REFERENCES public.lawyers (tenant_id, id) MATCH SIMPLE,
        ADD CONSTRAINT collection_job_party_same_tenant
          FOREIGN KEY (tenant_id, party_monitoring_id) REFERENCES public.party_monitorings (tenant_id, id) MATCH SIMPLE,
        ADD CONSTRAINT collection_job_process_same_tenant
          FOREIGN KEY (tenant_id, process_monitoring_id) REFERENCES public.process_monitorings (tenant_id, id) MATCH SIMPLE,
        ADD CONSTRAINT collection_job_audience
          FOREIGN KEY (run_id, tenant_id) REFERENCES public.collection_run_audiences (run_id, tenant_id);
    SQL

    execute <<~SQL
      ALTER TABLE public.collection_runs ENABLE ROW LEVEL SECURITY;
      ALTER TABLE public.collection_runs FORCE ROW LEVEL SECURITY;
      CREATE POLICY collection_despachante_read ON public.collection_runs
        FOR SELECT TO advocacia_despachante USING (true);
      CREATE POLICY collection_despachante_insert ON public.collection_runs
        FOR INSERT TO advocacia_despachante WITH CHECK (true);
      CREATE POLICY collection_despachante_update ON public.collection_runs
        FOR UPDATE TO advocacia_despachante USING (true) WITH CHECK (true);
      REVOKE ALL ON public.collection_runs FROM PUBLIC, advocacia_runtime, advocacia_despachante;
      GRANT SELECT, INSERT ON public.collection_runs TO advocacia_despachante;
      GRANT UPDATE (status, updated_at) ON public.collection_runs TO advocacia_despachante;
      GRANT UPDATE (audience_fixed) ON public.collection_runs TO advocacia_despachante;

      ALTER TABLE public.collection_jobs ENABLE ROW LEVEL SECURITY;
      ALTER TABLE public.collection_jobs FORCE ROW LEVEL SECURITY;
      CREATE POLICY tenant_isolation ON public.collection_jobs
        FOR SELECT TO advocacia_runtime, advocacia_migrator
        USING (tenant_id = (SELECT app_private.current_tenant_id()));
      CREATE POLICY collection_despachante_read ON public.collection_jobs
        FOR SELECT TO advocacia_despachante USING (true);
      CREATE POLICY collection_despachante_insert ON public.collection_jobs
        FOR INSERT TO advocacia_despachante WITH CHECK (true);
      REVOKE ALL ON public.collection_jobs FROM PUBLIC, advocacia_runtime, advocacia_despachante;
      GRANT SELECT ON public.collection_jobs TO advocacia_runtime;
      GRANT SELECT, INSERT ON public.collection_jobs TO advocacia_despachante;

      ALTER TABLE public.collection_run_audiences ENABLE ROW LEVEL SECURITY;
      ALTER TABLE public.collection_run_audiences FORCE ROW LEVEL SECURITY;
      CREATE POLICY tenant_isolation ON public.collection_run_audiences
        FOR SELECT TO advocacia_runtime, advocacia_migrator
        USING (tenant_id = (SELECT app_private.current_tenant_id()));
      CREATE POLICY collection_despachante_read ON public.collection_run_audiences
        FOR SELECT TO advocacia_despachante USING (true);
      CREATE POLICY collection_despachante_insert ON public.collection_run_audiences
        FOR INSERT TO advocacia_despachante WITH CHECK (true);
      REVOKE ALL ON public.collection_run_audiences FROM PUBLIC, advocacia_runtime, advocacia_despachante;
      GRANT SELECT ON public.collection_run_audiences TO advocacia_runtime;
      GRANT SELECT, INSERT ON public.collection_run_audiences TO advocacia_despachante;

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
    raise ActiveRecord::IrreversibleMigration, "The initial collection schema cannot be rolled back"
  end
end
