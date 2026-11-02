class CreateTeamCredentials < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE app_private.team_invitations (
        membership_id uuid PRIMARY KEY,
        tenant_id uuid NOT NULL,
        token_hash text NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
        issued_at timestamptz NOT NULL,
        expires_at timestamptz NOT NULL,
        consumed_at timestamptz,
        FOREIGN KEY (tenant_id, membership_id)
          REFERENCES app_private.tenant_memberships(tenant_id, id),
        CHECK (expires_at > issued_at AND expires_at <= issued_at + interval '24 hours')
      );
      REVOKE ALL ON app_private.team_invitations FROM PUBLIC, advocacia_runtime;
      ALTER TABLE app_private.tenant_memberships ENABLE ROW LEVEL SECURITY;
      ALTER TABLE app_private.tenant_memberships FORCE ROW LEVEL SECURITY;
      ALTER TABLE app_private.team_invitations ENABLE ROW LEVEL SECURITY;
      ALTER TABLE app_private.team_invitations FORCE ROW LEVEL SECURITY;
      -- Private bootstrap rows are inaccessible to runtime; only the fixed definer
      -- interfaces below may resolve an identity before a tenant has been selected.
      CREATE POLICY identity_bootstrap ON app_private.tenant_memberships
        TO advocacia_migrator USING (true) WITH CHECK (true);
      CREATE POLICY identity_bootstrap ON app_private.team_invitations
        TO advocacia_migrator USING (true) WITH CHECK (true);

      CREATE FUNCTION app_private.available_memberships()
      RETURNS TABLE(id uuid, tenant_id uuid, role text, expires_at timestamptz)
      LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
        SELECT m.id, m.tenant_id, m.role, m.expires_at
        FROM app_private.tenant_memberships m
        JOIN app_private.session_identity(current_setting('app.session_hash', true)) s ON s.identity_id = m.identity_id
        WHERE m.accepted_at IS NOT NULL AND m.revoked_at IS NULL
          AND (m.expires_at IS NULL OR m.expires_at > clock_timestamp())
        ORDER BY m.credential_started_at, m.id
      $fn$;

      CREATE FUNCTION app_private.select_membership(p_id text)
      RETURNS TABLE(selected boolean)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE member_id uuid;
      BEGIN
        SELECT m.id INTO member_id FROM app_private.available_memberships() m WHERE m.id = p_id::uuid;
        IF NOT FOUND THEN RAISE EXCEPTION 'Membership unavailable' USING ERRCODE = '42501'; END IF;
        UPDATE app_private.sessions SET selected_membership_id = member_id
          WHERE session_hash = current_setting('app.session_hash', true);
        PERFORM 1 FROM app_private.available_memberships() m WHERE m.id = member_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Membership unavailable' USING ERRCODE = '42501'; END IF;
        RETURN QUERY SELECT true;
      END $fn$;

      CREATE FUNCTION app_private.list_team_credentials()
      RETURNS SETOF app_private.tenant_memberships
      LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE owner_tenant uuid;
      BEGIN
        PERFORM app_private.lock_authorization(false);
        owner_tenant := app_private.require_owner();
        RETURN QUERY SELECT m.* FROM app_private.tenant_memberships m
          WHERE m.tenant_id = owner_tenant AND m.role = 'member'
          ORDER BY m.credential_started_at, m.id;
      END $fn$;

      CREATE FUNCTION app_private.create_team_credential(p_email text, p_days text, p_token_hash text)
      RETURNS SETOF app_private.tenant_memberships
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE owner_tenant uuid; member_row app_private.tenant_memberships%ROWTYPE;
        started timestamptz; days integer;
      BEGIN
        PERFORM app_private.lock_authorization(true);
        owner_tenant := app_private.require_owner();
        IF p_email IS NULL OR p_email <> lower(btrim(p_email)) OR length(p_email) > 254
          OR p_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
          OR (p_days IS NOT NULL AND p_days !~ '^[1-9][0-9]*$') THEN
          RAISE EXCEPTION 'Invalid credential input' USING ERRCODE = '22023';
        END IF;
        days := p_days::integer;
        started := clock_timestamp();
        INSERT INTO app_private.tenant_memberships(tenant_id, role, invited_email,
          validity_days, credential_started_at, expires_at)
          VALUES (owner_tenant, 'member', p_email, days, started, started + days * interval '24 hours')
          RETURNING * INTO member_row;
        INSERT INTO app_private.team_invitations(membership_id, tenant_id, token_hash, issued_at, expires_at)
          VALUES (member_row.id, owner_tenant, p_token_hash, started,
            LEAST(started + interval '24 hours', member_row.expires_at));
        PERFORM app_private.require_owner();
        RETURN NEXT member_row;
      END $fn$;

      CREATE FUNCTION app_private.change_credential_validity(p_id text, p_days text)
      RETURNS SETOF app_private.tenant_memberships
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE owner_tenant uuid; member_row app_private.tenant_memberships%ROWTYPE;
      BEGIN
        PERFORM app_private.lock_authorization(true);
        owner_tenant := app_private.require_owner();
        IF p_days IS NOT NULL AND p_days !~ '^[1-9][0-9]*$' THEN
          RAISE EXCEPTION 'Invalid validity' USING ERRCODE = '22023';
        END IF;
        UPDATE app_private.tenant_memberships m SET validity_days = p_days::integer
          WHERE m.id = p_id::uuid AND m.tenant_id = owner_tenant AND m.role = 'member'
          RETURNING m.* INTO member_row;
        IF NOT FOUND THEN RAISE EXCEPTION 'Credential unavailable' USING ERRCODE = 'P0002'; END IF;
        PERFORM app_private.require_owner();
        RETURN NEXT member_row;
      END $fn$;

      CREATE FUNCTION app_private.renew_team_credential(p_id text)
      RETURNS SETOF app_private.tenant_memberships
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE owner_tenant uuid; member_row app_private.tenant_memberships%ROWTYPE; started timestamptz;
      BEGIN
        PERFORM app_private.lock_authorization(true);
        owner_tenant := app_private.require_owner();
        SELECT m.* INTO member_row FROM app_private.tenant_memberships m
          WHERE m.id = p_id::uuid AND m.tenant_id = owner_tenant AND m.role = 'member' FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Credential unavailable' USING ERRCODE = 'P0002'; END IF;
        PERFORM app_private.require_owner();
        IF member_row.revoked_at IS NOT NULL THEN
          RAISE EXCEPTION 'Revoked credentials cannot be renewed' USING ERRCODE = '55000';
        END IF;
        started := clock_timestamp();
        UPDATE app_private.tenant_memberships m SET credential_started_at = started,
          expires_at = started + member_row.validity_days * interval '24 hours'
          WHERE m.id = member_row.id RETURNING m.* INTO member_row;
        -- Renewal never extends a previously issued invitation. A new invitation
        -- requires a separate explicit reissue, with a new random token.
        PERFORM app_private.require_owner();
        RETURN NEXT member_row;
      END $fn$;

      CREATE FUNCTION app_private.revoke_team_credential(p_id text)
      RETURNS SETOF app_private.tenant_memberships
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE owner_tenant uuid; member_row app_private.tenant_memberships%ROWTYPE;
      BEGIN
        PERFORM app_private.lock_authorization(true);
        owner_tenant := app_private.require_owner();
        UPDATE app_private.tenant_memberships m SET revoked_at = COALESCE(m.revoked_at, clock_timestamp())
          WHERE m.id = p_id::uuid AND m.tenant_id = owner_tenant AND m.role = 'member'
          RETURNING m.* INTO member_row;
        IF NOT FOUND THEN RAISE EXCEPTION 'Credential unavailable' USING ERRCODE = 'P0002'; END IF;
        PERFORM app_private.require_owner();
        RETURN NEXT member_row;
      END $fn$;

      CREATE FUNCTION app_private.reissue_team_invitation(p_id text, p_token_hash text)
      RETURNS SETOF app_private.tenant_memberships
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE owner_tenant uuid; member_row app_private.tenant_memberships%ROWTYPE; issued timestamptz;
      BEGIN
        PERFORM app_private.lock_authorization(true);
        owner_tenant := app_private.require_owner();
        SELECT m.* INTO member_row FROM app_private.tenant_memberships m
          WHERE m.id = p_id::uuid AND m.tenant_id = owner_tenant AND m.role = 'member' FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Credential unavailable' USING ERRCODE = 'P0002'; END IF;
        PERFORM app_private.require_owner();
        issued := clock_timestamp();
        IF member_row.revoked_at IS NOT NULL OR member_row.accepted_at IS NOT NULL
          OR (member_row.expires_at IS NOT NULL AND member_row.expires_at <= issued) THEN
          RAISE EXCEPTION 'Invitation unavailable' USING ERRCODE = '55000';
        END IF;
        UPDATE app_private.team_invitations SET token_hash = p_token_hash, issued_at = issued,
          expires_at = LEAST(issued + interval '24 hours', member_row.expires_at), consumed_at = NULL
          WHERE membership_id = member_row.id;
        PERFORM app_private.require_owner();
        RETURN NEXT member_row;
      END $fn$;

      CREATE FUNCTION app_private.accept_team_invitation(p_token_hash text)
      RETURNS TABLE(membership_id uuid, tenant_id uuid)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE signed_in record; invitation app_private.team_invitations%ROWTYPE;
        member_row app_private.tenant_memberships%ROWTYPE; accepted timestamptz;
      BEGIN
        SELECT * INTO signed_in FROM app_private.session_identity(current_setting('app.session_hash', true));
        IF NOT FOUND THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000'; END IF;
        SELECT i.* INTO invitation FROM app_private.team_invitations i WHERE i.token_hash = p_token_hash;
        IF NOT FOUND THEN RAISE EXCEPTION 'Invitation unavailable' USING ERRCODE = 'P0002'; END IF;
        -- The invitation hash, never a client tenant, resolves this destination.
        PERFORM pg_advisory_xact_lock(hashtextextended('authorization:' || invitation.tenant_id::text, 0));
        PERFORM 1 FROM app_private.sessions s
          WHERE s.session_hash = current_setting('app.session_hash', true) FOR UPDATE;
        SELECT m.* INTO member_row FROM app_private.tenant_memberships m
          WHERE m.id = invitation.membership_id FOR UPDATE;
        -- Serialize acceptance, reissue and revocation on the membership, then
        -- re-read the current token under lock. A previous token can never win.
        SELECT i.* INTO invitation FROM app_private.team_invitations i
          WHERE i.membership_id = member_row.id AND i.token_hash = p_token_hash FOR UPDATE;
        SELECT * INTO signed_in FROM app_private.session_identity(current_setting('app.session_hash', true));
        IF NOT FOUND THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000'; END IF;
        accepted := clock_timestamp();
        IF invitation.membership_id IS NULL OR invitation.consumed_at IS NOT NULL OR invitation.expires_at <= accepted
          OR member_row.revoked_at IS NOT NULL OR member_row.accepted_at IS NOT NULL
          OR (member_row.expires_at IS NOT NULL AND member_row.expires_at <= accepted)
          OR lower(btrim(signed_in.verified_email)) <> member_row.invited_email THEN
          RAISE EXCEPTION 'Invitation unavailable' USING ERRCODE = 'P0002';
        END IF;
        UPDATE app_private.team_invitations SET consumed_at = accepted WHERE team_invitations.membership_id = member_row.id;
        UPDATE app_private.tenant_memberships SET identity_id = signed_in.identity_id, accepted_at = accepted
          WHERE id = member_row.id;
        UPDATE app_private.sessions SET selected_membership_id = member_row.id
          WHERE session_hash = current_setting('app.session_hash', true);
        PERFORM 1 FROM app_private.session_context(current_setting('app.session_hash', true)) c
          WHERE c.membership_id = member_row.id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000'; END IF;
        RETURN QUERY SELECT member_row.id, member_row.tenant_id;
      END $fn$;

      REVOKE ALL ON ALL FUNCTIONS IN SCHEMA app_private FROM PUBLIC;
      GRANT EXECUTE ON FUNCTION app_private.available_memberships(), app_private.select_membership(text),
        app_private.list_team_credentials(), app_private.create_team_credential(text,text,text),
        app_private.change_credential_validity(text,text), app_private.renew_team_credential(text),
        app_private.revoke_team_credential(text), app_private.reissue_team_invitation(text,text),
        app_private.accept_team_invitation(text) TO advocacia_runtime;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
