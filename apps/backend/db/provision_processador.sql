\set ON_ERROR_STOP on
-- Incremental provisioning: run once as the PostgreSQL administrator after provision.sql.
-- Configure the processor's SCRAM password externally; never share this login with the API or despachante.
CREATE ROLE advocacia_processador LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT;
GRANT USAGE ON SCHEMA public TO advocacia_processador;

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_auth_members
    WHERE member = 'advocacia_processador'::regrole OR roleid = 'advocacia_processador'::regrole)
    OR pg_has_role('advocacia_processador', 'advocacia_migrator', 'MEMBER')
    OR pg_has_role('advocacia_runtime', 'advocacia_processador', 'MEMBER')
    OR pg_has_role('advocacia_despachante', 'advocacia_processador', 'MEMBER') THEN
    RAISE EXCEPTION 'The processor login must have no memberships or members';
  END IF;
END $guard$;
-- The migration grants only EXECUTE on the fixed processor functions, not direct table access.
-- PROCESSADOR_DATABASE_URL belongs only to the trusted processor and boundary integration tests.
