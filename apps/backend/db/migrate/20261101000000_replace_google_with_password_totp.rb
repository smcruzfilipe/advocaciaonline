class ReplaceGoogleWithPasswordTotp < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      DROP FUNCTION app_private.authenticate_google(text,text,text,text);
      DROP FUNCTION app_private.start_login(text,text,text,text);
      DROP FUNCTION app_private.consume_login(text,text);
      DROP TABLE app_private.login_attempts;
      ALTER TABLE app_private.identities DROP COLUMN google_subject;
      CREATE UNIQUE INDEX identities_verified_email_unique ON app_private.identities(lower(verified_email));
      -- Existing sessions predate mandatory second-factor authentication.
      UPDATE app_private.sessions SET revoked_at = clock_timestamp() WHERE revoked_at IS NULL;
      CREATE TABLE app_private.password_credentials (
        identity_id uuid PRIMARY KEY REFERENCES app_private.identities(id),
        password_hash text NOT NULL,
        totp_secret text NOT NULL,
        totp_confirmed boolean NOT NULL DEFAULT false,
        last_totp_step bigint NOT NULL DEFAULT -1
      );
      CREATE TABLE app_private.pending_registrations (
        token_hash text PRIMARY KEY, browser_hash text NOT NULL, email text NOT NULL, password_hash text NOT NULL,
        totp_secret text NOT NULL, expires_at timestamptz NOT NULL
      );
      CREATE INDEX ON app_private.pending_registrations(expires_at);
      CREATE TABLE app_private.password_challenges (
        challenge_hash text PRIMARY KEY, identity_id uuid NOT NULL REFERENCES app_private.identities(id),
        expires_at timestamptz NOT NULL
      );
      CREATE INDEX ON app_private.password_challenges(expires_at);

      CREATE FUNCTION app_private.auth_limit(p_bucket text) RETURNS TABLE(accepted boolean)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE n integer;
      BEGIN
        INSERT INTO app_private.auth_limits(bucket_hash, attempts, expires_at)
        VALUES (p_bucket, 1, clock_timestamp() + interval '15 minutes')
        ON CONFLICT (bucket_hash) DO UPDATE SET
          attempts = CASE WHEN app_private.auth_limits.expires_at <= clock_timestamp() THEN 1 ELSE app_private.auth_limits.attempts + 1 END,
          expires_at = CASE WHEN app_private.auth_limits.expires_at <= clock_timestamp() THEN clock_timestamp() + interval '15 minutes' ELSE app_private.auth_limits.expires_at END
        RETURNING attempts INTO n;
        RETURN QUERY SELECT n <= 20;
      END $fn$;

      CREATE FUNCTION app_private.register_password(p_token text, p_browser text, p_email text, p_password text, p_secret text)
      RETURNS TABLE(created boolean) LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      BEGIN
        DELETE FROM app_private.pending_registrations WHERE expires_at <= clock_timestamp();
        IF EXISTS (SELECT 1 FROM app_private.identities WHERE lower(verified_email) = p_email) THEN
          RETURN QUERY SELECT false; RETURN;
        END IF;
        INSERT INTO app_private.pending_registrations VALUES (p_token, p_browser, p_email, p_password, p_secret, clock_timestamp() + interval '24 hours');
        RETURN QUERY SELECT true;
      END $fn$;

      CREATE FUNCTION app_private.verify_password_email(p_token text, p_browser text) RETURNS TABLE(verified boolean)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE pending app_private.pending_registrations%ROWTYPE; ident uuid;
      BEGIN
        DELETE FROM app_private.pending_registrations WHERE token_hash = p_token AND browser_hash = p_browser AND expires_at > clock_timestamp() RETURNING * INTO pending;
        IF NOT FOUND THEN RETURN QUERY SELECT false; RETURN; END IF;
        INSERT INTO app_private.identities(verified_email) VALUES (pending.email) ON CONFLICT DO NOTHING RETURNING id INTO ident;
        IF ident IS NULL THEN RETURN QUERY SELECT false; RETURN; END IF;
        INSERT INTO app_private.password_credentials(identity_id, password_hash, totp_secret) VALUES (ident, pending.password_hash, pending.totp_secret);
        DELETE FROM app_private.pending_registrations WHERE email = pending.email;
        RETURN QUERY SELECT true;
      END $fn$;

      CREATE FUNCTION app_private.password_lookup(p_email text)
      RETURNS TABLE(identity_id uuid, password_hash text, totp_secret text, totp_confirmed boolean)
      LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
        SELECT i.id, c.password_hash, c.totp_secret, c.totp_confirmed FROM app_private.identities i
        JOIN app_private.password_credentials c ON c.identity_id = i.id
        WHERE lower(i.verified_email) = p_email AND i.disabled_at IS NULL
      $fn$;
      CREATE FUNCTION app_private.create_password_challenge(p_identity text, p_challenge text)
      RETURNS TABLE(created boolean) LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      BEGIN
        DELETE FROM app_private.password_challenges WHERE expires_at <= clock_timestamp();
        INSERT INTO app_private.password_challenges SELECT p_challenge, i.id, clock_timestamp() + interval '10 minutes'
          FROM app_private.identities i JOIN app_private.password_credentials c ON c.identity_id = i.id
          WHERE i.id = p_identity::uuid AND i.disabled_at IS NULL;
        RETURN QUERY SELECT FOUND;
      END $fn$;
      CREATE FUNCTION app_private.password_challenge(p_challenge text)
      RETURNS TABLE(totp_secret text) LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
        SELECT c.totp_secret FROM app_private.password_challenges ch
        JOIN app_private.identities i ON i.id = ch.identity_id
        JOIN app_private.password_credentials c ON c.identity_id = i.id
        WHERE ch.challenge_hash = p_challenge AND ch.expires_at > clock_timestamp() AND i.disabled_at IS NULL
      $fn$;
      CREATE FUNCTION app_private.finish_password_challenge(p_challenge text, p_step text, p_session text, p_csrf text, p_old text)
      RETURNS TABLE(created boolean) LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE ident uuid; step bigint;
      BEGIN
        step := p_step::bigint;
        SELECT ch.identity_id INTO ident FROM app_private.password_challenges ch
          JOIN app_private.identities i ON i.id = ch.identity_id
          WHERE ch.challenge_hash = p_challenge AND ch.expires_at > clock_timestamp() AND i.disabled_at IS NULL FOR UPDATE OF ch;
        IF ident IS NULL THEN RETURN QUERY SELECT false; RETURN; END IF;
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
      REVOKE ALL ON ALL TABLES IN SCHEMA app_private FROM PUBLIC, advocacia_runtime;
      REVOKE ALL ON FUNCTION app_private.auth_limit(text), app_private.register_password(text,text,text,text,text),
        app_private.verify_password_email(text,text), app_private.password_lookup(text), app_private.create_password_challenge(text,text),
        app_private.password_challenge(text), app_private.finish_password_challenge(text,text,text,text,text) FROM PUBLIC;
      GRANT EXECUTE ON FUNCTION app_private.auth_limit(text), app_private.register_password(text,text,text,text,text),
        app_private.verify_password_email(text,text), app_private.password_lookup(text), app_private.create_password_challenge(text,text),
        app_private.password_challenge(text), app_private.finish_password_challenge(text,text,text,text,text) TO advocacia_runtime;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
