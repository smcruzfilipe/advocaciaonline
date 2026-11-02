class CreatePlatformAdministration < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE app_private.platform_administrator (
        identity_id uuid PRIMARY KEY REFERENCES app_private.identities(id),
        singleton boolean NOT NULL DEFAULT true UNIQUE CHECK (singleton)
      );
      CREATE TABLE app_private.platform_recovery_codes (
        identity_id uuid NOT NULL REFERENCES app_private.platform_administrator(identity_id),
        code_hash text NOT NULL CHECK (code_hash ~ '^[0-9a-f]{64}$'),
        PRIMARY KEY (identity_id, code_hash)
      );
      CREATE TABLE app_private.platform_recovery_challenges (
        identity_id uuid PRIMARY KEY REFERENCES app_private.platform_administrator(identity_id),
        challenge_hash text NOT NULL UNIQUE CHECK (challenge_hash ~ '^[0-9a-f]{64}$'),
        password_hash text NOT NULL,
        totp_secret text NOT NULL,
        expires_at timestamptz NOT NULL
      );
      REVOKE ALL ON app_private.platform_administrator, app_private.platform_recovery_codes,
        app_private.platform_recovery_challenges FROM PUBLIC, advocacia_runtime;

      CREATE FUNCTION app_private.platform_admin_for_session(p_session text)
      RETURNS TABLE(authorized boolean) LANGUAGE sql SECURITY DEFINER
      SET search_path = pg_catalog, app_private, pg_temp AS $fn$
        SELECT EXISTS (
          SELECT 1 FROM app_private.sessions s
          JOIN app_private.identities i ON i.id = s.identity_id
          JOIN app_private.password_credentials c ON c.identity_id = i.id
          JOIN app_private.platform_administrator a ON a.identity_id = i.id
          WHERE s.session_hash = p_session AND s.revoked_at IS NULL AND s.expires_at > clock_timestamp()
            AND i.disabled_at IS NULL AND c.totp_confirmed
            AND NOT EXISTS (SELECT 1 FROM app_private.platform_recovery_challenges r WHERE r.identity_id = i.id)
        )
      $fn$;

      CREATE FUNCTION app_private.platform_recovery_begin(p_email text, p_password text, p_code text, p_challenge text, p_secret text)
      RETURNS TABLE(started boolean) LANGUAGE plpgsql SECURITY DEFINER
      SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE ident uuid;
      BEGIN
        SELECT c.identity_id INTO ident FROM app_private.password_credentials c
          JOIN app_private.identities i ON i.id = c.identity_id
          JOIN app_private.platform_administrator a ON a.identity_id = i.id
          WHERE lower(i.verified_email) = p_email AND i.disabled_at IS NULL
            AND c.password_hash = p_password FOR UPDATE OF c;
        IF ident IS NULL THEN RETURN QUERY SELECT false; RETURN; END IF;
        DELETE FROM app_private.platform_recovery_codes WHERE identity_id = ident AND code_hash = p_code;
        IF NOT FOUND THEN RETURN QUERY SELECT false; RETURN; END IF;
        INSERT INTO app_private.platform_recovery_challenges(identity_id, challenge_hash, password_hash, totp_secret, expires_at)
          VALUES (ident, p_challenge, p_password, p_secret, clock_timestamp() + interval '10 minutes')
          ON CONFLICT (identity_id) DO UPDATE SET challenge_hash = EXCLUDED.challenge_hash,
            password_hash = EXCLUDED.password_hash, totp_secret = EXCLUDED.totp_secret, expires_at = EXCLUDED.expires_at;
        UPDATE app_private.sessions SET revoked_at = clock_timestamp() WHERE identity_id = ident AND revoked_at IS NULL;
        DELETE FROM app_private.password_challenges WHERE identity_id = ident;
        RETURN QUERY SELECT true;
      END $fn$;

      CREATE FUNCTION app_private.platform_recovery_secret(p_challenge text)
      RETURNS TABLE(totp_secret text) LANGUAGE sql SECURITY DEFINER
      SET search_path = pg_catalog, app_private, pg_temp AS $fn$
        SELECT r.totp_secret FROM app_private.platform_recovery_challenges r
        JOIN app_private.password_credentials c ON c.identity_id = r.identity_id AND c.password_hash = r.password_hash
        JOIN app_private.identities i ON i.id = r.identity_id AND i.disabled_at IS NULL
        WHERE r.challenge_hash = p_challenge AND r.expires_at > clock_timestamp()
      $fn$;

      CREATE FUNCTION app_private.platform_recovery_finish(p_challenge text, p_secret text, p_step text, p_codes text)
      RETURNS TABLE(changed boolean) LANGUAGE plpgsql SECURITY DEFINER
      SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE ident uuid; hashes jsonb;
      BEGIN
        SELECT r.identity_id INTO ident FROM app_private.platform_recovery_challenges r WHERE r.challenge_hash = p_challenge;
        IF ident IS NULL THEN RETURN QUERY SELECT false; RETURN; END IF;
        PERFORM 1 FROM app_private.password_credentials c WHERE c.identity_id = ident FOR UPDATE;
        PERFORM 1 FROM app_private.platform_recovery_challenges r
          JOIN app_private.password_credentials c ON c.identity_id = r.identity_id AND c.password_hash = r.password_hash
          JOIN app_private.identities i ON i.id = r.identity_id AND i.disabled_at IS NULL
          WHERE r.identity_id = ident AND r.challenge_hash = p_challenge AND r.totp_secret = p_secret
            AND r.expires_at > clock_timestamp() FOR UPDATE OF r;
        IF NOT FOUND THEN RETURN QUERY SELECT false; RETURN; END IF;
        hashes := p_codes::jsonb;
        IF jsonb_typeof(hashes) <> 'array' OR jsonb_array_length(hashes) = 0 OR EXISTS (
          SELECT 1 FROM jsonb_array_elements(hashes) AS value
          WHERE jsonb_typeof(value) <> 'string' OR (value #>> '{}') !~ '^[0-9a-f]{64}$'
        ) OR (SELECT count(*) <> count(DISTINCT value) FROM jsonb_array_elements_text(hashes) AS value) THEN
          RAISE EXCEPTION 'Invalid recovery codes' USING ERRCODE = '22023';
        END IF;
        UPDATE app_private.password_credentials SET totp_secret = p_secret, totp_confirmed = true,
          last_totp_step = p_step::bigint WHERE identity_id = ident;
        DELETE FROM app_private.platform_recovery_codes WHERE identity_id = ident;
        INSERT INTO app_private.platform_recovery_codes(identity_id, code_hash)
          SELECT ident, value FROM jsonb_array_elements_text(hashes) AS value;
        DELETE FROM app_private.platform_recovery_challenges WHERE identity_id = ident;
        UPDATE app_private.sessions SET revoked_at = clock_timestamp() WHERE identity_id = ident AND revoked_at IS NULL;
        DELETE FROM app_private.password_challenges WHERE identity_id = ident;
        RETURN QUERY SELECT true;
      END $fn$;

      CREATE OR REPLACE FUNCTION app_private.request_password_reset(p_email text, p_token text)
      RETURNS TABLE(accepted boolean) LANGUAGE plpgsql SECURITY DEFINER
      SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE ident uuid;
      BEGIN
        SELECT c.identity_id INTO ident FROM app_private.password_credentials c
          JOIN app_private.identities i ON i.id = c.identity_id
          WHERE lower(i.verified_email) = p_email AND i.disabled_at IS NULL AND
            (c.totp_confirmed OR NOT EXISTS (
              SELECT 1 FROM app_private.platform_administrator a WHERE a.identity_id = c.identity_id
            )) FOR UPDATE OF c;
        IF ident IS NOT NULL THEN
          INSERT INTO app_private.password_resets(identity_id, token_hash, expires_at)
            VALUES (ident, p_token, clock_timestamp() + interval '30 minutes')
            ON CONFLICT (identity_id) DO UPDATE SET token_hash = EXCLUDED.token_hash, expires_at = EXCLUDED.expires_at;
        END IF;
        RETURN QUERY SELECT true;
      END $fn$;

      CREATE OR REPLACE FUNCTION app_private.create_password_challenge(p_identity text, p_challenge text, p_password text)
      RETURNS TABLE(created boolean) LANGUAGE plpgsql SECURITY DEFINER
      SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      BEGIN
        PERFORM 1 FROM app_private.password_credentials c JOIN app_private.identities i ON i.id = c.identity_id
          WHERE c.identity_id = p_identity::uuid AND c.password_hash = p_password AND i.disabled_at IS NULL
          FOR UPDATE OF c;
        IF NOT FOUND THEN RETURN QUERY SELECT false; RETURN; END IF;
        DELETE FROM app_private.platform_recovery_challenges r
          WHERE r.identity_id = p_identity::uuid AND
            (r.expires_at <= clock_timestamp() OR r.password_hash <> p_password);
        IF EXISTS (SELECT 1 FROM app_private.platform_recovery_challenges r WHERE r.identity_id = p_identity::uuid)
          THEN RETURN QUERY SELECT false; RETURN; END IF;
        DELETE FROM app_private.password_challenges WHERE identity_id = p_identity::uuid AND expires_at <= clock_timestamp();
        INSERT INTO app_private.password_challenges(challenge_hash, identity_id, expires_at)
          VALUES (p_challenge, p_identity::uuid, clock_timestamp() + interval '10 minutes');
        RETURN QUERY SELECT true;
      END $fn$;

      CREATE OR REPLACE FUNCTION app_private.finish_password_challenge(p_challenge text, p_step text, p_session text, p_csrf text, p_old text)
      RETURNS TABLE(created boolean) LANGUAGE plpgsql SECURITY DEFINER
      SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE ident uuid; step bigint;
      BEGIN
        step := p_step::bigint;
        SELECT ch.identity_id INTO ident FROM app_private.password_challenges ch WHERE ch.challenge_hash = p_challenge;
        IF ident IS NULL THEN RETURN QUERY SELECT false; RETURN; END IF;
        PERFORM 1 FROM app_private.password_credentials c WHERE c.identity_id = ident FOR UPDATE;
        PERFORM 1 FROM app_private.password_challenges ch JOIN app_private.identities i ON i.id = ch.identity_id
          WHERE ch.challenge_hash = p_challenge AND ch.identity_id = ident
            AND ch.expires_at > clock_timestamp() AND i.disabled_at IS NULL
            AND NOT EXISTS (SELECT 1 FROM app_private.platform_recovery_challenges r WHERE r.identity_id = ident)
          FOR UPDATE OF ch;
        IF NOT FOUND THEN RETURN QUERY SELECT false; RETURN; END IF;
        UPDATE app_private.password_credentials SET last_totp_step = step, totp_confirmed = true
          WHERE identity_id = ident AND last_totp_step < step;
        IF NOT FOUND THEN RETURN QUERY SELECT false; RETURN; END IF;
        DELETE FROM app_private.password_challenges WHERE challenge_hash = p_challenge;
        UPDATE app_private.sessions SET revoked_at = clock_timestamp() WHERE session_hash = p_old;
        INSERT INTO app_private.sessions(session_hash, identity_id, selected_membership_id, csrf_token, expires_at)
          SELECT p_session, ident, CASE WHEN count(*) = 1 THEN (array_agg(m.id))[1] END, p_csrf, clock_timestamp() + interval '12 hours'
          FROM app_private.tenant_memberships m WHERE m.identity_id = ident AND m.accepted_at IS NOT NULL
            AND m.revoked_at IS NULL AND (m.expires_at IS NULL OR m.expires_at > clock_timestamp());
        RETURN QUERY SELECT true;
      END $fn$;

      REVOKE ALL ON FUNCTION app_private.platform_admin_for_session(text),
        app_private.platform_recovery_begin(text,text,text,text,text), app_private.platform_recovery_secret(text),
        app_private.platform_recovery_finish(text,text,text,text) FROM PUBLIC;
      GRANT EXECUTE ON FUNCTION app_private.platform_admin_for_session(text),
        app_private.platform_recovery_begin(text,text,text,text,text), app_private.platform_recovery_secret(text),
        app_private.platform_recovery_finish(text,text,text,text) TO advocacia_runtime;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
