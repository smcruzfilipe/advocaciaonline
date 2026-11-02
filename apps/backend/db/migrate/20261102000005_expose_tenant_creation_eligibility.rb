class ExposeTenantCreationEligibility < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE FUNCTION app_private.can_create_tenant(p_session text)
      RETURNS TABLE(allowed boolean)
      LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = pg_catalog, app_private, pg_temp AS $fn$
        SELECT EXISTS (
          SELECT 1 FROM app_private.session_identity(p_session) s
          JOIN app_private.password_credentials c ON c.identity_id = s.identity_id AND c.totp_confirmed
          JOIN app_private.first_access_grants g ON g.identity_id = s.identity_id
          WHERE NOT EXISTS (
            SELECT 1 FROM app_private.tenant_memberships m
            WHERE m.identity_id = s.identity_id AND m.role = 'owner'
          )
        )
      $fn$;
      REVOKE ALL ON FUNCTION app_private.can_create_tenant(text) FROM PUBLIC;
      GRANT EXECUTE ON FUNCTION app_private.can_create_tenant(text) TO advocacia_runtime;
    SQL
  end

  def down
    execute "DROP FUNCTION app_private.can_create_tenant(text)"
  end
end
