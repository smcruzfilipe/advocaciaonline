class RequireTeamInvitationForRegistration < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE app_private.identities ADD COLUMN email_verified_at timestamptz;
      UPDATE app_private.identities SET email_verified_at = created_at;

      -- Public registration proofs have no invitation provenance and cannot survive cutover.
      DELETE FROM app_private.pending_registrations;
      ALTER TABLE app_private.pending_registrations
        ADD COLUMN invitation_hash text NOT NULL,
        ADD COLUMN existing_identity_id uuid REFERENCES app_private.identities(id);
      DROP FUNCTION app_private.register_password(text,text,text,text,text);
      DROP FUNCTION app_private.verify_password_email(text,text);

      CREATE FUNCTION app_private.register_team_password(
        p_invitation text, p_token text, p_browser text, p_email text,
        p_password text, p_secret text, p_session text
      ) RETURNS TABLE(created boolean)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE invitation app_private.team_invitations%ROWTYPE;
        member_row app_private.tenant_memberships%ROWTYPE;
        ident app_private.identities%ROWTYPE;
      BEGIN
        IF p_invitation IS NULL OR p_invitation !~ '^[0-9a-f]{64}$'
          OR p_token IS NULL OR p_token !~ '^[0-9a-f]{64}$'
          OR p_browser IS NULL OR p_browser !~ '^[0-9a-f]{64}$'
          OR p_email IS NULL OR p_email <> lower(btrim(p_email)) THEN
          RETURN QUERY SELECT false; RETURN;
        END IF;
        SELECT i.* INTO invitation FROM app_private.team_invitations i WHERE i.token_hash = p_invitation;
        IF NOT FOUND THEN RETURN QUERY SELECT false; RETURN; END IF;
        PERFORM pg_advisory_xact_lock(hashtextextended('first-access:' || p_email, 0));
        PERFORM pg_advisory_xact_lock(hashtextextended('authorization:' || invitation.tenant_id::text, 0));
        SELECT m.* INTO member_row FROM app_private.tenant_memberships m WHERE m.id = invitation.membership_id FOR UPDATE;
        SELECT i.* INTO invitation FROM app_private.team_invitations i
          WHERE i.membership_id = member_row.id AND i.token_hash = p_invitation FOR UPDATE;
        IF NOT FOUND OR invitation.consumed_at IS NOT NULL OR invitation.expires_at <= clock_timestamp()
          OR member_row.revoked_at IS NOT NULL OR member_row.accepted_at IS NOT NULL
          OR (member_row.expires_at IS NOT NULL AND member_row.expires_at <= clock_timestamp())
          OR member_row.invited_email <> p_email THEN
          RETURN QUERY SELECT false; RETURN;
        END IF;
        SELECT i.* INTO ident FROM app_private.identities i WHERE lower(i.verified_email) = p_email FOR UPDATE;
        IF FOUND THEN
          PERFORM 1 FROM app_private.sessions s WHERE s.session_hash = p_session FOR SHARE;
          IF ident.disabled_at IS NOT NULL OR NOT EXISTS (
            SELECT 1 FROM app_private.session_identity(p_session) s WHERE s.identity_id = ident.id
          ) THEN RETURN QUERY SELECT false; RETURN; END IF;
        ELSIF p_password IS NULL OR p_password = '' OR p_secret IS NULL OR p_secret = '' THEN
          RETURN QUERY SELECT false; RETURN;
        END IF;
        DELETE FROM app_private.pending_registrations WHERE expires_at <= clock_timestamp();
        IF invitation.expires_at <= clock_timestamp()
          OR (member_row.expires_at IS NOT NULL AND member_row.expires_at <= clock_timestamp()) THEN
          RETURN QUERY SELECT false; RETURN;
        END IF;
        INSERT INTO app_private.pending_registrations
          (token_hash, browser_hash, email, password_hash, totp_secret, expires_at, invitation_hash, existing_identity_id)
          VALUES (p_token, p_browser, p_email, COALESCE(p_password, ''), COALESCE(p_secret, ''),
            LEAST(clock_timestamp() + interval '24 hours', invitation.expires_at), p_invitation, ident.id);
        RETURN QUERY SELECT true;
      END $fn$;

      CREATE FUNCTION app_private.verify_team_email(p_token text, p_browser text, p_session text)
      RETURNS TABLE(verified boolean)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE pending app_private.pending_registrations%ROWTYPE;
        invitation app_private.team_invitations%ROWTYPE;
        member_row app_private.tenant_memberships%ROWTYPE; ident uuid;
      BEGIN
        SELECT p.* INTO pending FROM app_private.pending_registrations p
          WHERE p.token_hash = p_token AND p.browser_hash = p_browser;
        IF NOT FOUND THEN RETURN QUERY SELECT false; RETURN; END IF;
        SELECT i.* INTO invitation FROM app_private.team_invitations i WHERE i.token_hash = pending.invitation_hash;
        IF NOT FOUND THEN RETURN QUERY SELECT false; RETURN; END IF;
        PERFORM pg_advisory_xact_lock(hashtextextended('first-access:' || pending.email, 0));
        PERFORM pg_advisory_xact_lock(hashtextextended('authorization:' || invitation.tenant_id::text, 0));
        SELECT m.* INTO member_row FROM app_private.tenant_memberships m WHERE m.id = invitation.membership_id FOR UPDATE;
        SELECT i.* INTO invitation FROM app_private.team_invitations i
          WHERE i.membership_id = member_row.id AND i.token_hash = pending.invitation_hash FOR UPDATE;
        IF NOT FOUND THEN RETURN QUERY SELECT false; RETURN; END IF;
        SELECT p.* INTO pending FROM app_private.pending_registrations p
          WHERE p.token_hash = p_token AND p.browser_hash = p_browser FOR UPDATE;
        IF NOT FOUND OR pending.expires_at <= clock_timestamp() OR invitation.consumed_at IS NOT NULL
          OR invitation.expires_at <= clock_timestamp() OR member_row.revoked_at IS NOT NULL
          OR member_row.accepted_at IS NOT NULL OR member_row.invited_email <> pending.email
          OR (member_row.expires_at IS NOT NULL AND member_row.expires_at <= clock_timestamp()) THEN
          RETURN QUERY SELECT false; RETURN;
        END IF;
        IF pending.existing_identity_id IS NOT NULL THEN
          PERFORM 1 FROM app_private.identities i WHERE i.id = pending.existing_identity_id
            AND i.disabled_at IS NULL AND lower(i.verified_email) = pending.email FOR UPDATE;
          IF NOT FOUND THEN RETURN QUERY SELECT false; RETURN; END IF;
          PERFORM 1 FROM app_private.sessions s WHERE s.session_hash = p_session FOR SHARE;
          IF NOT EXISTS (
            SELECT 1 FROM app_private.session_identity(p_session) s WHERE s.identity_id = pending.existing_identity_id
          ) THEN RETURN QUERY SELECT false; RETURN; END IF;
        END IF;
        IF pending.expires_at <= clock_timestamp() OR invitation.expires_at <= clock_timestamp()
          OR (member_row.expires_at IS NOT NULL AND member_row.expires_at <= clock_timestamp()) THEN
          RETURN QUERY SELECT false; RETURN;
        END IF;
        IF pending.existing_identity_id IS NOT NULL THEN
          UPDATE app_private.identities SET email_verified_at = COALESCE(email_verified_at, clock_timestamp())
            WHERE id = pending.existing_identity_id;
        ELSE
          INSERT INTO app_private.identities(verified_email, email_verified_at)
            VALUES (pending.email, clock_timestamp()) ON CONFLICT DO NOTHING RETURNING id INTO ident;
          IF ident IS NULL THEN RETURN QUERY SELECT false; RETURN; END IF;
          INSERT INTO app_private.password_credentials(identity_id, password_hash, totp_secret)
            VALUES (ident, pending.password_hash, pending.totp_secret);
        END IF;
        DELETE FROM app_private.pending_registrations WHERE token_hash = p_token;
        RETURN QUERY SELECT true;
      END $fn$;

      CREATE OR REPLACE FUNCTION app_private.accept_team_invitation(p_token_hash text)
      RETURNS TABLE(membership_id uuid, tenant_id uuid)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE signed_in record; invitation app_private.team_invitations%ROWTYPE;
        member_row app_private.tenant_memberships%ROWTYPE; accepted timestamptz;
      BEGIN
        SELECT * INTO signed_in FROM app_private.session_identity(current_setting('app.session_hash', true));
        IF NOT FOUND THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000'; END IF;
        SELECT i.* INTO invitation FROM app_private.team_invitations i WHERE i.token_hash = p_token_hash;
        IF NOT FOUND THEN RAISE EXCEPTION 'Invitation unavailable' USING ERRCODE = 'P0002'; END IF;
        PERFORM pg_advisory_xact_lock(hashtextextended('authorization:' || invitation.tenant_id::text, 0));
        PERFORM 1 FROM app_private.sessions s
          WHERE s.session_hash = current_setting('app.session_hash', true) FOR UPDATE;
        SELECT m.* INTO member_row FROM app_private.tenant_memberships m
          WHERE m.id = invitation.membership_id FOR UPDATE;
        SELECT i.* INTO invitation FROM app_private.team_invitations i
          WHERE i.membership_id = member_row.id AND i.token_hash = p_token_hash FOR UPDATE;
        SELECT * INTO signed_in FROM app_private.session_identity(current_setting('app.session_hash', true));
        IF NOT FOUND THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '28000'; END IF;
        accepted := clock_timestamp();
        IF invitation.membership_id IS NULL OR invitation.consumed_at IS NOT NULL OR invitation.expires_at <= accepted
          OR member_row.revoked_at IS NOT NULL OR member_row.accepted_at IS NOT NULL
          OR (member_row.expires_at IS NOT NULL AND member_row.expires_at <= accepted)
          OR lower(btrim(signed_in.verified_email)) <> member_row.invited_email
          OR NOT EXISTS (SELECT 1 FROM app_private.identities i
            WHERE i.id = signed_in.identity_id AND i.email_verified_at IS NOT NULL) THEN
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

      REVOKE ALL ON FUNCTION app_private.register_team_password(text,text,text,text,text,text,text),
        app_private.verify_team_email(text,text,text) FROM PUBLIC;
      GRANT EXECUTE ON FUNCTION app_private.register_team_password(text,text,text,text,text,text,text),
        app_private.verify_team_email(text,text,text) TO advocacia_runtime;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
