require "test_helper"
require "pg"
require_relative "../../despachante/collection_despachante"

class EscreventeHttpTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  CATALOG = [
    { code: "TJAC", name: "Tribunal de Justiça do Estado do Acre" },
    { code: "TRF1", name: "Tribunal Regional Federal da 1ª Região" }
  ].freeze
  EVENT_FIELDS = %w[court entity_id entity_type event_type id job_id medium recorded_at source].freeze
  EXECUTION_FIELDS = %w[court job_id medium state].freeze

  setup do
    https!
    host! URI(AppSettings.origin).host
    assert_equal "advocacia_runtime", ApplicationRecord.connection.select_value("SELECT current_user")
    @despachante_url = ENV.fetch("DESPACHANTE_DATABASE_URL")
    @database = PG.connect(@despachante_url)
    assert_equal "advocacia_despachante", @database.exec("SELECT current_user").getvalue(0, 0)
    @processor = PG.connect(ENV.fetch("PROCESSADOR_DATABASE_URL"))
    assert_equal "advocacia_processador", @processor.exec("SELECT current_user").getvalue(0, 0)
    @date = Date.iso8601(@database.exec(<<~SQL).getvalue(0, 0))
      SELECT COALESCE(MAX(collection_date) + 1, DATE '2040-01-01')::text FROM public.collection_runs
    SQL
    @now = Time.utc(@date.year, @date.month, @date.day, 7)
  end

  teardown do
    @processor&.close
    @database&.close
  end

  test "anonymous requests cannot read events or execution using real tenant identifiers" do
    token, lawyer = create_lawyer
    run_id = plan(slot: 1)

    paths(run_id).each do |path|
      get path, params: { tenant_id: lawyer.tenant_id }
      assert_authentication_required
    end
    assert IdentityStore.context(token)
  end

  test "revoked sessions immediately lose access to events and execution" do
    token, lawyer = create_lawyer
    run_id = plan(slot: 1)
    cookies[ApplicationController::SESSION_COOKIE] = token
    IdentityStore.revoke(token)

    paths(run_id).each do |path|
      get path, params: { tenant_id: lawyer.tenant_id }
      assert_authentication_required
    end
  end

  test "sessions without onboarding cannot choose a tenant to read events or execution" do
    _, lawyer = create_lawyer
    run_id = plan(slot: 1)
    token, = authenticated_session
    cookies[ApplicationController::SESSION_COOKIE] = token

    paths(run_id).each do |path|
      get path, params: { tenant_id: lawyer.tenant_id }
      assert_response :not_found
      assert_equal "onboarding_required", response.parsed_body.dig("error", "code")
      refute response.parsed_body.key?("events")
      refute response.parsed_body.key?("jobs")
    end
    assert_nil IdentityStore.context(token).fetch("tenant_id")
  end

  test "invalid UUIDs and missing runs are not found without exposing a payload" do
    token, lawyer = create_lawyer
    cookies[ApplicationController::SESSION_COOKIE] = token

    ["not-a-uuid", "00000000-0000-0000-0000-00000000000z", SecureRandom.uuid].each do |run_id|
      paths(run_id).each do |path|
        get path, params: { tenant_id: lawyer.tenant_id }
        assert_run_not_found
      end
    end
  end

  test "unstarted work has no events and every persisted job is pending" do
    token, lawyer = create_lawyer
    create_monitorings(token, lawyer, name: "Parte não iniciada")
    run_id = plan(slot: 1)
    jobs = persisted_jobs(run_id, lawyer.tenant_id)
    assert_equal %w[lawyer party process], jobs.map { |job| job.fetch("entity_type") }.uniq.sort
    cookies[ApplicationController::SESSION_COOKIE] = token

    get "/api/collection-runs/#{run_id}/events"
    assert_events([])
    get "/api/collection-runs/#{run_id}/execution"
    assert_execution(jobs, {})
  end

  test "events and execution stay within the current lawyer even with forged tenant parameters" do
    first_token, first = create_lawyer
    create_monitorings(first_token, first, name: "Parte da Ana")
    first_only_id = plan(slot: 1)
    first_only_jobs = persisted_jobs(first_only_id, first.tenant_id)
    start_job(first_only_jobs.first.fetch("id"))
    second_token, second = create_lawyer(name: "Bruno Lima", number: "000777-B", uf: "MG")
    create_monitorings(second_token, second, name: "Parte do Bruno")
    shared_id = plan(slot: 2)
    first_jobs = persisted_jobs(shared_id, first.tenant_id)
    second_jobs = persisted_jobs(shared_id, second.tenant_id)
    first_completed = first_jobs.first.fetch("id")
    second_completed = second_jobs.first.fetch("id")
    finish_job(first_completed, start_job(first_completed))
    finish_job(second_completed, start_job(second_completed))

    [[first_token, first_jobs, first_completed, second.tenant_id],
      [second_token, second_jobs, second_completed, first.tenant_id]].each do |token, jobs, completed, forged_tenant|
      expected_events = persisted_events(token, shared_id, jobs)
      assert_equal 2, expected_events.length
      cookies[ApplicationController::SESSION_COOKIE] = token
      get "/api/collection-runs/#{shared_id}/events", params: { tenant_id: forged_tenant }
      assert_events(expected_events)
      get "/api/collection-runs/#{shared_id}/execution", params: { tenant_id: forged_tenant }
      assert_execution(jobs, completed => "succeeded")
    end

    cookies[ApplicationController::SESSION_COOKIE] = second_token
    [nil, { tenant_id: first.tenant_id }].each do |query|
      paths(first_only_id).each do |path|
        get path, params: query
        assert_run_not_found
      end
    end

    cookies[ApplicationController::SESSION_COOKIE] = first_token
    get "/api/collection-runs/#{shared_id}/events"
    assert_events(persisted_events(first_token, shared_id, first_jobs))
    get "/api/collection-runs/#{shared_id}/execution"
    assert_execution(first_jobs, first_completed => "succeeded")
    assert_equal [], ApplicationRecord.connection.select_values("SELECT id FROM public.collection_events")
    assert_equal [], ApplicationRecord.connection.select_values("SELECT job_id FROM public.collection_job_executions")
  end

  test "running succeeded failed and unstarted jobs remain distinct without fabricating completion" do
    token, lawyer = create_lawyer
    create_monitorings(token, lawyer, name: "Parte com estados distintos")
    run_id = plan(slot: 1)
    jobs = persisted_jobs(run_id, lawyer.tenant_id)
    assert_equal 5, jobs.length
    pending, running, succeeded, failed = jobs.first(4).map { |job| job.fetch("id") }
    start_job(running)
    finish_job(succeeded, start_job(succeeded))
    fail_job(failed, start_job(failed))
    cookies[ApplicationController::SESSION_COOKIE] = token

    get "/api/collection-runs/#{run_id}/execution"
    assert_execution(jobs, running => "running", succeeded => "succeeded", failed => "failed")
    get "/api/collection-runs/#{run_id}/events"
    assert_events(persisted_events(token, run_id, jobs))
    by_job = response.parsed_body.fetch("events").group_by { |event| event.fetch("job_id") }
    refute by_job.key?(pending)
    assert_equal ["started"], by_job.fetch(running).map { |event| event.fetch("event_type") }
    assert_equal %w[completed started], by_job.fetch(succeeded).map { |event| event.fetch("event_type") }.sort
    assert_equal ["started"], by_job.fetch(failed).map { |event| event.fetch("event_type") }
  end

  test "visible runs without work expose no fabricated event or successful job" do
    token, = create_lawyer
    run_id = plan(slot: 1, catalog: [])
    cookies[ApplicationController::SESSION_COOKIE] = token

    get "/api/collection-runs/#{run_id}/events"
    assert_events([])
    get "/api/collection-runs/#{run_id}/execution"
    assert_execution([], {})
  end

  private

  def paths(run_id)
    ["/api/collection-runs/#{run_id}/events", "/api/collection-runs/#{run_id}/execution"]
  end

  def create_lawyer(name: "Ana de Ávila", number: "001234-A", uf: "SP")
    token, = authenticated_session
    input = profile_payload.merge("full_name" => name,
      "primary_oab" => { "number" => number, "uf" => uf })
    [token, LawyerOnboarding.call(token: token, input: input)]
  end

  def create_monitorings(token, lawyer, name:)
    DatabaseContext.with_session(token) do
      PartyMonitoring.create!(tenant_id: lawyer.tenant_id, name: name, courts: ["TJAC"], active: true)
      ProcessMonitoring.create!(tenant_id: lawyer.tenant_id, number: "00012345620248010001", active: true)
    end
  end

  def plan(slot:, catalog: CATALOG)
    CourtCatalog.stub(:fetch, catalog) do
      CollectionDespachante.new(url: @despachante_url).plan(slot: slot, now: @now)
    end
  end

  def persisted_jobs(run_id, tenant_id)
    @database.exec_params(<<~SQL, [run_id, tenant_id]).to_a
      SELECT id, entity_type, entity_id, source, court, medium
      FROM public.collection_jobs WHERE run_id = $1 AND tenant_id = $2 ORDER BY id
    SQL
  end

  def start_job(job_id)
    claim = @processor.exec_params(
      "SELECT token FROM app_private.processor_claim($1::uuid)", [job_id]).getvalue(0, 0)
    @processor.exec_params("SELECT id FROM app_private.processor_start($1::uuid, $2::text)", [job_id, claim])
    claim
  end

  def finish_job(job_id, claim)
    @processor.exec_params("SELECT id FROM app_private.processor_finish($1::uuid, $2::text)", [job_id, claim])
  end

  def fail_job(job_id, claim)
    @processor.exec_params("SELECT state FROM app_private.processor_fail($1::uuid, $2::text)", [job_id, claim])
  end

  def persisted_events(token, run_id, jobs)
    by_id = jobs.index_by { |job| job.fetch("id") }
    DatabaseContext.with_session(token) do
      connection = ApplicationRecord.connection
      binds = [ActiveRecord::Relation::QueryAttribute.new("run_id", run_id, ActiveRecord::Type::String.new)]
      connection.exec_query(<<~SQL, "Expected tenant events", binds).to_a
        SELECT id, job_id, event_type, recorded_at FROM public.collection_events
        WHERE job_id IN (SELECT id FROM public.collection_jobs WHERE run_id = $1::uuid)
      SQL
    end.sort_by { |event| [event.fetch("recorded_at"), event.fetch("id")] }.map do |event|
      context = by_id.fetch(event.fetch("job_id")).except("id")
      event.merge(context).as_json
    end
  end

  def assert_events(expected)
    assert_json_payload("events")
    actual = response.parsed_body.fetch("events")
    actual.each { |event| assert_equal EVENT_FIELDS, event.keys.sort }
    assert_equal expected, actual
  end

  def assert_execution(jobs, states)
    assert_json_payload("jobs")
    actual = response.parsed_body.fetch("jobs")
    actual.each { |job| assert_equal EXECUTION_FIELDS, job.keys.sort }
    expected = jobs.map do |job|
      { "job_id" => job.fetch("id"), "court" => job.fetch("court"),
        "medium" => job.fetch("medium"), "state" => states.fetch(job.fetch("id"), "pending") }
    end
    assert_equal expected.sort_by { |job| job.fetch("job_id") }, actual.sort_by { |job| job.fetch("job_id") }
  end

  def assert_json_payload(key)
    assert_response :ok
    assert_equal "application/json", response.media_type
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal [key], response.parsed_body.keys
  end

  def assert_authentication_required
    assert_response :unauthorized
    assert_equal "authentication_required", response.parsed_body.dig("error", "code")
    refute response.parsed_body.key?("events")
    refute response.parsed_body.key?("jobs")
  end

  def assert_run_not_found
    assert_response :not_found
    assert_equal "collection_run_not_found", response.parsed_body.dig("error", "code")
    refute response.parsed_body.key?("events")
    refute response.parsed_body.key?("jobs")
  end
end
