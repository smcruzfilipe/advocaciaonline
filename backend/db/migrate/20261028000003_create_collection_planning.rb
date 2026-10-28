class CreateCollectionPlanning < ActiveRecord::Migration[8.1]
  REGISTRATION_TABLES = %w[tenants lawyers oab_registrations party_monitorings process_monitorings].freeze

  def up
    execute <<~SQL
      DO $guard$
      BEGIN
        IF current_user <> 'advocacia_migrator' THEN
          RAISE EXCEPTION 'Migrations require advocacia_migrator, never the web or planner role';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'advocacia_planner'
          AND rolcanlogin AND NOT rolsuper AND NOT rolbypassrls AND NOT rolcreaterole
          AND NOT rolcreatedb AND NOT rolreplication)
          OR EXISTS (SELECT 1 FROM pg_auth_members WHERE member = 'advocacia_planner'::regrole)
          OR pg_has_role('advocacia_runtime', 'advocacia_planner', 'MEMBER') THEN
          RAISE EXCEPTION 'Provision an isolated, non-bypass planner login first';
        END IF;
      END $guard$;
    SQL

    create_table :collection_runs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.date :collection_date, null: false
      t.integer :slot, null: false
      t.text :status, null: false
      t.timestamps default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :collection_runs, [:collection_date, :slot], unique: true, name: "unique_collection_date_slot"
    add_check_constraint :collection_runs, "slot IN (1, 2)", name: "collection_run_slot"
    add_check_constraint :collection_runs, "status IN ('planned', 'no_work', 'planning_failed')", name: "collection_run_status"

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
    end
    add_foreign_key :collection_jobs, :collection_runs, column: :run_id
    add_index :collection_jobs, [:tenant_id, :run_id]
    add_index :collection_jobs, [:run_id, :tenant_id, :entity_type, :entity_id, :court, :medium],
      unique: true, name: "unique_collection_work"
    add_check_constraint :collection_jobs, "entity_type IN ('lawyer', 'party', 'process')", name: "collection_job_entity"
    add_check_constraint :collection_jobs, "source = 'DJEN'", name: "collection_job_source"
    add_check_constraint :collection_jobs, "court ~ '[^[:space:]]'", name: "collection_job_court"
    add_check_constraint :collection_jobs, "medium IN ('D', 'E')", name: "collection_job_medium"
    add_check_constraint :collection_jobs, "jsonb_typeof(criteria) = 'object'", name: "collection_job_criteria"
    add_check_constraint :collection_jobs, "status = 'pending'", name: "collection_job_status"

    # SELECT policies are scoped to the login, not a client-settable GUC or PUBLIC.
    # https://www.postgresql.org/docs/18/sql-createpolicy.html
    REGISTRATION_TABLES.each do |table|
      execute <<~SQL
        ALTER POLICY tenant_isolation ON public.#{table} TO advocacia_runtime, advocacia_migrator;
        CREATE POLICY collection_planner_read ON public.#{table}
          FOR SELECT TO advocacia_planner USING (true);
        REVOKE ALL ON public.#{table} FROM advocacia_planner;
        GRANT SELECT ON public.#{table} TO advocacia_planner;
      SQL
    end

    execute <<~SQL
      ALTER TABLE public.collection_runs ENABLE ROW LEVEL SECURITY;
      ALTER TABLE public.collection_runs FORCE ROW LEVEL SECURITY;
      CREATE POLICY collection_planner_read ON public.collection_runs
        FOR SELECT TO advocacia_planner USING (true);
      CREATE POLICY collection_planner_insert ON public.collection_runs
        FOR INSERT TO advocacia_planner WITH CHECK (true);
      CREATE POLICY collection_planner_update ON public.collection_runs
        FOR UPDATE TO advocacia_planner USING (true) WITH CHECK (true);
      REVOKE ALL ON public.collection_runs FROM PUBLIC, advocacia_runtime, advocacia_planner;
      GRANT SELECT, INSERT ON public.collection_runs TO advocacia_planner;
      GRANT UPDATE (status, updated_at) ON public.collection_runs TO advocacia_planner;

      ALTER TABLE public.collection_jobs ENABLE ROW LEVEL SECURITY;
      ALTER TABLE public.collection_jobs FORCE ROW LEVEL SECURITY;
      CREATE POLICY tenant_isolation ON public.collection_jobs
        FOR SELECT TO advocacia_runtime, advocacia_migrator
        USING (tenant_id = (SELECT app_private.current_tenant_id()));
      CREATE POLICY collection_planner_read ON public.collection_jobs
        FOR SELECT TO advocacia_planner USING (true);
      CREATE POLICY collection_planner_insert ON public.collection_jobs
        FOR INSERT TO advocacia_planner WITH CHECK (true);
      REVOKE ALL ON public.collection_jobs FROM PUBLIC, advocacia_runtime, advocacia_planner;
      GRANT SELECT ON public.collection_jobs TO advocacia_runtime;
      GRANT SELECT, INSERT ON public.collection_jobs TO advocacia_planner;
    SQL
  end

  def down
    drop_table :collection_jobs
    drop_table :collection_runs
    REGISTRATION_TABLES.each do |table|
      execute <<~SQL
        DROP POLICY collection_planner_read ON public.#{table};
        REVOKE ALL ON public.#{table} FROM advocacia_planner;
        ALTER POLICY tenant_isolation ON public.#{table} TO PUBLIC;
      SQL
    end
  end
end
