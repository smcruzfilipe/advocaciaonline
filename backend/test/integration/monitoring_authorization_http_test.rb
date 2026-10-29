require "test_helper"
require "pg"
require "timeout"

class MonitoringAuthorizationHttpTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    https!
    host! URI(AppSettings.origin).host
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    assert_equal "advocacia_migrator", @admin.exec("SELECT current_user").getvalue(0, 0)
    assert_equal "advocacia_runtime", ApplicationRecord.connection.select_value("SELECT current_user")
    @owner, @owner_csrf = authenticated_session
    @lawyer = LawyerOnboarding.call(token: @owner, input: profile_payload)
    @member, @csrf = authenticated_session
    identity = IdentityStore.context(@member).fetch("identity_id")
    @membership = @admin.exec_params(<<~SQL, [@lawyer.tenant_id, identity]).getvalue(0, 0)
      INSERT INTO app_private.tenant_memberships(tenant_id, identity_id, role, invited_email, accepted_at, credential_started_at)
      VALUES ($1, $2, 'member', 'member@example.test', clock_timestamp(), clock_timestamp()) RETURNING id
    SQL
    @admin.exec_params("UPDATE app_private.sessions SET selected_membership_id = $1 WHERE session_hash = $2",
      [@membership, IdentityStore.digest(@member)])
    DatabaseContext.with_session(@owner) do
      @party = PartyMonitoring.create!(tenant_id: @lawyer.tenant_id, name: "Parte original")
      @process = ProcessMonitoring.create!(tenant_id: @lawyer.tenant_id, number: "00012345620248010001")
    end
    cookies[ApplicationController::SESSION_COOKIE] = @member
  end

  teardown { @admin&.close }

  test "a member without groups reads all monitoring configurations but cannot write" do
    get "/api/monitorings/parties"
    assert_response :ok
    assert_equal [@party.id], response.parsed_body.fetch("parties").map { |party| party.fetch("id") }
    get "/api/monitorings/parties/#{@party.id}"
    assert_response :ok
    get "/api/monitorings/processes"
    assert_response :ok
    assert_equal [@process.id], response.parsed_body.fetch("processes").map { |process| process.fetch("id") }
    get "/api/monitorings/processes/#{@process.id}"
    assert_response :ok
    get "/api/monitorings/lawyer"
    assert_response :ok
    assert_equal @lawyer.id, response.parsed_body.fetch("id")

    monitoring_inputs.each do |path, input|
      post path, params: input, as: :json, headers: write_headers
      assert_permission_denied
    end
    monitoring_records.each do |path, _record, field, value|
      [{ field => value }, { active: false }, { field => value, active: false }, {}].each do |input|
        patch path, params: input, as: :json, headers: write_headers
        assert_permission_denied
      end
    end
    assert_original_records
  end

  test "an assigned empty group removes default monitoring reads without granting access through the public catalog" do
    assign_group
    monitoring_read_paths.each do |path|
      get path
      assert_permission_denied
    end
    CourtCatalog.stub(:fetch, [{ code: "TJAC", name: "Acre" }]) do
      get "/api/courts"
      assert_response :ok
      assert_equal({ "courts" => [{ "code" => "TJAC", "name" => "Acre" }] }, response.parsed_body)
    end
    get "/api/monitorings/parties"
    assert_permission_denied
  end

  test "monitoring consultation is tenant-wide even when communications are denied in a tribunal" do
    CourtCatalog.stub(:fetch, [{ code: "TJAC", name: "Acre" }]) do
      assign_group(allow_rule("consultar_monitoramentos"),
        { "operation" => "consultar_comunicacoes", "effect" => "deny", "court" => "TJAC" })
    end
    DatabaseContext.with_session(@owner) do
      @party.update!(courts: ["TJAC"])
      @process.update!(courts: ["TJAC"])
    end
    monitoring_read_paths.each do |path|
      get path
      assert_response :ok
    end
  end

  test "an explicit consultation deny across groups wins over an allow" do
    assign_group(allow_rule("consultar_monitoramentos"))
    assign_group({ "operation" => "consultar_monitoramentos", "effect" => "deny", "court" => nil })
    monitoring_read_paths.each do |path|
      get path
      assert_permission_denied
    end
  end

  test "create permission grants creation but not consultation edit or deactivation" do
    assign_group(allow_rule("cadastrar_monitoramento"))
    monitoring_inputs.each do |path, input|
      post path, params: input, as: :json, headers: write_headers
      assert_response :created
      assert_equal @lawyer.tenant_id, response.parsed_body.fetch("tenant_id")
      get "#{path}/#{response.parsed_body.fetch('id')}"
      assert_permission_denied
    end
    monitoring_records.each do |path, _record, field, value|
      [{ field => value }, { active: false }].each do |input|
        patch path, params: input, as: :json, headers: write_headers
        assert_permission_denied
      end
    end
    assert_original_records
  end

  test "edit permission authorizes data and reactivation but never deactivation or a mixed false patch" do
    assign_group(allow_rule("editar_monitoramento"))
    monitoring_records.each do |path, record, field, value|
      patch path, params: { field => value, active: false }, as: :json, headers: write_headers
      assert_permission_denied
      DatabaseContext.with_session(@owner) do
        record.reload
        assert record.active
        assert_not_equal value, record.public_send(field)
      end
      patch path, params: { active: false }, as: :json, headers: write_headers
      assert_permission_denied
      patch path, params: { field => value }, as: :json, headers: write_headers
      assert_response :ok
      assert_equal({ "id" => record.id }, response.parsed_body)
      DatabaseContext.with_session(@owner) do
        assert_equal value, record.reload.public_send(field)
        record.update!(active: false)
      end
      patch path, params: { active: true }, as: :json, headers: write_headers
      assert_response :ok
      assert_equal({ "id" => record.id }, response.parsed_body)
      DatabaseContext.with_session(@owner) { assert record.reload.active }
    end
  end

  test "deactivation permission cannot reactivate or edit data and does not expose monitoring details" do
    assign_group(allow_rule("desativar_monitoramento"))
    monitoring_records.each do |path, record, field, value|
      patch path, params: { field => value, active: false }, as: :json, headers: write_headers
      assert_permission_denied
      DatabaseContext.with_session(@owner) { assert record.reload.active }
      patch path, params: { field => value }, as: :json, headers: write_headers
      assert_permission_denied
      patch path, params: { active: false }, as: :json, headers: write_headers
      assert_response :ok
      assert_equal({ "id" => record.id }, response.parsed_body)
      DatabaseContext.with_session(@owner) { assert_not record.reload.active }
      patch path, params: { active: true }, as: :json, headers: write_headers
      assert_permission_denied
      DatabaseContext.with_session(@owner) { assert_not record.reload.active }
    end
  end

  test "independent groups can jointly authorize both parts of a mixed patch" do
    assign_group(allow_rule("editar_monitoramento"))
    assign_group(allow_rule("desativar_monitoramento"))
    monitoring_records.each do |path, record, field, value|
      patch path, params: { field => value, active: false }, as: :json, headers: write_headers
      assert_response :ok
      assert_equal({ "id" => record.id }, response.parsed_body)
      DatabaseContext.with_session(@owner) do
        assert_equal value, record.reload.public_send(field)
        assert_not record.active
      end
    end
  end

  test "a permitted consultation preserves the complete monitoring PATCH response" do
    assign_group(*%w[consultar_monitoramentos editar_monitoramento desativar_monitoramento].map { |operation| allow_rule(operation) })
    monitoring_records.each do |path, record, field, value|
      patch path, params: { field => value, active: false }, as: :json, headers: write_headers
      assert_response :ok
      assert_equal record.id, response.parsed_body.fetch("id")
      assert_equal @lawyer.tenant_id, response.parsed_body.fetch("tenant_id")
      assert_equal value, response.parsed_body.fetch(field.to_s)
      assert_equal false, response.parsed_body.fetch("active")
      patch path, params: { active: true }, as: :json, headers: write_headers
      assert_response :ok
      assert_equal true, response.parsed_body.fetch("active")
    end
  end

  test "the owner is independent of groups including explicit denies" do
    membership = IdentityStore.context(@owner).fetch("membership_id")
    rules = %w[consultar_monitoramentos cadastrar_monitoramento editar_monitoramento desativar_monitoramento].map do |operation|
      { "operation" => operation, "effect" => "deny", "court" => nil }
    end
    assign_group(*rules, membership: membership)
    cookies[ApplicationController::SESSION_COOKIE] = @owner
    monitoring_read_paths.each do |path|
      get path
      assert_response :ok
    end
    monitoring_inputs.each do |path, input|
      post path, params: input, as: :json, headers: write_headers(@owner_csrf)
      assert_response :created
    end
    monitoring_records.each do |path, _record, field, value|
      patch path, params: { field => value, active: false }, as: :json, headers: write_headers(@owner_csrf)
      assert_response :ok
    end
    get "/api/onboarding"
    assert_response :ok
    get "/api/collection-runs"
    assert_response :ok
  end

  test "monitoring grants do not expose owner profile collection criteria events or execution states" do
    assign_group(*%w[consultar_monitoramentos cadastrar_monitoramento editar_monitoramento desativar_monitoramento].map { |operation| allow_rule(operation) })
    run = SecureRandom.uuid
    ["/api/onboarding", "/api/collection-runs", "/api/collection-runs/#{run}/jobs",
      "/api/collection-runs/#{run}/events", "/api/collection-runs/#{run}/execution"].each do |path|
      get path
      assert_permission_denied
    end
  end

  test "monitoring permission never changes the tenant selected by the verified membership" do
    other, = authenticated_session
    lawyer = LawyerOnboarding.call(token: other, input: profile_payload)
    other_party = DatabaseContext.with_session(other) do
      PartyMonitoring.create!(tenant_id: lawyer.tenant_id, name: "Outra parte")
    end
    assign_group(allow_rule("consultar_monitoramentos"), allow_rule("editar_monitoramento"))
    get "/api/monitorings/parties", params: { tenant_id: lawyer.tenant_id }
    assert_response :ok
    assert_equal [@party.id], response.parsed_body.fetch("parties").map { |party| party.fetch("id") }
    get "/api/monitorings/parties/#{other_party.id}", params: { tenant_id: lawyer.tenant_id }
    assert_response :not_found
    patch "/api/monitorings/parties/#{other_party.id}", params: { name: "Intrusão", tenant_id: lawyer.tenant_id },
      as: :json, headers: write_headers
    assert_response :not_found
    DatabaseContext.with_session(other) { assert_equal "Outra parte", other_party.reload.name }
  end

  test "revocation after authentication cannot reuse the memoized context as authorization" do
    with_membership_revoked_after_context_read(1) do
      get "/api/monitorings/parties"
      assert_permission_denied
    end
  end

  test "revocation during a previously permitted write prevents any data or active change" do
    assign_group(allow_rule("editar_monitoramento"), allow_rule("desativar_monitoramento"))
    with_membership_revoked_after_context_read(1) do
      patch "/api/monitorings/parties/#{@party.id}", params: { name: "Intrusão", active: false },
        as: :json, headers: write_headers
      assert_permission_denied
    end
    assert_original_records
  end

  test "revocation between fresh context and group resolution returns forbidden rather than a database failure" do
    with_membership_revoked_after_context_read(2) do
      get "/api/monitorings/processes"
      assert_permission_denied
    end
  end

  test "incomplete fresh contexts never authorize owner or member operations" do
    original = IdentityStore.method(:context)
    %w[identity_id tenant_id membership_id role].each do |missing|
      reads = 0
      context = lambda do |token|
        value = original.call(token)
        reads += 1
        reads == 2 ? value.except(missing) : value
      end
      IdentityStore.stub(:context, context) do
        get "/api/monitorings/parties"
        assert_permission_denied
      end
    end
  end

  test "monitoring grants preserve origin and CSRF validation" do
    assign_group(allow_rule("cadastrar_monitoramento"), allow_rule("editar_monitoramento"), allow_rule("desativar_monitoramento"))
    [write_headers.merge("Origin" => "https://attacker.test"),
      write_headers.merge("X-CSRF-Token" => SecureRandom.urlsafe_base64(32))].each do |headers|
      post "/api/monitorings/parties", params: { name: "Não autorizado" }, as: :json, headers: headers
      assert_response :forbidden
      assert_equal "invalid_csrf", response.parsed_body.dig("error", "code")
      patch "/api/monitorings/parties/#{@party.id}", params: { name: "Intrusão", active: false }, as: :json, headers: headers
      assert_response :forbidden
      assert_equal "invalid_csrf", response.parsed_body.dig("error", "code")
    end
    assert_original_records
  end

  test "court catalog remains available to an authenticated identity before onboarding without granting tenant access" do
    token, = authenticated_session
    cookies[ApplicationController::SESSION_COOKIE] = token
    CourtCatalog.stub(:fetch, [{ code: "TJAC", name: "Acre" }]) do
      get "/api/courts", params: { tenant_id: @lawyer.tenant_id }
      assert_response :ok
      assert_equal ["courts"], response.parsed_body.keys
    end
    get "/api/monitorings/parties"
    assert_response :not_found
    assert_equal "onboarding_required", response.parsed_body.dig("error", "code")
  end

  %i[party process].each do |kind|
    test "#{kind} PATCH revalidates a deadline after waiting for the monitoring row lock" do
      assign_group(allow_rule("editar_monitoramento"))
      record = instance_variable_get("@#{kind}")
      _path, _record, field, value = monitoring_records.find { |entry| entry[1] == record }
      client = with_locked_monitoring(record, { field => value }) do
        # Fixture clock control bypasses administrative locks to model natural expiration.
        expire_membership
      end
      assert_permission_denied(client.response)
      assert_original_records
    end

    test "#{kind} PATCH rolls back when its deadline passes during UPDATE" do
      assign_group(allow_rule("editar_monitoramento"))
      record = instance_variable_get("@#{kind}")
      path, _record, field, value = monitoring_records.find { |entry| entry[1] == record }
      with_deadline_after_write(record, "UPDATE") do
        patch path, params: { field => value }, as: :json, headers: write_headers
        assert_permission_denied
      end
      assert_original_records
    end

    test "#{kind} creation rolls back when its deadline passes during INSERT" do
      assign_group(allow_rule("cadastrar_monitoramento"))
      record = instance_variable_get("@#{kind}")
      path, input = monitoring_inputs[kind == :party ? 0 : 1]
      before_count = DatabaseContext.with_session(@owner) { record.class.count }
      with_deadline_after_write(record, "INSERT") do
        post path, params: input, as: :json, headers: write_headers
        assert_permission_denied
      end
      DatabaseContext.with_session(@owner) { assert_equal before_count, record.class.count }
    end
  end

  test "group changes serialize after an authorized PATCH until its transaction commits" do
    group = assign_group(allow_rule("editar_monitoramento"))
    ready = Queue.new
    policy_worker = nil
    client = with_locked_monitoring(@party, { name: "Alteração autorizada" }) do |request_pid|
      policy_worker = Thread.new do
        ApplicationRecord.connection_pool.with_connection do |connection|
          ready << connection.select_value("SELECT pg_backend_pid()")
          DatabaseContext.with_session(@owner) do
            AuthorizationGroupStore.remove_membership_group(membership_id: @membership, group_id: group.fetch("id"))
          end
        end
      end
      wait_for_blocker(Timeout.timeout(5) { ready.pop }, request_pid)
    end
    assert_equal 200, client.response.status
    assert_equal({ "id" => @party.id }, client.response.parsed_body)
    assert policy_worker.join(5), "Policy mutation did not finish after the monitoring commit"
    policy_worker.value
    DatabaseContext.with_session(@owner) { assert_equal "Alteração autorizada", @party.reload.name }
    patch "/api/monitorings/parties/#{@party.id}", params: { name: "Sem concessão" }, as: :json, headers: write_headers
    assert_permission_denied
  ensure
    policy_worker&.kill if policy_worker&.alive?
    policy_worker&.join
  end

  private

  def assign_group(*rules, membership: @membership)
    DatabaseContext.with_session(@owner) do
      group = AuthorizationGroupStore.create_group(name: "Grupo #{SecureRandom.hex(4)}")
      rules.each { |rule| AuthorizationGroupStore.create_rule(group_id: group.fetch("id"), input: rule) }
      AuthorizationGroupStore.assign_membership_group(membership_id: membership, group_id: group.fetch("id"))
    end
  end

  def allow_rule(operation)
    { "operation" => operation, "effect" => "allow", "court" => nil }
  end

  def monitoring_inputs
    [["/api/monitorings/parties", { name: "Nova parte" }],
      ["/api/monitorings/processes", { number: "00077776620248010003" }]]
  end

  def monitoring_records
    [["/api/monitorings/parties/#{@party.id}", @party, :name, "Nome alterado"],
      ["/api/monitorings/processes/#{@process.id}", @process, :number, "00099998820248010002"]]
  end

  def monitoring_read_paths
    ["/api/monitorings/parties", "/api/monitorings/parties/#{@party.id}",
      "/api/monitorings/processes", "/api/monitorings/processes/#{@process.id}", "/api/monitorings/lawyer"]
  end

  def write_headers(csrf = @csrf)
    { "Origin" => AppSettings.origin, "X-CSRF-Token" => csrf }
  end

  def assert_permission_denied(result = response)
    assert_equal 403, result.status
    assert_equal "application/json", result.media_type
    assert_equal "no-store", result.headers["Cache-Control"]
    assert_equal ["error"], result.parsed_body.keys
    assert_equal "permission_denied", result.parsed_body.dig("error", "code")
  end

  def assert_original_records
    DatabaseContext.with_session(@owner) do
      assert_equal "Parte original", @party.reload.name
      assert_equal "00012345620248010001", @process.reload.number
      assert @party.active
      assert @process.active
    end
  end

  def expire_membership
    @admin.exec_params("UPDATE app_private.tenant_memberships SET expires_at = clock_timestamp() - interval '1 second' WHERE id = $1",
      [@membership])
  end

  def with_deadline_after_write(record, verb)
    expired = false
    callback = lambda do |_name, _started, _finished, _id, payload|
      if !expired && payload.fetch(:sql).start_with?("#{verb} #{verb == 'INSERT' ? 'INTO ' : ''}\"#{record.class.table_name}\"")
        expired = true
        expire_membership
      end
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    assert expired, "The monitoring write was not observed"
  end

  def with_locked_monitoring(record, input)
    @admin.exec("BEGIN")
    @admin.exec_params("SELECT set_config('app.session_hash', $1, true)", [IdentityStore.digest(@owner)])
    @admin.exec_params("SELECT id FROM public.#{record.class.table_name} WHERE id = $1 FOR UPDATE", [record.id])
    ready = Queue.new
    worker = Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        ready << connection.select_value("SELECT pg_backend_pid()")
        client = ActionDispatch::Integration::Session.new(Rails.application)
        client.https!
        client.host! URI(AppSettings.origin).host
        client.cookies[ApplicationController::SESSION_COOKIE] = @member
        path = monitoring_records.find { |entry| entry[1] == record }.first
        client.patch path, params: input, as: :json, headers: write_headers
        client
      end
    end
    request_pid = Timeout.timeout(5) { ready.pop }
    wait_for_blocker(request_pid, @admin.backend_pid)
    yield request_pid
    @admin.exec("COMMIT")
    assert worker.join(5), "Monitoring request did not finish after releasing its row lock"
    worker.value
  ensure
    @admin.exec("ROLLBACK") if @admin && @admin.transaction_status != PG::PQTRANS_IDLE
    worker&.kill if worker&.alive?
    worker&.join
  end

  def wait_for_blocker(waiting_pid, blocking_pid)
    Timeout.timeout(5) do
      loop do
        blocked = @admin.exec_params("SELECT $1::integer = ANY(pg_blocking_pids($2::integer))",
          [blocking_pid, waiting_pid]).getvalue(0, 0)
        break if blocked == "t"
        sleep 0.01
      end
    end
  end

  def with_membership_revoked_after_context_read(read_number)
    original = IdentityStore.method(:context)
    reads = 0
    context = lambda do |token|
      value = original.call(token)
      reads += 1
      if reads == read_number
        @admin.exec_params("UPDATE app_private.tenant_memberships SET revoked_at = clock_timestamp() WHERE id = $1", [@membership])
      end
      value
    end
    IdentityStore.stub(:context, context) { yield }
  end
end
