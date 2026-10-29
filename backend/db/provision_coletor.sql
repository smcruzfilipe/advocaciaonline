\set ON_ERROR_STOP on
-- Incremental provisioning: run once as the PostgreSQL administrator after provision.sql.
-- Configure the collector's SCRAM password externally; never share this login with the API or despachante.
CREATE ROLE advocacia_coletor LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT;
GRANT USAGE ON SCHEMA public TO advocacia_coletor;

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_auth_members
    WHERE member = 'advocacia_coletor'::regrole OR roleid = 'advocacia_coletor'::regrole)
    OR pg_has_role('advocacia_coletor', 'advocacia_migrator', 'MEMBER')
    OR pg_has_role('advocacia_runtime', 'advocacia_coletor', 'MEMBER')
    OR pg_has_role('advocacia_despachante', 'advocacia_coletor', 'MEMBER') THEN
    RAISE EXCEPTION 'The collector login must have no memberships or members';
  END IF;
END $guard$;
-- The migration grants only EXECUTE on the fixed collector functions, not direct table access.
-- COLETOR_DATABASE_URL belongs only to the future trusted executor and boundary integration tests.
