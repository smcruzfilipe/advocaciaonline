class IsolateStfProcessing < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION app_private.require_djen_job(p_job_id uuid) RETURNS void
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM public.collection_jobs WHERE id = p_job_id AND source = 'DJEN') THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
      END $fn$;
      REVOKE ALL ON FUNCTION app_private.require_djen_job(uuid)
        FROM PUBLIC, advocacia_runtime, advocacia_despachante, advocacia_processador;

      CREATE OR REPLACE FUNCTION app_private.processor_claim(p_job_id uuid)
      RETURNS TABLE(token text, expires_at timestamptz, state text)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE execution public.collection_job_executions%ROWTYPE;
      BEGIN
        PERFORM app_private.require_djen_job(p_job_id);
        SELECT stored.* INTO execution FROM public.collection_job_executions AS stored
          WHERE stored.job_id = p_job_id FOR UPDATE;
        IF NOT FOUND
          OR (execution.claim_digest IS NOT NULL AND execution.lease_expires_at > clock_timestamp()) THEN
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

      CREATE OR REPLACE FUNCTION app_private.processor_next(p_limit integer)
      RETURNS TABLE(job_id uuid, token text, state text)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE next_job_id uuid;
      BEGIN
        IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 3 THEN
          RAISE EXCEPTION 'Invalid processor configuration' USING ERRCODE = '22023';
        END IF;
        SELECT execution.job_id INTO next_job_id
          FROM public.collection_job_executions AS execution
          JOIN public.collection_jobs AS job
            ON job.id = execution.job_id AND job.tenant_id = execution.tenant_id
          JOIN public.collection_runs AS run ON run.id = job.run_id
          WHERE job.source = 'DJEN' AND run.status = 'planned'
            AND run.collection_date <= (clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date
            AND execution.state IN ('pending', 'running')
            AND (execution.claim_digest IS NULL OR execution.lease_expires_at <= clock_timestamp())
            AND (run.collection_date < (clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date
              OR (execution.phase = 'fallback' AND execution.fallback_attempts >= p_limit)
              OR execution.next_attempt_at IS NULL OR execution.next_attempt_at <= clock_timestamp())
            AND (run.collection_date < (clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date
              OR (execution.phase = 'fallback' AND execution.fallback_attempts >= p_limit) OR NOT EXISTS (
              SELECT 1 FROM public.collection_job_executions AS other
              JOIN public.collection_jobs AS other_job ON other_job.id = other.job_id
              JOIN public.collection_runs AS other_run ON other_run.id = other_job.run_id
              WHERE other_run.collection_date = run.collection_date
                AND other_job.court = job.court AND other_job.medium = job.medium
                AND CASE WHEN execution.phase = 'caderno' THEN other.caderno_retry_after
                  ELSE other.fallback_retry_after END > clock_timestamp()
            ))
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

      CREATE OR REPLACE FUNCTION app_private.processor_renew(p_job_id uuid, p_token text)
      RETURNS TABLE(expires_at timestamptz)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE execution public.collection_job_executions%ROWTYPE;
      BEGIN
        PERFORM app_private.require_djen_job(p_job_id);
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

      CREATE OR REPLACE FUNCTION app_private.processor_start(p_job_id uuid, p_token text)
      RETURNS TABLE(id uuid, recorded_at timestamptz)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE execution public.collection_job_executions%ROWTYPE;
      BEGIN
        PERFORM app_private.require_djen_job(p_job_id);
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

      CREATE OR REPLACE FUNCTION app_private.processor_finish(p_job_id uuid, p_token text)
      RETURNS TABLE(id uuid, recorded_at timestamptz)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE execution public.collection_job_executions%ROWTYPE;
      BEGIN
        PERFORM app_private.require_djen_job(p_job_id);
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

      CREATE OR REPLACE FUNCTION app_private.processor_fail(p_job_id uuid, p_token text)
      RETURNS TABLE(state text)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE execution public.collection_job_executions%ROWTYPE;
      BEGIN
        PERFORM app_private.require_djen_job(p_job_id);
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

      CREATE OR REPLACE FUNCTION app_private.processor_job(p_job_id uuid, p_token text)
      RETURNS jsonb
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE
        execution public.collection_job_executions%ROWTYPE;
        job_data jsonb;
      BEGIN
        PERFORM app_private.require_djen_job(p_job_id);
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

      CREATE OR REPLACE FUNCTION app_private.processor_record_failure(p_job_id uuid, p_token text, p_code text)
      RETURNS jsonb
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE
        execution public.collection_job_executions%ROWTYPE;
        safe_code text;
      BEGIN
        PERFORM app_private.require_djen_job(p_job_id);
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
    SQL

    execute <<~SQL
      CREATE FUNCTION app_private.stf_processor_claim_available(p_job_id uuid)
      RETURNS TABLE(token text, expires_at timestamptz, state text)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE execution public.collection_job_executions%ROWTYPE;
      BEGIN
        SELECT stored.* INTO execution
          FROM public.collection_job_executions stored
          JOIN public.collection_jobs job ON job.id = stored.job_id AND job.tenant_id = stored.tenant_id
          JOIN public.collection_runs run ON run.id = job.run_id
          WHERE stored.job_id = p_job_id AND job.source = 'STF'
            AND run.collection_date <= (clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date
          FOR UPDATE OF stored;
        IF NOT FOUND OR (execution.claim_digest IS NOT NULL AND execution.lease_expires_at > clock_timestamp()) THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        token := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
        expires_at := clock_timestamp() + interval '15 minutes';
        state := execution.state;
        UPDATE public.collection_job_executions SET
          claim_digest = encode(sha256(convert_to(token, 'UTF8')), 'hex'),
          lease_expires_at = expires_at, updated_at = clock_timestamp()
          WHERE job_id = execution.job_id;
        RETURN NEXT;
      END $fn$;

      CREATE FUNCTION app_private.stf_processor_next()
      RETURNS TABLE(job_id uuid, token text, state text)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE next_job_id uuid;
      BEGIN
        SELECT execution.job_id INTO next_job_id
          FROM public.collection_job_executions execution
          JOIN public.collection_jobs job ON job.id = execution.job_id AND job.tenant_id = execution.tenant_id
          JOIN public.collection_runs run ON run.id = job.run_id
          WHERE job.source = 'STF' AND run.status = 'planned'
            AND run.collection_date <= (clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date
            AND execution.state IN ('pending', 'running')
            AND (execution.claim_digest IS NULL OR execution.lease_expires_at <= clock_timestamp())
          ORDER BY run.collection_date, run.slot, execution.job_id
          LIMIT 1 FOR UPDATE OF execution SKIP LOCKED;
        IF NOT FOUND THEN RETURN; END IF;
        RETURN QUERY SELECT next_job_id, claim.token, claim.state
          FROM app_private.stf_processor_claim_available(next_job_id) claim;
      END $fn$;

      CREATE FUNCTION app_private.stf_processor_job(p_job_id uuid, p_token text) RETURNS jsonb
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE execution public.collection_job_executions%ROWTYPE; job_data jsonb;
      BEGIN
        SELECT stored.* INTO execution FROM public.collection_job_executions stored
          JOIN public.collection_jobs job ON job.id = stored.job_id AND job.tenant_id = stored.tenant_id
          WHERE stored.job_id = p_job_id AND job.source = 'STF' FOR UPDATE OF stored;
        IF NOT FOUND OR p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$'
          OR execution.claim_digest IS NULL OR execution.lease_expires_at IS NULL
          OR execution.claim_digest <> encode(sha256(convert_to(p_token, 'UTF8')), 'hex')
          OR execution.lease_expires_at <= clock_timestamp() THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        SELECT jsonb_build_object('job_id', job.id, 'run_id', job.run_id, 'tenant_id', job.tenant_id,
          'collection_date', run.collection_date, 'entity_type', job.entity_type, 'entity_id', job.entity_id,
          'source', job.source, 'court', job.court, 'medium', job.medium, 'criteria', job.criteria,
          'state', execution.state) INTO job_data
          FROM public.collection_jobs job JOIN public.collection_runs run ON run.id = job.run_id
          WHERE job.id = execution.job_id AND job.tenant_id = execution.tenant_id;
        RETURN job_data;
      END $fn$;

      CREATE FUNCTION app_private.stf_processor_renew(p_job_id uuid, p_token text)
      RETURNS TABLE(expires_at timestamptz)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      BEGIN
        PERFORM app_private.stf_processor_job(p_job_id, p_token);
        expires_at := clock_timestamp() + interval '15 minutes';
        UPDATE public.collection_job_executions SET lease_expires_at = expires_at, updated_at = clock_timestamp()
          WHERE job_id = p_job_id;
        RETURN NEXT;
      END $fn$;

      CREATE FUNCTION app_private.stf_processor_start(p_job_id uuid, p_token text)
      RETURNS TABLE(id uuid, recorded_at timestamptz)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE job_data jsonb;
      BEGIN
        job_data := app_private.stf_processor_job(p_job_id, p_token);
        IF job_data->>'state' NOT IN ('pending', 'running', 'succeeded') THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        INSERT INTO public.collection_events (job_id, tenant_id, event_type)
          VALUES (p_job_id, (job_data->>'tenant_id')::uuid, 'started')
          ON CONFLICT (job_id, event_type) DO NOTHING;
        UPDATE public.collection_job_executions SET state = 'running', updated_at = clock_timestamp()
          WHERE job_id = p_job_id AND state = 'pending';
        RETURN QUERY SELECT event.id, event.recorded_at FROM public.collection_events event
          WHERE event.job_id = p_job_id AND event.event_type = 'started';
      END $fn$;

      CREATE FUNCTION app_private.stf_processor_commit(p_job_id uuid, p_token text, p_processes jsonb)
      RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE
        job_data jsonb; trusted_tenant uuid; trusted_run uuid; process jsonb; item jsonb;
        incident numeric; semantic_items jsonb; saved_items jsonb; capture_id uuid;
        ordinal bigint; matched bigint; eligible bigint;
        result_row public.collection_job_results%ROWTYPE;
      BEGIN
        job_data := app_private.stf_processor_job(p_job_id, p_token);
        IF job_data->>'state' = 'succeeded' THEN
          SELECT * INTO result_row FROM public.collection_job_results WHERE job_id = p_job_id;
          IF NOT FOUND OR result_row.source_path <> 'andamentos' THEN
            RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
          END IF;
          RETURN jsonb_build_object('state', 'succeeded', 'source_path', result_row.source_path,
            'matched_count', result_row.matched_count, 'pending_identity_count', result_row.pending_identity_count,
            'eligible_process_count', result_row.eligible_process_count);
        END IF;
        IF job_data->>'state' <> 'running'
          OR (job_data->>'collection_date')::date <> (clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date
          OR current_setting('transaction_isolation') <> 'read committed' THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        IF p_processes IS NULL OR jsonb_typeof(p_processes) <> 'array' THEN
          RAISE EXCEPTION 'Invalid processor result' USING ERRCODE = '22023';
        END IF;
        IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_processes) supplied(process)
          WHERE jsonb_typeof(supplied.process) IS DISTINCT FROM 'object'
            OR jsonb_typeof(supplied.process->'incidente') IS DISTINCT FROM 'number'
            OR jsonb_typeof(supplied.process->'items') IS DISTINCT FROM 'array') THEN
          RAISE EXCEPTION 'Invalid processor result' USING ERRCODE = '22023';
        END IF;
        IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_processes) supplied(process)
          WHERE (supplied.process->>'incidente')::numeric <= 0
            OR (supplied.process->>'incidente')::numeric <> trunc((supplied.process->>'incidente')::numeric))
          OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_processes) supplied(process)
            GROUP BY (supplied.process->>'incidente')::numeric HAVING count(*) > 1)
          OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_processes) supplied(process),
            LATERAL jsonb_array_elements(supplied.process->'items') movement(item)
            WHERE jsonb_typeof(movement.item) IS DISTINCT FROM 'object'
              OR jsonb_typeof(movement.item->'stf') IS DISTINCT FROM 'object') THEN
          RAISE EXCEPTION 'Invalid processor result' USING ERRCODE = '22023';
        END IF;
        trusted_tenant := (job_data->>'tenant_id')::uuid;
        trusted_run := (job_data->>'run_id')::uuid;
        PERFORM pg_advisory_xact_lock(hashtextextended('stf:' || trusted_tenant::text || ':' || trusted_run::text, 0));
        FOR process IN SELECT value FROM jsonb_array_elements(p_processes) LOOP
          incident := (process->>'incidente')::numeric;
          SELECT COALESCE(jsonb_agg(movement.item #- '{stf,capturado_em}' ORDER BY movement.ordinality), '[]'::jsonb)
            INTO semantic_items FROM jsonb_array_elements(process->'items') WITH ORDINALITY movement(item, ordinality);
          INSERT INTO public.stf_captures (tenant_id, run_id, incidente, semantic_items)
            VALUES (trusted_tenant, trusted_run, incident, semantic_items)
            ON CONFLICT (tenant_id, run_id, incidente) DO NOTHING RETURNING id INTO capture_id;
          IF capture_id IS NULL THEN
            SELECT capture.id, capture.semantic_items INTO capture_id, saved_items FROM public.stf_captures capture
              WHERE capture.tenant_id = trusted_tenant AND capture.run_id = trusted_run AND capture.incidente = incident;
            IF saved_items IS DISTINCT FROM semantic_items THEN
              RAISE EXCEPTION 'STF capture differs from previously committed source data' USING ERRCODE = '22023';
            END IF;
          ELSE
            FOR item, ordinal IN SELECT movement.item, movement.ordinality
              FROM jsonb_array_elements(process->'items') WITH ORDINALITY movement(item, ordinality) LOOP
              INSERT INTO public.collection_communications
                (tenant_id, source, identity_status, warning, payload, stf_capture_id, stf_ordinal)
                VALUES (trusted_tenant, 'STF', 'pending', 'possible_duplicate', item, capture_id, ordinal);
            END LOOP;
          END IF;
          INSERT INTO public.collection_communication_links (tenant_id, communication_id, job_id)
            SELECT trusted_tenant, communication.id, p_job_id FROM public.collection_communications communication
            WHERE communication.tenant_id = trusted_tenant AND communication.stf_capture_id = capture_id
            ON CONFLICT (job_id, communication_id) DO NOTHING;
          capture_id := NULL;
        END LOOP;
        SELECT count(*) INTO matched FROM public.collection_communication_links
          WHERE job_id = p_job_id AND tenant_id = trusted_tenant;
        eligible := jsonb_array_length(p_processes);
        INSERT INTO public.collection_job_results
          (job_id, tenant_id, source_path, matched_count, pending_identity_count, eligible_process_count)
          VALUES (p_job_id, trusted_tenant, 'andamentos', matched, matched, eligible);
        IF (job_data->>'collection_date')::date <> (clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        PERFORM app_private.stf_processor_job(p_job_id, p_token);
        INSERT INTO public.collection_events (job_id, tenant_id, event_type)
          VALUES (p_job_id, trusted_tenant, 'completed') ON CONFLICT (job_id, event_type) DO NOTHING;
        UPDATE public.collection_job_executions SET state = 'succeeded', updated_at = clock_timestamp()
          WHERE job_id = p_job_id;
        RETURN jsonb_build_object('state', 'succeeded', 'source_path', 'andamentos',
          'matched_count', matched, 'pending_identity_count', matched, 'eligible_process_count', eligible);
      END $fn$;

      CREATE FUNCTION app_private.stf_processor_record_failure(p_job_id uuid, p_token text, p_code text)
      RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE job_data jsonb; safe_code text;
      BEGIN
        job_data := app_private.stf_processor_job(p_job_id, p_token);
        IF job_data->>'state' NOT IN ('pending', 'running') THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        safe_code := CASE WHEN p_code IN ('source_unavailable', 'invalid_source', 'interrupted', 'processing_failed')
          THEN p_code ELSE 'processing_failed' END;
        IF (job_data->>'collection_date')::date <> (clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date
          AND safe_code <> 'interrupted' THEN
          RAISE EXCEPTION 'Processor operation unavailable' USING ERRCODE = '28000';
        END IF;
        INSERT INTO public.collection_job_failures (job_id, tenant_id, code)
          VALUES (p_job_id, (job_data->>'tenant_id')::uuid, safe_code);
        UPDATE public.collection_job_executions SET state = 'failed', claim_digest = NULL,
          lease_expires_at = NULL, updated_at = clock_timestamp() WHERE job_id = p_job_id;
        RETURN jsonb_build_object('state', 'failed', 'code', safe_code);
      END $fn$;

      REVOKE ALL ON FUNCTION app_private.stf_processor_next(), app_private.stf_processor_claim_available(uuid),
        app_private.stf_processor_job(uuid,text), app_private.stf_processor_renew(uuid,text),
        app_private.stf_processor_start(uuid,text), app_private.stf_processor_commit(uuid,text,jsonb),
        app_private.stf_processor_record_failure(uuid,text,text)
        FROM PUBLIC, advocacia_runtime, advocacia_despachante, advocacia_processador;
      GRANT EXECUTE ON FUNCTION app_private.stf_processor_next(), app_private.stf_processor_claim_available(uuid),
        app_private.stf_processor_job(uuid,text), app_private.stf_processor_renew(uuid,text),
        app_private.stf_processor_start(uuid,text), app_private.stf_processor_commit(uuid,text,jsonb),
        app_private.stf_processor_record_failure(uuid,text,text) TO advocacia_processador;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Processor source isolation protects durable history"
  end
end
