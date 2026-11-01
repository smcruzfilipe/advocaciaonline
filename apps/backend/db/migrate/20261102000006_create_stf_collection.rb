class CreateStfCollection < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE public.collection_jobs DROP CONSTRAINT collection_job_source,
        DROP CONSTRAINT collection_job_medium;
      ALTER TABLE public.collection_jobs ADD CONSTRAINT collection_job_source_medium CHECK (
        (source = 'DJEN' AND medium = 'D') OR
        (source = 'STF' AND court = 'STF' AND medium = 'A')
      );

      CREATE TABLE public.stf_captures (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id uuid NOT NULL REFERENCES public.tenants(id),
        run_id uuid NOT NULL,
        incidente numeric NOT NULL CHECK (incidente > 0 AND incidente = trunc(incidente)),
        semantic_items jsonb NOT NULL CHECK (jsonb_typeof(semantic_items) = 'array'),
        recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
        CONSTRAINT stf_capture_audience FOREIGN KEY (run_id, tenant_id)
          REFERENCES public.collection_run_audiences(run_id, tenant_id),
        CONSTRAINT stf_capture_key UNIQUE (tenant_id, run_id, incidente),
        CONSTRAINT stf_capture_tenant_id UNIQUE (tenant_id, id)
      );
      ALTER TABLE public.stf_captures ENABLE ROW LEVEL SECURITY;
      ALTER TABLE public.stf_captures FORCE ROW LEVEL SECURITY;
      CREATE POLICY tenant_isolation ON public.stf_captures FOR SELECT TO advocacia_runtime
        USING (tenant_id = (SELECT app_private.current_tenant_id()));
      CREATE POLICY processor_owner_read ON public.stf_captures FOR SELECT TO advocacia_migrator USING (true);
      CREATE POLICY processor_owner_insert ON public.stf_captures FOR INSERT TO advocacia_migrator WITH CHECK (true);
      REVOKE ALL ON public.stf_captures FROM PUBLIC, advocacia_runtime, advocacia_despachante, advocacia_processador;
      GRANT SELECT ON public.stf_captures TO advocacia_runtime;

      ALTER TABLE public.collection_communications
        ADD COLUMN stf_capture_id uuid, ADD COLUMN stf_ordinal bigint,
        ADD CONSTRAINT communication_stf_capture_tenant FOREIGN KEY (tenant_id, stf_capture_id)
          REFERENCES public.stf_captures (tenant_id, id),
        DROP CONSTRAINT collection_communication_source_payload;
      ALTER TABLE public.collection_communications ADD CONSTRAINT collection_communication_source_payload CHECK (
        jsonb_typeof(payload) = 'object' AND (
          (source = 'DJEN' AND stf_capture_id IS NULL AND stf_ordinal IS NULL) OR
          (source = 'STF' AND stf_capture_id IS NOT NULL AND stf_ordinal IS NOT NULL AND stf_ordinal > 0
            AND identity_status = 'pending' AND source_id IS NULL AND source_hash IS NULL
            AND identity_digest IS NULL AND warning = 'possible_duplicate')
        )
      );
      CREATE UNIQUE INDEX unique_stf_capture_ordinal
        ON public.collection_communications (stf_capture_id, stf_ordinal) WHERE stf_capture_id IS NOT NULL;

      ALTER TABLE public.collection_job_results ADD COLUMN eligible_process_count bigint;
      ALTER TABLE public.collection_job_results DROP CONSTRAINT collection_job_result_counts;
      ALTER TABLE public.collection_job_results ADD CONSTRAINT collection_job_result_counts CHECK (
        matched_count >= 0 AND pending_identity_count BETWEEN 0 AND matched_count AND (
          (source_path IN ('caderno', 'fallback') AND eligible_process_count IS NULL) OR
          (source_path = 'andamentos' AND eligible_process_count IS NOT NULL AND eligible_process_count >= 0)
        )
      );
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "STF captures are durable collection history"
  end
end
