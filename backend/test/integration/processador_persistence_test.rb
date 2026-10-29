require "test_helper"
require "pg"
require "json"
require "digest"
require "timeout"

class ProcessadorPersistenceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  LAWYER_NAME = "Guilherme Curcelli Guimarães".freeze
  TABLES = %w[collection_communications collection_communication_links collection_job_results collection_job_failures].freeze
  FUNCTIONS = {
    "processor_job(uuid,text)" => ["SELECT app_private.processor_job($1, $2)", 2],
    "processor_commit(uuid,text,text,jsonb)" => ["SELECT app_private.processor_commit($1, $2, $3, $4::jsonb)", 4],
    "processor_record_failure(uuid,text,text)" => ["SELECT app_private.processor_record_failure($1, $2, $3)", 3],
    "processor_attempt_begin(uuid,text,integer)" => ["SELECT app_private.processor_attempt_begin($1, $2, $3)", 3],
    "processor_attempt_failed(uuid,text,integer,integer,integer,integer)" => ["SELECT app_private.processor_attempt_failed($1, $2, $3, $4, $5, $6)", 6],
    "processor_defer(uuid,text,integer)" => ["SELECT app_private.processor_defer($1, $2, $3)", 3]
  }.freeze

  setup do
    @processor_url = ENV.fetch("PROCESSADOR_DATABASE_URL")
    @processor = PG.connect(@processor_url)
    @runtime = PG.connect(ENV.fetch("DATABASE_URL"))
    @migrator = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    @despachante = PG.connect(ENV.fetch("DESPACHANTE_DATABASE_URL"))
    { @processor => "advocacia_processador", @runtime => "advocacia_runtime",
      @migrator => "advocacia_migrator", @despachante => "advocacia_despachante" }.each do |connection, role|
      assert_equal role, connection.exec("SELECT current_user").getvalue(0, 0)
    end
    @session_a, = authenticated_session
    @lawyer_a = LawyerOnboarding.call(token: @session_a, input: profile_payload.merge("full_name" => LAWYER_NAME))
    @session_b, = authenticated_session
    @lawyer_b = LawyerOnboarding.call(token: @session_b, input: profile_payload.merge("full_name" => "Outro Advogado"))
    @date = @despachante.exec("SELECT (clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date::text").getvalue(0, 0)
    @run_id = create_run(@date, 1)
    @job_a = create_job(@lawyer_a)
    @job_b = create_job(@lawyer_b)
  end

  teardown do
    [@processor, @runtime, @migrator, @despachante].each { |connection| connection&.close }
  end

  test "processor reads the frozen Guilherme job only through a valid claim and ignores forged tenant context" do
    proof = claim(@job_a)
    other_proof = claim(@job_b)
    @processor.exec_params("SELECT set_config('app.tenant_id', $1, false)", [@lawyer_b.tenant_id])
    @processor.exec_params("SELECT set_config('app.session_hash', $1, false)", [IdentityStore.digest(@session_b)])
    job = processor_job(@job_a, proof)
    assert_equal @job_a, job.fetch("job_id")
    assert_equal @lawyer_a.tenant_id, job.fetch("tenant_id")
    assert_equal @run_id, job.fetch("run_id")
    assert_equal @date, job.fetch("collection_date")
    assert_equal LAWYER_NAME, job.fetch("criteria").fetch("name")
    assert_equal "pending", job.fetch("state")
    assert_equal "caderno", job.fetch("phase")
    assert_equal 0, job.fetch("caderno_attempts")
    assert_equal 0, job.fetch("fallback_attempts")
    assert_equal false, job.fetch("attempt_in_flight")
    assert_nil job.fetch("attempt_started_at")
    assert_nil job.fetch("next_attempt_at")
    refute job.key?("claim_digest")
    [nil, "", "bad", "a" * 64, other_proof].each do |invalid|
      assert_unavailable { processor_job(@job_a, invalid) }
      assert_unavailable { commit(@job_a, invalid, [publication]) }
      assert_unavailable { record_failure(@job_a, invalid, "source_unavailable") }
    end
    assert_unavailable { processor_job(@job_b, proof) }
    assert_unavailable { processor_job(SecureRandom.uuid, proof) }
    expire(@job_a)
    assert_unavailable { processor_job(@job_a, proof) }
    assert_unavailable { commit(@job_a, proof, []) }
    assert_unavailable { record_failure(@job_a, proof, "interrupted") }
    assert_empty communications(@lawyer_a)
  end

  test "second slot starts directly in fallback and never consumes a caderno attempt" do
    second_run = create_run(@date, 2)
    job = create_job(@lawyer_a, run_id: second_run)
    proof = claim(job)
    initial = processor_job(job, proof)
    assert_equal "D", initial.fetch("medium")
    assert_equal "fallback", initial.fetch("phase")
    assert_equal 0, initial.fetch("caderno_attempts")
    assert_equal 0, initial.fetch("fallback_attempts")
    assert_equal false, initial.fetch("attempt_in_flight")
    start(job, proof)
    assert_unavailable { commit(job, proof, [], source: "fallback") }

    attempt = attempt_begin(job, proof)
    assert_equal "fallback", attempt.fetch("phase")
    assert_equal 0, attempt.fetch("caderno_attempts")
    assert_equal 1, attempt.fetch("fallback_attempts")
    assert_unavailable { commit(job, proof, [publication], source: "caderno") }
    result = commit(job, proof, [publication], source: "fallback")
    assert_equal "succeeded", result.fetch("state")
    assert_equal 1, result.fetch("matched_count")
    persisted = @migrator.exec_params(<<~SQL, [job]).first
      SELECT execution.phase, execution.caderno_attempts, execution.fallback_attempts, result.source_path
      FROM public.collection_job_executions AS execution
      JOIN public.collection_job_results AS result ON result.job_id = execution.job_id
      WHERE execution.job_id = $1
    SQL
    assert_equal({ "phase" => "fallback", "caderno_attempts" => "0", "fallback_attempts" => "1",
      "source_path" => "fallback" }, persisted)
    assert_equal %w[started completed], event_types(job)
  end

  test "service functions have fixed definer ACLs while tenant tables force RLS and deny direct mutation" do
    FUNCTIONS.each do |signature, (sql, arity)|
      metadata = @migrator.exec_params(<<~SQL, ["app_private.#{signature}"]).first
        SELECT prosecdef, proconfig::text, pg_get_userbyid(proowner) AS owner,
          EXISTS (SELECT 1 FROM aclexplode(proacl) AS acl
            WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE') AS public_execute
        FROM pg_proc WHERE oid = $1::regprocedure
      SQL
      assert_equal "t", metadata.fetch("prosecdef")
      assert_equal "advocacia_migrator", metadata.fetch("owner")
      assert_equal "f", metadata.fetch("public_execute")
      assert_includes metadata.fetch("proconfig"), "search_path=pg_catalog, pg_temp"
      parameters = if signature.start_with?("processor_attempt_failed")
        [@job_a, "a" * 64, 0, 3, 60, 300]
      elsif signature.start_with?("processor_attempt_begin")
        [@job_a, "a" * 64, 3]
      elsif signature.start_with?("processor_defer")
        [@job_a, "a" * 64, 1]
      else
        [@job_a, "a" * 64, "caderno", "[]"].first(arity)
      end
      [@runtime, @despachante].each do |connection|
        assert_raises(PG::InsufficientPrivilege) { connection.exec_params(sql, parameters) }
      end
    end
    TABLES.each do |table|
      flags = @migrator.exec_params(<<~SQL, ["public.#{table}"]).first
        SELECT relrowsecurity, relforcerowsecurity FROM pg_class WHERE oid = $1::regclass
      SQL
      assert_equal "t", flags.fetch("relrowsecurity")
      assert_equal "t", flags.fetch("relforcerowsecurity")
      [@processor, @despachante].each do |connection|
        assert_raises(PG::InsufficientPrivilege) { connection.exec("SELECT * FROM public.#{table}") }
      end
      [@runtime, @processor, @despachante].each do |connection|
        ["INSERT INTO public.#{table} DEFAULT VALUES", "UPDATE public.#{table} SET tenant_id = tenant_id",
          "DELETE FROM public.#{table}", "TRUNCATE public.#{table}",
          "SELECT tenant_id FROM public.#{table} FOR UPDATE"].each do |sql|
          assert_raises(PG::InsufficientPrivilege) { connection.exec(sql) }
        end
      end
    end
    assert_raises(PG::InsufficientPrivilege) { @processor.exec("SELECT * FROM public.collection_jobs") }
    assert_raises(PG::InsufficientPrivilege) { @runtime.exec("SELECT caderno_attempts FROM public.collection_job_executions") }
  end

  test "complete joint identity deduplicates sources entities and runs while preserving first version and every link" do
    party_job = create_party_job
    second_run = create_run(@date, 2)
    later_job = create_job(@lawyer_a, run_id: second_run)
    first = publication.merge("texto" => "Primeira versão")
    commit_started(@job_a, [first])
    commit_started(party_job, [publication.merge("texto" => "Alteração que não substitui a primeira")], source: "fallback")
    commit_started(later_job, [publication], source: "fallback")
    commit_started(@job_b, [first])
    own = communications(@lawyer_a)
    assert_equal 1, own.length
    assert_equal first, JSON.parse(own.first.fetch("payload"))
    assert_equal "complete", own.first.fetch("identity_status")
    assert_nil own.first.fetch("warning")
    assert_equal 1, communications(@lawyer_b).length
    assert_not_equal own.first.fetch("id"), communications(@lawyer_b).first.fetch("id")
    assert_equal [@job_a, party_job, later_job].sort, @migrator.exec_params(<<~SQL, [own.first.fetch("id")]).column_values(0).sort
      SELECT job_id FROM public.collection_communication_links WHERE communication_id = $1
    SQL
    runtime_as(@session_a) do
      assert_equal [own.first.fetch("id")], @runtime.exec("SELECT id FROM public.collection_communications").column_values(0)
      @runtime.exec_params("SELECT set_config('app.tenant_id', $1, true)", [@lawyer_b.tenant_id])
      assert_empty @runtime.exec_params("SELECT id FROM public.collection_communications WHERE tenant_id = $1", [@lawyer_b.tenant_id]).to_a
      assert_empty @runtime.exec_params("SELECT job_id FROM public.collection_communication_links WHERE tenant_id = $1", [@lawyer_b.tenant_id]).to_a
    end
    runtime_as(@session_b) do
      assert_empty @runtime.exec_params("SELECT id FROM public.collection_communications WHERE tenant_id = $1", [@lawyer_a.tenant_id]).to_a
    end
    TABLES.each { |table| assert_empty @runtime.exec("SELECT tenant_id FROM public.#{table}").to_a }
  end

  test "changed id or hash is never collapsed even for the same process and court and long identifiers are exact" do
    long_hash = (1..600).map { |value| Digest::SHA256.hexdigest(value.to_s) }.join
    huge_id = 10**100 + 123
    items = [publication, publication.merge("id" => 2), publication.merge("hash" => "another"),
      publication.merge("id" => huge_id, "hash" => long_hash),
      publication.merge("id" => huge_id + 1, "hash" => long_hash)]
    commit_started(@job_a, items)
    extra = create_party_job
    commit_started(extra, [items[3]])
    rows = communications(@lawyer_a)
    assert_equal 5, rows.length
    large = rows.select { |row| row.fetch("source_hash") == long_hash }
    assert_equal [huge_id, huge_id + 1], large.map { |row| JSON.parse(row.fetch("payload")).fetch("id") }.sort
    assert_equal [long_hash], large.map { |row| row.fetch("source_hash") }.uniq
  end

  test "a digest collision candidate is not proof that complete source identities are equal" do
    # Administrative fixture models a colliding candidate without substituting
    # hashing or weakening the comparison used by the real processor function.
    @migrator.exec_params(<<~SQL, [@lawyer_a.tenant_id, JSON.generate(publication.merge("id" => 99, "hash" => "different"))])
      INSERT INTO public.collection_communications
        (tenant_id, source_id, source_hash, identity_digest, identity_status, payload)
      VALUES ($1, 99, 'different',
        sha256(convert_to(jsonb_build_array(1::numeric, 'fixture-joint-key'::text)::text, 'UTF8')), 'complete', $2::jsonb)
    SQL
    commit_started(@job_a, [publication])
    assert_equal 2, communications(@lawyer_a).length
    linked = @migrator.exec_params(<<~SQL, [@job_a]).first
      SELECT communication.source_id, communication.source_hash
      FROM public.collection_communication_links AS link
      JOIN public.collection_communications AS communication ON communication.id = link.communication_id
      WHERE link.job_id = $1
    SQL
    assert_equal "1", linked.fetch("source_id")
    assert_equal publication.fetch("hash"), linked.fetch("source_hash")
  end

  test "invalid key components remain separate pending records without numeric coercion or truncation" do
    invalid = [publication.except("id"), publication.except("hash"), publication.merge("id" => "1"),
      publication.merge("id" => 1.5), publication.merge("id" => 0), publication.merge("id" => -1),
      publication.merge("id" => true), publication.merge("hash" => 123), publication.merge("hash" => ""),
      publication.merge("hash" => nil)]
    result = commit_started(@job_a, invalid + [invalid.first])
    assert_equal invalid.length + 1, result.fetch("pending_identity_count")
    extra = create_party_job
    commit_started(extra, invalid)
    rows = communications(@lawyer_a)
    assert_equal invalid.length * 2 + 1, rows.length
    rows.each do |row|
      assert_equal "pending", row.fetch("identity_status")
      assert_equal "possible_duplicate", row.fetch("warning")
      assert_nil row.fetch("source_id")
      assert_nil row.fetch("source_hash")
    end
    runtime_as(@session_a) do
      assert_equal rows.length.to_s, @runtime.exec("SELECT count(*) FROM public.collection_communications WHERE warning = 'possible_duplicate'").getvalue(0, 0)
    end
  end

  test "composite foreign keys reject links results and failures crossing tenant boundaries" do
    commit_started(@job_a, [publication])
    communication_id = communications(@lawyer_a).first.fetch("id")
    assert_raises(PG::ForeignKeyViolation) do
      @migrator.exec_params(<<~SQL, [@lawyer_b.tenant_id, communication_id, @job_b])
        INSERT INTO public.collection_communication_links (tenant_id, communication_id, job_id)
        VALUES ($1, $2, $3)
      SQL
    end
    assert_raises(PG::ForeignKeyViolation) do
      @migrator.exec_params(<<~SQL, [@lawyer_a.tenant_id, communication_id, @job_b])
        INSERT INTO public.collection_communication_links (tenant_id, communication_id, job_id)
        VALUES ($1, $2, $3)
      SQL
    end
    assert_raises(PG::ForeignKeyViolation) do
      @migrator.exec_params(<<~SQL, [@job_b, @lawyer_a.tenant_id])
        INSERT INTO public.collection_job_results (job_id, tenant_id, source_path, matched_count, pending_identity_count)
        VALUES ($1, $2, 'caderno', 0, 0)
      SQL
    end
    assert_raises(PG::ForeignKeyViolation) do
      @migrator.exec_params(<<~SQL, [@job_b, @lawyer_a.tenant_id])
        INSERT INTO public.collection_job_failures (job_id, tenant_id, code) VALUES ($1, $2, 'interrupted')
      SQL
    end
  end

  test "commit requires running work valid shape source and current lease and completed jobs never persist again" do
    proof = claim(@job_a)
    assert_unavailable { commit(@job_a, proof, []) }
    start(@job_a, proof)
    assert_unavailable { commit(@job_a, proof, []) }
    attempt_begin(@job_a, proof)
    assert_unavailable { commit(@job_a, proof, [], source: "fallback") }
    [nil, {}, [publication, nil], [publication, []], [publication, "bad"]].each do |items|
      assert_raises(PG::InvalidParameterValue) { commit(@job_a, proof, items) }
    end
    assert_raises(PG::InvalidParameterValue) { commit(@job_a, proof, [], source: "API") }
    assert_empty communications(@lawyer_a)
    assert_equal "running", state(@job_a)
    result = commit(@job_a, proof, [publication])
    assert_equal "succeeded", result.fetch("state")
    assert_equal 1, result.fetch("matched_count")
    assert_unavailable { commit(@job_a, proof, [publication.merge("id" => 9)]) }
    assert_equal 1, communications(@lawyer_a).length
    assert_equal %w[started completed], event_types(@job_a)
    expire(@job_a)
    confirmation = claim(@job_a)
    assert_equal "succeeded", processor_job(@job_a, confirmation).fetch("state")
    assert_unavailable { commit(@job_a, confirmation, []) }
  end

  test "an active collection attempt cannot finish without persisting its result" do
    proof = claim(@job_a)
    start(@job_a, proof)
    attempt_begin(@job_a, proof)
    assert_unavailable { @processor.exec_params("SELECT * FROM app_private.processor_finish($1, $2)", [@job_a, proof]) }
    assert_equal "running", state(@job_a)
    assert_equal ["started"], event_types(@job_a)
    assert_equal "succeeded", commit(@job_a, proof, [publication]).fetch("state")
    assert_equal %w[started completed], event_types(@job_a)
  end

  test "a failed attempt cannot finish without persisting its result" do
    proof = claim(@job_a)
    start(@job_a, proof)
    attempt_begin(@job_a, proof)
    attempt_failed(@job_a, proof, 0)
    assert_unavailable { @processor.exec_params("SELECT * FROM app_private.processor_finish($1, $2)", [@job_a, proof]) }
    assert_equal "running", state(@job_a)
    assert_equal ["started"], event_types(@job_a)
  end

  test "concurrent jobs keep one complete communication with both links" do
    second_job = create_party_job
    proofs = [@job_a, second_job].map do |job|
      proof = claim(job)
      start(job, proof)
      attempt_begin(job, proof)
      [job, proof]
    end
    ready = Queue.new
    release = Queue.new
    workers = proofs.map do |job, proof|
      Thread.new do
        Thread.current.report_on_exception = false
        PG.connect(@processor_url) do |connection|
          ready << true
          release.pop
          JSON.parse(connection.exec_params("SELECT app_private.processor_commit($1, $2, 'caderno', $3::jsonb)",
            [job, proof, JSON.generate([publication])]).getvalue(0, 0))
        end
      end
    end
    results = Timeout.timeout(15) do
      2.times { ready.pop }
      2.times { release << true }
      workers.map(&:value)
    end
    assert_equal ["succeeded"], results.map { |result| result.fetch("state") }.uniq
    assert_equal 1, communications(@lawyer_a).length
    assert_equal "2", @migrator.exec_params("SELECT count(*) FROM public.collection_communication_links WHERE tenant_id = $1",
      [@lawyer_a.tenant_id]).getvalue(0, 0)
  ensure
    2.times { release << true } if release
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end

  test "a lease expiring during the tenant lock wait rolls back all commit effects" do
    proof = claim(@job_a)
    start(@job_a, proof)
    attempt_begin(@job_a, proof)
    @migrator.exec_params("UPDATE public.collection_job_executions SET lease_expires_at = clock_timestamp() + interval '5 seconds' WHERE job_id = $1", [@job_a])
    error = while_commit_blocked(@job_a, proof) do
      @migrator.exec_params(<<~SQL, [@job_a])
        SELECT pg_sleep(GREATEST(0, EXTRACT(EPOCH FROM lease_expires_at - clock_timestamp())) + 0.01)
        FROM public.collection_job_executions WHERE job_id = $1
      SQL
    end
    assert_instance_of PG::InvalidAuthorizationSpecification, error
    assert_equal "Processor operation unavailable", error.result.error_field(PG::Result::PG_DIAG_MESSAGE_PRIMARY)
    assert_empty communications(@lawyer_a)
    assert_equal "running", state(@job_a)
    assert_equal ["started"], event_types(@job_a)
    assert_equal "0", @migrator.exec_params("SELECT count(*) FROM public.collection_job_results WHERE job_id = $1", [@job_a]).getvalue(0, 0)
  end

  test "repeatable snapshots cannot bypass the serialized exact identity check" do
    proof = claim(@job_a)
    start(@job_a, proof)
    attempt_begin(@job_a, proof)
    @processor.exec("BEGIN ISOLATION LEVEL REPEATABLE READ")
    assert_unavailable { commit(@job_a, proof, [publication]) }
    @processor.exec("ROLLBACK")
    assert_empty communications(@lawyer_a)
    assert_equal "running", state(@job_a)
  ensure
    @processor.exec("ROLLBACK") if @processor.transaction_status != PG::PQTRANS_IDLE
  end

  test "publication links result and Escrevente completion roll back atomically including a finish write failure" do
    proof = claim(@job_a)
    start(@job_a, proof)
    attempt_begin(@job_a, proof)
    @processor.exec("BEGIN")
    commit(@job_a, proof, [publication])
    assert_empty communications(@lawyer_a)
    assert_equal "running", state(@job_a)
    assert_equal ["started"], event_types(@job_a)
    @processor.exec("ROLLBACK")
    @migrator.exec("BEGIN")
    @migrator.exec("ALTER TABLE public.collection_events ADD CONSTRAINT persistence_reject_completion CHECK (event_type <> 'completed') NOT VALID")
    @migrator.exec("COMMIT")
    assert_raises(PG::CheckViolation) { commit(@job_a, proof, [publication]) }
    assert_empty communications(@lawyer_a)
    assert_equal "running", state(@job_a)
    assert_equal ["started"], event_types(@job_a)
    assert_equal "0", @migrator.exec_params("SELECT count(*) FROM public.collection_job_results WHERE job_id = $1", [@job_a]).getvalue(0, 0)
  ensure
    @processor.exec("ROLLBACK") if @processor.transaction_status != PG::PQTRANS_IDLE
    @migrator.exec("ROLLBACK") if @migrator.transaction_status != PG::PQTRANS_IDLE
    @migrator.exec("ALTER TABLE public.collection_events DROP CONSTRAINT IF EXISTS persistence_reject_completion")
  end

  test "failure remains queryable outside minimal Escrevente and empty success is not failure or missing work" do
    extra = create_party_job
    runtime_as(@session_a) do
      assert_equal "running", court_state.fetch("state")
      assert_nil court_state.fetch("matched_count")
    end
    proof = claim(@job_a)
    start(@job_a, proof)
    @processor.exec("BEGIN")
    record_failure(@job_a, proof, "source_unavailable")
    assert_equal "running", state(@job_a)
    assert_equal "0", @migrator.exec_params("SELECT count(*) FROM public.collection_job_failures WHERE job_id = $1", [@job_a]).getvalue(0, 0)
    @processor.exec("ROLLBACK")
    assert_equal({ "state" => "failed", "code" => "processing_failed" }, record_failure(@job_a, proof, "secret #{LAWYER_NAME} token=hidden"))
    assert_equal ["started"], event_types(@job_a)
    assert_equal "failed", state(@job_a)
    runtime_as(@session_a) do
      assert_equal ["processing_failed"], @runtime.exec_params("SELECT code FROM public.collection_job_failures WHERE job_id = $1", [@job_a]).column_values(0)
      assert_equal "running", court_state.fetch("state"), "a pending job takes priority over final failure without success"
    end
    commit_started(extra, [])
    runtime_as(@session_a) do
      assert_equal "partial", court_state.fetch("state")
      assert_nil court_state.fetch("matched_count"), "partial failure is never presented as zero"
    end
    recovery = claim(@job_a)
    start(@job_a, recovery)
    attempt_begin(@job_a, recovery)
    commit(@job_a, recovery, [])
    runtime_as(@session_a) do
      summary = court_state
      assert_equal "succeeded", summary.fetch("state")
      assert_equal "0", summary.fetch("matched_count")
      assert_equal "0", summary.fetch("pending_identity_count")
      assert_equal "2", summary.fetch("succeeded_count")
      assert_equal "1", @runtime.exec_params("SELECT count(*) FROM public.collection_job_failures WHERE job_id = $1", [@job_a]).getvalue(0, 0)
    end
    runtime_as(@session_b) do
      assert_empty @runtime.exec_params("SELECT code FROM public.collection_job_failures WHERE job_id = $1", [@job_a]).to_a
      assert_equal "running", court_state.fetch("state")
    end
    assert_equal %w[started completed], event_types(@job_a)
    columns = @migrator.exec(<<~SQL).column_values(0)
      SELECT column_name FROM information_schema.columns
      WHERE table_name = 'collection_events' AND table_schema = 'public' ORDER BY ordinal_position
    SQL
    assert_equal %w[id job_id tenant_id event_type recorded_at], columns
  ensure
    @processor.exec("ROLLBACK") if @processor.transaction_status != PG::PQTRANS_IDLE
  end

  test "all terminal failures produce failed with null counts and visible audience with no jobs has no fake court success" do
    proof = claim(@job_a)
    record_failure(@job_a, proof, "source_unavailable")
    runtime_as(@session_a) do
      summary = court_state
      assert_equal "failed", summary.fetch("state")
      assert_equal "1", summary.fetch("failed_count")
      assert_nil summary.fetch("matched_count")
    end
    assert_empty event_types(@job_a)
    empty_run = create_run(@date, 2)
    @despachante.exec_params("INSERT INTO public.collection_run_audiences (run_id, tenant_id) VALUES ($1, $2) ON CONFLICT DO NOTHING", [empty_run, @lawyer_a.tenant_id])
    runtime_as(@session_a) do
      assert_empty @runtime.exec_params("SELECT * FROM app_private.collection_court_states($1)", [empty_run]).to_a
    end
  end

  test "a retry after received during an attempt survives a lost lease and cannot be shortened" do
    proof = claim(@job_a)
    start(@job_a, proof)
    assert_unavailable { @processor.exec_params("SELECT app_private.processor_defer($1, $2, 200)", [@job_a, proof]) }
    attempt_begin(@job_a, proof)
    @processor.exec_params("SELECT app_private.processor_defer($1, $2, 200)", [@job_a, proof])
    expire(@job_a)
    replacement = claim(@job_a)
    attempt_failed(@job_a, replacement, 0)
    seconds = @migrator.exec_params("SELECT EXTRACT(EPOCH FROM next_attempt_at - clock_timestamp()) FROM public.collection_job_executions WHERE job_id = $1", [@job_a]).getvalue(0, 0).to_f
    assert_operator seconds, :>, 190
    assert_unavailable { attempt_begin(@job_a, replacement) }
  end

  test "attempt counters leases retry after and resumed in flight work survive without a fourth attempt" do
    proof = claim(@job_a)
    start(@job_a, proof)
    first = attempt_begin(@job_a, proof)
    assert_equal 1, first.fetch("caderno_attempts")
    assert_equal true, first.fetch("attempt_in_flight")
    assert_unavailable { attempt_begin(@job_a, proof) }
    failed = attempt_failed(@job_a, proof, 120)
    assert_equal false, failed.fetch("attempt_in_flight")
    seconds = @migrator.exec_params("SELECT EXTRACT(EPOCH FROM next_attempt_at - clock_timestamp()) FROM public.collection_job_executions WHERE job_id = $1", [@job_a]).getvalue(0, 0).to_f
    assert_operator seconds, :>, 110
    assert_unavailable { attempt_begin(@job_a, proof) }
    allow_retry(@job_a)
    attempt_begin(@job_a, proof)
    expire(@job_a)
    replacement = claim(@job_a)
    inherited = processor_job(@job_a, replacement)
    assert_equal 2, inherited.fetch("caderno_attempts")
    assert_equal true, inherited.fetch("attempt_in_flight")
    assert_unavailable { attempt_begin(@job_a, replacement) }
    assert_unavailable { attempt_failed(@job_a, proof, nil) }
    attempt_failed(@job_a, replacement, nil)
    allow_retry(@job_a)
    attempt_begin(@job_a, replacement)
    switched = attempt_failed(@job_a, replacement, nil)
    assert_equal "fallback", switched.fetch("phase")
    assert_equal 3, switched.fetch("caderno_attempts")
    assert_equal false, switched.fetch("exhausted")
    3.times do |index|
      allow_retry(@job_a)
      attempt = attempt_begin(@job_a, replacement)
      assert_equal index + 1, attempt.fetch("fallback_attempts")
      exhausted = attempt_failed(@job_a, replacement, nil)
      assert_equal index == 2, exhausted.fetch("exhausted")
    end
    allow_retry(@job_a)
    assert_unavailable { attempt_begin(@job_a, replacement) }
    assert_equal "running", state(@job_a), "exhaustion is not a fabricated success or final failure"
    record_failure(@job_a, replacement, "source_unavailable")
    assert_equal "failed", state(@job_a)
  end

  test "attempt limits backoffs and retry after reject invalid configuration without consuming work" do
    proof = claim(@job_a)
    start(@job_a, proof)
    [nil, 0, 4].each do |limit|
      assert_raises(PG::InvalidParameterValue) { attempt_begin(@job_a, proof, limit: limit) }
    end
    assert_equal 0, processor_job(@job_a, proof).fetch("caderno_attempts")
    attempt_begin(@job_a, proof, limit: 1)
    [{ limit: 0 }, { backoff_1: 0 }, { backoff_2: -1 }].each do |configuration|
      assert_raises(PG::InvalidParameterValue) { attempt_failed(@job_a, proof, nil, **configuration) }
    end
    assert_raises(PG::InvalidParameterValue) { attempt_failed(@job_a, proof, -1) }
    assert_equal true, processor_job(@job_a, proof).fetch("attempt_in_flight")
    switched = attempt_failed(@job_a, proof, nil, limit: 1)
    assert_equal "fallback", switched.fetch("phase")
    assert_equal 1, switched.fetch("caderno_attempts")
    attempt_begin(@job_a, proof, limit: 1)
    exhausted = attempt_failed(@job_a, proof, nil, limit: 1)
    assert_equal true, exhausted.fetch("exhausted")
    assert_unavailable { attempt_begin(@job_a, proof, limit: 1) }
  end

  test "yesterday plan can be identified but no new source attempt or commit is allowed" do
    previous_date = @despachante.exec("SELECT ((clock_timestamp() AT TIME ZONE 'America/Sao_Paulo')::date - 1)::text").getvalue(0, 0)
    old_run = create_run(previous_date, 1)
    old_job = create_job(@lawyer_a, run_id: old_run)
    proof = claim(old_job)
    start(old_job, proof)
    assert_equal previous_date, processor_job(old_job, proof).fetch("collection_date")
    assert_unavailable { attempt_begin(old_job, proof) }
    assert_unavailable { commit(old_job, proof, []) }
    assert_equal "interrupted", record_failure(old_job, proof, "interrupted").fetch("code")
    assert_equal ["started"], event_types(old_job)
  end

  private

  def create_run(date, slot)
    @despachante.exec_params("INSERT INTO public.collection_runs (collection_date, slot, status) VALUES ($1, $2, 'planned') ON CONFLICT DO NOTHING", [date, slot])
    @despachante.exec_params("SELECT id FROM public.collection_runs WHERE collection_date = $1 AND slot = $2", [date, slot]).getvalue(0, 0)
  end

  def create_job(lawyer, run_id: @run_id, entity_type: "lawyer", entity_id: lawyer.id, criteria: { "name" => LAWYER_NAME })
    @despachante.exec_params("INSERT INTO public.collection_run_audiences (run_id, tenant_id) VALUES ($1, $2) ON CONFLICT DO NOTHING", [run_id, lawyer.tenant_id])
    @despachante.exec_params(<<~SQL, [run_id, lawyer.tenant_id, entity_type, entity_id, JSON.generate(criteria)]).getvalue(0, 0)
      INSERT INTO public.collection_jobs (run_id, tenant_id, entity_type, entity_id, source, court, medium, criteria)
      VALUES ($1, $2, $3, $4, 'DJEN', 'TJAC', 'D', $5::jsonb) RETURNING id
    SQL
  end

  def create_party_job
    party = DatabaseContext.with_session(@session_a) do
      PartyMonitoring.create!(tenant_id: @lawyer_a.tenant_id, name: "Parte controlada")
    end
    create_job(@lawyer_a, entity_type: "party", entity_id: party.id, criteria: { "name" => party.name })
  end

  def publication
    { "id" => 1, "hash" => "fixture-joint-key", "numero_processo" => "00000010020268260001",
      "siglaTribunal" => "TJAC", "texto" => "Publicação controlada", "destinatarioadvogados" => [{ "advogado" => { "nome" => LAWYER_NAME } }] }
  end

  def claim(job)
    @processor.exec_params("SELECT * FROM app_private.processor_claim($1)", [job]).first.fetch("token")
  end

  def start(job, proof)
    @processor.exec_params("SELECT * FROM app_private.processor_start($1, $2)", [job, proof])
  end

  def processor_job(job, proof)
    JSON.parse(@processor.exec_params("SELECT app_private.processor_job($1, $2)", [job, proof]).getvalue(0, 0))
  end

  def commit(job, proof, items, source: "caderno")
    JSON.parse(@processor.exec_params("SELECT app_private.processor_commit($1, $2, $3, $4::jsonb)", [job, proof, source, JSON.generate(items)]).getvalue(0, 0))
  end

  def commit_started(job, items, source: "caderno")
    proof = claim(job)
    start(job, proof)
    if source == "fallback" && processor_job(job, proof).fetch("phase") == "caderno"
      attempt_begin(job, proof, limit: 1)
      attempt_failed(job, proof, 0, limit: 1)
    end
    attempt_begin(job, proof, limit: 1)
    commit(job, proof, items, source: source)
  end

  def record_failure(job, proof, code)
    JSON.parse(@processor.exec_params("SELECT app_private.processor_record_failure($1, $2, $3)", [job, proof, code]).getvalue(0, 0))
  end

  def attempt_begin(job, proof, limit: 3)
    JSON.parse(@processor.exec_params("SELECT app_private.processor_attempt_begin($1, $2, $3)", [job, proof, limit]).getvalue(0, 0))
  end

  def attempt_failed(job, proof, retry_after, limit: 3, backoff_1: 60, backoff_2: 300)
    JSON.parse(@processor.exec_params("SELECT app_private.processor_attempt_failed($1, $2, $3, $4, $5, $6)",
      [job, proof, retry_after, limit, backoff_1, backoff_2]).getvalue(0, 0))
  end

  def communications(lawyer)
    @migrator.exec_params("SELECT * FROM public.collection_communications WHERE tenant_id = $1 ORDER BY recorded_at, id", [lawyer.tenant_id]).to_a
  end

  def state(job)
    @migrator.exec_params("SELECT state FROM public.collection_job_executions WHERE job_id = $1", [job]).getvalue(0, 0)
  end

  def event_types(job)
    @migrator.exec_params("SELECT event_type FROM public.collection_events WHERE job_id = $1 ORDER BY recorded_at, id", [job]).column_values(0)
  end

  def expire(job)
    @migrator.exec_params("UPDATE public.collection_job_executions SET lease_expires_at = clock_timestamp() WHERE job_id = $1", [job])
  end

  def allow_retry(job)
    @migrator.exec_params("UPDATE public.collection_job_executions SET next_attempt_at = clock_timestamp() WHERE job_id = $1", [job])
  end

  def runtime_as(token)
    @runtime.exec("BEGIN")
    @runtime.exec_params("SELECT set_config('app.session_hash', $1, true)", [IdentityStore.digest(token)])
    yield
  ensure
    @runtime.exec("ROLLBACK")
  end

  def court_state
    @runtime.exec_params("SELECT * FROM app_private.collection_court_states($1)", [@run_id]).first
  end

  def while_commit_blocked(job, proof)
    pid = Queue.new
    @migrator.exec("BEGIN")
    @migrator.exec_params("SELECT pg_advisory_xact_lock(hashtextextended('processor:' || $1::text, 0))", [@lawyer_a.tenant_id])
    worker = Thread.new do
      Thread.current.report_on_exception = false
      PG.connect(@processor_url) do |connection|
        pid << connection.backend_pid
        begin
          JSON.parse(connection.exec_params("SELECT app_private.processor_commit($1, $2, 'caderno', $3::jsonb)",
            [job, proof, JSON.generate([publication])]).getvalue(0, 0))
        rescue PG::Error => error
          error
        end
      end
    end
    Timeout.timeout(15) do
      blocked_pid = pid.pop
      loop do
        blocked = @migrator.exec_params("SELECT $1::integer = ANY(pg_blocking_pids($2::integer))",
          [@migrator.backend_pid, blocked_pid]).getvalue(0, 0)
        break if blocked == "t"
        Thread.pass
      end
      yield
      @migrator.exec("COMMIT")
      worker.value
    end
  ensure
    @migrator.exec("ROLLBACK") if @migrator.transaction_status != PG::PQTRANS_IDLE
    worker&.kill if worker&.alive?
    worker&.join
  end

  def assert_unavailable
    error = assert_raises(PG::InvalidAuthorizationSpecification) { yield }
    assert_equal "Processor operation unavailable", error.result.error_field(PG::Result::PG_DIAG_MESSAGE_PRIMARY)
  end
end
