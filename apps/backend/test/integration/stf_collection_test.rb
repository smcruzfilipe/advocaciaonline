require "test_helper"
require "pg"
require "json"
require "timeout"

class StfCollectionTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @processor_url = ENV.fetch("PROCESSADOR_DATABASE_URL")
    @processor = PG.connect(@processor_url)
    @runtime = PG.connect(ENV.fetch("DATABASE_URL"))
    @migrator = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    @despachante = PG.connect(ENV.fetch("DESPACHANTE_DATABASE_URL"))
    @session_a, = authenticated_session(owner: true)
    @lawyer_a = LawyerOnboarding.call(token: @session_a, input: profile_payload)
    @session_b, = authenticated_session(owner: true)
    @lawyer_b = LawyerOnboarding.call(token: @session_b, input: profile_payload.merge("full_name" => "Outra Advogada"))
    @date = @despachante.exec("SELECT (clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date::text").getvalue(0, 0)
    @run = create_run(@date)
    @job_a = create_job(@lawyer_a)
    @job_b = create_job(@lawyer_b)
    party = DatabaseContext.with_session(@session_a) do
      PartyMonitoring.create!(tenant_id: @lawyer_a.tenant_id, name: "Parte STF")
    end
    @job_a2 = create_job(@lawyer_a, entity_type: "party", entity_id: party.id)
  end

  teardown do
    [@processor, @runtime, @migrator, @despachante].each { |connection| connection&.close }
  end

  test "STF functions are fixed-path migrator definers executable only by processor" do
    signatures = %w[stf_processor_next() stf_processor_claim_available(uuid) stf_processor_job(uuid,text)
      stf_processor_renew(uuid,text) stf_processor_start(uuid,text) stf_processor_commit(uuid,text,jsonb)
      stf_processor_record_failure(uuid,text,text)]
    signatures.each do |signature|
      properties = @processor.exec_params(<<~SQL, ["app_private.#{signature}"]).first
        SELECT p.prosecdef, p.proconfig::text, pg_get_userbyid(p.proowner) AS owner,
          has_function_privilege('advocacia_processador', p.oid, 'EXECUTE') AS processor,
          has_function_privilege('advocacia_runtime', p.oid, 'EXECUTE') AS runtime,
          has_function_privilege('advocacia_despachante', p.oid, 'EXECUTE') AS scheduler,
          EXISTS (SELECT 1 FROM aclexplode(p.proacl) acl
            WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE') AS public_execute
        FROM pg_proc p WHERE p.oid = $1::regprocedure
      SQL
      assert_equal "t", properties.fetch("prosecdef"), signature
      assert_equal "advocacia_migrator", properties.fetch("owner"), signature
      assert_includes properties.fetch("proconfig"), "search_path=pg_catalog, pg_temp"
      assert_equal "t", properties.fetch("processor"), signature
      assert_equal "f", properties.fetch("runtime"), signature
      assert_equal "f", properties.fetch("scheduler"), signature
      assert_equal "f", properties.fetch("public_execute"), signature
    end
    assert_raises(PG::InsufficientPrivilege) { @processor.exec("SELECT app_private.require_djen_job(NULL)") }
    assert_equal "t", @migrator.exec("SELECT relforcerowsecurity FROM pg_class WHERE oid = 'public.stf_captures'::regclass").getvalue(0, 0)
  end

  test "same run reuses ordinal items for multiple jobs without merging equal movements or tenants" do
    proof = start(@job_a)
    original = movement("2026-11-01T10:00:00Z")
    result = commit(@job_a, proof, [{ incidente: 123, items: [original, original] }])
    assert_equal({ "state" => "succeeded", "source_path" => "andamentos", "matched_count" => 2,
      "pending_identity_count" => 2, "eligible_process_count" => 1 }, result)
    second = start(@job_a2)
    assert_equal result, commit(@job_a2, second, [{ incidente: 123,
      items: [movement("2026-11-01T11:00:00Z"), movement("2026-11-01T11:00:00Z")] }])
    assert_equal result, commit(@job_a, proof, [])
    rows = @migrator.exec_params(<<~SQL, [@lawyer_a.tenant_id]).to_a
      SELECT communication.id, communication.stf_ordinal, communication.identity_status, communication.warning,
        communication.source_id, communication.source_hash, communication.identity_digest, communication.payload,
        (SELECT count(*) FROM public.collection_communication_links link WHERE link.communication_id = communication.id) AS links
      FROM public.collection_communications communication
      WHERE communication.tenant_id = $1 AND communication.source = 'STF' ORDER BY stf_ordinal
    SQL
    assert_equal %w[1 2], rows.map { |row| row.fetch("stf_ordinal") }
    assert_equal 2, rows.map { |row| row.fetch("id") }.uniq.size
    rows.each do |row|
      assert_equal "pending", row.fetch("identity_status")
      assert_equal "possible_duplicate", row.fetch("warning")
      assert_nil row.fetch("source_id")
      assert_nil row.fetch("source_hash")
      assert_nil row.fetch("identity_digest")
      assert_equal "2", row.fetch("links")
      assert_equal "2026-11-01T10:00:00Z", JSON.parse(row.fetch("payload")).fetch("stf").fetch("capturado_em")
    end
    other = start(@job_b)
    commit(@job_b, other, [{ incidente: 123, items: [original] }])
    @runtime.exec("BEGIN")
    @runtime.exec_params("SELECT set_config('app.session_hash', $1, true)", [IdentityStore.digest(@session_a)])
    assert_equal "1", @runtime.exec("SELECT count(*) FROM public.stf_captures").getvalue(0, 0)
    assert_equal "2", @runtime.exec("SELECT count(*) FROM public.collection_communications WHERE source = 'STF'").getvalue(0, 0)
    assert_raises(PG::InsufficientPrivilege) { @processor.exec("SELECT * FROM public.stf_captures") }
  ensure
    @runtime.exec("ROLLBACK") if @runtime.transaction_status != PG::PQTRANS_IDLE
  end

  test "divergent same-capture data fails atomically and empty outcomes stay distinguishable" do
    first = start(@job_a)
    commit(@job_a, first, [{ incidente: 123, items: [movement("one")] }])
    second = start(@job_a2)
    changed = movement("two").merge("texto" => "alterado")
    assert_raises(PG::InvalidParameterValue) do
      commit(@job_a2, second, [{ incidente: 555, items: [movement("two")] }, { incidente: 123, items: [changed] }])
    end
    assert_equal "0", @migrator.exec_params("SELECT count(*) FROM public.stf_captures WHERE tenant_id = $1 AND incidente = 555", [@lawyer_a.tenant_id]).getvalue(0, 0)
    result = commit(@job_a2, second, [{ incidente: 123, items: [movement("two")] }, { incidente: 555, items: [] }])
    assert_equal 2, result.fetch("eligible_process_count")
    assert_equal 1, result.fetch("matched_count")
    empty = commit(@job_b, start(@job_b), [])
    assert_equal 0, empty.fetch("eligible_process_count")
    assert_equal 0, empty.fetch("matched_count")
    stored = @migrator.exec_params("SELECT eligible_process_count FROM public.collection_job_results WHERE job_id = $1", [@job_a2]).getvalue(0, 0)
    assert_equal "2", stored
  end

  test "eligible process without movements differs from no eligible processes" do
    empty_process = commit(@job_a, start(@job_a), [{ incidente: 123, items: [] }])
    no_process = commit(@job_b, start(@job_b), [])
    assert_equal [0, 1], empty_process.values_at("matched_count", "eligible_process_count")
    assert_equal [0, 0], no_process.values_at("matched_count", "eligible_process_count")
    assert_equal "1", @migrator.exec_params("SELECT count(*) FROM public.stf_captures WHERE tenant_id = $1", [@lawyer_a.tenant_id]).getvalue(0, 0)
    assert_equal "0", @migrator.exec_params("SELECT count(*) FROM public.stf_captures WHERE tenant_id = $1", [@lawyer_b.tenant_id]).getvalue(0, 0)
  end

  test "lease source and wrong tenant proofs cannot mutate a job" do
    token = claim(@job_a)
    other = claim(@job_b)
    assert_raises(PG::InvalidAuthorizationSpecification) { commit(@job_a, other, []) }
    %w[processor_claim processor_claim_available].each do |function|
      assert_raises(PG::InvalidAuthorizationSpecification) { @processor.exec_params("SELECT * FROM app_private.#{function}($1)", [@job_a]) }
    end
    %w[processor_job processor_renew processor_start processor_finish processor_fail].each do |function|
      assert_raises(PG::InvalidAuthorizationSpecification) { @processor.exec_params("SELECT * FROM app_private.#{function}($1,$2)", [@job_a, token]) }
    end
    assert_raises(PG::InvalidAuthorizationSpecification) { @processor.exec_params("SELECT app_private.processor_record_failure($1,$2,'processing_failed')", [@job_a, token]) }
    [
      ["SELECT app_private.processor_commit($1,$2,'caderno','[]'::jsonb)", [@job_a, token]],
      ["SELECT app_private.processor_attempt_begin($1,$2,1)", [@job_a, token]],
      ["SELECT app_private.processor_attempt_failed($1,$2,0,1,1,1)", [@job_a, token]],
      ["SELECT app_private.processor_defer($1,$2,1)", [@job_a, token]],
      ["SELECT app_private.processor_release($1,$2)", [@job_a, token]],
      ["SELECT app_private.processor_source_deadline($1,$2)", [@job_a, token]]
    ].each do |sql, arguments|
      assert_raises(PG::InvalidAuthorizationSpecification) { @processor.exec_params(sql, arguments) }
    end
    djen = create_job(@lawyer_a, source: "DJEN", court: "TJAC", medium: "D")
    djen_token = @processor.exec_params("SELECT * FROM app_private.processor_claim($1)", [djen]).first.fetch("token")
    assert_raises(PG::InvalidAuthorizationSpecification) { claim(djen) }
    assert_raises(PG::InvalidAuthorizationSpecification) { @processor.exec_params("SELECT app_private.stf_processor_job($1,$2)", [djen, djen_token]) }
    %w[stf_processor_renew stf_processor_start].each do |function|
      assert_raises(PG::InvalidAuthorizationSpecification) { @processor.exec_params("SELECT * FROM app_private.#{function}($1,$2)", [djen, djen_token]) }
    end
    assert_raises(PG::InvalidAuthorizationSpecification) { commit(djen, djen_token, []) }
    assert_raises(PG::InvalidAuthorizationSpecification) do
      @processor.exec_params("SELECT app_private.stf_processor_record_failure($1,$2,'processing_failed')", [djen, djen_token])
    end
    @migrator.exec_params("UPDATE public.collection_job_executions SET lease_expires_at = clock_timestamp() WHERE job_id = $1", [@job_a])
    assert_raises(PG::InvalidAuthorizationSpecification) { @processor.exec_params("SELECT * FROM app_private.stf_processor_renew($1,$2)", [@job_a, token]) }
    replacement = claim(@job_a)
    assert_not_equal token, replacement
    assert_raises(PG::InvalidAuthorizationSpecification) { commit(@job_a, token, []) }
  end

  test "next skips locked and leased work and excludes DJEN" do
    djen = create_job(@lawyer_a, source: "DJEN", court: "TJAC", medium: "D")
    @migrator.exec("BEGIN")
    @migrator.exec_params("SELECT job_id FROM public.collection_job_executions WHERE NOT job_id = ANY($1::uuid[]) FOR UPDATE", ["{#{@job_a},#{@job_b},#{djen}}"])
    @processor.exec("BEGIN")
    first = @processor.exec("SELECT * FROM app_private.stf_processor_next()").first
    PG.connect(@processor_url) do |other|
      other.exec("BEGIN")
      second = other.exec("SELECT * FROM app_private.stf_processor_next()").first
      assert_equal [@job_a, @job_b].sort, [first.fetch("job_id"), second.fetch("job_id")].sort
      assert_empty other.exec("SELECT * FROM app_private.stf_processor_next()").to_a
      assert_equal djen, @processor.exec("SELECT * FROM app_private.processor_next(3)").first.fetch("job_id")
      other.exec("COMMIT")
    end
    @processor.exec("ROLLBACK")
    assert_equal first.fetch("job_id"), @processor.exec("SELECT * FROM app_private.stf_processor_next()").first.fetch("job_id")
  ensure
    @processor.exec("ROLLBACK") if @processor.transaction_status != PG::PQTRANS_IDLE
    @migrator.exec("ROLLBACK") if @migrator.transaction_status != PG::PQTRANS_IDLE
  end

  test "concurrent jobs reuse one committed capture after waiting" do
    first = start(@job_a)
    second = start(@job_a2)
    @processor.exec("BEGIN")
    expected = commit(@job_a, first, [{ incidente: 123, items: [movement("first")] }])
    pid = Queue.new
    worker = Thread.new do
      PG.connect(@processor_url) do |connection|
        pid << connection.backend_pid
        JSON.parse(connection.exec_params("SELECT app_private.stf_processor_commit($1,$2,$3::jsonb)",
          [@job_a2, second, JSON.generate([{ incidente: 123, items: [movement("second")] }])]).getvalue(0, 0))
      end
    end
    Timeout.timeout(15) do
      blocked_pid = pid.pop
      until @migrator.exec_params("SELECT $1::integer = ANY(pg_blocking_pids($2::integer))",
        [@processor.backend_pid, blocked_pid]).getvalue(0, 0) == "t"
        Thread.pass
      end
      @processor.exec("COMMIT")
      assert_equal expected, worker.value
    end
    assert_equal "1", @migrator.exec_params("SELECT count(*) FROM public.stf_captures WHERE tenant_id = $1 AND run_id = $2",
      [@lawyer_a.tenant_id, @run]).getvalue(0, 0)
    assert_equal "2", @migrator.exec_params("SELECT count(*) FROM public.collection_communication_links WHERE job_id = ANY($1::uuid[])",
      ["{#{@job_a},#{@job_a2}}"]).getvalue(0, 0)
  ensure
    @processor.exec("ROLLBACK") if @processor.transaction_status != PG::PQTRANS_IDLE
    worker&.kill if worker&.alive?
    worker&.join
  end

  test "lease expiring during capture lock wait rolls back every result and publication" do
    proof = start(@job_a)
    @migrator.exec_params("UPDATE public.collection_job_executions SET lease_expires_at = clock_timestamp() + interval '3 seconds' WHERE job_id = $1", [@job_a])
    @migrator.exec("BEGIN")
    @migrator.exec_params("SELECT pg_advisory_xact_lock(hashtextextended('stf:' || $1::text || ':' || $2::text, 0))", [@lawyer_a.tenant_id, @run])
    pid = Queue.new
    worker = Thread.new do
      PG.connect(@processor_url) do |connection|
        pid << connection.backend_pid
        begin
          connection.exec_params("SELECT app_private.stf_processor_commit($1,$2,$3::jsonb)",
            [@job_a, proof, JSON.generate([{ incidente: 123, items: [movement("first")] }])])
          nil
        rescue PG::Error => error
          error
        end
      end
    end
    Timeout.timeout(15) do
      blocked_pid = pid.pop
      until @migrator.exec_params("SELECT $1::integer = ANY(pg_blocking_pids($2::integer))",
        [@migrator.backend_pid, blocked_pid]).getvalue(0, 0) == "t"
        Thread.pass
      end
      @migrator.exec("SELECT pg_sleep(3.1)")
      @migrator.exec("COMMIT")
      assert_kind_of PG::InvalidAuthorizationSpecification, worker.value
    end
    assert_equal "0", @migrator.exec_params("SELECT count(*) FROM public.stf_captures WHERE tenant_id = $1", [@lawyer_a.tenant_id]).getvalue(0, 0)
    assert_equal "0", @migrator.exec_params("SELECT count(*) FROM public.collection_job_results WHERE job_id = $1", [@job_a]).getvalue(0, 0)
    assert_equal ["started"], @migrator.exec_params("SELECT event_type FROM public.collection_events WHERE job_id = $1", [@job_a]).column_values(0)
  ensure
    @migrator.exec("ROLLBACK") if @migrator.transaction_status != PG::PQTRANS_IDLE
    worker&.kill if worker&.alive?
    worker&.join
  end

  test "past work can record interruption but cannot commit and future work cannot be claimed" do
    today = Date.iso8601(@date)
    old_run, future_run = [today - 1, today + 1].map { |date| create_run(date.to_s) }
    old_job = create_job(@lawyer_a, run_id: old_run)
    future_job = create_job(@lawyer_a, run_id: future_run)
    assert_raises(PG::InvalidAuthorizationSpecification) { claim(future_job) }
    token = start(old_job)
    assert_raises(PG::InvalidAuthorizationSpecification) { commit(old_job, token, []) }
    assert_raises(PG::InvalidAuthorizationSpecification) do
      @processor.exec_params("SELECT app_private.stf_processor_record_failure($1,$2,'source_unavailable')", [old_job, token])
    end
    failure = JSON.parse(@processor.exec_params("SELECT app_private.stf_processor_record_failure($1,$2,'interrupted')", [old_job, token]).getvalue(0, 0))
    assert_equal({ "state" => "failed", "code" => "interrupted" }, failure)
  end

  test "capture foreign key cannot cross tenants" do
    commit(@job_a, start(@job_a), [{ incidente: 123, items: [movement("first")] }])
    capture = @migrator.exec_params("SELECT id FROM public.stf_captures WHERE tenant_id = $1", [@lawyer_a.tenant_id]).getvalue(0, 0)
    assert_raises(PG::ForeignKeyViolation) do
      @migrator.exec_params(<<~SQL, [@lawyer_b.tenant_id, capture, JSON.generate(movement("other"))])
        INSERT INTO public.collection_communications
          (tenant_id, source, identity_status, warning, stf_capture_id, stf_ordinal, payload)
        VALUES ($1, 'STF', 'pending', 'possible_duplicate', $2, 2, $3::jsonb)
      SQL
    end
  end

  private

  def create_run(date)
    @despachante.exec_params("INSERT INTO public.collection_runs (collection_date, slot, status) VALUES ($1, 1, 'planned') ON CONFLICT DO NOTHING", [date])
    @despachante.exec_params("SELECT id FROM public.collection_runs WHERE collection_date = $1 AND slot = 1", [date]).getvalue(0, 0)
  end

  def create_job(lawyer, run_id: @run, entity_type: "lawyer", entity_id: lawyer.id, source: "STF", court: "STF", medium: "A")
    @despachante.exec_params("INSERT INTO public.collection_run_audiences (run_id, tenant_id) VALUES ($1,$2) ON CONFLICT DO NOTHING", [run_id, lawyer.tenant_id])
    @despachante.exec_params(<<~SQL, [run_id, lawyer.tenant_id, entity_type, entity_id, source, court, medium]).getvalue(0, 0)
      INSERT INTO public.collection_jobs (run_id, tenant_id, entity_type, entity_id, source, court, medium, criteria)
      VALUES ($1,$2,$3,$4,$5,$6,$7,'{}'::jsonb) RETURNING id
    SQL
  end

  def movement(timestamp)
    { "siglaTribunal" => "STF", "numero_processo" => "0188263-19.2026.1.00.0000",
      "texto" => "Andamento", "stf" => { "incidente" => 123, "capturado_em" => timestamp } }
  end

  def claim(job)
    @processor.exec_params("SELECT * FROM app_private.stf_processor_claim_available($1)", [job]).first.fetch("token")
  end

  def start(job)
    proof = claim(job)
    @processor.exec_params("SELECT * FROM app_private.stf_processor_start($1,$2)", [job, proof])
    proof
  end

  def commit(job, proof, processes)
    JSON.parse(@processor.exec_params("SELECT app_private.stf_processor_commit($1,$2,$3::jsonb)",
      [job, proof, JSON.generate(processes)]).getvalue(0, 0))
  end
end
