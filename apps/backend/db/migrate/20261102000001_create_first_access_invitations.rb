class CreateFirstAccessInvitations < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE app_private.first_access_invitations (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        email text NOT NULL UNIQUE CHECK (email = lower(btrim(email))),
        token_hash text NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
        token_ciphertext text NOT NULL,
        created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
        expires_at timestamptz NOT NULL
      );
      CREATE INDEX ON app_private.first_access_invitations(expires_at);
      CREATE TABLE app_private.first_access_preparations (
        invitation_id uuid PRIMARY KEY REFERENCES app_private.first_access_invitations(id) ON DELETE CASCADE,
        challenge_hash text NOT NULL CHECK (challenge_hash ~ '^[0-9a-f]{64}$'),
        password_hash text NOT NULL,
        totp_secret text NOT NULL,
        expires_at timestamptz NOT NULL
      );
      CREATE TABLE app_private.first_access_grants (
        identity_id uuid PRIMARY KEY REFERENCES app_private.identities(id)
      );
      REVOKE ALL ON app_private.first_access_invitations, app_private.first_access_preparations,
        app_private.first_access_grants FROM PUBLIC, advocacia_runtime;

      CREATE FUNCTION app_private.first_access_require_admin(p_session text) RETURNS void
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE ident uuid;
      BEGIN
        SELECT s.identity_id INTO ident FROM app_private.session_identity(p_session) s;
        IF ident IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000'; END IF;
        -- Recovery takes the credential lock before revoking sessions.
        PERFORM 1 FROM app_private.password_credentials c WHERE c.identity_id = ident FOR UPDATE;
        PERFORM 1 FROM app_private.identities i WHERE i.id = ident FOR SHARE;
        PERFORM 1 FROM app_private.sessions s WHERE s.session_hash = p_session FOR SHARE;
        IF NOT EXISTS (SELECT 1 FROM app_private.session_identity(p_session) s WHERE s.identity_id = ident) THEN
          RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
        END IF;
        IF NOT (SELECT a.authorized FROM app_private.platform_admin_for_session(p_session) a) THEN
          RAISE EXCEPTION 'Platform administrator required' USING ERRCODE = '42501';
        END IF;
      END $fn$;

      CREATE FUNCTION app_private.first_access_purge_expired() RETURNS void
      LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
        DELETE FROM app_private.first_access_invitations i WHERE i.id IN (
          SELECT expired.id FROM app_private.first_access_invitations expired
          WHERE expired.expires_at <= clock_timestamp() FOR UPDATE SKIP LOCKED
        )
      $fn$;

      CREATE FUNCTION app_private.first_access_purge_preparations() RETURNS void
      LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
        DELETE FROM app_private.first_access_preparations p WHERE p.invitation_id IN (
          SELECT pending.invitation_id FROM app_private.first_access_preparations pending
          WHERE pending.expires_at <= clock_timestamp() FOR UPDATE SKIP LOCKED
        )
      $fn$;

      CREATE FUNCTION app_private.first_access_admin_list(p_session text)
      RETURNS TABLE(id uuid, email text, created_at timestamptz, expires_at timestamptz)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      BEGIN
        PERFORM app_private.first_access_require_admin(p_session);
        PERFORM app_private.first_access_purge_expired();
        PERFORM app_private.first_access_purge_preparations();
        RETURN QUERY SELECT i.id, i.email, i.created_at, i.expires_at
          FROM app_private.first_access_invitations i WHERE i.expires_at > clock_timestamp()
          ORDER BY i.created_at, i.id;
      END $fn$;

      CREATE FUNCTION app_private.first_access_admin_issue(p_session text, p_email text, p_token text, p_ciphertext text)
      RETURNS TABLE(id uuid, email text, created_at timestamptz, expires_at timestamptz)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE address text; ident app_private.identities%ROWTYPE; invitation app_private.first_access_invitations%ROWTYPE; issued timestamptz;
      BEGIN
        PERFORM app_private.first_access_require_admin(p_session);
        address := lower(btrim(p_email));
        IF address IS NULL OR octet_length(address) > 254 OR
          address !~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9]+([.-][a-z0-9]+)*$' THEN
          RAISE EXCEPTION 'Invalid email' USING ERRCODE = '22023';
        END IF;
        PERFORM app_private.first_access_purge_expired();
        PERFORM pg_advisory_xact_lock(hashtextextended('first-access:' || address, 0));
        SELECT i.* INTO ident FROM app_private.identities i WHERE lower(i.verified_email) = address FOR UPDATE;
        IF FOUND AND (ident.disabled_at IS NOT NULL OR EXISTS (
          SELECT 1 FROM app_private.tenant_memberships m WHERE m.identity_id = ident.id AND m.role = 'owner'
        )) THEN RAISE EXCEPTION 'Identity unavailable' USING ERRCODE = '55000'; END IF;
        DELETE FROM app_private.first_access_invitations i WHERE i.email = address AND i.expires_at <= clock_timestamp();
        IF EXISTS (SELECT 1 FROM app_private.first_access_invitations i WHERE i.email = address) THEN
          RAISE EXCEPTION 'Invitation already active' USING ERRCODE = '55000';
        END IF;
        issued := clock_timestamp();
        INSERT INTO app_private.first_access_invitations(email, token_hash, token_ciphertext, created_at, expires_at)
          VALUES (address, p_token, p_ciphertext, issued, issued + interval '24 hours') RETURNING * INTO invitation;
        RETURN QUERY SELECT invitation.id, invitation.email, invitation.created_at, invitation.expires_at;
      END $fn$;

      -- Return no rows for unavailable invitations: raising here would roll back
      -- the opportunistic purge. Ruby maps absence after the statement commits.
      CREATE FUNCTION app_private.first_access_admin_link(p_session text, p_id text)
      RETURNS TABLE(id uuid, email text, created_at timestamptz, expires_at timestamptz, token_hash text, token_ciphertext text)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      BEGIN
        PERFORM app_private.first_access_require_admin(p_session);
        PERFORM app_private.first_access_purge_expired();
        PERFORM app_private.first_access_purge_preparations();
        RETURN QUERY SELECT i.id, i.email, i.created_at, i.expires_at, i.token_hash, i.token_ciphertext
          FROM app_private.first_access_invitations i WHERE i.id = p_id::uuid AND i.expires_at > clock_timestamp();
      END $fn$;

      CREATE FUNCTION app_private.first_access_admin_reissue(p_session text, p_id text, p_token text, p_ciphertext text)
      RETURNS TABLE(id uuid, email text, created_at timestamptz, expires_at timestamptz)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE address text; ident app_private.identities%ROWTYPE; invitation app_private.first_access_invitations%ROWTYPE; issued timestamptz;
      BEGIN
        PERFORM app_private.first_access_require_admin(p_session);
        PERFORM app_private.first_access_purge_expired();
        SELECT i.email INTO address FROM app_private.first_access_invitations i
          WHERE i.id = p_id::uuid AND i.expires_at > clock_timestamp();
        IF address IS NULL THEN RETURN; END IF;
        PERFORM pg_advisory_xact_lock(hashtextextended('first-access:' || address, 0));
        SELECT i.* INTO ident FROM app_private.identities i WHERE lower(i.verified_email) = address FOR UPDATE;
        IF FOUND AND (ident.disabled_at IS NOT NULL OR EXISTS (
          SELECT 1 FROM app_private.tenant_memberships m WHERE m.identity_id = ident.id AND m.role = 'owner'
        )) THEN RAISE EXCEPTION 'Identity unavailable' USING ERRCODE = '55000'; END IF;
        DELETE FROM app_private.first_access_invitations i
          WHERE i.id = p_id::uuid AND i.email = address AND i.expires_at > clock_timestamp();
        IF NOT FOUND THEN RETURN; END IF;
        issued := clock_timestamp();
        INSERT INTO app_private.first_access_invitations(email, token_hash, token_ciphertext, created_at, expires_at)
          VALUES (address, p_token, p_ciphertext, issued, issued + interval '24 hours') RETURNING * INTO invitation;
        RETURN QUERY SELECT invitation.id, invitation.email, invitation.created_at, invitation.expires_at;
      END $fn$;

      CREATE FUNCTION app_private.first_access_inspect(p_token text)
      RETURNS TABLE(id uuid, email text, created_at timestamptz, expires_at timestamptz, requires_login boolean)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      BEGIN
        PERFORM app_private.first_access_purge_expired();
        PERFORM app_private.first_access_purge_preparations();
        RETURN QUERY SELECT i.id, i.email, i.created_at, i.expires_at, ident.id IS NOT NULL
          FROM app_private.first_access_invitations i
          LEFT JOIN app_private.identities ident ON lower(ident.verified_email) = i.email
          WHERE i.token_hash = p_token AND i.expires_at > clock_timestamp() AND ident.disabled_at IS NULL;
      END $fn$;

      CREATE FUNCTION app_private.first_access_prepare(p_token text, p_challenge text, p_password text, p_secret text)
      RETURNS TABLE(email text, expires_at timestamptz)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE invitation app_private.first_access_invitations%ROWTYPE; address text; deadline timestamptz;
      BEGIN
        PERFORM app_private.first_access_purge_expired();
        SELECT i.email INTO address FROM app_private.first_access_invitations i
          WHERE i.token_hash = p_token AND i.expires_at > clock_timestamp();
        IF address IS NULL THEN RETURN; END IF;
        PERFORM pg_advisory_xact_lock(hashtextextended('first-access:' || address, 0));
        SELECT i.* INTO invitation FROM app_private.first_access_invitations i
          WHERE i.token_hash = p_token AND i.email = address AND i.expires_at > clock_timestamp() FOR UPDATE;
        IF NOT FOUND THEN RETURN; END IF;
        IF EXISTS (SELECT 1 FROM app_private.identities i WHERE lower(i.verified_email) = address) THEN
          RAISE EXCEPTION 'Identity already exists' USING ERRCODE = '55000';
        END IF;
        deadline := least(invitation.expires_at, clock_timestamp() + interval '10 minutes');
        INSERT INTO app_private.first_access_preparations(invitation_id, challenge_hash, password_hash, totp_secret, expires_at)
          VALUES (invitation.id, p_challenge, p_password, p_secret, deadline)
          ON CONFLICT ON CONSTRAINT first_access_preparations_pkey DO UPDATE SET
            challenge_hash = EXCLUDED.challenge_hash, password_hash = EXCLUDED.password_hash,
            totp_secret = EXCLUDED.totp_secret, expires_at = EXCLUDED.expires_at;
        RETURN QUERY SELECT address, deadline;
      END $fn$;

      CREATE FUNCTION app_private.first_access_prepared(p_token text, p_challenge text)
      RETURNS TABLE(email text, password_hash text, totp_secret text, expires_at timestamptz)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      BEGIN
        PERFORM app_private.first_access_purge_expired();
        PERFORM app_private.first_access_purge_preparations();
        RETURN QUERY SELECT i.email, p.password_hash, p.totp_secret, p.expires_at
          FROM app_private.first_access_invitations i JOIN app_private.first_access_preparations p ON p.invitation_id = i.id
          WHERE i.token_hash = p_token AND p.challenge_hash = p_challenge
            AND i.expires_at > clock_timestamp() AND p.expires_at > clock_timestamp()
            AND NOT EXISTS (SELECT 1 FROM app_private.identities ident WHERE lower(ident.verified_email) = i.email);
      END $fn$;

      CREATE FUNCTION app_private.first_access_consume(p_token text, p_session text)
      RETURNS TABLE(identity_id uuid)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE signed_in record; address text; ident app_private.identities%ROWTYPE; invitation app_private.first_access_invitations%ROWTYPE;
      BEGIN
        SELECT * INTO signed_in FROM app_private.session_identity(p_session);
        IF NOT FOUND THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000'; END IF;
        PERFORM 1 FROM app_private.password_credentials c WHERE c.identity_id = signed_in.identity_id FOR UPDATE;
        PERFORM app_private.first_access_purge_expired();
        SELECT i.email INTO address FROM app_private.first_access_invitations i
          WHERE i.token_hash = p_token AND i.expires_at > clock_timestamp();
        IF address IS NULL THEN RETURN; END IF;
        PERFORM pg_advisory_xact_lock(hashtextextended('first-access:' || address, 0));
        SELECT i.* INTO ident FROM app_private.identities i WHERE i.id = signed_in.identity_id FOR UPDATE;
        PERFORM 1 FROM app_private.sessions s WHERE s.session_hash = p_session FOR SHARE;
        IF NOT EXISTS (SELECT 1 FROM app_private.session_identity(p_session) s WHERE s.identity_id = signed_in.identity_id) THEN
          RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000';
        END IF;
        IF lower(ident.verified_email) <> address OR NOT EXISTS (
          SELECT 1 FROM app_private.password_credentials c WHERE c.identity_id = ident.id AND c.totp_confirmed
        ) THEN RAISE EXCEPTION 'Invitation unavailable' USING ERRCODE = 'P0002'; END IF;
        SELECT i.* INTO invitation FROM app_private.first_access_invitations i
          WHERE i.token_hash = p_token AND i.email = address AND i.expires_at > clock_timestamp() FOR UPDATE;
        IF NOT FOUND THEN RETURN; END IF;
        IF EXISTS (SELECT 1 FROM app_private.tenant_memberships m WHERE m.identity_id = ident.id AND m.role = 'owner') THEN
          RAISE EXCEPTION 'Identity already owns a tenant' USING ERRCODE = '55000';
        END IF;
        INSERT INTO app_private.first_access_grants(identity_id) VALUES (ident.id) ON CONFLICT DO NOTHING;
        DELETE FROM app_private.first_access_invitations i WHERE i.id = invitation.id;
        RETURN QUERY SELECT ident.id;
      END $fn$;

      REVOKE ALL ON FUNCTION app_private.first_access_require_admin(text), app_private.first_access_purge_expired(),
        app_private.first_access_purge_preparations() FROM PUBLIC, advocacia_runtime;
      REVOKE ALL ON FUNCTION app_private.first_access_admin_list(text), app_private.first_access_admin_issue(text,text,text,text),
        app_private.first_access_admin_link(text,text), app_private.first_access_admin_reissue(text,text,text,text),
        app_private.first_access_inspect(text), app_private.first_access_prepare(text,text,text,text),
        app_private.first_access_prepared(text,text), app_private.first_access_consume(text,text) FROM PUBLIC;
      GRANT EXECUTE ON FUNCTION app_private.first_access_admin_list(text), app_private.first_access_admin_issue(text,text,text,text),
        app_private.first_access_admin_link(text,text), app_private.first_access_admin_reissue(text,text,text,text),
        app_private.first_access_inspect(text), app_private.first_access_prepare(text,text,text,text),
        app_private.first_access_prepared(text,text), app_private.first_access_consume(text,text) TO advocacia_runtime;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
