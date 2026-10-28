class DatabaseContext
  def self.assert_runtime!(connection)
    safe = connection.select_value(<<~SQL)
      SELECT current_user = 'advocacia_runtime' AND NOT rolsuper AND NOT rolbypassrls
        AND NOT rolcreaterole AND NOT rolcreatedb AND NOT rolreplication
        AND NOT pg_has_role(current_user, 'advocacia_migrator', 'MEMBER')
      FROM pg_roles WHERE rolname = current_user
    SQL
    raise SecurityError, "The web process requires the isolated advocacia_runtime role" unless safe == true
  end

  def self.with_session(token)
    connection = ApplicationRecord.connection
    connection.clear_query_cache
    assert_runtime!(connection)
    previous_hash = connection.uncached { connection.select_value("SELECT current_setting('app.session_hash', true)") }
    begin
      ApplicationRecord.transaction(requires_new: true) do
        set_session_hash(connection, IdentityStore.digest(token))
        yield
      end
    ensure
      # Rails caches SELECT results by SQL/binds, not by the RLS session GUC.
      # A top-level COMMIT resets PostgreSQL state but not those cached rows.
      connection.clear_query_cache
      # RELEASE SAVEPOINT retains SET LOCAL in its outer transaction. Restore
      # only after release/rollback; a top-level commit/rollback clears it itself.
      set_session_hash(connection, previous_hash.to_s) if connection.transaction_open?
    end
  end

  def self.set_session_hash(connection, value)
    bind = ActiveRecord::Relation::QueryAttribute.new("session_hash", value, ActiveRecord::Type::String.new)
    connection.exec_query("SELECT set_config('app.session_hash', $1, true)", "Session context", [bind])
  end
  private_class_method :set_session_hash
end
