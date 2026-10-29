class CreateIdentityAndLawyerProfiles < ActiveRecord::Migration[8.1]
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
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'advocacia_despachante'
          AND rolcanlogin AND NOT rolsuper AND NOT rolbypassrls AND NOT rolcreaterole
          AND NOT rolcreatedb AND NOT rolreplication)
          OR EXISTS (SELECT 1 FROM pg_auth_members WHERE member = 'advocacia_despachante'::regrole)
          OR pg_has_role('advocacia_runtime', 'advocacia_despachante', 'MEMBER') THEN
          RAISE EXCEPTION 'Provision an isolated, non-bypass despachante login first';
        END IF;
      END $guard$;
    SQL

    create_table :tenants, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.timestamps
    end
    create_table :lawyers, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.text :full_name, null: false
      t.text :office_name
      t.timestamps
    end
    add_check_constraint :lawyers, "full_name ~ '[^[:space:]]'", name: "lawyer_name_present"
    add_index :lawyers, [:tenant_id, :id], unique: true
    create_table :oab_registrations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :tenant_id, null: false
      t.uuid :lawyer_id, null: false
      t.text :number, null: false, collation: "C"
      t.text :uf, null: false, collation: "C"
      t.boolean :primary, null: false
      t.timestamps
    end
    add_index :oab_registrations, [:tenant_id, :lawyer_id, :number, :uf], unique: true, name: "unique_profile_oab"
    add_index :oab_registrations, [:tenant_id, :lawyer_id], unique: true, where: '"primary"', name: "one_primary_oab"
    add_check_constraint :oab_registrations, "number ~ '[^[:space:]]'", name: "oab_number_present"
    add_check_constraint :oab_registrations, "uf IN ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO')", name: "oab_valid_uf"
    execute <<~SQL
      ALTER TABLE public.oab_registrations ADD CONSTRAINT oab_lawyer_same_tenant
        FOREIGN KEY (tenant_id, lawyer_id) REFERENCES public.lawyers(tenant_id, id);
      CREATE SCHEMA app_private AUTHORIZATION advocacia_migrator;
      REVOKE ALL ON SCHEMA app_private FROM PUBLIC;
      CREATE TABLE app_private.identities (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        google_subject text NOT NULL UNIQUE CHECK (length(google_subject) BETWEEN 1 AND 255),
        verified_email text NOT NULL,
        tenant_id uuid UNIQUE REFERENCES public.tenants(id) DEFERRABLE INITIALLY DEFERRED,
        disabled_at timestamptz,
        created_at timestamptz NOT NULL DEFAULT clock_timestamp()
      );
      CREATE TABLE app_private.sessions (
        session_hash text PRIMARY KEY CHECK (session_hash ~ '^[0-9a-f]{64}$'),
        identity_id uuid NOT NULL REFERENCES app_private.identities(id),
        csrf_token text NOT NULL,
        expires_at timestamptz NOT NULL,
        revoked_at timestamptz,
        created_at timestamptz NOT NULL DEFAULT clock_timestamp()
      );
      CREATE INDEX ON app_private.sessions(identity_id);
      CREATE INDEX ON app_private.sessions(expires_at);
      CREATE TABLE app_private.login_attempts (
        browser_hash text PRIMARY KEY CHECK (browser_hash ~ '^[0-9a-f]{64}$'),
        state_hash text NOT NULL CHECK (state_hash ~ '^[0-9a-f]{64}$'),
        encrypted_payload text NOT NULL,
        expires_at timestamptz NOT NULL
      );
      CREATE INDEX ON app_private.login_attempts(expires_at);
      CREATE TABLE app_private.auth_limits (
        bucket_hash text PRIMARY KEY CHECK (bucket_hash ~ '^[0-9a-f]{64}$'),
        attempts integer NOT NULL,
        expires_at timestamptz NOT NULL
      );

      -- Every definer fixes its search_path and fully qualifies private data.
      -- PUBLIC execute is revoked in this same migration transaction.
      CREATE FUNCTION app_private.start_login(p_browser text, p_state text, p_payload text, p_bucket text)
      RETURNS TABLE(accepted boolean)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE attempts_now integer;
      BEGIN
        DELETE FROM app_private.login_attempts WHERE expires_at <= statement_timestamp();
        DELETE FROM app_private.auth_limits WHERE expires_at <= statement_timestamp();
        DELETE FROM app_private.sessions WHERE expires_at <= statement_timestamp();
        INSERT INTO app_private.auth_limits(bucket_hash, attempts, expires_at)
          VALUES (p_bucket, 1, statement_timestamp() + interval '15 minutes')
          ON CONFLICT (bucket_hash) DO UPDATE SET attempts = app_private.auth_limits.attempts + 1
          RETURNING attempts INTO attempts_now;
        IF attempts_now > 20 THEN RETURN QUERY SELECT false; RETURN; END IF;
        IF length(p_payload) > 16384 THEN RAISE EXCEPTION 'Invalid login payload'; END IF;
        INSERT INTO app_private.login_attempts(browser_hash, state_hash, encrypted_payload, expires_at)
          VALUES (p_browser, p_state, p_payload, statement_timestamp() + interval '10 minutes');
        RETURN QUERY SELECT true;
      END $fn$;

      CREATE FUNCTION app_private.consume_login(p_browser text, p_state text)
      RETURNS TABLE(encrypted_payload text)
      LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
        DELETE FROM app_private.login_attempts AS attempt
          WHERE attempt.browser_hash = p_browser AND attempt.state_hash = p_state
            AND attempt.expires_at > statement_timestamp()
          RETURNING attempt.encrypted_payload
      $fn$;

      -- Only server-verified Google subject/email reach this trusted bootstrap interface.
      -- No email-based account linking and no client identity/tenant parameter exist.
      CREATE FUNCTION app_private.authenticate_google(p_subject text, p_email text, p_hash text, p_csrf text)
      RETURNS TABLE(identity_id uuid)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE identity_row app_private.identities%ROWTYPE;
      BEGIN
        IF p_subject IS NULL OR p_email IS NULL OR p_csrf IS NULL OR length(p_csrf) < 43 THEN
          RAISE EXCEPTION 'Invalid verified identity' USING ERRCODE = '28000';
        END IF;
        INSERT INTO app_private.identities(google_subject, verified_email)
          VALUES (p_subject, p_email)
          ON CONFLICT (google_subject) DO UPDATE SET verified_email = EXCLUDED.verified_email
          RETURNING * INTO identity_row;
        IF identity_row.disabled_at IS NOT NULL THEN
          RAISE EXCEPTION 'Identity unavailable' USING ERRCODE = '28000';
        END IF;
        INSERT INTO app_private.sessions(session_hash, identity_id, csrf_token, expires_at)
          VALUES (p_hash, identity_row.id, p_csrf, statement_timestamp() + interval '12 hours');
        RETURN QUERY SELECT identity_row.id;
      END $fn$;

      CREATE FUNCTION app_private.session_context(p_hash text)
      RETURNS TABLE(identity_id uuid, tenant_id uuid, csrf_token text)
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
        SELECT identity.id, identity.tenant_id, session.csrf_token
          FROM app_private.sessions AS session
          JOIN app_private.identities AS identity ON identity.id = session.identity_id
          WHERE session.session_hash = p_hash AND session.revoked_at IS NULL
            AND session.expires_at > statement_timestamp() AND identity.disabled_at IS NULL
      $fn$;

      CREATE FUNCTION app_private.current_tenant_id() RETURNS uuid
      LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
        SELECT context.tenant_id FROM app_private.session_context(current_setting('app.session_hash', true)) AS context
      $fn$;

      CREATE FUNCTION app_private.claim_tenant(p_hash text)
      RETURNS TABLE(tenant_id uuid, claimed boolean)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE identity_row app_private.identities%ROWTYPE; new_tenant uuid;
      BEGIN
        SELECT identity.* INTO identity_row FROM app_private.identities AS identity
          JOIN app_private.sessions AS session ON session.identity_id = identity.id
          WHERE session.session_hash = p_hash AND session.revoked_at IS NULL
            AND session.expires_at > statement_timestamp() AND identity.disabled_at IS NULL
          FOR UPDATE OF identity;
        IF NOT FOUND THEN RETURN; END IF;
        IF identity_row.tenant_id IS NOT NULL THEN
          RETURN QUERY SELECT identity_row.tenant_id, false; RETURN;
        END IF;
        new_tenant := gen_random_uuid();
        UPDATE app_private.identities SET tenant_id = new_tenant WHERE id = identity_row.id;
        RETURN QUERY SELECT new_tenant, true;
      END $fn$;

      CREATE FUNCTION app_private.revoke_session(p_hash text) RETURNS void
      LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
        UPDATE app_private.sessions SET revoked_at = statement_timestamp() WHERE session_hash = p_hash
      $fn$;

      REVOKE ALL ON ALL TABLES IN SCHEMA app_private FROM PUBLIC, advocacia_runtime;
      REVOKE ALL ON ALL FUNCTIONS IN SCHEMA app_private FROM PUBLIC;
      ALTER DEFAULT PRIVILEGES IN SCHEMA app_private REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
      GRANT USAGE ON SCHEMA app_private TO advocacia_runtime;
      GRANT EXECUTE ON FUNCTION app_private.start_login(text,text,text,text),
        app_private.consume_login(text,text), app_private.authenticate_google(text,text,text,text),
        app_private.session_context(text), app_private.current_tenant_id(),
        app_private.claim_tenant(text), app_private.revoke_session(text) TO advocacia_runtime;

      CREATE FUNCTION app_private.require_primary_oab() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public, pg_temp AS $fn$
      BEGIN
        IF (SELECT count(*) FROM public.oab_registrations WHERE lawyer_id = NEW.id
          AND tenant_id = NEW.tenant_id AND "primary") <> 1 THEN
          RAISE EXCEPTION 'A lawyer requires exactly one primary OAB' USING ERRCODE = '23514';
        END IF;
        RETURN NULL;
      END $fn$;
      REVOKE ALL ON FUNCTION app_private.require_primary_oab() FROM PUBLIC;
      CREATE CONSTRAINT TRIGGER lawyer_requires_primary_oab AFTER INSERT ON public.lawyers
        DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION app_private.require_primary_oab();
    SQL

    { tenants: "id", lawyers: "tenant_id", oab_registrations: "tenant_id" }.each do |table, column|
      execute <<~SQL
        ALTER TABLE public.#{table} ENABLE ROW LEVEL SECURITY;
        ALTER TABLE public.#{table} FORCE ROW LEVEL SECURITY;
        CREATE POLICY tenant_isolation ON public.#{table}
          TO advocacia_runtime, advocacia_migrator
          USING (#{column} = (SELECT app_private.current_tenant_id()))
          WITH CHECK (#{column} = (SELECT app_private.current_tenant_id()));
        CREATE POLICY collection_despachante_read ON public.#{table}
          FOR SELECT TO advocacia_despachante USING (true);
        REVOKE ALL ON public.#{table} FROM PUBLIC, advocacia_runtime, advocacia_despachante;
        GRANT SELECT, INSERT ON public.#{table} TO advocacia_runtime;
        GRANT SELECT ON public.#{table} TO advocacia_despachante;
      SQL
    end
    execute "GRANT SELECT ON public.schema_migrations TO advocacia_runtime"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
