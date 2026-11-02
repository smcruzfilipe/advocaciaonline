class CanonicalizeStfCaptureProvenance < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION app_private.stf_semantic_cnj(p_data jsonb, p_key text)
      RETURNS jsonb LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
        SELECT CASE WHEN jsonb_typeof(p_data->p_key) = 'string'
          AND p_data->>p_key ~ '^([0-9]{20}|[0-9]{7}-[0-9]{2}[.][0-9]{4}[.][0-9][.][0-9]{2}[.][0-9]{4})$'
          THEN jsonb_set(p_data, ARRAY[p_key], to_jsonb(regexp_replace(p_data->>p_key, '[^0-9]', '', 'g')))
          ELSE p_data END
      $fn$;
      REVOKE ALL ON FUNCTION app_private.stf_semantic_cnj(jsonb, text) FROM PUBLIC;

      CREATE FUNCTION app_private.stf_semantic_items(p_items jsonb)
      RETURNS jsonb LANGUAGE sql IMMUTABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
        SELECT COALESCE(jsonb_agg(app_private.stf_semantic_cnj(movement.item #- '{stf,capturado_em}', 'numero_processo')
          ORDER BY movement.ordinality), '[]'::jsonb)
        FROM jsonb_array_elements(p_items) WITH ORDINALITY movement(item, ordinality)
      $fn$;
      REVOKE ALL ON FUNCTION app_private.stf_semantic_items(jsonb) FROM PUBLIC;

      CREATE OR REPLACE FUNCTION app_private.stf_processor_commit(p_job_id uuid, p_token text, p_processes jsonb)
      RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $fn$
      DECLARE
        job_data jsonb; trusted_tenant uuid; trusted_run uuid; process jsonb; item jsonb;
        incident numeric; semantic_items jsonb; saved_items jsonb; v_process_data jsonb; saved_process_data jsonb; capture_id uuid;
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
            OR jsonb_typeof(supplied.process->'items') IS DISTINCT FROM 'array'
            OR (jsonb_typeof(supplied.process->'cnj') IS DISTINCT FROM 'null'
              AND (jsonb_typeof(supplied.process->'cnj') IS DISTINCT FROM 'string'
                OR COALESCE(supplied.process->>'cnj', '') !~ '^([0-9]{20}|[0-9]{7}-[0-9]{2}[.][0-9]{4}[.][0-9][.][0-9]{2}[.][0-9]{4})$'))
            OR jsonb_typeof(supplied.process->'capturado_em') IS DISTINCT FROM 'string'
            OR COALESCE(supplied.process->>'capturado_em', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$'
            OR jsonb_typeof(supplied.process->'classe') IS DISTINCT FROM 'string'
            OR COALESCE(supplied.process->>'classe', '') !~ '[^[:space:]]'
            OR jsonb_typeof(supplied.process->'identificacao') IS DISTINCT FROM 'string'
            OR COALESCE(supplied.process->>'identificacao', '') !~ '[^[:space:]]'
            OR (supplied.process->'em_tramitacao') IS DISTINCT FROM '"Sim"'::jsonb
            OR (supplied.process->'publicidade') IS DISTINCT FROM '"Público"'::jsonb) THEN
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
              OR jsonb_typeof(movement.item->'stf') IS DISTINCT FROM 'object'
              OR (movement.item->'stf'->'incidente') IS DISTINCT FROM (supplied.process->'incidente')
              OR jsonb_typeof(movement.item->'stf'->'data_andamento') IS DISTINCT FROM 'string'
              OR (movement.item->'stf'->>'data_andamento') IS DISTINCT FROM (job_data->>'collection_date')) THEN
          RAISE EXCEPTION 'Invalid processor result' USING ERRCODE = '22023';
        END IF;
        BEGIN
          FOR process IN SELECT value FROM jsonb_array_elements(p_processes) LOOP
            IF ((process->>'capturado_em')::timestamptz AT TIME ZONE 'America/Sao_Paulo')::date
              IS DISTINCT FROM (job_data->>'collection_date')::date THEN
              RAISE EXCEPTION 'Invalid processor result' USING ERRCODE = '22023';
            END IF;
          END LOOP;
        EXCEPTION WHEN data_exception THEN
          RAISE EXCEPTION 'Invalid processor result' USING ERRCODE = '22023';
        END;
        trusted_tenant := (job_data->>'tenant_id')::uuid;
        trusted_run := (job_data->>'run_id')::uuid;
        PERFORM pg_advisory_xact_lock(hashtextextended('stf:' || trusted_tenant::text || ':' || trusted_run::text, 0));
        FOR process IN SELECT value FROM jsonb_array_elements(p_processes) LOOP
          incident := (process->>'incidente')::numeric;
          v_process_data := process - 'items';
          semantic_items := app_private.stf_semantic_items(process->'items');
          INSERT INTO public.stf_captures (tenant_id, run_id, incidente, semantic_items, process_data)
            VALUES (trusted_tenant, trusted_run, incident, semantic_items, v_process_data)
            ON CONFLICT (tenant_id, run_id, incidente) DO NOTHING RETURNING id INTO capture_id;
          IF capture_id IS NULL THEN
            SELECT capture.id, capture.semantic_items, capture.process_data
              INTO capture_id, saved_items, saved_process_data FROM public.stf_captures capture
              WHERE capture.tenant_id = trusted_tenant AND capture.run_id = trusted_run AND capture.incidente = incident;
            IF app_private.stf_semantic_items(saved_items) IS DISTINCT FROM semantic_items
              OR app_private.stf_semantic_cnj(saved_process_data - 'capturado_em', 'cnj')
                IS DISTINCT FROM app_private.stf_semantic_cnj(v_process_data - 'capturado_em', 'cnj') THEN
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
          INSERT INTO public.stf_capture_links (tenant_id, capture_id, job_id)
            VALUES (trusted_tenant, capture_id, p_job_id) ON CONFLICT ON CONSTRAINT stf_capture_link_unique DO NOTHING;
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
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "STF captures are durable collection history"
  end
end
