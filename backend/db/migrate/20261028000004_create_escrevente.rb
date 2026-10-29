class CreateEscrevente < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DO $guard$
      BEGIN
        IF current_user <> 'advocacia_migrator'
          OR EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND (rolsuper OR rolbypassrls)) THEN
          RAISE EXCEPTION 'Migrations require the non-bypass advocacia_migrator owner';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'advocacia_processador'
          AND rolcanlogin AND NOT rolsuper AND NOT rolbypassrls AND NOT rolcreaterole
          AND NOT rolcreatedb AND NOT rolreplication AND NOT rolinherit)
          OR EXISTS (SELECT 1 FROM pg_auth_members
            WHERE member = 'advocacia_processador'::regrole OR roleid = 'advocacia_processador'::regrole) THEN
          RAISE EXCEPTION 'Provision an isolated, non-bypass processor login first';
        END IF;
      END $guard$;
    SQL

    create_table :collection_job_executions, id: false do |t|
      t.uuid :job_id, null: false, primary_key: true
      t.references :tenant, type: :uuid, null: false, foreign_key: true, index: false
      t.text :state, null: false, default: "pending"
      t.timestamptz :updated_at, null: false, default: -> { "clock_timestamp()" }
      t.text :claim_digest
      t.timestamptz :lease_expires_at
      t.integer :caderno_attempts, null: false, default: 0
      t.integer :fallback_attempts, null: false, default: 0
      t.text :phase, null: false, default: "caderno"
      t.boolean :attempt_in_flight, null: false, default: false
      t.timestamptz :attempt_started_at
      t.timestamptz :next_attempt_at
    end
    add_index :collection_job_executions, [:tenant_id, :state, :job_id], name: "tenant_collection_execution_state"
    add_index :collection_job_executions, :lease_expires_at, where: "claim_digest IS NOT NULL",
      name: "collection_execution_lease_expiry"
    add_check_constraint :collection_job_executions, "state IN ('pending', 'running', 'succeeded', 'failed')",
      name: "collection_execution_state"
    add_check_constraint :collection_job_executions,
      "(claim_digest IS NULL AND lease_expires_at IS NULL) OR (claim_digest IS NOT NULL AND claim_digest ~ '^[0-9a-f]{64}$' AND lease_expires_at IS NOT NULL)",
      name: "collection_execution_claim_pair"
    add_check_constraint :collection_job_executions,
      "caderno_attempts BETWEEN 0 AND 3 AND fallback_attempts BETWEEN 0 AND 3 AND phase IN ('caderno', 'fallback')",
      name: "collection_execution_attempt_progress"
    add_check_constraint :collection_job_executions,
      "NOT attempt_in_flight OR attempt_started_at IS NOT NULL",
      name: "collection_execution_in_flight_proof"

    create_table :collection_events, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :job_id, null: false
      t.references :tenant, type: :uuid, null: false, foreign_key: true, index: false
      t.text :event_type, null: false
      t.timestamptz :recorded_at, null: false, default: -> { "clock_timestamp()" }
    end
    add_index :collection_events, [:job_id, :event_type], unique: true, name: "unique_collection_job_event"
    add_index :collection_events, [:tenant_id, :recorded_at, :id], name: "tenant_collection_event_history"
    add_check_constraint :collection_events, "event_type IN ('started', 'completed')", name: "collection_event_type"

    execute <<~SQL
      ALTER TABLE public.collection_job_executions ADD CONSTRAINT collection_execution_job_same_tenant
        FOREIGN KEY (tenant_id, job_id) REFERENCES public.collection_jobs (tenant_id, id);
      ALTER TABLE public.collection_events ADD CONSTRAINT collection_event_job_same_tenant
        FOREIGN KEY (tenant_id, job_id) REFERENCES public.collection_jobs (tenant_id, id);

      ALTER TABLE public.collection_job_executions ENABLE ROW LEVEL SECURITY;
      ALTER TABLE public.collection_job_executions FORCE ROW LEVEL SECURITY;
      CREATE POLICY tenant_isolation ON public.collection_job_executions
        FOR SELECT TO advocacia_runtime
        USING (tenant_id = (SELECT app_private.current_tenant_id()));
      -- FORCE RLS also applies inside the migrator-owned definers. Only their
      -- administrative owner can read/insert/update the execution row they lock.
      CREATE POLICY processor_owner_read ON public.collection_job_executions
        FOR SELECT TO advocacia_migrator USING (true);
      CREATE POLICY processor_owner_insert ON public.collection_job_executions
        FOR INSERT TO advocacia_migrator WITH CHECK (true);
      CREATE POLICY processor_owner_update ON public.collection_job_executions
        FOR UPDATE TO advocacia_migrator USING (true) WITH CHECK (true);
      REVOKE ALL ON public.collection_job_executions FROM PUBLIC, advocacia_runtime, advocacia_despachante, advocacia_processador;
      GRANT SELECT (job_id, tenant_id, state, updated_at) ON public.collection_job_executions TO advocacia_runtime;

      ALTER TABLE public.collection_events ENABLE ROW LEVEL SECURITY;
      ALTER TABLE public.collection_events FORCE ROW LEVEL SECURITY;
      CREATE POLICY tenant_isolation ON public.collection_events
        FOR SELECT TO advocacia_runtime
        USING (tenant_id = (SELECT app_private.current_tenant_id()));
      CREATE POLICY processor_owner_read ON public.collection_events
        FOR SELECT TO advocacia_migrator USING (true);
      CREATE POLICY processor_owner_insert ON public.collection_events
        FOR INSERT TO advocacia_migrator WITH CHECK (true);
      REVOKE ALL ON public.collection_events FROM PUBLIC, advocacia_runtime, advocacia_despachante, advocacia_processador;
      GRANT SELECT ON public.collection_events TO advocacia_runtime;

      -- New jobs get their pending execution row transactionally;
      -- skipped ON CONFLICT rows fire no trigger.

      CREATE FUNCTION app_private.initialize_collection_execution() RETURNS trigger
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      BEGIN
        INSERT INTO public.collection_job_executions (job_id, tenant_id, phase)
          SELECT NEW.id, NEW.tenant_id, CASE WHEN run.slot = 2 THEN 'fallback' ELSE 'caderno' END
          FROM public.collection_runs AS run WHERE run.id = NEW.run_id;
        RETURN NULL;
      END $fn$;
      REVOKE ALL ON FUNCTION app_private.initialize_collection_execution()
        FROM PUBLIC, advocacia_runtime, advocacia_despachante, advocacia_processador;
      CREATE TRIGGER initialize_collection_execution AFTER INSERT ON public.collection_jobs
        FOR EACH ROW EXECUTE FUNCTION app_private.initialize_collection_execution();

      CREATE FUNCTION app_private.processor_claim(p_job_id uuid)
      RETURNS TABLE(token text, expires_at timestamptz, state text)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE execution public.collection_job_executions%ROWTYPE;
      BEGIN
        SELECT stored.* INTO execution FROM public.collection_job_executions AS stored
          WHERE stored.job_id = p_job_id FOR UPDATE;
        IF NOT FOUND
          OR (execution.claim_digest IS NOT NULL AND execution.lease_expires_at > clock_timestamp()) THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        IF EXISTS (
          SELECT 1 FROM public.collection_jobs AS job
          JOIN public.collection_runs AS run ON run.id = job.run_id
          WHERE job.id = execution.job_id
            AND run.collection_date > (clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date
        ) THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        -- Two independently generated UUID v4 values supply 244 random bits.
        -- Only their SHA-256 digest is persisted; no extension or client secret is required.
        token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
        expires_at := clock_timestamp() + interval '15 minutes';
        -- A lease transfers ownership, not execution state. Succeeded claims
        -- only recover confirmed events; processors must not repeat collection.
        state := execution.state;
        UPDATE public.collection_job_executions SET
          claim_digest = encode(sha256(convert_to(token, 'UTF8')), 'hex'),
          lease_expires_at = expires_at, updated_at = clock_timestamp()
          WHERE job_id = execution.job_id;
        RETURN NEXT;
      END $fn$;

      CREATE FUNCTION app_private.processor_next()
      RETURNS TABLE(job_id uuid, token text, state text)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE next_job_id uuid;
      BEGIN
        SELECT execution.job_id INTO next_job_id
          FROM public.collection_job_executions AS execution
          JOIN public.collection_jobs AS job
            ON job.id = execution.job_id AND job.tenant_id = execution.tenant_id
          JOIN public.collection_runs AS run ON run.id = job.run_id
          WHERE run.status = 'planned'
            AND run.collection_date <= (clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date
            AND execution.state IN ('pending', 'running')
            AND (execution.claim_digest IS NULL OR execution.lease_expires_at <= clock_timestamp())
            AND (run.collection_date < (clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date
              OR execution.next_attempt_at IS NULL OR execution.next_attempt_at <= clock_timestamp())
          ORDER BY run.collection_date, run.slot, execution.job_id
          LIMIT 1 FOR UPDATE OF execution SKIP LOCKED;
        IF NOT FOUND THEN
          RETURN;
        END IF;
        -- The row remains locked until this transaction commits. Reuse the
        -- claim generator without exposing tenant data or releasing that lock.
        RETURN QUERY SELECT next_job_id, claim.token, claim.state
          FROM app_private.processor_claim(next_job_id) AS claim;
      END $fn$;

      CREATE FUNCTION app_private.processor_renew(p_job_id uuid, p_token text)
      RETURNS TABLE(expires_at timestamptz)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE execution public.collection_job_executions%ROWTYPE;
      BEGIN
        SELECT stored.* INTO execution FROM public.collection_job_executions AS stored
          WHERE stored.job_id = p_job_id FOR UPDATE;
        IF NOT FOUND OR p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$'
          OR execution.claim_digest IS NULL OR execution.lease_expires_at IS NULL
          OR execution.claim_digest <> encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
          OR execution.lease_expires_at <= clock_timestamp() THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        expires_at := clock_timestamp() + interval '15 minutes';
        UPDATE public.collection_job_executions SET lease_expires_at = expires_at, updated_at = clock_timestamp()
          WHERE job_id = execution.job_id;
        RETURN NEXT;
      END $fn$;

      CREATE FUNCTION app_private.processor_start(p_job_id uuid, p_token text)
      RETURNS TABLE(id uuid, recorded_at timestamptz)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE execution public.collection_job_executions%ROWTYPE;
      BEGIN
        SELECT stored.* INTO execution FROM public.collection_job_executions AS stored
          WHERE stored.job_id = p_job_id FOR UPDATE;
        IF NOT FOUND OR p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$'
          OR execution.claim_digest IS NULL OR execution.lease_expires_at IS NULL
          OR execution.claim_digest <> encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
          OR execution.lease_expires_at <= clock_timestamp() OR execution.state NOT IN ('pending', 'running', 'failed', 'succeeded') THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        INSERT INTO public.collection_events (job_id, tenant_id, event_type)
          VALUES (execution.job_id, execution.tenant_id, 'started')
          ON CONFLICT (job_id, event_type) DO NOTHING;
        UPDATE public.collection_job_executions SET state = 'running', updated_at = clock_timestamp()
          WHERE job_id = execution.job_id AND state IN ('pending', 'failed');
        RETURN QUERY SELECT event.id, event.recorded_at FROM public.collection_events AS event
          WHERE event.job_id = execution.job_id AND event.event_type = 'started';
      END $fn$;

      CREATE FUNCTION app_private.processor_finish(p_job_id uuid, p_token text)
      RETURNS TABLE(id uuid, recorded_at timestamptz)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE execution public.collection_job_executions%ROWTYPE;
      BEGIN
        SELECT stored.* INTO execution FROM public.collection_job_executions AS stored
          WHERE stored.job_id = p_job_id FOR UPDATE;
        IF NOT FOUND OR p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$'
          OR execution.claim_digest IS NULL OR execution.lease_expires_at IS NULL
          OR execution.claim_digest <> encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
          OR execution.lease_expires_at <= clock_timestamp() OR execution.state NOT IN ('running', 'succeeded') THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.collection_events AS event
          WHERE event.job_id = execution.job_id AND event.event_type = 'started') THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        -- A collection attempt may only finish through the transaction that
        -- persisted its result. The existing standalone Escrevente contract
        -- remains available for work that has not started a source attempt.
        IF execution.state = 'running' AND (execution.caderno_attempts > 0 OR execution.fallback_attempts > 0)
          AND NOT EXISTS (SELECT 1 FROM public.collection_job_results AS result
            WHERE result.job_id = execution.job_id AND result.tenant_id = execution.tenant_id) THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        INSERT INTO public.collection_events (job_id, tenant_id, event_type)
          VALUES (execution.job_id, execution.tenant_id, 'completed')
          ON CONFLICT (job_id, event_type) DO NOTHING;
        UPDATE public.collection_job_executions SET state = 'succeeded', updated_at = clock_timestamp()
          WHERE job_id = execution.job_id AND state = 'running';
        RETURN QUERY SELECT event.id, event.recorded_at FROM public.collection_events AS event
          WHERE event.job_id = execution.job_id AND event.event_type = 'completed';
      END $fn$;

      CREATE FUNCTION app_private.processor_fail(p_job_id uuid, p_token text)
      RETURNS TABLE(state text)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE execution public.collection_job_executions%ROWTYPE;
      BEGIN
        SELECT stored.* INTO execution FROM public.collection_job_executions AS stored
          WHERE stored.job_id = p_job_id FOR UPDATE;
        IF NOT FOUND OR p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$'
          OR execution.claim_digest IS NULL OR execution.lease_expires_at IS NULL
          OR execution.claim_digest <> encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
          OR execution.lease_expires_at <= clock_timestamp() OR execution.state NOT IN ('pending', 'running') THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        UPDATE public.collection_job_executions SET state = 'failed', claim_digest = NULL,
          lease_expires_at = NULL, updated_at = clock_timestamp() WHERE job_id = execution.job_id;
        RETURN QUERY SELECT 'failed'::text;
      END $fn$;

      REVOKE ALL ON FUNCTION app_private.processor_next(), app_private.processor_claim(uuid),
        app_private.processor_renew(uuid,text), app_private.processor_start(uuid,text),
        app_private.processor_finish(uuid,text), app_private.processor_fail(uuid,text)
        FROM PUBLIC, advocacia_runtime, advocacia_despachante, advocacia_processador;
      GRANT USAGE ON SCHEMA app_private TO advocacia_processador;
      GRANT EXECUTE ON FUNCTION app_private.processor_next(), app_private.processor_claim(uuid),
        app_private.processor_renew(uuid,text), app_private.processor_start(uuid,text),
        app_private.processor_finish(uuid,text), app_private.processor_fail(uuid,text)
        TO advocacia_processador;
    SQL

    create_table :collection_communications, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: true, index: false
      t.text :source, null: false, default: "DJEN"
      t.decimal :source_id
      t.text :source_hash
      t.binary :identity_digest
      t.text :identity_status, null: false
      t.text :warning
      t.jsonb :payload, null: false
      t.timestamptz :recorded_at, null: false, default: -> { "clock_timestamp()" }
    end
    add_index :collection_communications, [:tenant_id, :id], unique: true, name: "unique_collection_communication_tenant"
    # Never index a truncated ID/hash or use a digest as equality. The fixed-size,
    # non-unique index narrows candidates; the function compares the complete pair.
    add_index :collection_communications, [:tenant_id, :source, :identity_digest],
      where: "identity_status = 'complete'", name: "collection_communication_identity_candidates"
    add_check_constraint :collection_communications, "source = 'DJEN' AND jsonb_typeof(payload) = 'object'",
      name: "collection_communication_source_payload"
    add_check_constraint :collection_communications, <<~SQL.squish, name: "collection_communication_identity"
      (identity_status = 'complete' AND source_id IS NOT NULL AND source_id > 0
        AND source_id = trunc(source_id) AND source_hash IS NOT NULL AND source_hash <> ''
        AND identity_digest IS NOT NULL AND octet_length(identity_digest) = 32 AND warning IS NULL)
      OR (identity_status = 'pending' AND source_id IS NULL AND source_hash IS NULL
        AND identity_digest IS NULL AND warning IS NOT NULL AND warning = 'possible_duplicate')
    SQL

    create_table :collection_communication_links, id: false do |t|
      t.uuid :tenant_id, null: false
      t.uuid :communication_id, null: false
      t.uuid :job_id, null: false
      t.timestamptz :recorded_at, null: false, default: -> { "clock_timestamp()" }
    end
    add_index :collection_communication_links, [:job_id, :communication_id], unique: true,
      name: "unique_collection_communication_job_link"
    add_index :collection_communication_links, [:tenant_id, :communication_id, :job_id],
      name: "tenant_collection_communication_links"

    create_table :collection_job_results, id: false do |t|
      t.uuid :job_id, null: false, primary_key: true
      t.uuid :tenant_id, null: false
      t.text :source_path, null: false
      t.bigint :matched_count, null: false
      t.bigint :pending_identity_count, null: false
      t.timestamptz :recorded_at, null: false, default: -> { "clock_timestamp()" }
    end
    add_index :collection_job_results, [:tenant_id, :job_id], name: "tenant_collection_job_results"
    add_check_constraint :collection_job_results,
      "source_path IN ('caderno', 'fallback') AND matched_count >= 0 AND pending_identity_count BETWEEN 0 AND matched_count",
      name: "collection_job_result_counts"

    create_table :collection_job_failures, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :job_id, null: false
      t.uuid :tenant_id, null: false
      t.text :code, null: false
      t.timestamptz :recorded_at, null: false, default: -> { "clock_timestamp()" }
    end
    add_index :collection_job_failures, [:tenant_id, :job_id, :recorded_at],
      name: "tenant_collection_job_failure_history"
    add_check_constraint :collection_job_failures,
      "code IN ('source_unavailable', 'invalid_source', 'interrupted', 'processing_failed')",
      name: "collection_job_failure_code"

    execute <<~SQL
      ALTER TABLE public.collection_communication_links
        ADD CONSTRAINT collection_link_communication_same_tenant FOREIGN KEY (tenant_id, communication_id)
          REFERENCES public.collection_communications (tenant_id, id),
        ADD CONSTRAINT collection_link_job_same_tenant FOREIGN KEY (tenant_id, job_id)
          REFERENCES public.collection_jobs (tenant_id, id);
      ALTER TABLE public.collection_job_results
        ADD CONSTRAINT collection_result_job_same_tenant FOREIGN KEY (tenant_id, job_id)
          REFERENCES public.collection_jobs (tenant_id, id);
      ALTER TABLE public.collection_job_failures
        ADD CONSTRAINT collection_failure_job_same_tenant FOREIGN KEY (tenant_id, job_id)
          REFERENCES public.collection_jobs (tenant_id, id);

      -- Only migration-owned definers may read a job without a human session.
      -- Selection returns its ID and lease proof; tenant data requires that proof.
      CREATE POLICY processor_owner_read ON public.collection_jobs
        FOR SELECT TO advocacia_migrator USING (true);
      CREATE POLICY processor_owner_read ON public.collection_runs
        FOR SELECT TO advocacia_migrator USING (true);
    SQL

    %w[collection_communications collection_communication_links collection_job_results collection_job_failures].each do |table|
      execute <<~SQL
        ALTER TABLE public.#{table} ENABLE ROW LEVEL SECURITY;
        ALTER TABLE public.#{table} FORCE ROW LEVEL SECURITY;
        CREATE POLICY tenant_isolation ON public.#{table}
          FOR SELECT TO advocacia_runtime
          USING (tenant_id = (SELECT app_private.current_tenant_id()));
        CREATE POLICY processor_owner_read ON public.#{table}
          FOR SELECT TO advocacia_migrator USING (true);
        CREATE POLICY processor_owner_insert ON public.#{table}
          FOR INSERT TO advocacia_migrator WITH CHECK (true);
        REVOKE ALL ON public.#{table} FROM PUBLIC, advocacia_runtime, advocacia_despachante, advocacia_processador;
        GRANT SELECT ON public.#{table} TO advocacia_runtime;
      SQL
    end

    execute <<~SQL
      CREATE FUNCTION app_private.processor_job(p_job_id uuid, p_token text)
      RETURNS jsonb
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE
        execution public.collection_job_executions%ROWTYPE;
        job_data jsonb;
      BEGIN
        SELECT stored.* INTO execution FROM public.collection_job_executions AS stored
          WHERE stored.job_id = p_job_id FOR UPDATE;
        IF NOT FOUND OR p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$'
          OR execution.claim_digest IS NULL OR execution.lease_expires_at IS NULL
          OR execution.claim_digest <> encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
          OR execution.lease_expires_at <= clock_timestamp() THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        SELECT jsonb_build_object(
          'job_id', job.id, 'run_id', job.run_id, 'tenant_id', job.tenant_id,
          'collection_date', run.collection_date, 'entity_type', job.entity_type,
          'entity_id', job.entity_id, 'source', job.source, 'court', job.court,
          'medium', job.medium, 'criteria', job.criteria, 'state', execution.state,
          'phase', execution.phase, 'caderno_attempts', execution.caderno_attempts,
          'fallback_attempts', execution.fallback_attempts,
          'attempt_in_flight', execution.attempt_in_flight,
          'attempt_started_at', execution.attempt_started_at, 'next_attempt_at', execution.next_attempt_at)
          INTO job_data
          FROM public.collection_jobs AS job
          JOIN public.collection_runs AS run ON run.id = job.run_id
          WHERE job.id = execution.job_id AND job.tenant_id = execution.tenant_id;
        IF NOT FOUND THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        RETURN job_data;
      END $fn$;

      CREATE FUNCTION app_private.processor_release(p_job_id uuid, p_token text)
      RETURNS void
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE job_data jsonb;
      BEGIN
        job_data := app_private.processor_job(p_job_id, p_token);
        IF job_data->>'state' <> 'running'
          OR (job_data->>'attempt_in_flight')::boolean IS TRUE
          OR job_data->>'next_attempt_at' IS NULL THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        UPDATE public.collection_job_executions SET claim_digest = NULL, lease_expires_at = NULL,
          updated_at = clock_timestamp() WHERE job_id = p_job_id;
      END $fn$;

      CREATE FUNCTION app_private.processor_attempt_begin(p_job_id uuid, p_token text, p_limit integer)
      RETURNS jsonb
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE
        job_data jsonb;
        execution public.collection_job_executions%ROWTYPE;
      BEGIN
        job_data := app_private.processor_job(p_job_id, p_token);
        IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 3 THEN
          RAISE EXCEPTION 'Invalid processor configuration' USING ERRCODE = '22023';
        END IF;
        SELECT stored.* INTO execution FROM public.collection_job_executions AS stored WHERE stored.job_id = p_job_id;
        IF execution.state <> 'running' OR execution.attempt_in_flight
          OR (job_data->>'collection_date')::date <> (clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date
          OR execution.next_attempt_at > clock_timestamp()
          OR (execution.phase = 'caderno' AND execution.caderno_attempts >= p_limit)
          OR (execution.phase = 'fallback' AND execution.fallback_attempts >= p_limit) THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        UPDATE public.collection_job_executions SET
          caderno_attempts = caderno_attempts + CASE WHEN phase = 'caderno' THEN 1 ELSE 0 END,
          fallback_attempts = fallback_attempts + CASE WHEN phase = 'fallback' THEN 1 ELSE 0 END,
          attempt_in_flight = true, attempt_started_at = clock_timestamp(),
          next_attempt_at = NULL, updated_at = clock_timestamp()
          WHERE job_id = p_job_id;
        RETURN (app_private.processor_job(p_job_id, p_token)
          - ARRAY['criteria', 'tenant_id', 'entity_type', 'entity_id', 'court', 'medium', 'source', 'run_id', 'collection_date'])
          || jsonb_build_object('exhausted', false);
      END $fn$;
      CREATE FUNCTION app_private.processor_defer(p_job_id uuid, p_token text, p_seconds integer)
      RETURNS timestamptz
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE job_data jsonb; deadline timestamptz;
      BEGIN
        job_data := app_private.processor_job(p_job_id, p_token);
        IF p_seconds IS NULL OR p_seconds < 0 THEN
          RAISE EXCEPTION 'Invalid processor configuration' USING ERRCODE = '22023';
        END IF;
        IF job_data->>'state' <> 'running' OR (job_data->>'attempt_in_flight')::boolean IS NOT TRUE THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        UPDATE public.collection_job_executions SET
          next_attempt_at = GREATEST(next_attempt_at, clock_timestamp() + make_interval(secs => p_seconds)),
          updated_at = clock_timestamp() WHERE job_id = p_job_id RETURNING next_attempt_at INTO deadline;
        RETURN deadline;
      END $fn$;


      CREATE FUNCTION app_private.processor_attempt_failed(p_job_id uuid, p_token text, p_retry_after integer,
        p_limit integer, p_backoff_1 integer, p_backoff_2 integer)
      RETURNS jsonb
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE
        job_data jsonb;
        execution public.collection_job_executions%ROWTYPE;
        attempts integer;
        delay_seconds integer;
        exhausted boolean;
      BEGIN
        job_data := app_private.processor_job(p_job_id, p_token);
        IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 3
          OR p_backoff_1 IS NULL OR p_backoff_1 <= 0 OR p_backoff_2 IS NULL OR p_backoff_2 <= 0
          OR p_retry_after < 0 THEN
          RAISE EXCEPTION 'Invalid processor configuration' USING ERRCODE = '22023';
        END IF;
        SELECT stored.* INTO execution FROM public.collection_job_executions AS stored WHERE stored.job_id = p_job_id;
        IF execution.state <> 'running' OR NOT execution.attempt_in_flight THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        attempts := CASE WHEN execution.phase = 'caderno'
          THEN execution.caderno_attempts ELSE execution.fallback_attempts END;
        exhausted := execution.phase = 'fallback' AND attempts >= p_limit;
        delay_seconds := GREATEST(COALESCE(p_retry_after, 0), CASE
          WHEN attempts >= p_limit THEN 0
          WHEN attempts = 1 THEN p_backoff_1 ELSE p_backoff_2 END);
        -- Unknown in-flight outcomes already consumed an attempt. Their failure
        -- time is unknown: start the required wait when failure is acknowledged.
        UPDATE public.collection_job_executions SET
          phase = CASE WHEN phase = 'caderno' AND attempts >= p_limit THEN 'fallback' ELSE phase END,
          attempt_in_flight = false,
          next_attempt_at = GREATEST(next_attempt_at, clock_timestamp() + make_interval(secs => delay_seconds)),
          updated_at = clock_timestamp() WHERE job_id = p_job_id;
        RETURN (app_private.processor_job(p_job_id, p_token)
          - ARRAY['criteria', 'tenant_id', 'entity_type', 'entity_id', 'court', 'medium', 'source', 'run_id', 'collection_date'])
          || jsonb_build_object('exhausted', exhausted);
      END $fn$;

      CREATE FUNCTION app_private.processor_commit(p_job_id uuid, p_token text, p_source_path text, p_items jsonb)
      RETURNS jsonb
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE
        job_data jsonb;
        trusted_tenant uuid;
        item jsonb;
        v_source_id numeric;
        v_source_hash text;
        v_identity_digest bytea;
        v_communication_id uuid;
        matched_count bigint;
        pending_count bigint;
      BEGIN
        job_data := app_private.processor_job(p_job_id, p_token);
        IF job_data->>'state' <> 'running'
          OR (job_data->>'collection_date')::date <> (clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date
          OR current_setting('transaction_isolation') <> 'read committed' THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        IF p_source_path IS NULL OR p_source_path NOT IN ('caderno', 'fallback')
          OR p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
          RAISE EXCEPTION 'Invalid processor result' USING ERRCODE = '22023';
        END IF;
        IF (job_data->>'attempt_in_flight')::boolean IS NOT TRUE OR job_data->>'phase' <> p_source_path THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_items) AS supplied(item)
          WHERE jsonb_typeof(supplied.item) <> 'object') THEN
          RAISE EXCEPTION 'Invalid processor result' USING ERRCODE = '22023';
        END IF;
        trusted_tenant := (job_data->>'tenant_id')::uuid;
        -- Serialize the short persistence phase for this tenant, not the source
        -- requests. A lock-hash collision only serializes unrelated tenants.
        -- READ COMMITTED makes the candidate SELECT see the previous commit.
        -- https://www.postgresql.org/docs/18/functions-admin.html#FUNCTIONS-ADVISORY-LOCKS
        PERFORM pg_advisory_xact_lock(hashtextextended('processor:' || trusted_tenant::text, 0));
        FOR item IN SELECT supplied.item FROM jsonb_array_elements(p_items) AS supplied(item) LOOP
          v_source_id := NULL;
          v_source_hash := NULL;
          v_identity_digest := NULL;
          v_communication_id := NULL;
          -- Check JSON types before casting. Numeric has no declared precision
          -- or scale; bigint/float casts must not round or truncate source IDs.
          IF jsonb_typeof(item->'id') = 'number' AND jsonb_typeof(item->'hash') = 'string' THEN
            v_source_id := (item->>'id')::numeric;
            IF v_source_id > 0 AND v_source_id = trunc(v_source_id) AND item->>'hash' <> '' THEN
              v_source_id := trim_scale(v_source_id);
              v_source_hash := item->>'hash';
              v_identity_digest := sha256(convert_to(jsonb_build_array(v_source_id, v_source_hash)::text, 'UTF8'));
              SELECT stored.id INTO v_communication_id FROM public.collection_communications AS stored
                WHERE stored.tenant_id = trusted_tenant AND stored.source = 'DJEN'
                  AND stored.identity_status = 'complete' AND stored.identity_digest = v_identity_digest
                  AND stored.source_id = v_source_id AND stored.source_hash COLLATE "C" = v_source_hash COLLATE "C";
            ELSE
              v_source_id := NULL;
            END IF;
          END IF;
          IF v_communication_id IS NULL THEN
            INSERT INTO public.collection_communications
              (tenant_id, source, source_id, source_hash, identity_digest, identity_status, warning, payload)
              VALUES (trusted_tenant, 'DJEN', v_source_id, v_source_hash, v_identity_digest,
                CASE WHEN v_identity_digest IS NULL THEN 'pending' ELSE 'complete' END,
                CASE WHEN v_identity_digest IS NULL THEN 'possible_duplicate' END, item)
              RETURNING id INTO v_communication_id;
          END IF;
          INSERT INTO public.collection_communication_links (tenant_id, communication_id, job_id)
            VALUES (trusted_tenant, v_communication_id, p_job_id) ON CONFLICT (job_id, communication_id) DO NOTHING;
        END LOOP;
        SELECT count(*), count(*) FILTER (WHERE communication.identity_status = 'pending')
          INTO matched_count, pending_count FROM public.collection_communication_links AS link
          JOIN public.collection_communications AS communication
            ON communication.id = link.communication_id AND communication.tenant_id = link.tenant_id
          WHERE link.job_id = p_job_id AND link.tenant_id = trusted_tenant;
        INSERT INTO public.collection_job_results
          (job_id, tenant_id, source_path, matched_count, pending_identity_count)
          VALUES (p_job_id, trusted_tenant, p_source_path, matched_count, pending_count);
        UPDATE public.collection_job_executions SET attempt_in_flight = false,
          next_attempt_at = NULL, updated_at = clock_timestamp() WHERE job_id = p_job_id;
        -- Recheck both the date and lease after advisory-lock waits and inserts.
        -- A changed date must roll back all partial publications and results.
        IF (SELECT run.collection_date FROM public.collection_jobs AS job
          JOIN public.collection_runs AS run ON run.id = job.run_id WHERE job.id = p_job_id)
          <> (clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        PERFORM app_private.processor_finish(p_job_id, p_token);
        RETURN jsonb_build_object('state', 'succeeded', 'source_path', p_source_path,
          'matched_count', matched_count, 'pending_identity_count', pending_count);
      END $fn$;

      CREATE FUNCTION app_private.processor_record_failure(p_job_id uuid, p_token text, p_code text)
      RETURNS jsonb
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE
        execution public.collection_job_executions%ROWTYPE;
        safe_code text;
      BEGIN
        SELECT stored.* INTO execution FROM public.collection_job_executions AS stored
          WHERE stored.job_id = p_job_id FOR UPDATE;
        IF NOT FOUND OR p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$'
          OR execution.claim_digest IS NULL OR execution.lease_expires_at IS NULL
          OR execution.claim_digest <> encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
          OR execution.lease_expires_at <= clock_timestamp() OR execution.state NOT IN ('pending', 'running') THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        safe_code := CASE WHEN p_code IN ('source_unavailable', 'invalid_source', 'interrupted', 'processing_failed')
          THEN p_code ELSE 'processing_failed' END;
        INSERT INTO public.collection_job_failures (job_id, tenant_id, code)
          VALUES (execution.job_id, execution.tenant_id, safe_code);
        PERFORM app_private.processor_fail(p_job_id, p_token);
        RETURN jsonb_build_object('state', 'failed', 'code', safe_code);
      END $fn$;

      REVOKE ALL ON FUNCTION app_private.processor_job(uuid,text),
        app_private.processor_commit(uuid,text,text,jsonb), app_private.processor_record_failure(uuid,text,text),
        app_private.processor_attempt_begin(uuid,text,integer),
        app_private.processor_attempt_failed(uuid,text,integer,integer,integer,integer),
        app_private.processor_defer(uuid,text,integer), app_private.processor_release(uuid,text)
        FROM PUBLIC, advocacia_runtime, advocacia_despachante, advocacia_processador;
      GRANT EXECUTE ON FUNCTION app_private.processor_job(uuid,text),
        app_private.processor_commit(uuid,text,text,jsonb), app_private.processor_record_failure(uuid,text,text),
        app_private.processor_attempt_begin(uuid,text,integer),
        app_private.processor_attempt_failed(uuid,text,integer,integer,integer,integer),
        app_private.processor_defer(uuid,text,integer), app_private.processor_release(uuid,text)
        TO advocacia_processador;

      -- SECURITY INVOKER is intentional: every source row is protected by the
      -- authenticated runtime's forced RLS, including all aggregations.
      CREATE FUNCTION app_private.collection_court_states(p_run_id uuid)
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
          WHERE job.run_id = p_run_id
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
      REVOKE ALL ON FUNCTION app_private.collection_court_states(uuid)
        FROM PUBLIC, advocacia_runtime, advocacia_despachante, advocacia_processador;
      GRANT EXECUTE ON FUNCTION app_private.collection_court_states(uuid) TO advocacia_runtime;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "The initial escrevente schema cannot be rolled back"
  end
end
