require "test_helper"
require_relative "../../db/migrate/20261102000004_require_administrative_tenant_authorization"

class TenantCreationAuthorizationTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    https!
    host! URI(AppSettings.origin).host
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    @token = SecureRandom.urlsafe_base64(32)
    @csrf = SecureRandom.urlsafe_base64(32)
    @identity = @admin.exec_params("INSERT INTO app_private.identities(verified_email) VALUES ($1) RETURNING id",
      ["owner-authorization-#{SecureRandom.hex(12)}@example.test"]).getvalue(0, 0)
    @admin.exec_params(<<~SQL, [IdentityStore.digest(@token), @identity, @csrf])
      INSERT INTO app_private.sessions(session_hash, identity_id, csrf_token, expires_at)
      VALUES ($1, $2, $3, clock_timestamp() + interval '1 hour')
    SQL
    cookies[ApplicationController::SESSION_COOKIE] = @token
  end

  teardown do
    if @admin && @identity
      @admin.exec_params("DELETE FROM app_private.first_access_grants WHERE identity_id = $1", [@identity])
      @admin.exec_params("DELETE FROM app_private.sessions WHERE identity_id = $1", [@identity])
      @admin.exec_params("DELETE FROM app_private.identities WHERE id = $1", [@identity])
    end
    @admin&.close
  end

  test "an authenticated identity without an administrative grant cannot claim through SQL, service or HTTP" do
    rolled_back do
      claim = IdentityStore.call("claim_tenant", IdentityStore.digest(@token))
      assert_nil claim.fetch("tenant_id")
      assert_equal false, claim.fetch("claimed")
      assert_raises(LawyerOnboarding::NotAuthorized) { LawyerOnboarding.call(token: @token, input: profile_payload) }
      post "/api/onboarding", params: profile_payload, as: :json,
        headers: { "Origin" => AppSettings.origin, "X-CSRF-Token" => @csrf }
      assert_response :forbidden
      assert_equal "first_access_required", response.parsed_body.fetch("error").fetch("code")
      assert_nil IdentityStore.context(@token).fetch("tenant_id")
      assert_empty IdentityStore.memberships(@token)
    end
  end

  test "an accepted team membership does not authorize a tenant of its own" do
    owner = @admin.exec_params("INSERT INTO app_private.identities(verified_email) VALUES ($1) RETURNING id",
      ["existing-owner-#{SecureRandom.hex(12)}@example.test"]).getvalue(0, 0)
    owner_hash = SecureRandom.hex(32)
    tenant = SecureRandom.uuid
    @admin.transaction do |db|
      db.exec_params("INSERT INTO app_private.sessions(session_hash, identity_id, csrf_token, expires_at) VALUES ($1,$2,'csrf',clock_timestamp()+interval '1 hour')", [owner_hash, owner])
      owner_membership = db.exec_params(<<~SQL, [tenant, owner]).getvalue(0, 0)
        INSERT INTO app_private.tenant_memberships(tenant_id, identity_id, role, accepted_at)
        VALUES ($1,$2,'owner',clock_timestamp()) RETURNING id
      SQL
      db.exec_params("UPDATE app_private.sessions SET selected_membership_id=$1 WHERE session_hash=$2", [owner_membership, owner_hash])
      db.exec_params("SELECT set_config('app.session_hash',$1,true)", [owner_hash])
      db.exec_params("INSERT INTO public.tenants(id,created_at,updated_at) VALUES ($1,clock_timestamp(),clock_timestamp())", [tenant])
      member = db.exec_params(<<~SQL, [tenant, @identity]).getvalue(0, 0)
        INSERT INTO app_private.tenant_memberships(tenant_id, identity_id, role, invited_email, accepted_at)
        VALUES ($1,$2,'member','member@example.test',clock_timestamp()) RETURNING id
      SQL
      db.exec_params("UPDATE app_private.sessions SET selected_membership_id=$1 WHERE identity_id=$2", [member, @identity])
    end

    rolled_back do
      claim = IdentityStore.call("claim_tenant", IdentityStore.digest(@token))
      assert_nil claim.fetch("tenant_id")
      assert_equal false, claim.fetch("claimed")
      assert_raises(LawyerOnboarding::NotAuthorized) { LawyerOnboarding.call(token: @token, input: profile_payload) }
      post "/api/onboarding", params: profile_payload, as: :json,
        headers: { "Origin" => AppSettings.origin, "X-CSRF-Token" => @csrf }
      assert_response :forbidden
      assert_equal tenant, IdentityStore.context(@token).fetch("tenant_id")
      assert_equal "member", IdentityStore.context(@token).fetch("role")
    end
  ensure
    if owner && tenant
      @admin.transaction do |db|
        db.exec_params("SELECT set_config('app.session_hash',$1,true)", [owner_hash])
        db.exec_params("DELETE FROM public.tenants WHERE id=$1", [tenant])
        db.exec_params("UPDATE app_private.sessions SET selected_membership_id=NULL WHERE selected_membership_id IN (SELECT id FROM app_private.tenant_memberships WHERE tenant_id=$1)", [tenant])
        db.exec_params("DELETE FROM app_private.tenant_memberships WHERE tenant_id=$1", [tenant])
        db.exec_params("DELETE FROM app_private.sessions WHERE identity_id=$1", [owner])
        db.exec_params("DELETE FROM app_private.identities WHERE id=$1", [owner])
      end
    end
  end

  test "migration grants only existing owners and preserves their sessions" do
    @admin.exec("BEGIN")
    owner = @admin.exec_params("INSERT INTO app_private.identities(verified_email) VALUES ($1) RETURNING id",
      ["legacy-owner-#{SecureRandom.hex(12)}@example.test"]).getvalue(0, 0)
    owner_hash = SecureRandom.hex(32)
    tenant = SecureRandom.uuid
    @admin.exec_params("INSERT INTO app_private.sessions(session_hash, identity_id, csrf_token, expires_at) VALUES ($1,$2,'legacy-csrf',clock_timestamp()+interval '1 hour')", [owner_hash, owner])
    membership = @admin.exec_params(<<~SQL, [tenant, owner]).getvalue(0, 0)
      INSERT INTO app_private.tenant_memberships(tenant_id, identity_id, role, accepted_at)
      VALUES ($1,$2,'owner',clock_timestamp()) RETURNING id
    SQL
    @admin.exec_params("UPDATE app_private.sessions SET selected_membership_id=$1 WHERE session_hash=$2", [membership, owner_hash])
    @admin.exec_params("SELECT set_config('app.session_hash',$1,true)", [owner_hash])
    @admin.exec_params("INSERT INTO public.tenants(id,created_at,updated_at) VALUES ($1,clock_timestamp(),clock_timestamp())", [tenant])
    @admin.exec_params(<<~SQL, [tenant, @identity])
      INSERT INTO app_private.tenant_memberships(tenant_id, identity_id, role, invited_email, accepted_at)
      VALUES ($1,$2,'member','member@example.test',clock_timestamp())
    SQL
    before = @admin.exec_params("SELECT * FROM app_private.session_context($1)", [owner_hash]).first
    migration = RequireAdministrativeTenantAuthorization.new
    migration.define_singleton_method(:execute) { |sql| @admin_connection.exec(sql) }
    migration.instance_variable_set(:@admin_connection, @admin)
    migration.up
    assert_equal "1", @admin.exec_params("SELECT count(*) FROM app_private.first_access_grants WHERE identity_id=$1", [owner]).getvalue(0, 0)
    assert_equal "0", @admin.exec_params("SELECT count(*) FROM app_private.first_access_grants WHERE identity_id=$1", [@identity]).getvalue(0, 0)
    assert_equal before, @admin.exec_params("SELECT * FROM app_private.session_context($1)", [owner_hash]).first
    assert_equal tenant, before.fetch("tenant_id")
  ensure
    @admin.exec("ROLLBACK")
  end

  test "a granted identity can complete onboarding and cannot claim a second tenant" do
    @admin.exec_params("INSERT INTO app_private.first_access_grants(identity_id) VALUES ($1)", [@identity])
    rolled_back do
      post "/api/onboarding", params: profile_payload, as: :json,
        headers: { "Origin" => AppSettings.origin, "X-CSRF-Token" => @csrf }
      assert_response :created
      tenant = IdentityStore.context(@token).fetch("tenant_id")
      assert tenant
      assert_equal "owner", IdentityStore.context(@token).fetch("role")
      claim = IdentityStore.call("claim_tenant", IdentityStore.digest(@token))
      assert_equal tenant, claim.fetch("tenant_id")
      assert_equal false, claim.fetch("claimed")
      assert_raises(LawyerOnboarding::AlreadyOnboarded) { LawyerOnboarding.call(token: @token, input: profile_payload) }
    end
  end

  private

  def rolled_back
    ApplicationRecord.transaction do
      yield
      raise ActiveRecord::Rollback
    end
  end
end
