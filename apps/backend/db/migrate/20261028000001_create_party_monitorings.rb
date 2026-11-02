class CreatePartyMonitorings < ActiveRecord::Migration[8.1]
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

    create_table :party_monitorings, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: true, index: false
      t.text :name, null: false
      t.text :canonical_name, null: false, collation: "C"
      t.text :courts, array: true
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :party_monitorings, [:tenant_id, :canonical_name], unique: true, name: "unique_party_name_per_tenant"
    add_index :party_monitorings, [:tenant_id, :id], unique: true, name: "unique_party_tenant_identity"
    add_check_constraint :party_monitorings, "name ~ '[^[:space:]]'", name: "party_name_present"
    add_check_constraint :party_monitorings,
      "courts IS NULL OR (cardinality(courts) > 0 AND array_position(courts, NULL) IS NULL)",
      name: "party_courts_nonempty"

    execute <<~SQL
      ALTER TABLE public.party_monitorings ENABLE ROW LEVEL SECURITY;
      ALTER TABLE public.party_monitorings FORCE ROW LEVEL SECURITY;
      CREATE POLICY tenant_isolation ON public.party_monitorings
        TO advocacia_runtime, advocacia_migrator
        USING (tenant_id = (SELECT app_private.current_tenant_id()))
        WITH CHECK (tenant_id = (SELECT app_private.current_tenant_id()));
      CREATE POLICY collection_despachante_read ON public.party_monitorings
        FOR SELECT TO advocacia_despachante USING (true);
      REVOKE ALL ON public.party_monitorings FROM PUBLIC, advocacia_runtime, advocacia_despachante;
      GRANT SELECT, INSERT ON public.party_monitorings TO advocacia_runtime;
      GRANT UPDATE (name, canonical_name, courts, active, updated_at)
        ON public.party_monitorings TO advocacia_runtime;
      GRANT SELECT ON public.party_monitorings TO advocacia_despachante;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
