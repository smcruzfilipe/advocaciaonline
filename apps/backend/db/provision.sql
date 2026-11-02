\set ON_ERROR_STOP on
-- Execute once as the existing PostgreSQL administrator, in the application database.
-- No passwords are generated or embedded. Configure SCRAM passwords externally.
CREATE ROLE advocacia_migrator LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE advocacia_runtime LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO advocacia_migrator;
GRANT USAGE ON SCHEMA public TO advocacia_runtime;
GRANT CREATE ON DATABASE :"DBNAME" TO advocacia_migrator;
-- Do not grant runtime membership of migrator (including indirect membership).
-- DATABASE_URL connects as runtime; only bin/migrate receives MIGRATION_DATABASE_URL.
