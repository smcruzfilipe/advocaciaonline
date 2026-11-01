class SeparateInvitedEmailAuthorization < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      -- verified_email remains the canonical login address. email_verified_at,
      -- introduced by the team registration migration, alone records mailbox proof.
      CREATE FUNCTION app_private.first_access_finish(
        p_token text, p_challenge text, p_secret text, p_step text,
        p_session text, p_csrf text, p_old text
      ) RETURNS TABLE(created boolean)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE address text; invitation app_private.first_access_invitations%ROWTYPE;
        pending app_private.first_access_preparations%ROWTYPE; ident uuid;
      BEGIN
        PERFORM app_private.first_access_purge_expired();
        SELECT i.email INTO address FROM app_private.first_access_invitations i
          WHERE i.token_hash = p_token AND i.expires_at > clock_timestamp();
        IF address IS NULL THEN RETURN QUERY SELECT false; RETURN; END IF;
        PERFORM pg_advisory_xact_lock(hashtextextended('first-access:' || address, 0));
        SELECT i.* INTO invitation FROM app_private.first_access_invitations i
          WHERE i.token_hash = p_token AND i.email = address AND i.expires_at > clock_timestamp() FOR UPDATE;
        IF NOT FOUND THEN RETURN QUERY SELECT false; RETURN; END IF;
        SELECT p.* INTO pending FROM app_private.first_access_preparations p
          WHERE p.invitation_id = invitation.id AND p.challenge_hash = p_challenge
            AND p.totp_secret = p_secret AND p.expires_at > clock_timestamp() FOR UPDATE;
        IF NOT FOUND OR EXISTS (SELECT 1 FROM app_private.identities i WHERE lower(i.verified_email) = address) THEN
          RETURN QUERY SELECT false; RETURN;
        END IF;
        INSERT INTO app_private.identities(verified_email, email_verified_at)
          VALUES (address, NULL) RETURNING id INTO ident;
        INSERT INTO app_private.password_credentials(identity_id, password_hash, totp_secret, totp_confirmed, last_totp_step)
          VALUES (ident, pending.password_hash, pending.totp_secret, true, p_step::bigint);
        INSERT INTO app_private.first_access_grants(identity_id) VALUES (ident);
        UPDATE app_private.sessions SET revoked_at = clock_timestamp() WHERE session_hash = p_old;
        INSERT INTO app_private.sessions(session_hash, identity_id, csrf_token, expires_at)
          VALUES (p_session, ident, p_csrf, clock_timestamp() + interval '12 hours');
        DELETE FROM app_private.first_access_invitations i
          WHERE i.id = invitation.id AND i.expires_at > clock_timestamp()
            AND pending.expires_at > clock_timestamp();
        IF NOT FOUND THEN RAISE EXCEPTION 'Invitation unavailable' USING ERRCODE = 'P0002'; END IF;
        RETURN QUERY SELECT true;
      END $fn$;
      REVOKE ALL ON FUNCTION app_private.first_access_finish(text,text,text,text,text,text,text) FROM PUBLIC;
      GRANT EXECUTE ON FUNCTION app_private.first_access_finish(text,text,text,text,text,text,text) TO advocacia_runtime;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
