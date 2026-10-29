require "test_helper"
require "pg"
require_relative "../../despachante/collection_despachante"

class CollectionRunsHttpTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  CATALOG = [
    { code: "TJAC", name: "Tribunal de Justiça do Estado do Acre" },
    { code: "TRF1", name: "Tribunal Regional Federal da 1ª Região" }
  ].freeze

  setup do
    https!
    host! URI(AppSettings.origin).host
    assert_equal "advocacia_runtime", ApplicationRecord.connection.select_value("SELECT current_user")
    @despachante_url = ENV.fetch("DESPACHANTE_DATABASE_URL")
    @database = PG.connect(@despachante_url)
    assert_equal "advocacia_despachante", @database.exec("SELECT current_user").getvalue(0, 0)
    @date = Date.iso8601(@database.exec(<<~SQL).getvalue(0, 0))
      SELECT COALESCE(MAX(collection_date) + 1, DATE '2040-01-01')::text FROM public.collection_runs
    SQL
    @now = Time.utc(@date.year, @date.month, @date.day, 7)
  end

  teardown do
    @database&.close
  end

  test "run visibility is fixed at planning time and forged tenant queries cannot expand it" do
    first_token, first = create_lawyer
    first_only_id = plan(slot: 1)
    second_token, second = create_lawyer(name: "Bruno Lima", number: "000777-B", uf: "MG")

    cookies[ApplicationController::SESSION_COOKIE] = second_token
    get "/api/collection-runs", params: { tenant_id: first.tenant_id }
    assert_response :ok
    assert_equal({ "runs" => [] }, response.parsed_body)

    shared_id = plan(slot: 2)
    cookies[ApplicationController::SESSION_COOKIE] = first_token
    get "/api/collection-runs", params: { tenant_id: second.tenant_id }
    assert_runs(first_only_id => [1, "planned"], shared_id => [2, "planned"])

    cookies[ApplicationController::SESSION_COOKIE] = second_token
    get "/api/collection-runs", params: { tenant_id: first.tenant_id }
    assert_runs(shared_id => [2, "planned"])

    cookies[ApplicationController::SESSION_COOKIE] = first_token
    get "/api/collection-runs"
    assert_runs(first_only_id => [1, "planned"], shared_id => [2, "planned"])
  end

  test "jobs contain only the current tenant work and another tenant run ID stays inaccessible" do
    first_token, first = create_lawyer
    create_monitorings(first_token, first, name: "Parte da Ana")
    first_only_id = plan(slot: 1)
    second_token, second = create_lawyer(name: "Bruno Lima", number: "000777-B", uf: "MG")
    create_monitorings(second_token, second, name: "Parte do Bruno")
    shared_id = plan(slot: 2)
    first_jobs = persisted_jobs(shared_id, first.tenant_id)
    second_jobs = persisted_jobs(shared_id, second.tenant_id)
    assert_equal %w[lawyer party process], first_jobs.map { |job| job.fetch("entity_type") }.uniq.sort
    assert_equal %w[D E], first_jobs.map { |job| job.fetch("medium") }.uniq.sort
    assert_equal %w[TJAC TRF1], first_jobs.map { |job| job.fetch("court") }.uniq.sort
    assert_empty first_jobs.map { |job| job.fetch("id") } & second_jobs.map { |job| job.fetch("id") }

    cookies[ApplicationController::SESSION_COOKIE] = first_token
    get "/api/collection-runs/#{shared_id}/jobs", params: { tenant_id: second.tenant_id }
    assert_jobs(first_jobs)

    cookies[ApplicationController::SESSION_COOKIE] = second_token
    get "/api/collection-runs/#{shared_id}/jobs", params: { tenant_id: first.tenant_id }
    assert_jobs(second_jobs)

    [nil, { tenant_id: first.tenant_id }].each do |query|
      get "/api/collection-runs/#{first_only_id}/jobs", params: query
      assert_response :not_found
      assert response.parsed_body.key?("error")
      refute response.parsed_body.key?("jobs")
    end

    get "/api/collection-runs/#{SecureRandom.uuid}/jobs"
    assert_response :not_found
    assert response.parsed_body.key?("error")

    cookies[ApplicationController::SESSION_COOKIE] = first_token
    get "/api/collection-runs/#{shared_id}/jobs"
    assert_jobs(first_jobs)
    assert_equal [], ApplicationRecord.connection.select_values("SELECT id FROM public.collection_jobs")
  end

  test "a valid empty catalog exposes no_work to its fixed audience even without any jobs" do
    first_token, first = create_lawyer
    first_only_id = plan(slot: 1, catalog: [])
    second_token, second = create_lawyer(name: "Bruno Lima", number: "000777-B", uf: "MG")
    shared_id = plan(slot: 2, catalog: [])
    assert_empty persisted_jobs(first_only_id, first.tenant_id)
    assert_empty persisted_jobs(shared_id, first.tenant_id)
    assert_empty persisted_jobs(shared_id, second.tenant_id)

    cookies[ApplicationController::SESSION_COOKIE] = first_token
    get "/api/collection-runs", params: { tenant_id: second.tenant_id }
    assert_runs(first_only_id => [1, "no_work"], shared_id => [2, "no_work"])
    get "/api/collection-runs/#{first_only_id}/jobs"
    assert_response :ok
    assert_equal({ "jobs" => [] }, response.parsed_body)

    cookies[ApplicationController::SESSION_COOKIE] = second_token
    get "/api/collection-runs", params: { tenant_id: first.tenant_id }
    assert_runs(shared_id => [2, "no_work"])
    get "/api/collection-runs/#{shared_id}/jobs", params: { tenant_id: first.tenant_id }
    assert_response :ok
    assert_equal({ "jobs" => [] }, response.parsed_body)
    get "/api/collection-runs/#{first_only_id}/jobs", params: { tenant_id: first.tenant_id }
    assert_response :not_found
    refute response.parsed_body.key?("jobs")
  end

  test "catalog failure is planning_failed for its known audience and never successful empty work" do
    first_token, first = create_lawyer
    first_only_id = failed_plan(slot: 1)
    second_token, second = create_lawyer(name: "Bruno Lima", number: "000777-B", uf: "MG")
    shared_id = failed_plan(slot: 2)
    assert_empty persisted_jobs(first_only_id, first.tenant_id)
    assert_empty persisted_jobs(shared_id, first.tenant_id)
    assert_empty persisted_jobs(shared_id, second.tenant_id)

    cookies[ApplicationController::SESSION_COOKIE] = first_token
    get "/api/collection-runs", params: { tenant_id: second.tenant_id }
    assert_runs(first_only_id => [1, "planning_failed"], shared_id => [2, "planning_failed"])

    cookies[ApplicationController::SESSION_COOKIE] = second_token
    get "/api/collection-runs", params: { tenant_id: first.tenant_id }
    assert_runs(shared_id => [2, "planning_failed"])
    get "/api/collection-runs/#{first_only_id}/jobs", params: { tenant_id: first.tenant_id }
    assert_response :not_found
    refute response.parsed_body.key?("jobs")
  end

  test "retrying a failed execution does not add a tenant created after its original audience" do
    first_token, first = create_lawyer
    run_id = failed_plan(slot: 1)
    second_token, second = create_lawyer(name: "Bruno Lima", number: "000777-B", uf: "MG")

    assert_equal run_id, plan(slot: 1)
    assert_empty persisted_jobs(run_id, second.tenant_id)
    refute_empty persisted_jobs(run_id, first.tenant_id)

    cookies[ApplicationController::SESSION_COOKIE] = first_token
    get "/api/collection-runs"
    assert_runs(run_id => [1, "planned"])

    cookies[ApplicationController::SESSION_COOKIE] = second_token
    get "/api/collection-runs", params: { tenant_id: first.tenant_id }
    assert_response :ok
    assert_equal({ "runs" => [] }, response.parsed_body)
    get "/api/collection-runs/#{run_id}/jobs", params: { tenant_id: first.tenant_id }
    assert_response :not_found
  end

  test "audiences force tenant RLS without granting global run reads or web writes" do
    first_token, first = create_lawyer
    second_token, second = create_lawyer(name: "Bruno Lima", number: "000777-B", uf: "MG")
    run_id = plan(slot: 1)
    connection = ApplicationRecord.connection
    table = connection.select_one(<<~SQL)
      SELECT relrowsecurity, relforcerowsecurity, pg_get_userbyid(relowner) AS owner
      FROM pg_class WHERE oid = 'public.collection_run_audiences'::regclass
    SQL
    assert_equal true, table.fetch("relrowsecurity")
    assert_equal true, table.fetch("relforcerowsecurity")
    assert_not_equal "advocacia_runtime", table.fetch("owner")
    assert_not_equal "advocacia_despachante", table.fetch("owner")
    assert_equal [], connection.select_values("SELECT tenant_id FROM public.collection_run_audiences")
    assert_equal [], connection.select_values("SELECT id FROM app_private.collection_runs_for_session()")
    assert_equal false, connection.select_value(
      "SELECT has_table_privilege(current_user, 'public.collection_runs', 'SELECT')")

    [[first_token, first], [second_token, second]].each do |token, lawyer|
      DatabaseContext.with_session(token) do
        quoted_run = connection.quote(run_id)
        query = "SELECT tenant_id FROM public.collection_run_audiences WHERE run_id = #{quoted_run}"
        assert_equal [lawyer.tenant_id], connection.select_values(query)
        connection.execute("SELECT set_config('app.tenant_id', #{connection.quote(first.tenant_id)}, true)")
        connection.execute("SELECT set_config('app.despachante', 'true', true)")
        assert_equal [lawyer.tenant_id], connection.select_values(query)
        %w[INSERT UPDATE DELETE TRUNCATE].each do |privilege|
          assert_equal false, connection.select_value(
            "SELECT has_table_privilege(current_user, 'public.collection_run_audiences', '#{privilege}')")
        end
        assert_equal [run_id], connection.select_values("SELECT id FROM app_private.collection_runs_for_session()")
      end
    end
    assert_equal [], connection.select_values("SELECT id FROM app_private.collection_runs_for_session()")
    assert_raises(PG::InsufficientPrivilege) { @database.exec("SELECT * FROM app_private.identities") }
    assert_raises(PG::InsufficientPrivilege) { @database.exec("SELECT * FROM app_private.sessions") }
  end

  test "both endpoints require a server side session even with real run and tenant identifiers" do
    token, lawyer = create_lawyer
    run_id = plan(slot: 1)

    ["/api/collection-runs", "/api/collection-runs/#{run_id}/jobs"].each do |path|
      get path, params: { tenant_id: lawyer.tenant_id }
      assert_authentication_required
    end
    assert IdentityStore.context(token)
  end

  test "revoking a session immediately denies both run and job reads" do
    token, lawyer = create_lawyer
    run_id = plan(slot: 1)
    cookies[ApplicationController::SESSION_COOKIE] = token
    IdentityStore.revoke(token)

    ["/api/collection-runs", "/api/collection-runs/#{run_id}/jobs"].each do |path|
      get path, params: { tenant_id: lawyer.tenant_id }
      assert_authentication_required
    end
    assert_nil IdentityStore.context(token)
  end

  test "a valid session without onboarding cannot inspect runs or jobs or invent a tenant" do
    _, lawyer = create_lawyer
    run_id = plan(slot: 1)
    token, = authenticated_session
    cookies[ApplicationController::SESSION_COOKIE] = token

    ["/api/collection-runs", "/api/collection-runs/#{run_id}/jobs"].each do |path|
      get path, params: { tenant_id: lawyer.tenant_id }
      assert_response :not_found
      assert_equal "onboarding_required", response.parsed_body.dig("error", "code")
      refute response.parsed_body.key?("runs")
      refute response.parsed_body.key?("jobs")
    end
    assert_nil IdentityStore.context(token).fetch("tenant_id")
    DatabaseContext.with_session(token) do
      assert_equal 0, Tenant.count
      assert_equal 0, Lawyer.count
    end
  end

  private

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

  def failed_plan(slot:)
    unavailable = -> { raise CourtCatalog::Unavailable, "DJEN indisponível" }
    CourtCatalog.stub(:fetch, unavailable) do
      assert_raises(CourtCatalog::Unavailable) do
        CollectionDespachante.new(url: @despachante_url).plan(slot: slot, now: @now)
      end
    end
    rows = @database.exec_params(
      "SELECT id, status FROM public.collection_runs WHERE collection_date = $1 AND slot = $2", [@date, slot]).to_a
    assert_equal 1, rows.length
    assert_equal "planning_failed", rows.first.fetch("status")
    rows.first.fetch("id")
  end

  def persisted_jobs(run_id, tenant_id)
    @database.exec_params(<<~SQL, [run_id, tenant_id]).map do |job|
      SELECT id, entity_type, entity_id, court, medium, criteria::text, status, source
      FROM public.collection_jobs WHERE run_id = $1 AND tenant_id = $2
    SQL
      job.merge("criteria" => JSON.parse(job.fetch("criteria")))
    end
  end

  def assert_runs(expected)
    assert_response :ok
    assert_equal "application/json", response.media_type
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal ["runs"], response.parsed_body.keys
    actual = response.parsed_body.fetch("runs")
    actual.each { |run| assert_equal %w[collection_date id slot status], run.keys.sort }
    rows = expected.map do |id, (slot, status)|
      { "id" => id, "collection_date" => @date.iso8601, "slot" => slot, "status" => status }
    end
    assert_equal rows.sort_by { |run| run.fetch("id") }, actual.sort_by { |run| run.fetch("id") }
  end

  def assert_jobs(expected)
    assert_response :ok
    assert_equal "application/json", response.media_type
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal ["jobs"], response.parsed_body.keys
    actual = response.parsed_body.fetch("jobs")
    actual.each do |job|
      assert_equal %w[court criteria entity_id entity_type id medium status], job.except("source").keys.sort
      assert_equal "DJEN", job.fetch("source") if job.key?("source")
    end
    assert_equal expected.map { |job| normalized_job(job) }.sort_by { |job| job.fetch("id") },
      actual.map { |job| normalized_job(job) }.sort_by { |job| job.fetch("id") }
  end

  def normalized_job(job)
    normalized = job.except("source").deep_dup
    oabs = normalized.fetch("criteria")["oabs"]
    oabs&.sort_by! { |oab| [oab.fetch("number"), oab.fetch("uf")] }
    normalized
  end

  def assert_authentication_required
    assert_response :unauthorized
    assert_equal "authentication_required", response.parsed_body.dig("error", "code")
    refute response.parsed_body.key?("runs")
    refute response.parsed_body.key?("jobs")
  end
end
