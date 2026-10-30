\set ON_ERROR_STOP on
-- Administrative upgrade, not a Rails migration. Stop the old collection process
-- and concurrent provisioning/migrations before running this in the application DB:
-- psql -X --username=<administrator> --dbname=<application_database> --file=apps/backend/db/rename_despachante.sql
-- Use a PostgreSQL superuser, or an administrator with CREATEROLE, ADMIN OPTION
-- on the old role and ownership of every affected table. Migrator is not sufficient.
--
-- Old role only: rename it in place, retaining its OID, grants, memberships,
-- attributes and settings. SCRAM passwords survive; PostgreSQL clears MD5 passwords
-- on rename, so configure SCRAM externally before upgrading, or reset the credential
-- externally before restarting. This script never reads or supplies passwords.
-- New role only (including fresh provisioning): leave the role unchanged and rename
-- any remaining old-prefixed policies; with no such policies this is a no-op.
-- Both roles or neither role: abort without committing changes. Provision a fresh
-- installation with provision.sql then provision_despachante.sql, not this script.
-- Policy-name collisions or any other error roll back the entire upgrade; no role,
-- policy or application data is dropped/recreated and no grants/expressions change.
-- Role names are cluster-wide, but policies are database-local: run in every
-- application database sharing this role, then switch the process connection login.
-- https://www.postgresql.org/docs/18/sql-alterrole.html
-- https://www.postgresql.org/docs/18/sql-alterpolicy.html
-- https://www.postgresql.org/docs/18/catalog-pg-policy.html

BEGIN;
SET LOCAL search_path = pg_catalog;

DO $upgrade$
DECLARE
  old_role_oid oid;
  new_role_oid oid;
  policy record;
  new_policy_name text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = current_user AND (rolsuper OR rolcreaterole)
  ) THEN
    RAISE EXCEPTION 'Run this script as a PostgreSQL administrator, never advocacia_migrator';
  END IF;

  SELECT oid INTO old_role_oid FROM pg_roles WHERE rolname = 'advocacia_planner';
  SELECT oid INTO new_role_oid FROM pg_roles WHERE rolname = 'advocacia_despachante';

  IF old_role_oid IS NOT NULL AND new_role_oid IS NOT NULL THEN
    RAISE EXCEPTION 'Both advocacia_planner and advocacia_despachante exist; resolve the ambiguous roles before upgrading';
  ELSIF old_role_oid IS NULL AND new_role_oid IS NULL THEN
    RAISE EXCEPTION 'Neither collection role exists; run provision_despachante.sql for a fresh installation';
  END IF;

  IF old_role_oid IS NOT NULL THEN
    ALTER ROLE advocacia_planner RENAME TO advocacia_despachante;
  END IF;

  -- pg_policy.polroles stores role OIDs, so role targets already follow the rename.
  FOR policy IN
    SELECT p.polname::text AS old_name, p.polrelid, n.nspname, c.relname
    FROM pg_policy AS p
    JOIN pg_class AS c ON c.oid = p.polrelid
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE left(p.polname::text, length('collection_planner_')) = 'collection_planner_'
    ORDER BY n.nspname, c.relname, p.polname
  LOOP
    new_policy_name := 'collection_despachante_' ||
      substring(policy.old_name FROM length('collection_planner_') + 1);
    IF octet_length(new_policy_name) > current_setting('max_identifier_length')::integer THEN
      RAISE EXCEPTION 'Renamed policy would exceed PostgreSQL identifier length: %', new_policy_name;
    END IF;
    IF EXISTS (
      SELECT 1 FROM pg_policy
      WHERE polrelid = policy.polrelid AND polname::text = new_policy_name
    ) THEN
      RAISE EXCEPTION 'Both policies % and % exist on %.%; resolve the collision before upgrading',
        policy.old_name, new_policy_name, policy.nspname, policy.relname;
    END IF;
    EXECUTE format('ALTER POLICY %I ON %I.%I RENAME TO %I',
      policy.old_name, policy.nspname, policy.relname, new_policy_name);
  END LOOP;
END $upgrade$;

COMMIT;
