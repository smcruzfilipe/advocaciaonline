require "test_helper"

class SessionValidityTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  def administer
    # Fixture control only: the assertions and all application requests still use
    # DATABASE_URL / advocacia_runtime. Never give this URL to the web container.
    connection = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    assert_equal "advocacia_migrator", connection.exec("SELECT current_user").getvalue(0, 0)
    yield connection
  ensure
    connection&.close
  end

  test "session expires at its exact server-side deadline without granting a tenant" do
    token, = authenticated_session
    LawyerOnboarding.call(token: token, input: profile_payload)
    administer do |connection|
      connection.exec_params("UPDATE app_private.sessions SET expires_at = statement_timestamp() WHERE session_hash = $1", [IdentityStore.digest(token)])
      assert_equal "1", connection.exec_params("SELECT count(*) FROM app_private.sessions WHERE session_hash = $1", [IdentityStore.digest(token)]).getvalue(0, 0)
    end
    assert_nil IdentityStore.context(token)
    DatabaseContext.with_session(token) { assert_equal 0, Lawyer.count }
  end

  test "disabled identity invalidates an already open session" do
    token, = authenticated_session
    LawyerOnboarding.call(token: token, input: profile_payload)
    administer do |connection|
      connection.exec_params(<<~SQL, [IdentityStore.digest(token)])
        UPDATE app_private.identities SET disabled_at = statement_timestamp()
        WHERE id = (SELECT identity_id FROM app_private.sessions WHERE session_hash = $1)
      SQL
    end
    assert_nil IdentityStore.context(token)
    DatabaseContext.with_session(token) { assert_equal 0, Lawyer.count }
  end

  test "concurrent onboarding creates exactly one complete lawyer tenant" do
    token, = authenticated_session
    input = profile_payload
    ready = Queue.new
    start = Queue.new
    threads = 2.times.map do
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          ready << true
          start.pop
          begin
            LawyerOnboarding.call(token: token, input: input)
          rescue LawyerOnboarding::AlreadyOnboarded => error
            error
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    results = threads.map(&:value)
    assert_equal 1, results.count { |result| result.is_a?(Lawyer) }
    assert_equal 1, results.count { |result| result.is_a?(LawyerOnboarding::AlreadyOnboarded) }
    DatabaseContext.with_session(token) do
      assert_equal 1, Tenant.count
      assert_equal 1, Lawyer.count
      assert_equal 2, OabRegistration.count
    end
  end
end
