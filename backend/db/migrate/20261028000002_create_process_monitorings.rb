class CreateProcessMonitorings < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DO $guard$
      BEGIN
        IF current_user <> 'advocacia_migrator' THEN
          RAISE EXCEPTION 'Migrations require advocacia_migrator, never the web role';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'advocacia_runtime'
          AND NOT rolsuper AND NOT rolbypassrls AND NOT rolcreaterole AND NOT rolcreatedb
          AND NOT rolreplication) OR pg_has_role('advocacia_runtime', 'advocacia_migrator', 'MEMBER') THEN
          RAISE EXCEPTION 'Provision an isolated, non-bypass runtime role first';
        END IF;
      END $guard$;
    SQL

    create_table :process_monitorings, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: true, index: false
      t.text :number, null: false, collation: "C"
      t.text :courts, array: true
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :process_monitorings, [:tenant_id, :number], unique: true, name: "unique_tenant_process_number"
    add_check_constraint :process_monitorings, "length(number) = 20 AND number !~ '[^0-9]'",
      name: "process_canonical_number"
    add_check_constraint :process_monitorings,
      "courts IS NULL OR (cardinality(courts) > 0 AND array_position(courts, NULL) IS NULL)",
      name: "process_courts_nonempty"

    execute <<~SQL
      ALTER TABLE public.process_monitorings ENABLE ROW LEVEL SECURITY;
      ALTER TABLE public.process_monitorings FORCE ROW LEVEL SECURITY;
      CREATE POLICY tenant_isolation ON public.process_monitorings
        USING (tenant_id = (SELECT app_private.current_tenant_id()))
        WITH CHECK (tenant_id = (SELECT app_private.current_tenant_id()));
      REVOKE ALL ON public.process_monitorings FROM PUBLIC, advocacia_runtime;
      GRANT SELECT, INSERT ON public.process_monitorings TO advocacia_runtime;
      GRANT UPDATE (number, courts, active, updated_at) ON public.process_monitorings TO advocacia_runtime;
    SQL
  end

  def down
    drop_table :process_monitorings
  end
end
