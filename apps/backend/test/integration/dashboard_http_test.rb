require "test_helper"
require "pg"

class DashboardHttpTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  CATALOG = %w[TJSP TJRJ TJAC].map { |court| { code: court, name: court } }.freeze
  NUMBER = "00000010020268260001".freeze
  MASKED_NUMBER = "0000001-00.2026.8.26.0001".freeze
  MICROSECOND = Rational(1, 1_000_000)

  setup do
    https!
    host! URI(AppSettings.origin).host
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    @planner = PG.connect(ENV.fetch("DESPACHANTE_DATABASE_URL"))
    assert_equal "advocacia_migrator", @admin.exec("SELECT current_user").getvalue(0, 0)
    assert_equal "advocacia_despachante", @planner.exec("SELECT current_user").getvalue(0, 0)
    assert_equal "advocacia_runtime", ApplicationRecord.connection.select_value("SELECT current_user")
    @owner, = authenticated_session
    @lawyer = LawyerOnboarding.call(token: @owner, input: profile_payload)
    @member, = authenticated_session
    identity = IdentityStore.context(@member).fetch("identity_id")
    @membership = @admin.exec_params(<<~SQL, [@lawyer.tenant_id, identity]).getvalue(0, 0)
      INSERT INTO app_private.tenant_memberships
        (tenant_id, identity_id, role, invited_email, accepted_at, credential_started_at)
      VALUES ($1, $2, 'member', 'dashboard@example.test', clock_timestamp(), clock_timestamp()) RETURNING id
    SQL
    @admin.exec_params("UPDATE app_private.sessions SET selected_membership_id = $1 WHERE session_hash = $2",
      [@membership, IdentityStore.digest(@member)])
    # Runs are global and earlier integration tests retain their fixtures.
    # Allocate a fresh Wednesday without changing another tenant's run or jobs.
    @date = Date.iso8601(@planner.exec(<<~SQL).getvalue(0, 0))
      SELECT COALESCE(MAX(collection_date) + 7, DATE '2200-01-01')::text FROM public.collection_runs
    SQL
    @date += (3 - @date.wday) % 7
    @now = Time.utc(@date.year, @date.month, @date.day, 13)
    @midnight = @now - 10.hours
    @sequence = 0
    cookies[ApplicationController::SESSION_COOKIE] = @member
  end

  teardown do
    @planner&.close
    @admin&.close
  end

  test "authentication onboarding and credential validity cannot be replaced with a tenant parameter" do
    job = create_job
    succeed(job)
    persist(job, at: @midnight)
    cookies.delete(ApplicationController::SESSION_COOKIE)
    dashboard(tenant_id: @lawyer.tenant_id)
    assert_response :unauthorized
    assert_equal "authentication_required", response.parsed_body.dig("error", "code")

    token, = authenticated_session
    cookies[ApplicationController::SESSION_COOKIE] = token
    dashboard(tenant_id: @lawyer.tenant_id)
    assert_response :not_found
    assert_equal "onboarding_required", response.parsed_body.dig("error", "code")

    cookies[ApplicationController::SESSION_COOKIE] = @member
    @admin.exec_params("UPDATE app_private.tenant_memberships SET expires_at = clock_timestamp() - interval '1 second' WHERE id = $1", [@membership])
    dashboard
    assert_response :unauthorized
    refute response.parsed_body.key?("periods")
  end

  test "no groups grants reads while completed empty work alone permits zero" do
    job = create_job
    succeed(job, matched_count: 999)
    dashboard
    assert_response :ok
    assert_equal "succeeded", body.fetch("state")
    assert_equal [{ "court" => "TJSP", "state" => "succeeded" }], body.fetch("courts")
    assert_equal [], body.fetch("warnings")
    assert_metrics today: [0, 0], week: [0, 0], last_seven_days: [0, 0]
    assert_equal "no-store", response.headers.fetch("Cache-Control")
    assert_equal "no-cache", response.headers.fetch("Pragma")
    assert_equal "America/Sao_Paulo", body.fetch("timezone")
    assert_equal @now.in_time_zone("America/Sao_Paulo").iso8601(6), body.fetch("as_of")
    assert_equal %w[as_of courts periods state timezone warnings], body.keys.sort
  end

  test "calendar windows include their local start exclude the exact query instant and overlap independently" do
    job = create_job
    succeed(job)
    persist(job, at: @midnight, number: NUMBER)
    persist(job, at: @midnight - MICROSECOND, number: MASKED_NUMBER)
    persist(job, at: @midnight - 2.days, number: "00000020020268260001")
    persist(job, at: @midnight - 2.days - MICROSECOND, number: "00000030020268260001")
    persist(job, at: @midnight - 6.days, number: "00000040020268260001")
    persist(job, at: @midnight - 6.days - MICROSECOND, number: "00000050020268260001")
    persist(job, at: @now - MICROSECOND, number: MASKED_NUMBER)
    persist(job, at: @now, number: "00000060020268260001")
    persist(job, at: @now + MICROSECOND, number: "00000070020268260001")

    Time.use_zone("Pacific/Kiritimati") { dashboard }
    assert_response :ok
    assert_metrics today: [2, 1], week: [4, 2], last_seven_days: [6, 4]
    { "today" => @midnight, "week" => @midnight - 2.days, "last_seven_days" => @midnight - 6.days }.each do |name, start|
      period = body.fetch("periods").fetch(name)
      assert_equal start.in_time_zone("America/Sao_Paulo").iso8601(6), period.fetch("start")
      assert_equal @now.in_time_zone("America/Sao_Paulo").iso8601(6), period.fetch("end")
      assert_equal %w[communications end processes start], period.keys.sort
    end
  end

  test "Monday and the local midnight boundary do not follow the server UTC date" do
    @date -= 2
    @now = Time.utc(@date.year, @date.month, @date.day, 2, 30) + 1.day
    local = @now.in_time_zone("America/Sao_Paulo")
    @date = local.to_date
    @midnight = local.beginning_of_day
    job = create_job
    succeed(job)
    persist(job, at: @midnight - MICROSECOND)
    persist(job, at: @midnight)
    dashboard
    assert_response :ok
    assert_metrics today: [1, 1], week: [1, 1], last_seven_days: [2, 1]
    assert_equal @midnight.iso8601(6), body.dig("periods", "week", "start")
  end

  test "canonical CNJs preserve leading zeros and invalid source values never create a process" do
    job = create_job
    succeed(job)
    [NUMBER, MASKED_NUMBER, "00000020020268260001", "  #{NUMBER}", "#{NUMBER}\n",
      "0000001/00.2026.8.26.0001", 12345678901234567890, nil, { "number" => NUMBER }].each do |number|
      persist(job, at: @midnight, number: number)
    end
    dashboard
    assert_response :ok
    assert_metrics today: [9, 2], week: [9, 2], last_seven_days: [9, 2]
  end

  test "pending identities never enter either metric even when they contain a valid process" do
    job = create_job
    succeed(job)
    persist(job, at: @midnight, pending: true)
    persist(job, at: @midnight, pending: true)
    persist(job, at: @midnight, payload: { "data_disponibilizacao" => "1900-01-01" })
    dashboard
    assert_response :ok
    assert_metrics today: [1, 1], week: [1, 1], last_seven_days: [1, 1]
  end

  test "dashboard grants never widen readable courts and explicit court denial wins across groups" do
    sp = create_job
    rj = create_job(court: "TJRJ")
    ac = create_job(court: "TJAC")
    [sp, rj].each { |job| succeed(job); persist(job, at: @midnight) }
    fail_job(ac)
    assign_group(rule("consultar_dashboard"), rule("consultar_comunicacoes", court: "TJSP"),
      rule("consultar_comunicacoes", court: "TJRJ"))
    assign_group(rule("consultar_comunicacoes", court: "TJRJ", effect: "deny"))
    dashboard(court: "TJAC", tenant_id: SecureRandom.uuid)
    assert_response :ok
    assert_equal [{ "court" => "TJSP", "state" => "succeeded" }], body.fetch("courts")
    assert_equal [], body.fetch("warnings")
    assert_equal "succeeded", body.fetch("state")
    assert_metrics today: [1, 1], week: [1, 1], last_seven_days: [1, 1]
    refute_includes response.body, "TJRJ"
    refute_includes response.body, "TJAC"
  end

  test "a dashboard only grant exposes no court states warnings or aggregate" do
    job = create_job
    fail_job(job)
    assign_group(rule("consultar_dashboard"))
    dashboard
    assert_response :ok
    assert_equal "unavailable", body.fetch("state")
    assert_equal [], body.fetch("courts")
    assert_equal [], body.fetch("warnings")
    assert_metrics today: [nil, nil], week: [nil, nil], last_seven_days: [nil, nil]
    refute_includes response.body, "TJSP"
  end

  test "dashboard denial masks every value without a metrics query or alternative numeric fields" do
    sp = create_job
    rj = create_job(court: "TJRJ")
    succeed(sp)
    persist(sp, at: @midnight)
    fail_job(rj)
    assign_group(rule("consultar_dashboard"), rule("consultar_comunicacoes", court: "TJSP"))
    assign_group(rule("consultar_dashboard", effect: "deny"))
    sql = []
    callback = ->(_name, _start, _finish, _id, payload) { sql << payload.fetch(:sql) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { dashboard }
    assert_response :ok
    assert_equal "masked", body.fetch("state")
    assert_metrics today: ["*", "*"], week: ["*", "*"], last_seven_days: ["*", "*"]
    refute sql.any? { |query| query.match?(/collection_communications|collection_communication_links|collection_court_states/) },
      "denied dashboard must not fetch publications or invoke a function that computes their totals"
    refute numeric_value?(body), "there must be no alternative numeric value in the payload"
    refute_includes response.body, "TJRJ"
  end

  test "masked requests can still show only readable persistent failure warnings" do
    sp = create_job
    rj = create_job(court: "TJRJ")
    [sp, rj].each { |job| fail_job(job) }
    assign_group(rule("consultar_comunicacoes", court: "TJSP"))
    dashboard
    assert_response :ok
    assert_equal [{ "court" => "TJSP", "code" => "collection_failed" }], body.fetch("warnings")
    assert_equal [{ "court" => "TJSP", "state" => "failed" }], body.fetch("courts")
    assert_metrics today: ["*", "*"], week: ["*", "*"], last_seven_days: ["*", "*"]
    refute_includes response.body, "TJRJ"
  end

  test "all failed and all pending courts are not successful empty results" do
    job = create_job
    dashboard
    assert_response :ok
    assert_equal "running", body.fetch("state")
    assert_metrics today: [nil, nil], week: [nil, nil], last_seven_days: [nil, nil]
    fail_job(job)
    dashboard
    assert_response :ok
    assert_equal "failed", body.fetch("state")
    assert_equal [{ "court" => "TJSP", "code" => "collection_failed" }], body.fetch("warnings")
    assert_metrics today: [nil, nil], week: [nil, nil], last_seven_days: [nil, nil]
  end

  test "a succeeded execution without a persisted result remains incomplete" do
    job = create_job
    @admin.exec_params("UPDATE public.collection_job_executions SET state = 'succeeded' WHERE job_id = $1", [job.fetch("id")])
    persist(job, at: @midnight)
    dashboard
    assert_response :ok
    assert_equal "running", body.fetch("state")
    assert_metrics today: [nil, nil], week: [nil, nil], last_seven_days: [nil, nil]
  end

  test "partial courts are excluded entirely while complete courts contribute to a partial aggregate" do
    sp = create_job
    succeed(sp)
    persist(sp, at: @midnight)
    rj = create_job(court: "TJRJ")
    succeed(rj)
    persist(rj, at: @midnight, number: "00000020020268260001")
    failed = create_extra_job(court: "TJRJ")
    fail_job(failed)
    ac = create_job(court: "TJAC")
    @admin.exec_params("UPDATE public.collection_job_executions SET state = 'running' WHERE job_id = $1", [ac.fetch("id")])
    dashboard
    assert_response :ok
    assert_equal "partial", body.fetch("state")
    assert_equal({ "TJAC" => "running", "TJRJ" => "partial", "TJSP" => "succeeded" },
      body.fetch("courts").to_h { |court| court.values_at("court", "state") })
    assert_equal [{ "court" => "TJRJ", "code" => "collection_failed" }], body.fetch("warnings")
    assert_metrics today: [1, 1], week: [1, 1], last_seven_days: [1, 1]
  end

  test "a partially successful court alone has no count and pending work outranks another failure" do
    job = create_job
    succeed(job)
    persist(job, at: @midnight)
    create_extra_job
    dashboard
    assert_response :ok
    assert_equal "partial", body.fetch("state")
    assert_equal [], body.fetch("warnings")
    assert_metrics today: [nil, nil], week: [nil, nil], last_seven_days: [nil, nil]

    failed = create_job(court: "TJRJ")
    fail_job(failed)
    create_extra_job(court: "TJRJ")
    assign_group(rule("consultar_dashboard"), rule("consultar_comunicacoes", court: "TJRJ"))
    dashboard
    assert_response :ok
    assert_equal "running", body.fetch("state")
    assert_equal [{ "court" => "TJRJ", "code" => "collection_failed" }], body.fetch("warnings")
    assert_metrics today: [nil, nil], week: [nil, nil], last_seven_days: [nil, nil]
  end

  test "missing runs planning without work and planning failure remain distinct from zero" do
    dashboard
    assert_response :ok
    assert_equal "unavailable", body.fetch("state")
    assert_metrics today: [nil, nil], week: [nil, nil], last_seven_days: [nil, nil]
    run = create_run
    dashboard
    assert_response :ok
    assert_equal "no_work", body.fetch("state")
    assert_equal [], body.fetch("courts")
    assert_metrics today: [nil, nil], week: [nil, nil], last_seven_days: [nil, nil]
    @planner.exec_params("UPDATE public.collection_runs SET status = 'no_work' WHERE id = $1", [run])
    dashboard
    assert_response :ok
    assert_equal "no_work", body.fetch("state")
    assert_metrics today: [nil, nil], week: [nil, nil], last_seven_days: [nil, nil]
    @planner.exec_params("UPDATE public.collection_runs SET status = 'planning_failed' WHERE id = $1", [run])
    dashboard
    assert_response :ok
    assert_equal "unavailable", body.fetch("state")
    assert_metrics today: [nil, nil], week: [nil, nil], last_seven_days: [nil, nil]
  end

  test "a later failed or empty plan does not inherit an earlier successful zero" do
    job = create_job
    succeed(job)
    second = create_run(slot: 2, status: "planning_failed")
    dashboard
    assert_response :ok
    assert_equal "unavailable", body.fetch("state")
    assert_equal [], body.fetch("courts")
    assert_metrics today: [nil, nil], week: [nil, nil], last_seven_days: [nil, nil]

    @planner.exec_params("UPDATE public.collection_runs SET status = 'no_work' WHERE id = $1", [second])
    dashboard
    assert_equal "no_work", body.fetch("state")
    assert_metrics today: [nil, nil], week: [nil, nil], last_seven_days: [nil, nil]
  end

  test "unrecovered failures remain visible across days only to authorized courts" do
    old = create_job(run: create_run(date: @date - 1), court: "TJRJ")
    fail_job(old)
    current = create_job
    succeed(current)
    dashboard
    assert_equal [{ "court" => "TJRJ", "code" => "collection_failed" }], body.fetch("warnings")
    assign_group(rule("consultar_dashboard"), rule("consultar_comunicacoes", court: "TJSP"))
    dashboard
    assert_equal [], body.fetch("warnings")
    refute_includes response.body, "TJRJ"
  end

  test "a previous day success does not manufacture a current conclusion" do
    previous = create_job(run: create_run(date: @date - 1))
    succeed(previous)
    persist(previous, at: @midnight - 1.day)
    dashboard
    assert_response :ok
    assert_equal "unavailable", body.fetch("state")
    assert_equal [], body.fetch("courts")
    assert_metrics today: [nil, nil], week: [nil, nil], last_seven_days: [nil, nil]
  end

  test "nonnumeric masked states preserve the collection state matrix without publication queries" do
    partial = create_job
    succeed(partial)
    create_extra_job
    running = create_job(court: "TJRJ")
    fail_job(running)
    create_extra_job(court: "TJRJ")
    failed = create_job(court: "TJAC")
    fail_job(failed)
    assign_group(rule("consultar_dashboard"), rule("consultar_comunicacoes"))
    dashboard
    assert_response :ok
    expected_courts = body.fetch("courts")
    expected_warnings = body.fetch("warnings")
    assert_equal({ "TJAC" => "failed", "TJRJ" => "running", "TJSP" => "partial" },
      expected_courts.to_h { |court| court.values_at("court", "state") })
    assign_group(rule("consultar_dashboard", effect: "deny"))
    dashboard
    assert_response :ok
    assert_equal "masked", body.fetch("state")
    assert_equal expected_courts, body.fetch("courts")
    assert_equal expected_warnings, body.fetch("warnings")
    assert_metrics today: ["*", "*"], week: ["*", "*"], last_seven_days: ["*", "*"]
  end

  test "later same day recovery replaces the current failure without deleting historical failure" do
    first = create_job
    fail_job(first)
    dashboard
    assert_equal "failed", body.fetch("state")
    second = create_job(run: create_run(slot: 2))
    dashboard
    assert_equal "running", body.fetch("state")
    assert_equal [{ "court" => "TJSP", "code" => "collection_failed" }], body.fetch("warnings")
    succeed(second)
    persist(second, at: @midnight)
    dashboard
    assert_response :ok
    assert_equal "succeeded", body.fetch("state")
    assert_equal [], body.fetch("warnings")
    assert_metrics today: [1, 1], week: [1, 1], last_seven_days: [1, 1]
    assert_equal "failed", @admin.exec_params("SELECT state FROM public.collection_job_executions WHERE job_id = $1", [first.fetch("id")]).getvalue(0, 0)
  end

  test "a later incomplete execution supersedes earlier success only for its own court" do
    first = create_job
    succeed(first)
    persist(first, at: @midnight)
    other = create_job(court: "TJRJ")
    succeed(other)
    persist(other, at: @midnight)
    create_job(run: create_run(slot: 2))
    dashboard
    assert_response :ok
    assert_equal "partial", body.fetch("state")
    assert_equal({ "TJRJ" => "succeeded", "TJSP" => "running" },
      body.fetch("courts").to_h { |court| court.values_at("court", "state") })
    assert_metrics today: [1, 1], week: [1, 1], last_seven_days: [1, 1]
  end

  test "tenant parameters query cache and policy changes cannot reuse another authorized snapshot" do
    first = create_job
    succeed(first)
    persist(first, at: @midnight)
    other_token, = authenticated_session
    other_lawyer = LawyerOnboarding.call(token: other_token, input: profile_payload)
    other_job = create_job(lawyer: other_lawyer)
    succeed(other_job)
    2.times { persist(other_job, at: @midnight) }
    ApplicationRecord.cache do
      dashboard(tenant_id: other_lawyer.tenant_id)
      assert_response :ok
      assert_metrics today: [1, 1], week: [1, 1], last_seven_days: [1, 1]
      cookies[ApplicationController::SESSION_COOKIE] = other_token
      dashboard(tenant_id: @lawyer.tenant_id)
      assert_response :ok
      assert_metrics today: [2, 1], week: [2, 1], last_seven_days: [2, 1]
      cookies[ApplicationController::SESSION_COOKIE] = @member
      assign_group(rule("consultar_comunicacoes", court: "TJSP"))
      dashboard
      assert_response :ok
      assert_metrics today: ["*", "*"], week: ["*", "*"], last_seven_days: ["*", "*"]
    end
    assert_empty ApplicationRecord.connection.select_values("SELECT id FROM public.collection_communications")
  end

  test "the owner remains authorized independently of explicit group denials" do
    job = create_job
    succeed(job)
    persist(job, at: @midnight)
    membership = IdentityStore.context(@owner).fetch("membership_id")
    assign_group(rule("consultar_dashboard", effect: "deny"),
      rule("consultar_comunicacoes", effect: "deny"), membership: membership)
    cookies[ApplicationController::SESSION_COOKIE] = @owner
    dashboard
    assert_response :ok
    assert_metrics today: [1, 1], week: [1, 1], last_seven_days: [1, 1]
  end

  test "a later readable court link cannot reclassify the first persisted communication" do
    hidden = create_job(court: "TJRJ")
    visible = create_job
    [hidden, visible].each { |job| succeed(job) }
    communication = persist(hidden, at: @midnight)
    link(visible, communication, at: @midnight + 1.hour)
    assign_group(rule("consultar_dashboard"), rule("consultar_comunicacoes", court: "TJSP"))
    dashboard
    assert_response :ok
    assert_metrics today: [0, 0], week: [0, 0], last_seven_days: [0, 0]
  end

  test "ambiguous origins are excluded and conflicting source courts require read permission" do
    sp = create_job
    rj = create_job(court: "TJRJ")
    [sp, rj].each { |job| succeed(job) }
    ambiguous = persist(sp, at: @midnight, link_at: @midnight)
    link(rj, ambiguous, at: @midnight)
    ["TJRJ", nil, 123, ["TJSP"]].each do |court|
      persist(sp, at: @midnight, payload: { "siglaTribunal" => court })
    end
    persist(sp, at: @midnight, payload: { "siglaTribunal" => "TJSP" })
    persist(sp, at: @midnight, omit_court: true)
    dashboard
    assert_response :ok
    assert_metrics today: [6, 1], week: [6, 1], last_seven_days: [6, 1]
    assign_group(rule("consultar_dashboard"), rule("consultar_comunicacoes", court: "TJSP"))
    dashboard
    assert_response :ok
    assert_metrics today: [5, 1], week: [5, 1], last_seven_days: [5, 1]
  end

  test "repeated links do not change the first persistence window or duplicate a communication" do
    first = create_job
    succeed(first)
    second = create_job(run: create_run(slot: 2))
    succeed(second)
    old = persist(first, at: @midnight - 3.days)
    link(second, old, at: @midnight + 1.hour)
    recent = persist(first, at: @midnight)
    link(second, recent, at: @midnight + 1.hour)
    dashboard
    assert_response :ok
    assert_metrics today: [1, 1], week: [1, 1], last_seven_days: [2, 1]
  end

  test "revocation after the initial context and expiry after aggregation cannot release a protected response" do
    job = create_job
    succeed(job)
    persist(job, at: @midnight)
    original = IdentityStore.method(:context)
    reads = 0
    context = lambda do |token|
      value = original.call(token)
      reads += 1
      @admin.exec_params("UPDATE app_private.tenant_memberships SET revoked_at = clock_timestamp() WHERE id = $1", [@membership]) if reads == 1
      value
    end
    IdentityStore.stub(:context, context) { dashboard }
    assert_response :forbidden
    refute response.parsed_body.key?("periods")
    @admin.exec_params("UPDATE app_private.tenant_memberships SET revoked_at = NULL WHERE id = $1", [@membership])
    expired = false
    callback = lambda do |_name, _start, _finish, _id, payload|
      if !expired && payload[:name] == "Dashboard metrics"
        expired = true
        @admin.exec_params("UPDATE app_private.tenant_memberships SET expires_at = clock_timestamp() - interval '1 second' WHERE id = $1", [@membership])
      end
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { dashboard }
    assert expired, "the aggregate must run before the credential expires"
    assert_response :forbidden
    refute response.parsed_body.key?("periods")
  end

  private

  def dashboard(**params)
    travel_to(@now) { get "/api/dashboard", params: params }
  end

  def body
    response.parsed_body
  end

  def assert_metrics(expected)
    expected.each do |name, values|
      assert_equal values, body.fetch("periods").fetch(name.to_s).values_at("communications", "processes"), name.to_s
    end
  end

  def numeric_value?(value)
    case value
    when Numeric then true
    when Hash then value.values.any? { |item| numeric_value?(item) }
    when Array then value.any? { |item| numeric_value?(item) }
    else false
    end
  end

  def rule(operation, court: nil, effect: "allow")
    { "operation" => operation, "effect" => effect, "court" => court }
  end

  def assign_group(*rules, membership: @membership)
    CourtCatalog.stub(:fetch, CATALOG) do
      DatabaseContext.with_session(@owner) do
        group = AuthorizationGroupStore.create_group(name: "Dashboard #{SecureRandom.hex(4)}")
        rules.each { |entry| AuthorizationGroupStore.create_rule(group_id: group.fetch("id"), input: entry) }
        AuthorizationGroupStore.assign_membership_group(membership_id: membership, group_id: group.fetch("id"))
      end
    end
  end

  def create_run(slot: 1, date: @date, status: "planned", lawyer: @lawyer)
    @planner.exec_params(<<~SQL, [date.iso8601, slot, status])
      INSERT INTO public.collection_runs (collection_date, slot, status)
      VALUES ($1, $2, $3) ON CONFLICT (collection_date, slot) DO NOTHING
    SQL
    id = @planner.exec_params("SELECT id FROM public.collection_runs WHERE collection_date = $1 AND slot = $2", [date.iso8601, slot]).getvalue(0, 0)
    @planner.exec_params("INSERT INTO public.collection_run_audiences (run_id, tenant_id) VALUES ($1, $2) ON CONFLICT DO NOTHING", [id, lawyer.tenant_id])
    id
  end

  def create_job(court: "TJSP", run: create_run, lawyer: @lawyer, entity_type: "lawyer", entity_id: lawyer.id)
    @planner.exec_params("INSERT INTO public.collection_run_audiences (run_id, tenant_id) VALUES ($1, $2) ON CONFLICT DO NOTHING", [run, lawyer.tenant_id])
    @planner.exec_params(<<~SQL, [run, lawyer.tenant_id, entity_type, entity_id, court]).first
      INSERT INTO public.collection_jobs (run_id, tenant_id, entity_type, entity_id, source, court, medium, criteria)
      VALUES ($1, $2, $3, $4, 'DJEN', $5, 'D', '{}') RETURNING id, tenant_id, court
    SQL
  end

  def create_extra_job(court: "TJSP")
    party = DatabaseContext.with_session(@owner) do
      PartyMonitoring.create!(tenant_id: @lawyer.tenant_id, name: "Parte #{SecureRandom.hex(4)}")
    end
    create_job(court: court, entity_type: "party", entity_id: party.id)
  end

  def succeed(job, matched_count: 0)
    @admin.exec_params("UPDATE public.collection_job_executions SET state = 'succeeded' WHERE job_id = $1", [job.fetch("id")])
    @admin.exec_params(<<~SQL, [job.fetch("id"), job.fetch("tenant_id"), matched_count])
      INSERT INTO public.collection_job_results (job_id, tenant_id, source_path, matched_count, pending_identity_count)
      VALUES ($1, $2, 'caderno', $3, 0)
    SQL
  end

  def fail_job(job)
    @admin.exec_params("UPDATE public.collection_job_executions SET state = 'failed' WHERE job_id = $1", [job.fetch("id")])
  end

  def persist(job, at:, number: NUMBER, pending: false, payload: {}, omit_court: false, link_at: at + MICROSECOND)
    @sequence += 1
    content = { "numero_processo" => number, "siglaTribunal" => job.fetch("court") }.merge(payload)
    content.delete("siglaTribunal") if omit_court
    values = [job.fetch("tenant_id"), @sequence, SecureRandom.hex(16), JSON.generate(content), at.iso8601(6)]
    id = if pending
      @admin.exec_params(<<~SQL, [values[0], values[3], values[4]]).getvalue(0, 0)
        INSERT INTO public.collection_communications (tenant_id, identity_status, warning, payload, recorded_at)
        VALUES ($1, 'pending', 'possible_duplicate', $2::jsonb, $3::timestamptz) RETURNING id
      SQL
    else
      @admin.exec_params(<<~SQL, values).getvalue(0, 0)
        INSERT INTO public.collection_communications
          (tenant_id, source_id, source_hash, identity_digest, identity_status, payload, recorded_at)
        VALUES ($1, $2::numeric, $3, sha256(convert_to(jsonb_build_array($2::numeric, $3::text)::text, 'UTF8')),
          'complete', $4::jsonb, $5::timestamptz) RETURNING id
      SQL
    end
    link(job, id, at: link_at)
    id
  end

  def link(job, communication, at:)
    @admin.exec_params(<<~SQL, [job.fetch("tenant_id"), communication, job.fetch("id"), at.iso8601(6)])
      INSERT INTO public.collection_communication_links (tenant_id, communication_id, job_id, recorded_at)
      VALUES ($1, $2, $3, $4::timestamptz)
    SQL
  end
end
