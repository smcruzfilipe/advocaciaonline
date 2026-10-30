require "test_helper"

class TenantIsolationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "actual runtime role is unprivileged and tenant tables force RLS" do
    connection = ApplicationRecord.connection
    role = connection.select_one("SELECT rolname, rolsuper, rolbypassrls, rolcreaterole, rolcreatedb FROM pg_roles WHERE rolname = current_user")
    assert_equal "advocacia_runtime", role.fetch("rolname")
    %w[rolsuper rolbypassrls rolcreaterole rolcreatedb].each { |flag| assert_equal false, role.fetch(flag) }
    %w[tenants lawyers oab_registrations].each do |table|
      flags = connection.select_one("SELECT relrowsecurity, relforcerowsecurity, pg_get_userbyid(relowner) AS owner FROM pg_class WHERE oid = '#{table}'::regclass")
      assert flags.fetch("relrowsecurity")
      assert flags.fetch("relforcerowsecurity")
      assert_not_equal "advocacia_runtime", flags.fetch("owner")
      assert_equal false, connection.select_value("SELECT has_table_privilege(current_user, '#{table}', 'TRUNCATE')")
    end
    assert_raises(ActiveRecord::StatementInvalid) { connection.execute("SELECT * FROM app_private.identities") }
  end

  test "no context fabricated tenant and reused connections fail closed" do
    token_a, = authenticated_session
    token_b, = authenticated_session
    lawyer_a = LawyerOnboarding.call(token: token_a, input: profile_payload)
    lawyer_b = LawyerOnboarding.call(token: token_b, input: profile_payload)
    assert_equal 0, Lawyer.count
    DatabaseContext.with_session(token_a) do
      assert_equal [lawyer_a.id], Lawyer.pluck(:id)
      assert_nil Lawyer.find_by(id: lawyer_b.id)
      ApplicationRecord.connection.execute("SELECT set_config('app.tenant_id', '#{lawyer_b.tenant_id}', true)")
      assert_equal [lawyer_a.id], Lawyer.pluck(:id)
      assert_raises(ActiveRecord::StatementInvalid) do
        ApplicationRecord.transaction(requires_new: true) do
          Lawyer.where(id: lawyer_b.id).update_all(full_name: "intruder")
        end
      end
      failure = assert_raises(ActiveRecord::StatementInvalid) do
        ApplicationRecord.transaction(requires_new: true) do
          OabRegistration.insert_all!([
            { tenant_id: lawyer_b.tenant_id, lawyer_id: lawyer_b.id, number: "999", uf: "SP", primary: false }
          ])
        end
      end
      assert_instance_of PG::InsufficientPrivilege, failure.cause
      assert_match(/row-level security/i, failure.cause.message)
    end
    assert_equal 0, Lawyer.count
    DatabaseContext.with_session(token_b) { assert_equal [lawyer_b.id], Lawyer.pluck(:id) }
    assert_equal 0, Lawyer.count
    assert_raises(RuntimeError) { DatabaseContext.with_session(token_a) { raise "rollback" } }
    assert_equal 0, Lawyer.count
  end

  test "revoked server session loses access immediately" do
    token, = authenticated_session
    LawyerOnboarding.call(token: token, input: profile_payload)
    IdentityStore.revoke(token)
    assert_nil IdentityStore.context(token)
    DatabaseContext.with_session(token) { assert_equal 0, Lawyer.count }
  end
end
