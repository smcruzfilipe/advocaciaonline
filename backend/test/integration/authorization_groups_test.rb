require "test_helper"
require "pg"
require "timeout"

class AuthorizationGroupsTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    assert_equal "advocacia_migrator", @admin.exec("SELECT current_user").getvalue(0, 0)
    @admin.exec("SET lock_timeout = '5s'; SET statement_timeout = '10s'")
    @runtime = ApplicationRecord.connection
    @runtime_timeouts = %w[lock_timeout statement_timeout].to_h { |name| [name, @runtime.select_value("SHOW #{name}")] }
    @runtime.execute("SET lock_timeout = '5s'; SET statement_timeout = '10s'")
    @owner, = authenticated_session
    @lawyer = LawyerOnboarding.call(token: @owner, input: profile_payload)
  end

  teardown do
    @runtime_timeouts&.each { |name, value| @runtime.execute("SET #{name} = #{@runtime.quote(value)}") }
  ensure
    @admin&.close
  end

  test "owner administers groups and each rule independently including the agenda catalog" do
    as_owner do
      operations = AuthorizationGroupStore.catalog.map { |entry| entry.fetch("operation") }
      assert_equal %w[cadastrar_compromisso cadastrar_monitoramento cancelar_compromisso consultar_agenda consultar_comunicacoes consultar_dashboard consultar_monitoramentos desativar_monitoramento editar_monitoramento remarcar_compromisso], operations.sort
      assert_empty AuthorizationGroupStore.list_groups
      group = AuthorizationGroupStore.create_group(name: "  Consulta   TJSP  ")
      assert_equal "Consulta TJSP", group.fetch("name")
      assert_empty group.fetch("rules")
      group = AuthorizationGroupStore.create_rule(group_id: group.fetch("id"),
        input: { "operation" => "consultar_comunicacoes", "effect" => "allow", "court" => nil })
      rule = group.fetch("rules").sole
      group = AuthorizationGroupStore.update_rule(group_id: group.fetch("id"), rule_id: rule.fetch("id"),
        input: { "effect" => "deny" })
      assert_equal "deny", group.fetch("rules").sole.fetch("effect")
      group = AuthorizationGroupStore.update_group(group_id: group.fetch("id"), name: "Restrições")
      assert_equal "Restrições", group.fetch("name")
      group = AuthorizationGroupStore.destroy_rule(group_id: group.fetch("id"), rule_id: rule.fetch("id"))
      assert_empty group.fetch("rules")
      assert_equal [group], AuthorizationGroupStore.list_groups
      AuthorizationGroupStore.destroy_group(group_id: group.fetch("id"))
      assert_empty AuthorizationGroupStore.list_groups
    end
  end

  test "session rules preserve empty groups and removing the last association restores the no group state" do
    member, membership = member_session
    group = as_owner { AuthorizationGroupStore.create_group(name: "Sem concessões") }
    assert_equal [], session_rules(member)
    as_owner { AuthorizationGroupStore.assign_membership_group(membership_id: membership, group_id: group.fetch("id")) }
    assert_equal [[]], session_rules(member)
    assert_not AuthorizationPolicy.allowed?(owner: false, groups: session_rules(member), operation: "consultar_monitoramentos")
    as_owner { AuthorizationGroupStore.remove_membership_group(membership_id: membership, group_id: group.fetch("id")) }
    assert_equal [], session_rules(member)
    assert AuthorizationPolicy.allowed?(owner: false, groups: session_rules(member), operation: "consultar_monitoramentos")
  end

  test "concessions add across groups and an explicit deny wins for the same operation and scope" do
    member, membership = member_session
    CourtCatalog.stub(:fetch, [{ code: "TJSP", name: "São Paulo" }, { code: "TJRJ", name: "Rio de Janeiro" }]) do
      as_owner do
        [["TJSP", "allow"], ["TJRJ", "allow"], ["TJRJ", "deny"]].each do |court, effect|
          group = AuthorizationGroupStore.create_group(name: "#{court} #{effect}")
          AuthorizationGroupStore.create_rule(group_id: group.fetch("id"), input: {
            "operation" => "consultar_comunicacoes", "effect" => effect, "court" => court
          })
          AuthorizationGroupStore.assign_membership_group(membership_id: membership, group_id: group.fetch("id"))
        end
      end
    end
    rules = session_rules(member)
    assert_equal 3, rules.length
    assert rules.flatten.all? { |rule| rule.keys.sort == %w[court effect operation] }
    assert AuthorizationPolicy.allowed?(owner: false, groups: rules, operation: "consultar_comunicacoes", court: "TJSP")
    assert_not AuthorizationPolicy.allowed?(owner: false, groups: rules, operation: "consultar_comunicacoes", court: "TJRJ")
    assert_not AuthorizationPolicy.allowed?(owner: false, groups: rules, operation: "consultar_dashboard")
  end

  test "pending memberships receive groups before acceptance but revoked memberships do not" do
    pending = @admin.exec_params(<<~SQL, [@lawyer.tenant_id, "pending@example.test"]).getvalue(0, 0)
      INSERT INTO app_private.tenant_memberships(tenant_id, role, invited_email, credential_started_at)
      VALUES ($1, 'member', $2, clock_timestamp()) RETURNING id
    SQL
    group = as_owner { AuthorizationGroupStore.create_group(name: "Convite restrito") }
    assigned = as_owner { AuthorizationGroupStore.assign_membership_group(membership_id: pending, group_id: group.fetch("id")) }
    assert_equal [pending], assigned.fetch("membership_ids")
    assert_equal assigned, as_owner { AuthorizationGroupStore.assign_membership_group(membership_id: pending, group_id: group.fetch("id")) }
    assert_not ApplicationRecord.connection.transaction_open?, "Release the runtime membership lock before the administrative fixture update"
    @admin.exec_params("UPDATE app_private.tenant_memberships SET revoked_at = clock_timestamp() WHERE id = $1", [pending])
    assert_raises(AuthorizationGroupStore::NotFound) do
      as_owner { AuthorizationGroupStore.assign_membership_group(membership_id: pending, group_id: group.fetch("id")) }
    end
  end

  test "another tenant cannot read mutate or assign a group and a member cannot administer any group" do
    member, membership = member_session
    group = as_owner { AuthorizationGroupStore.create_group(name: "Privado") }
    other_owner, = authenticated_session
    LawyerOnboarding.call(token: other_owner, input: profile_payload)
    DatabaseContext.with_session(other_owner) do
      assert_empty AuthorizationGroupStore.list_groups
      [:find_group, :destroy_group].each do |method|
        assert_raises(AuthorizationGroupStore::NotFound) { AuthorizationGroupStore.public_send(method, group_id: group.fetch("id")) }
      end
      assert_raises(AuthorizationGroupStore::NotFound) do
        AuthorizationGroupStore.assign_membership_group(membership_id: membership, group_id: group.fetch("id"))
      end
      other_group = AuthorizationGroupStore.create_group(name: "Outro")
      assert_raises(AuthorizationGroupStore::NotFound) do
        AuthorizationGroupStore.assign_membership_group(membership_id: membership, group_id: other_group.fetch("id"))
      end
    end
    DatabaseContext.with_session(member) do
      assert_raises(AuthorizationGroupStore::Forbidden) { AuthorizationGroupStore.list_groups }
      assert_raises(AuthorizationGroupStore::Forbidden) { AuthorizationGroupStore.create_group(name: "Escalada") }
      assert_raises(AuthorizationGroupStore::Forbidden) do
        AuthorizationGroupStore.assign_membership_group(membership_id: membership, group_id: group.fetch("id"))
      end
    end
    assert_equal [group], as_owner { AuthorizationGroupStore.list_groups }
  end

  test "unknown operations invalid effects and tribunal scopes on tenant operations are rejected without mutation" do
    as_owner do
      group = AuthorizationGroupStore.create_group(name: "Validação")
      [
        { "operation" => "administrar_usuarios", "effect" => "allow" },
        { "operation" => "consultar_agenda", "effect" => "ALLOW" },
        { "operation" => "consultar_agenda", "effect" => "allow", "court" => "TJSP" },
        { "operation" => "consultar_comunicacoes", "effect" => "allow", "court" => "*" },
        { "operation" => "consultar_dashboard", "effect" => "allow", "tenant_id" => @lawyer.tenant_id }
      ].each do |input|
        assert_raises(AuthorizationGroupStore::InvalidInput) { AuthorizationGroupStore.create_rule(group_id: group.fetch("id"), input: input) }
      end
      assert_empty AuthorizationGroupStore.find_group(group_id: group.fetch("id")).fetch("rules")
      assert_raises(AuthorizationGroupStore::InvalidInput) { AuthorizationGroupStore.create_group(name: " \t ") }
      assert_raises(AuthorizationGroupStore::InvalidInput) { AuthorizationGroupStore.create_group(name: "x" * 121) }
    end
  end

  test "database rejects malformed rules and forged tenant payloads even without Ruby validation" do
    group = as_owner { AuthorizationGroupStore.create_group(name: "Fronteira SQL") }
    PG.connect(ENV.fetch("DATABASE_URL")) do |runtime|
      runtime.exec("SET lock_timeout = '5s'; SET statement_timeout = '10s'")
      [
        { operation: "administrar_usuarios", effect: "allow" },
        { operation: "consultar_agenda", effect: false },
        { operation: "consultar_agenda", effect: "allow", court: "TJSP" },
        { operation: "consultar_comunicacoes", effect: "allow", court: ["TJSP"] },
        { operation: "consultar_agenda", effect: "allow", tenant_id: @lawyer.tenant_id }
      ].each do |input|
        error = assert_raises(PG::InvalidParameterValue) do
          runtime.transaction do
            runtime.exec_params("SELECT set_config('app.session_hash', $1, true)", [IdentityStore.digest(@owner)])
            runtime.exec_params("SELECT app_private.manage_authorization_groups($1, $2, $3::jsonb)",
              ["create_rule", group.fetch("id"), JSON.generate(input)])
          end
        end
        assert_equal "22023", error.result.error_field(PG::Result::PG_DIAG_SQLSTATE)
      end
    end
    assert_empty as_owner { AuthorizationGroupStore.find_group(group_id: group.fetch("id")) }.fetch("rules")
  end

  test "deleting the last assigned group removes its rules and restores the approved no group default" do
    member, membership = member_session
    group = as_owner do
      created = AuthorizationGroupStore.create_group(name: "Agenda")
      AuthorizationGroupStore.create_rule(group_id: created.fetch("id"), input: {
        "operation" => "consultar_agenda", "effect" => "allow"
      })
      AuthorizationGroupStore.assign_membership_group(membership_id: membership, group_id: created.fetch("id"))
    end
    assert AuthorizationPolicy.allowed?(owner: false, groups: session_rules(member), operation: "consultar_agenda")
    as_owner { AuthorizationGroupStore.destroy_group(group_id: group.fetch("id")) }
    assert_equal [], session_rules(member)
    assert AuthorizationPolicy.allowed?(owner: false, groups: session_rules(member), operation: "consultar_monitoramentos")
    assert_not AuthorizationPolicy.allowed?(owner: false, groups: session_rules(member), operation: "consultar_agenda")
  end

  test "invalid revoked and expired contexts fail closed rather than returning the no group default" do
    member, membership = member_session
    group = as_owner { AuthorizationGroupStore.create_group(name: "Restrito") }
    as_owner { AuthorizationGroupStore.assign_membership_group(membership_id: membership, group_id: group.fetch("id")) }
    @admin.exec_params("UPDATE app_private.tenant_memberships SET expires_at = clock_timestamp() - interval '1 second' WHERE id = $1", [membership])
    assert_raises(AuthorizationGroupStore::Forbidden) { session_rules(member) }
    @admin.exec_params("UPDATE app_private.tenant_memberships SET expires_at = NULL, revoked_at = clock_timestamp() WHERE id = $1", [membership])
    assert_raises(AuthorizationGroupStore::Forbidden) { session_rules(member) }
    assert_raises(AuthorizationGroupStore::Forbidden) { session_rules(SecureRandom.urlsafe_base64(32)) }
  end

  test "even the no group decision holds a shared tenant lock until the protected transaction ends" do
    member, membership = member_session
    group = as_owner { AuthorizationGroupStore.create_group(name: "Nova restrição") }
    with_runtime_transaction(member) do |reader|
      assert_equal [], JSON.parse(reader.exec("SELECT app_private.session_group_rules()").getvalue(0, 0))
      result = while_runtime_blocked(reader, @owner,
        "SELECT app_private.manage_authorization_groups('assign_membership', $1, $2::jsonb)",
        [group.fetch("id"), JSON.generate(membership_id: membership)]) do
        reader.exec("COMMIT")
      end
      assert_equal [membership], JSON.parse(result).fetch("membership_ids")
    end
    assert_equal [[]], session_rules(member)
  end

  test "a rules reader waiting for administration observes the committed denial rather than the old grant" do
    member, membership = member_session
    group = as_owner do
      created = AuthorizationGroupStore.create_group(name: "Agenda concorrente")
      AuthorizationGroupStore.create_rule(group_id: created.fetch("id"), input: {
        "operation" => "consultar_agenda", "effect" => "allow"
      })
      AuthorizationGroupStore.assign_membership_group(membership_id: membership, group_id: created.fetch("id"))
    end
    with_runtime_transaction(@owner) do |writer|
      writer.exec_params("SELECT app_private.manage_authorization_groups('update_rule', $1, $2::jsonb)",
        [group.fetch("id"), JSON.generate(rule_id: group.fetch("rules").sole.fetch("id"), effect: "deny")])
      result = while_runtime_blocked(writer, member, "SELECT app_private.session_group_rules()") { writer.exec("COMMIT") }
      rules = JSON.parse(result)
      assert_equal "deny", rules.sole.sole.fetch("effect")
      assert_not AuthorizationPolicy.allowed?(owner: false, groups: rules, operation: "consultar_agenda")
    end
  end

  test "membership revoked during a tenant lock wait is denied instead of receiving the no groups default" do
    member, membership = member_session
    with_runtime_transaction(@owner) do |writer|
      writer.exec_params("SELECT app_private.revoke_team_credential($1::text)", [membership])
      result = while_runtime_blocked(writer, member, "SELECT app_private.session_group_rules()") { writer.exec("COMMIT") }
      assert_instance_of PG::InsufficientPrivilege, result
      assert_equal "42501", result.result.error_field(PG::Result::PG_DIAG_SQLSTATE)
    end
  end

  test "context selection changed during a tenant lock wait is denied" do
    member, = member_session
    with_runtime_transaction(@owner) do |writer|
      writer.exec("SELECT app_private.lock_authorization(true)")
      result = while_runtime_blocked(writer, member, "SELECT app_private.session_group_rules()") do
        @admin.exec_params("UPDATE app_private.sessions SET selected_membership_id = NULL WHERE session_hash = $1",
          [IdentityStore.digest(member)])
        writer.exec("COMMIT")
      end
      assert_instance_of PG::InsufficientPrivilege, result
      assert_equal "42501", result.result.error_field(PG::Result::PG_DIAG_SQLSTATE)
    end
  end

  test "session expired during a tenant lock wait is denied" do
    member, = member_session
    with_runtime_transaction(@owner) do |writer|
      writer.exec("SELECT app_private.lock_authorization(true)")
      result = while_runtime_blocked(writer, member, "SELECT app_private.session_group_rules()") do
        @admin.exec_params("UPDATE app_private.sessions SET expires_at = clock_timestamp() - interval '1 second' WHERE session_hash = $1",
          [IdentityStore.digest(member)])
        writer.exec("COMMIT")
      end
      assert_instance_of PG::InsufficientPrivilege, result
      assert_equal "42501", result.result.error_field(PG::Result::PG_DIAG_SQLSTATE)
    end
  end

  test "runtime has no direct table access and only narrow definers with fixed search paths" do
    connection = ApplicationRecord.connection
    %w[authorization_groups authorization_group_rules authorization_group_memberships].each do |table|
      %w[SELECT INSERT UPDATE DELETE TRUNCATE].each do |privilege|
        assert_equal false, connection.select_value("SELECT has_table_privilege(current_user, 'app_private.#{table}', '#{privilege}')")
      end
      flags = connection.select_one("SELECT relrowsecurity, relforcerowsecurity FROM pg_class WHERE oid = 'app_private.#{table}'::regclass")
      assert_equal true, flags.fetch("relrowsecurity")
      assert_equal true, flags.fetch("relforcerowsecurity")
      assert_raises(ActiveRecord::StatementInvalid) { connection.execute("SELECT * FROM app_private.#{table}") }
    end
    %w[manage_authorization_groups session_group_rules].each do |name|
      function = connection.select_one(<<~SQL)
        SELECT prosecdef, proconfig::text, pg_get_userbyid(proowner) AS owner,
          EXISTS (SELECT 1 FROM aclexplode(COALESCE(proacl, acldefault('f', proowner))) WHERE grantee = 0 AND privilege_type = 'EXECUTE') AS public_execute
        FROM pg_proc JOIN pg_namespace ON pg_namespace.oid = pronamespace
        WHERE nspname = 'app_private' AND proname = '#{name}'
      SQL
      assert_equal true, function.fetch("prosecdef")
      assert_equal "advocacia_migrator", function.fetch("owner")
      assert_equal false, function.fetch("public_execute")
      assert_includes function.fetch("proconfig"), "search_path=pg_catalog, pg_temp"
    end
  end

  private

  def as_owner(&block)
    DatabaseContext.with_session(@owner, &block)
  end

  def session_rules(token)
    DatabaseContext.with_session(token) { AuthorizationGroupStore.session_group_rules }
  end

  def with_runtime_transaction(token)
    connection = PG.connect(ENV.fetch("DATABASE_URL"))
    connection.exec("SET lock_timeout = '5s'; SET statement_timeout = '10s'")
    connection.exec("BEGIN")
    connection.exec_params("SELECT set_config('app.session_hash', $1, true)", [IdentityStore.digest(token)])
    yield connection
  ensure
    connection.exec("ROLLBACK") if connection && connection.transaction_status != PG::PQTRANS_IDLE
    connection&.close
  end

  def while_runtime_blocked(blocker, token, sql, values = [])
    pid = Queue.new
    worker = Thread.new do
      Thread.current.report_on_exception = false
      begin
        with_runtime_transaction(token) do |connection|
          pid << connection.backend_pid
          result = connection.exec_params(sql, values).getvalue(0, 0)
          connection.exec("COMMIT")
          result
        end
      rescue PG::Error => error
        error
      end
    end
    Timeout.timeout(15) do
      blocked_pid = pid.pop
      loop do
        blocked = @admin.exec_params("SELECT $1::integer = ANY(pg_blocking_pids($2::integer))",
          [blocker.backend_pid, blocked_pid]).getvalue(0, 0)
        break if blocked == "t"
        Thread.pass
      end
      yield
      worker.value
    end
  ensure
    worker&.kill if worker&.alive?
    raise Timeout::Error, "Authorization worker did not stop" if worker && !worker.join(5)
  end

  def member_session
    token, = authenticated_session
    identity = IdentityStore.context(token).fetch("identity_id")
    membership = @admin.exec_params(<<~SQL, [@lawyer.tenant_id, identity, "#{identity}@example.test"]).getvalue(0, 0)
      INSERT INTO app_private.tenant_memberships(tenant_id, identity_id, role, invited_email, accepted_at, credential_started_at)
      VALUES ($1, $2, 'member', $3, clock_timestamp(), clock_timestamp()) RETURNING id
    SQL
    @admin.exec_params("UPDATE app_private.sessions SET selected_membership_id = $1 WHERE session_hash = $2", [membership, IdentityStore.digest(token)])
    [token, membership]
  end
end
