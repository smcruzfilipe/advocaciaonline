class CreateEscrevente < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DO $guard$
      BEGIN
        IF current_user <> 'advocacia_migrator'
          OR EXISTS (SELECT 1 FROM pg_roles WHERE rolname = current_user AND (rolsuper OR rolbypassrls)) THEN
          RAISE EXCEPTION 'Migrations require the non-bypass advocacia_migrator owner';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'advocacia_coletor'
          AND rolcanlogin AND NOT rolsuper AND NOT rolbypassrls AND NOT rolcreaterole
          AND NOT rolcreatedb AND NOT rolreplication AND NOT rolinherit)
          OR EXISTS (SELECT 1 FROM pg_auth_members
            WHERE member = 'advocacia_coletor'::regrole OR roleid = 'advocacia_coletor'::regrole) THEN
          RAISE EXCEPTION 'Provision an isolated, non-bypass collector login first';
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
    end
    add_index :collection_job_executions, [:tenant_id, :state, :job_id], name: "tenant_collection_execution_state"
    add_index :collection_job_executions, :lease_expires_at, where: "claim_digest IS NOT NULL",
      name: "collection_execution_lease_expiry"
    add_check_constraint :collection_job_executions, "state IN ('pending', 'running', 'succeeded', 'failed')",
      name: "collection_execution_state"
    add_check_constraint :collection_job_executions,
      "(claim_digest IS NULL AND lease_expires_at IS NULL) OR (claim_digest IS NOT NULL AND claim_digest ~ '^[0-9a-f]{64}$' AND lease_expires_at IS NOT NULL)",
      name: "collection_execution_claim_pair"

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
      CREATE POLICY collector_owner_read ON public.collection_job_executions
        FOR SELECT TO advocacia_migrator USING (true);
      CREATE POLICY collector_owner_insert ON public.collection_job_executions
        FOR INSERT TO advocacia_migrator WITH CHECK (true);
      CREATE POLICY collector_owner_update ON public.collection_job_executions
        FOR UPDATE TO advocacia_migrator USING (true) WITH CHECK (true);
      REVOKE ALL ON public.collection_job_executions FROM PUBLIC, advocacia_runtime, advocacia_despachante, advocacia_coletor;
      GRANT SELECT (job_id, tenant_id, state, updated_at) ON public.collection_job_executions TO advocacia_runtime;

      ALTER TABLE public.collection_events ENABLE ROW LEVEL SECURITY;
      ALTER TABLE public.collection_events FORCE ROW LEVEL SECURITY;
      CREATE POLICY tenant_isolation ON public.collection_events
        FOR SELECT TO advocacia_runtime
        USING (tenant_id = (SELECT app_private.current_tenant_id()));
      CREATE POLICY collector_owner_read ON public.collection_events
        FOR SELECT TO advocacia_migrator USING (true);
      CREATE POLICY collector_owner_insert ON public.collection_events
        FOR INSERT TO advocacia_migrator WITH CHECK (true);
      REVOKE ALL ON public.collection_events FROM PUBLIC, advocacia_runtime, advocacia_despachante, advocacia_coletor;
      GRANT SELECT ON public.collection_events TO advocacia_runtime;

      -- New jobs get their pending execution row transactionally;
      -- skipped ON CONFLICT rows fire no trigger.

      CREATE FUNCTION app_private.initialize_collection_execution() RETURNS trigger
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      BEGIN
        INSERT INTO public.collection_job_executions (job_id, tenant_id) VALUES (NEW.id, NEW.tenant_id);
        RETURN NULL;
      END $fn$;
      REVOKE ALL ON FUNCTION app_private.initialize_collection_execution()
        FROM PUBLIC, advocacia_runtime, advocacia_despachante, advocacia_coletor;
      CREATE TRIGGER initialize_collection_execution AFTER INSERT ON public.collection_jobs
        FOR EACH ROW EXECUTE FUNCTION app_private.initialize_collection_execution();

      CREATE FUNCTION app_private.collector_claim(p_job_id uuid)
      RETURNS TABLE(token text, expires_at timestamptz, state text)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE execution public.collection_job_executions%ROWTYPE;
      BEGIN
        SELECT stored.* INTO execution FROM public.collection_job_executions AS stored
          WHERE stored.job_id = p_job_id FOR UPDATE;
        IF NOT FOUND
          OR (execution.claim_digest IS NOT NULL AND execution.lease_expires_at > clock_timestamp()) THEN
          RAISE EXCEPTION 'Collector operation unavailable' USING ERRCODE = '28000';
        END IF;
        -- Two independently generated UUID v4 values supply 244 random bits.
        -- Only their SHA-256 digest is persisted; no extension or client secret is required.
        token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
        expires_at := clock_timestamp() + interval '15 minutes';
        -- A lease transfers ownership, not execution state. Succeeded claims
        -- only recover confirmed events; collectors must not repeat collection.
        state := execution.state;
        UPDATE public.collection_job_executions SET
          claim_digest = encode(sha256(convert_to(token, 'UTF8')), 'hex'),
          lease_expires_at = expires_at, updated_at = clock_timestamp()
          WHERE job_id = execution.job_id;
        RETURN NEXT;
      END $fn$;

      CREATE FUNCTION app_private.collector_renew(p_job_id uuid, p_token text)
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
          RAISE EXCEPTION 'Collector operation unavailable' USING ERRCODE = '28000';
        END IF;
        expires_at := clock_timestamp() + interval '15 minutes';
        UPDATE public.collection_job_executions SET lease_expires_at = expires_at, updated_at = clock_timestamp()
          WHERE job_id = execution.job_id;
        RETURN NEXT;
      END $fn$;

      CREATE FUNCTION app_private.collector_start(p_job_id uuid, p_token text)
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
          RAISE EXCEPTION 'Collector operation unavailable' USING ERRCODE = '28000';
        END IF;
        INSERT INTO public.collection_events (job_id, tenant_id, event_type)
          VALUES (execution.job_id, execution.tenant_id, 'started')
          ON CONFLICT (job_id, event_type) DO NOTHING;
        UPDATE public.collection_job_executions SET state = 'running', updated_at = clock_timestamp()
          WHERE job_id = execution.job_id AND state IN ('pending', 'failed');
        RETURN QUERY SELECT event.id, event.recorded_at FROM public.collection_events AS event
          WHERE event.job_id = execution.job_id AND event.event_type = 'started';
      END $fn$;

      CREATE FUNCTION app_private.collector_finish(p_job_id uuid, p_token text)
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
          RAISE EXCEPTION 'Collector operation unavailable' USING ERRCODE = '28000';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM public.collection_events AS event
          WHERE event.job_id = execution.job_id AND event.event_type = 'started') THEN
          RAISE EXCEPTION 'Collector operation unavailable' USING ERRCODE = '28000';
        END IF;
        INSERT INTO public.collection_events (job_id, tenant_id, event_type)
          VALUES (execution.job_id, execution.tenant_id, 'completed')
          ON CONFLICT (job_id, event_type) DO NOTHING;
        UPDATE public.collection_job_executions SET state = 'succeeded', updated_at = clock_timestamp()
          WHERE job_id = execution.job_id AND state = 'running';
        RETURN QUERY SELECT event.id, event.recorded_at FROM public.collection_events AS event
          WHERE event.job_id = execution.job_id AND event.event_type = 'completed';
      END $fn$;

      CREATE FUNCTION app_private.collector_fail(p_job_id uuid, p_token text)
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
          RAISE EXCEPTION 'Collector operation unavailable' USING ERRCODE = '28000';
        END IF;
        UPDATE public.collection_job_executions SET state = 'failed', claim_digest = NULL,
          lease_expires_at = NULL, updated_at = clock_timestamp() WHERE job_id = execution.job_id;
        RETURN QUERY SELECT 'failed'::text;
      END $fn$;

      REVOKE ALL ON FUNCTION app_private.collector_claim(uuid), app_private.collector_renew(uuid,text),
        app_private.collector_start(uuid,text), app_private.collector_finish(uuid,text), app_private.collector_fail(uuid,text)
        FROM PUBLIC, advocacia_runtime, advocacia_despachante, advocacia_coletor;
      GRANT USAGE ON SCHEMA app_private TO advocacia_coletor;
      GRANT EXECUTE ON FUNCTION app_private.collector_claim(uuid), app_private.collector_renew(uuid,text),
        app_private.collector_start(uuid,text), app_private.collector_finish(uuid,text), app_private.collector_fail(uuid,text)
        TO advocacia_coletor;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "The initial escrevente schema cannot be rolled back"
  end
end
