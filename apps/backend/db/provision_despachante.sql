\set ON_ERROR_STOP on
-- Incremental provisioning: run once as the PostgreSQL administrator after provision.sql.
-- Configure the despachante's SCRAM password externally; never give this login to the web process.
CREATE ROLE advocacia_despachante LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS NOINHERIT;
GRANT USAGE ON SCHEMA public TO advocacia_despachante;

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_auth_members WHERE member = 'advocacia_despachante'::regrole)
    OR pg_has_role('advocacia_runtime', 'advocacia_despachante', 'MEMBER')
    OR pg_has_role('advocacia_despachante', 'advocacia_migrator', 'MEMBER') THEN
    RAISE EXCEPTION 'The despachante login must have no role memberships and must remain inaccessible to runtime';
  END IF;
END $guard$;
-- The migration grants only registration SELECT and collection-plan writes, with role-specific RLS.
-- DESPACHANTE_DATABASE_URL belongs only to the trusted despachante process, not the API or ETL.
