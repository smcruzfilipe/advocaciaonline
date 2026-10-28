class AddCollectionJobEntityIntegrity < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DO $guard$
      BEGIN
        IF current_user <> 'advocacia_migrator' THEN
          RAISE EXCEPTION 'Migrations require advocacia_migrator, never the web or planner role';
        END IF;
      END $guard$;
    SQL

    # Lawyers already have a unique (tenant_id, id) index from the identity migration.
    add_index :party_monitorings, [:tenant_id, :id], unique: true, name: "unique_party_tenant_identity"
    add_index :process_monitorings, [:tenant_id, :id], unique: true, name: "unique_process_tenant_identity"

    # Generated keys cannot be supplied independently of the frozen entity_type/entity_id.
    # MATCH SIMPLE skips the two inapplicable NULL keys, while the applicable FK includes tenant_id.
    # https://www.postgresql.org/docs/18/ddl-generated-columns.html
    # https://www.postgresql.org/docs/18/ddl-constraints.html#DDL-CONSTRAINTS-FK
    execute <<~SQL
      ALTER TABLE public.collection_jobs
        ADD COLUMN lawyer_id uuid GENERATED ALWAYS AS
          (CASE WHEN entity_type = 'lawyer' THEN entity_id END) STORED,
        ADD COLUMN party_monitoring_id uuid GENERATED ALWAYS AS
          (CASE WHEN entity_type = 'party' THEN entity_id END) STORED,
        ADD COLUMN process_monitoring_id uuid GENERATED ALWAYS AS
          (CASE WHEN entity_type = 'process' THEN entity_id END) STORED;

      ALTER TABLE public.collection_jobs
        ADD CONSTRAINT collection_job_lawyer_same_tenant
          FOREIGN KEY (tenant_id, lawyer_id) REFERENCES public.lawyers (tenant_id, id) MATCH SIMPLE,
        ADD CONSTRAINT collection_job_party_same_tenant
          FOREIGN KEY (tenant_id, party_monitoring_id) REFERENCES public.party_monitorings (tenant_id, id) MATCH SIMPLE,
        ADD CONSTRAINT collection_job_process_same_tenant
          FOREIGN KEY (tenant_id, process_monitoring_id) REFERENCES public.process_monitorings (tenant_id, id) MATCH SIMPLE;
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE public.collection_jobs
        DROP CONSTRAINT collection_job_lawyer_same_tenant,
        DROP CONSTRAINT collection_job_party_same_tenant,
        DROP CONSTRAINT collection_job_process_same_tenant,
        DROP COLUMN lawyer_id,
        DROP COLUMN party_monitoring_id,
        DROP COLUMN process_monitoring_id;
    SQL
    remove_index :process_monitorings, name: "unique_process_tenant_identity"
    remove_index :party_monitorings, name: "unique_party_tenant_identity"
  end
end
