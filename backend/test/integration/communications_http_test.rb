require "test_helper"
require "pg"
require "json"

class CommunicationsHttpTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  PROCESS_NUMBER = "00000010020268260001".freeze

  setup do
    https!
    host! URI(AppSettings.origin).host
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    @planner = PG.connect(ENV.fetch("DESPACHANTE_DATABASE_URL"))
    @processor = PG.connect(ENV.fetch("PROCESSADOR_DATABASE_URL"))
    assert_equal "advocacia_migrator", @admin.exec("SELECT current_user").getvalue(0, 0)
    assert_equal "advocacia_despachante", @planner.exec("SELECT current_user").getvalue(0, 0)
    assert_equal "advocacia_processador", @processor.exec("SELECT current_user").getvalue(0, 0)
    assert_equal "advocacia_runtime", ApplicationRecord.connection.select_value("SELECT current_user")
    @owner, = authenticated_session
    @lawyer = LawyerOnboarding.call(token: @owner, input: profile_payload)
    @member, = authenticated_session
    identity = IdentityStore.context(@member).fetch("identity_id")
    @membership = @admin.exec_params(<<~SQL, [@lawyer.tenant_id, identity]).getvalue(0, 0)
      INSERT INTO app_private.tenant_memberships
        (tenant_id, identity_id, role, invited_email, accepted_at, credential_started_at)
      VALUES ($1, $2, 'member', 'reader@example.test', clock_timestamp(), clock_timestamp()) RETURNING id
    SQL
    @admin.exec_params("UPDATE app_private.sessions SET selected_membership_id = $1 WHERE session_hash = $2",
      [@membership, IdentityStore.digest(@member)])
    date = @planner.exec("SELECT (clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date::text").getvalue(0, 0)
    @planner.exec_params(<<~SQL, [date])
      INSERT INTO public.collection_runs (collection_date, slot, status)
      VALUES ($1, 1, 'planned') ON CONFLICT DO NOTHING
    SQL
    @run = @planner.exec_params("SELECT id FROM public.collection_runs WHERE collection_date = $1 AND slot = 1", [date]).getvalue(0, 0)
    @sp_job = create_job("TJSP")
    @rj_job = create_job("TJRJ")
    cookies[ApplicationController::SESSION_COOKIE] = @member
  end

  teardown { [@admin, @planner, @processor].each { |connection| connection&.close } }

  test "anonymous and not onboarded identities cannot query communications" do
    cookies.delete(ApplicationController::SESSION_COOKIE)
    ["/api/communications", "/api/communications/#{SecureRandom.uuid}"].each do |path|
      get path
      assert_response :unauthorized
      assert_equal "authentication_required", response.parsed_body.dig("error", "code")
    end
    token, = authenticated_session
    cookies[ApplicationController::SESSION_COOKIE] = token
    get "/api/communications", params: { tenant_id: @lawyer.tenant_id }
    assert_response :not_found
    assert_equal "onboarding_required", response.parsed_body.dig("error", "code")
  end

  test "without groups communications stay independent and are grouped by their trusted tribunal without totals" do
    first, second = persist(@sp_job, publication(1), publication(2))
    other = persist(@rj_job, publication(3, court: "TJRJ")).sole

    get "/api/communications", params: { tenant_id: SecureRandom.uuid, court: "TJRJ", operation: "consultar_dashboard" }

    assert_json_response
    assert_equal ["courts"], response.parsed_body.keys
    assert_equal ["TJRJ", "TJSP"], response.parsed_body.fetch("courts").map { |group| group.fetch("court") }
    assert_equal [first, second].sort, court_communications("TJSP").map { |item| item.fetch("id") }.sort
    assert_equal [other], court_communications("TJRJ").map { |item| item.fetch("id") }
    court_communications("TJSP").each do |item|
      assert_equal "TJSP", item.fetch("court")
      assert_equal PROCESS_NUMBER, item.fetch("process_number")
      assert_equal "complete", item.fetch("identity_status")
      assert_nil item.fetch("warning")
      assert_equal %w[court id identity_status process_number source warning], item.keys.sort
    end
    response.parsed_body.fetch("courts").each { |group| assert_equal %w[communications court], group.keys.sort }
  end

  test "detail preserves the first source payload and every same court monitoring link without executing HTML" do
    payload = publication(1).merge("texto" => '<p>Origem &amp; partes</p><script>alert("fonte")</script>',
      "extra" => { "html" => '<img src=x onerror="alert(1)">' })
    id = persist(@sp_job, payload).sole
    repeated_job = create_party_job("TJSP")
    assert_equal [id], persist(repeated_job, payload.merge("texto" => "versão posterior", "numero_processo" => "outro processo"))

    get "/api/communications/#{id}", headers: { "Accept" => "text/html" }

    assert_json_response
    body = response.parsed_body
    assert_equal id, body.fetch("id")
    assert_equal "TJSP", body.fetch("court")
    assert_equal PROCESS_NUMBER, body.fetch("process_number")
    assert_equal payload, body.fetch("payload")
    assert_equal [@sp_job, repeated_job].sort, body.fetch("links").map { |link| link.fetch("job_id") }.sort
    body.fetch("links").each do |link|
      assert_equal "TJSP", link.fetch("court")
      assert_equal @run, link.fetch("run_id")
      assert_equal "D", link.fetch("medium")
      refute link.key?("criteria")
      refute link.key?("tenant_id")
    end
    refute_includes response.body, "<script>"
    refute_includes response.body, "<img"
    assert_includes response.body, "\\u003cscript\\u003e"
  end

  test "incomplete source keys remain separate pending communications with the original warning" do
    payload = publication(1).except("hash")
    first, second = persist(@sp_job, payload, payload)
    assert_not_equal first, second

    get "/api/communications"
    assert_json_response
    assert_equal [first, second].sort, court_communications("TJSP").map { |item| item.fetch("id") }.sort
    court_communications("TJSP").each do |item|
      assert_equal "pending", item.fetch("identity_status")
      assert_equal "possible_duplicate", item.fetch("warning")
    end
    get "/api/communications/#{first}"
    assert_json_response
    assert_equal "pending", response.parsed_body.fetch("identity_status")
    assert_equal "possible_duplicate", response.parsed_body.fetch("warning")
    assert_equal payload, response.parsed_body.fetch("payload")
  end

  test "a missing source process or tribunal is not replaced with monitoring criteria or fabricated source fields" do
    payload = publication(1).except("numero_processo", "siglaTribunal", "texto")
    id = persist(@sp_job, payload).sole

    get "/api/communications/#{id}"

    assert_json_response
    assert_equal "TJSP", response.parsed_body.fetch("court")
    refute response.parsed_body.key?("process_number")
    assert_equal payload, response.parsed_body.fetch("payload")
    refute response.parsed_body.fetch("payload").key?("texto")
    get "/api/communications"
    assert_json_response
    refute court_communications("TJSP").sole.key?("process_number")
  end

  test "a TJSP group filters both endpoints and cannot be widened by request parameters" do
    sp = persist(@sp_job, publication(1)).sole
    rj = persist(@rj_job, publication(2, court: "TJRJ")).sole
    assign_group(read_rule("TJSP"))

    get "/api/communications", params: { court: "TJRJ", tenant_id: SecureRandom.uuid, owner: true, groups: [] }
    assert_json_response
    assert_equal ["TJSP"], response.parsed_body.fetch("courts").map { |group| group.fetch("court") }
    assert_equal [sp], court_communications("TJSP").map { |item| item.fetch("id") }
    get "/api/communications/#{sp}"
    assert_json_response
    get "/api/communications/#{rj}"
    assert_communication_not_found
  end

  test "grants from multiple groups add and an explicit tribunal deny overrides them without hiding permitted tribunals" do
    sp = persist(@sp_job, publication(1)).sole
    rj = persist(@rj_job, publication(2, court: "TJRJ")).sole
    assign_group(read_rule("TJSP"))
    assign_group(read_rule("TJRJ"))
    get "/api/communications"
    assert_json_response
    assert_equal ["TJRJ", "TJSP"], response.parsed_body.fetch("courts").map { |group| group.fetch("court") }

    assign_group(read_rule("TJRJ", effect: "deny"))
    get "/api/communications"
    assert_json_response
    assert_equal [sp], court_communications("TJSP").map { |item| item.fetch("id") }
    assert_equal ["TJSP"], response.parsed_body.fetch("courts").map { |group| group.fetch("court") }
    get "/api/communications/#{rj}"
    assert_communication_not_found
  end

  test "dashboard and monitoring grants never grant communications and an empty group removes default reads" do
    id = persist(@sp_job, publication(1)).sole
    assign_group
    [nil, "consultar_dashboard", "consultar_monitoramentos"].each do |operation|
      assign_group({ "operation" => operation, "effect" => "allow", "court" => nil }) if operation
      get "/api/communications"
      assert_json_response
      assert_equal({ "courts" => [] }, response.parsed_body)
      get "/api/communications/#{id}"
      assert_communication_not_found
    end
  end

  test "a dashboard deny does not mask readable communication data or introduce dashboard totals in the list" do
    id = persist(@sp_job, publication(1)).sole
    assign_group(read_rule(nil), { "operation" => "consultar_dashboard", "effect" => "deny", "court" => nil })
    get "/api/communications"
    assert_json_response
    assert_equal ["courts"], response.parsed_body.keys
    assert_equal [id], court_communications("TJSP").map { |item| item.fetch("id") }
    get "/api/communications/#{id}"
    assert_json_response
  end

  test "the owner reads its own communications independently of group denies" do
    id = persist(@sp_job, publication(1)).sole
    assign_group(read_rule(nil, effect: "deny"), membership: IdentityStore.context(@owner).fetch("membership_id"))
    cookies[ApplicationController::SESSION_COOKIE] = @owner
    get "/api/communications"
    assert_json_response
    assert_equal [id], court_communications("TJSP").map { |item| item.fetch("id") }
    get "/api/communications/#{id}"
    assert_json_response
  end

  test "another tenant and a forbidden tribunal are indistinguishable from missing or malformed identifiers" do
    own = persist(@sp_job, publication(1)).sole
    denied = persist(@rj_job, publication(2, court: "TJRJ")).sole
    other_token, = authenticated_session
    other_lawyer = LawyerOnboarding.call(token: other_token, input: profile_payload)
    other_job = create_job("TJSP", lawyer: other_lawyer)
    foreign = persist(other_job, publication(1).merge("texto" => "conteúdo de outro tenant")).sole
    assign_group(read_rule("TJSP"))
    get "/api/communications", params: { tenant_id: other_lawyer.tenant_id }
    assert_json_response
    assert_equal [own], court_communications("TJSP").map { |item| item.fetch("id") }
    errors = [foreign, denied, SecureRandom.uuid, "not-a-uuid", "1' OR '1'='1"].map do |id|
      get "/api/communications/#{ERB::Util.url_encode(id)}", params: { tenant_id: other_lawyer.tenant_id }
      assert_communication_not_found
      response.parsed_body
    end
    assert_equal 1, errors.uniq.size

    DatabaseContext.with_session(@member) do
      bind = ActiveRecord::Relation::QueryAttribute.new("id", foreign, ActiveRecord::Type::String.new)
      assert_empty ApplicationRecord.connection.exec_query("SELECT id FROM public.collection_communications WHERE id = $1::uuid", "RLS proof", [bind])
    end
  end

  test "a later permitted tribunal link cannot release the payload first persisted in a forbidden tribunal" do
    payload = publication(1, court: "TJRJ").merge("texto" => "origem TJRJ restrita")
    missing_tribunal = publication(2).except("siglaTribunal").merge("texto" => "origem restrita sem sigla")
    ids = persist(@rj_job, payload, missing_tribunal)
    assert_equal ids.sort, persist(@sp_job,
      payload.merge("siglaTribunal" => "TJSP", "texto" => "reencontro"),
      missing_tribunal.merge("siglaTribunal" => "TJSP")).sort
    assign_group(read_rule("TJSP"))

    get "/api/communications"
    assert_json_response
    assert_equal({ "courts" => [] }, response.parsed_body)
    refute_includes response.body, "origem TJRJ restrita"
    ids.each do |id|
      get "/api/communications/#{id}"
      assert_communication_not_found
    end
  end

  test "later links in another tribunal do not reclassify the first payload or expose cross tribunal links" do
    payload = publication(1).except("siglaTribunal")
    id = persist(@sp_job, payload).sole
    assert_equal [id], persist(@rj_job, publication(1, court: "TJRJ").merge("numero_processo" => "processo de outro tribunal"))
    cookies[ApplicationController::SESSION_COOKIE] = @owner
    get "/api/communications/#{id}"
    assert_json_response
    assert_equal [@sp_job, @rj_job].sort, response.parsed_body.fetch("links").map { |link| link.fetch("job_id") }.sort
    cookies[ApplicationController::SESSION_COOKIE] = @member
    assign_group(read_rule("TJSP"))
    get "/api/communications"
    assert_json_response
    assert_equal ["TJSP"], response.parsed_body.fetch("courts").map { |group| group.fetch("court") }
    assert_equal [id], court_communications("TJSP").map { |item| item.fetch("id") }
    get "/api/communications/#{id}"
    assert_json_response
    assert_equal payload, response.parsed_body.fetch("payload")
    assert_equal PROCESS_NUMBER, response.parsed_body.fetch("process_number")
    assert_equal [@sp_job], response.parsed_body.fetch("links").map { |link| link.fetch("job_id") }
    refute_includes response.body, "TJRJ"
  end

  test "pending communications with malformed source tribunals remain visible while a conflicting court requires permission" do
    items = ["TJRJ", nil, ["TJSP"], 123].each_with_index.map { |court, index| publication(index + 1).merge("siglaTribunal" => court) }
    items[1].delete("hash")
    ids = persist(@sp_job, *items)
    get "/api/communications"
    assert_json_response
    assert_equal ids.sort, court_communications("TJSP").map { |item| item.fetch("id") }.sort
    assert_equal "possible_duplicate", court_communications("TJSP").find { |item| item["identity_status"] == "pending" }.fetch("warning")

    assign_group(read_rule("TJSP"))
    get "/api/communications"
    assert_json_response
    assert_equal ids.drop(1).sort, court_communications("TJSP").map { |item| item.fetch("id") }.sort
    get "/api/communications/#{ids.first}"
    assert_communication_not_found
  end

  test "ambiguous earliest links across tribunals fail closed even for an unrestricted identity" do
    id = persist(@sp_job, publication(1).except("siglaTribunal")).sole
    @admin.exec_params(<<~SQL, [@lawyer.tenant_id, id, @rj_job, @sp_job])
      INSERT INTO public.collection_communication_links (tenant_id, communication_id, job_id, recorded_at)
      SELECT $1, $2, $3, recorded_at FROM public.collection_communication_links
      WHERE communication_id = $2 AND job_id = $4
    SQL
    get "/api/communications"
    assert_json_response
    assert_equal({ "courts" => [] }, response.parsed_body)
    get "/api/communications/#{id}"
    assert_communication_not_found
  end

  test "revoked and expired memberships lose both endpoints with a previously open session" do
    id = persist(@sp_job, publication(1)).sole
    get "/api/communications/#{id}"
    assert_json_response
    @admin.exec_params("UPDATE app_private.tenant_memberships SET expires_at = clock_timestamp() - interval '1 second' WHERE id = $1", [@membership])
    ["/api/communications", "/api/communications/#{id}"].each do |path|
      get path
      assert_response :unauthorized
      refute_includes response.body, PROCESS_NUMBER
    end
    @admin.exec_params("UPDATE app_private.tenant_memberships SET expires_at = NULL, revoked_at = clock_timestamp() WHERE id = $1", [@membership])
    ["/api/communications", "/api/communications/#{id}"].each do |path|
      get path
      assert_response :unauthorized
      refute_includes response.body, PROCESS_NUMBER
    end
  end

  test "revocation after the authentication callback cannot authorize from its memoized context" do
    id = persist(@sp_job, publication(1)).sole
    original = IdentityStore.method(:context)
    revoked = false
    callback = lambda do |token|
      value = original.call(token)
      unless revoked
        @admin.exec_params("UPDATE app_private.tenant_memberships SET revoked_at = clock_timestamp() WHERE id = $1", [@membership])
        revoked = true
      end
      value
    end
    IdentityStore.stub(:context, callback) { get "/api/communications/#{id}" }
    assert_response :forbidden
    assert_equal "permission_denied", response.parsed_body.dig("error", "code")
    refute_includes response.body, PROCESS_NUMBER
  end

  test "credential expiration while reading discards both list and detail instead of returning already loaded data" do
    id = persist(@sp_job, publication(1)).sole
    ["/api/communications", "/api/communications/#{id}"].each do |path|
      @admin.exec_params("UPDATE app_private.tenant_memberships SET expires_at = NULL WHERE id = $1", [@membership])
      expired = false
      callback = lambda do |_name, _started, _finished, _id, payload|
        if !expired && payload[:name] == "Authorized communications"
          @admin.exec_params("UPDATE app_private.tenant_memberships SET expires_at = clock_timestamp() - interval '1 second' WHERE id = $1", [@membership])
          expired = true
        end
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get path }
      assert expired, "The protected communications read was not observed"
      assert_response :forbidden
      assert_equal "permission_denied", response.parsed_body.dig("error", "code")
      refute_includes response.body, PROCESS_NUMBER
    end
  end

  test "query cache cannot carry communication data between tenants or across a changed group decision" do
    own = persist(@sp_job, publication(1)).sole
    other_token, = authenticated_session
    other_lawyer = LawyerOnboarding.call(token: other_token, input: profile_payload)
    foreign = persist(create_job("TJSP", lawyer: other_lawyer), publication(1)).sole

    ApplicationRecord.cache do
      cached_read = false
      callback = lambda do |_name, _started, _finished, _id, payload|
        cached_read = true if payload[:cached] && payload[:sql].include?("collection_communications")
      end
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
        DatabaseContext.with_session(@member) do
          2.times do
            assert_equal [own], ApplicationRecord.connection.select_values("SELECT id FROM public.collection_communications ORDER BY id")
          end
        end
      end
      assert cached_read, "The isolation scenario must exercise the real Rails query cache"
      get "/api/communications"
      assert_json_response
      assert_equal [own], court_communications("TJSP").map { |item| item.fetch("id") }
      cookies[ApplicationController::SESSION_COOKIE] = other_token
      get "/api/communications"
      assert_json_response
      assert_equal [foreign], court_communications("TJSP").map { |item| item.fetch("id") }
      cookies[ApplicationController::SESSION_COOKIE] = @member
      get "/api/communications/#{foreign}"
      assert_communication_not_found
      get "/api/communications/#{own}"
      assert_json_response
      assign_group(read_rule("TJSP", effect: "deny"))
      get "/api/communications"
      assert_json_response
      assert_equal({ "courts" => [] }, response.parsed_body)
      get "/api/communications/#{own}"
      assert_communication_not_found
    end
  end

  test "malformed process values remain only in the untrusted payload rather than becoming a process number" do
    payload = publication(1).merge("numero_processo" => { "html" => "<script>fonte</script>" })
    id = persist(@sp_job, payload).sole
    get "/api/communications/#{id}"
    assert_json_response
    refute response.parsed_body.key?("process_number")
    assert_equal payload, response.parsed_body.fetch("payload")
  end

  private

  def create_job(court, lawyer: @lawyer, entity_type: "lawyer", entity_id: lawyer.id)
    @planner.exec_params("INSERT INTO public.collection_run_audiences (run_id, tenant_id) VALUES ($1, $2) ON CONFLICT DO NOTHING", [@run, lawyer.tenant_id])
    @planner.exec_params(<<~SQL, [@run, lawyer.tenant_id, entity_type, entity_id, court]).getvalue(0, 0)
      INSERT INTO public.collection_jobs (run_id, tenant_id, entity_type, entity_id, source, court, medium, criteria)
      VALUES ($1, $2, $3, $4, 'DJEN', $5, 'D', '{"number":"99999999999999999999"}'::jsonb) RETURNING id
    SQL
  end

  def create_party_job(court)
    party = DatabaseContext.with_session(@owner) do
      PartyMonitoring.create!(tenant_id: @lawyer.tenant_id, name: "Parte #{SecureRandom.hex(4)}")
    end
    create_job(court, entity_type: "party", entity_id: party.id)
  end

  def persist(job, *items)
    proof = @processor.exec_params("SELECT * FROM app_private.processor_claim($1)", [job]).first.fetch("token")
    @processor.exec_params("SELECT * FROM app_private.processor_start($1, $2)", [job, proof])
    @processor.exec_params("SELECT app_private.processor_attempt_begin($1, $2, 3)", [job, proof])
    result = JSON.parse(@processor.exec_params("SELECT app_private.processor_commit($1, $2, 'caderno', $3::jsonb)",
      [job, proof, JSON.generate(items)]).getvalue(0, 0))
    assert_equal "succeeded", result.fetch("state")
    @admin.exec_params(<<~SQL, [job]).column_values(0)
      SELECT communication.id FROM public.collection_communications AS communication
      JOIN public.collection_communication_links AS link ON link.communication_id = communication.id
        AND link.tenant_id = communication.tenant_id
      WHERE link.job_id = $1 ORDER BY communication.recorded_at, communication.id
    SQL
  end

  def publication(id, court: "TJSP")
    { "id" => id, "hash" => "communication-#{id}", "siglaTribunal" => court,
      "numero_processo" => PROCESS_NUMBER, "texto" => "Comunicação #{id}" }
  end

  def assign_group(*rules, membership: @membership)
    catalog = [{ code: "TJSP", name: "São Paulo" }, { code: "TJRJ", name: "Rio de Janeiro" }]
    CourtCatalog.stub(:fetch, catalog) do
      DatabaseContext.with_session(@owner) do
        group = AuthorizationGroupStore.create_group(name: "Consulta #{SecureRandom.hex(4)}")
        rules.each { |rule| AuthorizationGroupStore.create_rule(group_id: group.fetch("id"), input: rule) }
        AuthorizationGroupStore.assign_membership_group(membership_id: membership, group_id: group.fetch("id"))
      end
    end
  end

  def read_rule(court, effect: "allow")
    { "operation" => "consultar_comunicacoes", "effect" => effect, "court" => court }
  end

  def court_communications(court)
    response.parsed_body.fetch("courts").find { |group| group.fetch("court") == court }.fetch("communications")
  end

  def assert_json_response
    assert_response :ok
    assert_equal "application/json", response.media_type
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  def assert_communication_not_found
    assert_response :not_found
    assert_equal "application/json", response.media_type
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal({ "error" => { "code" => "communication_not_found", "message" => "Comunicação não encontrada." } }, response.parsed_body)
  end
end
