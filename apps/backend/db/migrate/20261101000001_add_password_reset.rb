class AddPasswordReset < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE app_private.password_resets (
        identity_id uuid PRIMARY KEY REFERENCES app_private.identities(id),
        token_hash text NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
        expires_at timestamptz NOT NULL
      );
      CREATE INDEX ON app_private.password_resets(expires_at);

      CREATE FUNCTION app_private.request_password_reset(p_email text, p_token text)
      RETURNS TABLE(accepted boolean) LANGUAGE plpgsql SECURITY DEFINER
      SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE ident uuid;
      BEGIN
        -- Credential locks serialize issuance, confirmation and both login stages.
        SELECT c.identity_id INTO ident FROM app_private.password_credentials c
          JOIN app_private.identities i ON i.id = c.identity_id
          WHERE lower(i.verified_email) = p_email AND i.disabled_at IS NULL FOR UPDATE OF c;
        IF ident IS NOT NULL THEN
          INSERT INTO app_private.password_resets(identity_id, token_hash, expires_at)
            VALUES (ident, p_token, clock_timestamp() + interval '30 minutes')
            ON CONFLICT (identity_id) DO UPDATE SET token_hash = EXCLUDED.token_hash, expires_at = EXCLUDED.expires_at;
        END IF;
        -- Do not expose account existence, even to the transport caller.
        RETURN QUERY SELECT true;
      END $fn$;

      CREATE FUNCTION app_private.cancel_password_reset(p_token text)
      RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
        DELETE FROM app_private.password_resets WHERE token_hash = p_token
      $fn$;

      CREATE FUNCTION app_private.confirm_password_reset(p_token text, p_password text)
      RETURNS TABLE(changed boolean, email text) LANGUAGE plpgsql SECURITY DEFINER
      SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE ident uuid; recipient text;
      BEGIN
        SELECT r.identity_id INTO ident FROM app_private.password_resets r WHERE r.token_hash = p_token;
        IF ident IS NULL THEN RETURN QUERY SELECT false, NULL::text; RETURN; END IF;
        PERFORM 1 FROM app_private.password_credentials c WHERE c.identity_id = ident FOR UPDATE;
        -- Recheck after waiting for login, another reset, or token rotation.
        DELETE FROM app_private.password_resets r USING app_private.identities i
          WHERE r.identity_id = ident AND i.id = ident AND i.disabled_at IS NULL
            AND r.token_hash = p_token AND r.expires_at > clock_timestamp()
          RETURNING i.verified_email INTO recipient;
        IF NOT FOUND THEN RETURN QUERY SELECT false, NULL::text; RETURN; END IF;
        UPDATE app_private.password_credentials SET password_hash = p_password WHERE identity_id = ident;
        UPDATE app_private.sessions SET revoked_at = clock_timestamp() WHERE identity_id = ident AND revoked_at IS NULL;
        DELETE FROM app_private.password_challenges WHERE identity_id = ident;
        RETURN QUERY SELECT true, recipient;
      END $fn$;

      DROP FUNCTION app_private.create_password_challenge(text,text);
      CREATE FUNCTION app_private.create_password_challenge(p_identity text, p_challenge text, p_password text)
      RETURNS TABLE(created boolean) LANGUAGE plpgsql SECURITY DEFINER
      SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      BEGIN
        -- A password verified in Ruby must still match after a concurrent reset.
        PERFORM 1 FROM app_private.password_credentials c JOIN app_private.identities i ON i.id = c.identity_id
          WHERE c.identity_id = p_identity::uuid AND c.password_hash = p_password AND i.disabled_at IS NULL FOR UPDATE OF c;
        IF NOT FOUND THEN RETURN QUERY SELECT false; RETURN; END IF;
        DELETE FROM app_private.password_challenges WHERE identity_id = p_identity::uuid AND expires_at <= clock_timestamp();
        INSERT INTO app_private.password_challenges(challenge_hash, identity_id, expires_at)
          VALUES (p_challenge, p_identity::uuid, clock_timestamp() + interval '10 minutes');
        RETURN QUERY SELECT true;
      END $fn$;

      CREATE OR REPLACE FUNCTION app_private.finish_password_challenge(p_challenge text, p_step text, p_session text, p_csrf text, p_old text)
      RETURNS TABLE(created boolean) LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE ident uuid; step bigint;
      BEGIN
        step := p_step::bigint;
        SELECT ch.identity_id INTO ident FROM app_private.password_challenges ch WHERE ch.challenge_hash = p_challenge;
        IF ident IS NULL THEN RETURN QUERY SELECT false; RETURN; END IF;
        PERFORM 1 FROM app_private.password_credentials c WHERE c.identity_id = ident FOR UPDATE;
        -- Never lock a challenge before its credential: reset uses the same order.
        PERFORM 1 FROM app_private.password_challenges ch JOIN app_private.identities i ON i.id = ch.identity_id
          WHERE ch.challenge_hash = p_challenge AND ch.identity_id = ident
            AND ch.expires_at > clock_timestamp() AND i.disabled_at IS NULL FOR UPDATE OF ch;
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

      REVOKE ALL ON app_private.password_resets FROM PUBLIC, advocacia_runtime;
      REVOKE ALL ON FUNCTION app_private.request_password_reset(text,text), app_private.cancel_password_reset(text),
        app_private.confirm_password_reset(text,text), app_private.create_password_challenge(text,text,text),
        app_private.finish_password_challenge(text,text,text,text,text) FROM PUBLIC;
      GRANT EXECUTE ON FUNCTION app_private.request_password_reset(text,text), app_private.cancel_password_reset(text),
        app_private.confirm_password_reset(text,text), app_private.create_password_challenge(text,text,text),
        app_private.finish_password_challenge(text,text,text,text,text) TO advocacia_runtime;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
