class RequireAdministrativeTenantAuthorization < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      -- The membership's deferred foreign key guarantees an existing tenant at commit.
      INSERT INTO app_private.first_access_grants(identity_id)
        SELECT m.identity_id FROM app_private.tenant_memberships m
        WHERE m.role = 'owner'
        ON CONFLICT (identity_id) DO NOTHING;

      CREATE OR REPLACE FUNCTION app_private.claim_tenant(p_hash text)
      RETURNS TABLE(tenant_id uuid, claimed boolean)
      LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
      DECLARE identity_row app_private.identities%ROWTYPE; new_tenant uuid; owner_membership uuid;
      BEGIN
        SELECT identity.* INTO identity_row FROM app_private.identities AS identity
          JOIN app_private.sessions AS session ON session.identity_id = identity.id
          WHERE session.session_hash = p_hash AND session.revoked_at IS NULL
            AND session.expires_at > statement_timestamp() AND identity.disabled_at IS NULL
          FOR UPDATE OF identity;
        IF NOT FOUND THEN RETURN; END IF;
        IF NOT EXISTS (SELECT 1 FROM app_private.first_access_grants g WHERE g.identity_id = identity_row.id) THEN
          RETURN QUERY SELECT NULL::uuid, false;
          RETURN;
        END IF;
        SELECT m.tenant_id INTO new_tenant FROM app_private.tenant_memberships m
          WHERE m.identity_id = identity_row.id AND m.role = 'owner';
        IF FOUND THEN RETURN QUERY SELECT new_tenant, false; RETURN; END IF;
        new_tenant := gen_random_uuid();
        INSERT INTO app_private.tenant_memberships(tenant_id, identity_id, role, accepted_at)
          VALUES (new_tenant, identity_row.id, 'owner', statement_timestamp())
          RETURNING id INTO owner_membership;
        UPDATE app_private.sessions SET selected_membership_id = owner_membership WHERE session_hash = p_hash;
        RETURN QUERY SELECT new_tenant, true;
      END $fn$;
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
