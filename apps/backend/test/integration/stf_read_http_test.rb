require "test_helper"
require "pg"
require "json"

class StfReadHttpTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    https!
    host! URI(AppSettings.origin).host
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    @planner = PG.connect(ENV.fetch("DESPACHANTE_DATABASE_URL"))
    @processor = PG.connect(ENV.fetch("PROCESSADOR_DATABASE_URL"))
    @owner, = authenticated_session(owner: true)
    @lawyer = LawyerOnboarding.call(token: @owner, input: profile_payload)
    @member, = authenticated_session
    identity = IdentityStore.context(@member).fetch("identity_id")
    @membership = @admin.exec_params(<<~SQL, [@lawyer.tenant_id, identity]).getvalue(0, 0)
      INSERT INTO app_private.tenant_memberships
        (tenant_id, identity_id, role, invited_email, accepted_at, credential_started_at)
      VALUES ($1, $2, 'member', 'stf-reader@example.test', clock_timestamp(), clock_timestamp()) RETURNING id
    SQL
    @admin.exec_params("UPDATE app_private.sessions SET selected_membership_id = $1 WHERE session_hash = $2",
      [@membership, IdentityStore.digest(@member)])
    @date = @planner.exec("SELECT (clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date::text").getvalue(0, 0)
    @planner.exec_params("INSERT INTO public.collection_runs (collection_date, slot, status) VALUES ($1, 1, 'planned') ON CONFLICT DO NOTHING", [@date])
    @run = @planner.exec_params("SELECT id FROM public.collection_runs WHERE collection_date = $1 AND slot = 1", [@date]).getvalue(0, 0)
  end

  teardown { [@admin, @planner, @processor].each { |connection| connection&.close } }

  test "public STF movements remain distinct pending and require tenant and tribunal authorization" do
    job = create_job(@owner, @lawyer)
    commit(job, [process_record(123, [movement(123), movement(123)])])
    own = communication_ids(job)
    assert_equal 2, own.length
    legacy = legacy_communication(job, 456, nil)
    private_id = legacy_communication(job, 457, { "publicidade" => "Sigiloso" })
    other_token, = authenticated_session(owner: true)
    other_lawyer = LawyerOnboarding.call(token: other_token, input: profile_payload)
    foreign_job = create_job(other_token, other_lawyer)
    commit(foreign_job, [process_record(123, [movement(123)])])
    foreign = communication_ids(foreign_job).sole

    cookies[ApplicationController::SESSION_COOKIE] = @member
    get "/api/communications", params: { tenant_id: other_lawyer.tenant_id }
    assert_response :ok
    items = response.parsed_body.fetch("courts").find { |group| group.fetch("court") == "STF" }.fetch("communications")
    assert_equal own.sort, items.map { |item| item.fetch("id") }.sort
    items.each do |item|
      assert_equal "STF", item.fetch("source")
      assert_equal "pending", item.fetch("identity_status")
      assert_equal "possible_duplicate", item.fetch("warning")
      assert_equal "Rcl 101463", item.fetch("process_identification")
    end
    get "/api/communications/#{own.first}"
    assert_response :ok
    assert_equal "Rcl 101463", response.parsed_body.fetch("process_identification")
    assert_equal movement(123), response.parsed_body.fetch("payload")
    [legacy, private_id, foreign].each do |id|
      get "/api/communications/#{id}"
      assert_response :not_found
    end

    assign_group("deny")
    get "/api/communications"
    assert_response :ok
    assert_empty response.parsed_body.fetch("courts")
    get "/api/communications/#{own.first}"
    assert_response :not_found

    cookies[ApplicationController::SESSION_COOKIE] = other_token
    get "/api/communications/#{foreign}"
    assert_response :ok
    get "/api/communications/#{own.first}"
    assert_response :not_found
  end

  test "execution returns persisted STF results without inventing zero for unstarted or failed work" do
    positive = create_job(@owner, @lawyer)
    empty_process = create_job(@owner, @lawyer, party: true)
    no_process = create_job(@owner, @lawyer, party: true)
    pending = create_job(@owner, @lawyer, party: true)
    failed = create_job(@owner, @lawyer, party: true)
    commit(positive, [process_record(123, [movement(123), movement(123)])])
    commit(empty_process, [process_record(124, [])])
    commit(no_process, [])
    token = start(failed)
    @processor.exec_params("SELECT app_private.stf_processor_record_failure($1,$2,'source_unavailable')", [failed, token])

    other_token, = authenticated_session(owner: true)
    other_lawyer = LawyerOnboarding.call(token: other_token, input: profile_payload)
    foreign = create_job(other_token, other_lawyer)
    commit(foreign, [])
    cookies[ApplicationController::SESSION_COOKIE] = @owner
    get "/api/collection-runs/#{@run}/execution", params: { tenant_id: other_lawyer.tenant_id }
    assert_response :ok
    jobs = response.parsed_body.fetch("jobs").index_by { |entry| entry.fetch("job_id") }
    refute jobs.key?(foreign)
    fields = %w[source_path eligible_process_count matched_count pending_identity_count]
    assert_equal ["andamentos", 1, 2, 2], jobs.fetch(positive).values_at(*fields)
    assert_equal ["andamentos", 1, 0, 0], jobs.fetch(empty_process).values_at(*fields)
    assert_equal ["andamentos", 0, 0, 0], jobs.fetch(no_process).values_at(*fields)
    [pending, failed].each { |id| assert_equal [nil, nil, nil, nil], jobs.fetch(id).values_at(*fields) }
    assert_equal "pending", jobs.fetch(pending).fetch("state")
    assert_equal "failed", jobs.fetch(failed).fetch("state")
  end

  private

  def create_job(token, lawyer, party: false)
    entity = if party
      DatabaseContext.with_session(token) do
        PartyMonitoring.create!(tenant_id: lawyer.tenant_id, name: "Parte #{SecureRandom.hex(4)}").id
      end
    else
      lawyer.id
    end
    @planner.exec_params("INSERT INTO public.collection_run_audiences (run_id, tenant_id) VALUES ($1,$2) ON CONFLICT DO NOTHING", [@run, lawyer.tenant_id])
    @planner.exec_params(<<~SQL, [@run, lawyer.tenant_id, party ? "party" : "lawyer", entity]).getvalue(0, 0)
      INSERT INTO public.collection_jobs (run_id, tenant_id, entity_type, entity_id, source, court, medium, criteria)
      VALUES ($1,$2,$3,$4,'STF','STF','A','{}') RETURNING id
    SQL
  end

  def process_record(incident, items)
    { "incidente" => incident, "cnj" => nil, "classe" => "Rcl", "identificacao" => "Rcl 101463",
      "em_tramitacao" => "Sim", "publicidade" => "Público", "capturado_em" => "#{@date}T00:00:00-03:00", "items" => items }
  end

  def movement(incident)
    { "siglaTribunal" => "STF", "numero_processo" => nil, "nomeClasse" => "Rcl", "texto" => "Andamento",
      "link" => "https://portal.stf.jus.br/processos/detalhe.asp?incidente=#{incident}",
      "stf" => { "incidente" => incident, "identificacao" => "Rcl 101463", "data_andamento" => @date,
        "titulo" => "Andamento", "julgador" => nil, "observacao" => nil, "links" => [],
        "url_coleta" => "https://portal.stf.jus.br/processos/abaAndamentos.asp?incidente=#{incident}",
        "capturado_em" => "#{@date}T00:00:00-03:00" } }
  end

  def start(job)
    token = @processor.exec_params("SELECT * FROM app_private.stf_processor_claim_available($1)", [job]).first.fetch("token")
    @processor.exec_params("SELECT * FROM app_private.stf_processor_start($1,$2)", [job, token])
    token
  end

  def commit(job, processes)
    @processor.exec_params("SELECT app_private.stf_processor_commit($1,$2,$3::jsonb)", [job, start(job), JSON.generate(processes)])
  end

  def communication_ids(job)
    @admin.exec_params("SELECT communication_id FROM public.collection_communication_links WHERE job_id = $1 ORDER BY communication_id", [job]).column_values(0)
  end

  def legacy_communication(job, incident, process_data)
    capture = @admin.exec_params(<<~SQL, [@lawyer.tenant_id, @run, incident, process_data&.to_json]).getvalue(0, 0)
      INSERT INTO public.stf_captures (tenant_id, run_id, incidente, semantic_items, process_data)
      VALUES ($1,$2,$3,'[]'::jsonb,$4::jsonb) RETURNING id
    SQL
    id = @admin.exec_params(<<~SQL, [@lawyer.tenant_id, capture, movement(incident).to_json]).getvalue(0, 0)
      INSERT INTO public.collection_communications (tenant_id, source, identity_status, warning, stf_capture_id, stf_ordinal, payload)
      VALUES ($1,'STF','pending','possible_duplicate',$2,1,$3::jsonb) RETURNING id
    SQL
    @admin.exec_params("INSERT INTO public.collection_communication_links (tenant_id, communication_id, job_id) VALUES ($1,$2,$3)", [@lawyer.tenant_id, id, job])
    id
  end

  def assign_group(effect)
    CourtCatalog.stub(:fetch, [{ code: "STF", name: "Supremo Tribunal Federal" }]) do
      DatabaseContext.with_session(@owner) do
        group = AuthorizationGroupStore.create_group(name: "STF #{SecureRandom.hex(4)}")
        AuthorizationGroupStore.create_rule(group_id: group.fetch("id"), input: { "operation" => "consultar_comunicacoes", "effect" => effect, "court" => "STF" })
        AuthorizationGroupStore.assign_membership_group(membership_id: @membership, group_id: group.fetch("id"))
      end
    end
  end
end
