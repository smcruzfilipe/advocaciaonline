\set ON_ERROR_STOP on
\getenv runtime_password LOCAL_RUNTIME_PASSWORD
\getenv migrator_password LOCAL_MIGRATOR_PASSWORD
ALTER ROLE advocacia_runtime PASSWORD :'runtime_password';
ALTER ROLE advocacia_migrator PASSWORD :'migrator_password';
-- Worker roles exist for migrations but cannot connect without their own credentials.
