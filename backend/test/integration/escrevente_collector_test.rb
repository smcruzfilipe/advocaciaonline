require "test_helper"
require "pg"
require "time"
require "timeout"

class EscreventeCollectorTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  FUNCTIONS = {
    "collector_claim(uuid)" => "SELECT * FROM app_private.collector_claim($1)",
    "collector_renew(uuid,text)" => "SELECT * FROM app_private.collector_renew($1, $2)",
    "collector_start(uuid,text)" => "SELECT * FROM app_private.collector_start($1, $2)",
    "collector_finish(uuid,text)" => "SELECT * FROM app_private.collector_finish($1, $2)",
    "collector_fail(uuid,text)" => "SELECT * FROM app_private.collector_fail($1, $2)"
  }.freeze
  PUBLIC_EXECUTION_COLUMNS = %w[job_id tenant_id state updated_at].freeze

  setup do
    @collector_url = ENV.fetch("COLETOR_DATABASE_URL")
    @collector = PG.connect(@collector_url)
    @runtime = PG.connect(ENV.fetch("DATABASE_URL"))
    @migrator = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    @despachante = PG.connect(ENV.fetch("DESPACHANTE_DATABASE_URL"))
    { @collector => "advocacia_coletor", @runtime => "advocacia_runtime",
      @migrator => "advocacia_migrator", @despachante => "advocacia_despachante" }.each do |connection, role|
      assert_equal role, connection.exec("SELECT current_user").getvalue(0, 0)
    end
    @session_a, = authenticated_session
    @lawyer_a = LawyerOnboarding.call(token: @session_a, input: profile_payload)
    @session_b, = authenticated_session
    @lawyer_b = LawyerOnboarding.call(token: @session_b, input: profile_payload.merge("full_name" => "Bruno Lima"))
    date = @despachante.exec(<<~SQL).getvalue(0, 0)
      SELECT COALESCE(MAX(collection_date) + 1, DATE '2080-01-01')::text FROM public.collection_runs
    SQL
    @run_id = @despachante.exec_params(<<~SQL, [date]).getvalue(0, 0)
      INSERT INTO public.collection_runs (collection_date, slot, status)
      VALUES ($1, 1, 'planned') RETURNING id
    SQL
    @job_a = create_job(@lawyer_a)
    @job_b = create_job(@lawyer_b)
  end

  teardown do
    [@collector, @runtime, @migrator, @despachante].each { |connection| connection&.close }
  end

  test "collector is an isolated non bypass login with only the five executor entry points" do
    role = @collector.exec(<<~SQL).first
      SELECT rolsuper, rolbypassrls, rolcreatedb, rolcreaterole, rolreplication, rolinherit
      FROM pg_roles WHERE rolname = current_user
    SQL
    role.each { |flag, value| assert_equal "f", value, flag }
    assert_equal "0", @collector.exec(<<~SQL).getvalue(0, 0)
      SELECT count(*) FROM pg_auth_members
      WHERE member = 'advocacia_coletor'::regrole OR roleid = 'advocacia_coletor'::regrole
    SQL
    [@runtime, @despachante].each do |connection|
      assert_raises(PG::InsufficientPrivilege) { connection.exec("SET ROLE advocacia_coletor") }
      FUNCTIONS.each do |signature, sql|
        arguments = signature.include?("text") ? [@job_a, "a" * 64] : [@job_a]
        assert_raises(PG::InsufficientPrivilege) { connection.exec_params(sql, arguments) }
      end
    end
    FUNCTIONS.each_key do |signature|
      function = @collector.exec_params(<<~SQL, ["app_private.#{signature}"]).first
        SELECT procedure.prosecdef, procedure.proconfig::text,
          pg_get_userbyid(procedure.proowner) AS owner,
          has_function_privilege(current_user, procedure.oid, 'EXECUTE') AS executable,
          EXISTS (SELECT 1 FROM aclexplode(procedure.proacl) AS acl
            WHERE acl.grantee = 0 AND acl.privilege_type = 'EXECUTE') AS public_execute
        FROM pg_proc AS procedure WHERE procedure.oid = $1::regprocedure
      SQL
      assert_equal "t", function.fetch("prosecdef"), signature
      assert_equal "advocacia_migrator", function.fetch("owner"), signature
      assert_equal "t", function.fetch("executable"), signature
      assert_equal "f", function.fetch("public_execute"), signature
      assert_includes function.fetch("proconfig"), "search_path=pg_catalog, pg_temp"
    end
    assert_raises(PG::InsufficientPrivilege) { @collector.exec("SELECT * FROM app_private.sessions") }
    assert_raises(PG::InsufficientPrivilege) { @collector.exec("SELECT app_private.current_tenant_id()") }
    assert_raises(PG::InsufficientPrivilege) { @collector.exec("SELECT * FROM public.collection_jobs") }
    assert_raises(PG::InsufficientPrivilege) { @collector.exec("SET ROLE advocacia_migrator") }
  end

  test "pending execution is created with the job including conflict do nothing and insertion rollback" do
    assert_equal "pending", execution(@job_a).fetch("state")
    assert_empty events(@job_a)
    assert_equal "1", @migrator.exec_params(
      "SELECT count(*) FROM public.collection_job_executions WHERE job_id = $1", [@job_a]).getvalue(0, 0)
    duplicate = @despachante.exec_params(<<~SQL, [@job_a])
      INSERT INTO public.collection_jobs (run_id, tenant_id, entity_type, entity_id, source, court, medium, criteria)
      SELECT run_id, tenant_id, entity_type, entity_id, source, court, medium, criteria
      FROM public.collection_jobs WHERE id = $1
      ON CONFLICT DO NOTHING RETURNING id
    SQL
    assert_empty duplicate.to_a
    assert_equal "1", @migrator.exec_params(
      "SELECT count(*) FROM public.collection_job_executions WHERE job_id = $1", [@job_a]).getvalue(0, 0)

    rolled_back_id = nil
    @despachante.exec("BEGIN")
    begin
      rolled_back_id = insert_job(@lawyer_a, medium: "E")
      @despachante.exec("ROLLBACK")
    ensure
      @despachante.exec("ROLLBACK") if @despachante.transaction_status != PG::PQTRANS_IDLE
    end
    assert_empty @migrator.exec_params(
      "SELECT job_id FROM public.collection_job_executions WHERE job_id = $1", [rolled_back_id]).to_a
    assert_unavailable { claim(rolled_back_id) }
  end

  test "events expose only minimal references and the tenant always derives from the persisted job" do
    proof_a = claim(@job_a).fetch("token")
    proof_b = claim(@job_b).fetch("token")
    @collector.exec_params("SELECT set_config('app.tenant_id', $1, false)", [@lawyer_b.tenant_id])
    @collector.exec_params("SELECT set_config('app.session_hash', $1, false)", [IdentityStore.digest(@session_b)])
    start(@job_a, proof_a)
    finish(@job_a, proof_a)
    start(@job_b, proof_b)
    assert_equal %w[id job_id tenant_id event_type recorded_at], @migrator.exec_params(<<~SQL, ["collection_events"]).map { |row| row.fetch("column_name") }
      SELECT column_name FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = $1 ORDER BY ordinal_position
    SQL
    assert_equal [@lawyer_a.tenant_id], events(@job_a).map { |row| row.fetch("tenant_id") }.uniq
    assert_empty @runtime.exec("SELECT id FROM public.collection_events").to_a
    assert_empty @runtime.exec("SELECT job_id FROM public.collection_job_executions").to_a
    runtime_as(@session_a) do
      assert_equal %w[completed started], @runtime.exec_params(
        "SELECT event_type FROM public.collection_events WHERE job_id = $1 ORDER BY event_type", [@job_a]).column_values(0)
      assert_empty @runtime.exec_params("SELECT id FROM public.collection_events WHERE job_id = $1", [@job_b]).to_a
      assert_empty @runtime.exec_params("SELECT job_id FROM public.collection_job_executions WHERE job_id = $1", [@job_b]).to_a
      assert_equal @lawyer_a.tenant_id, @runtime.exec_params(<<~SQL, [@job_a]).getvalue(0, 0)
        SELECT job.tenant_id FROM public.collection_events AS event
        JOIN public.collection_jobs AS job ON job.id = event.job_id AND job.tenant_id = event.tenant_id
        WHERE event.job_id = $1 LIMIT 1
      SQL
      @runtime.exec_params("SELECT set_config('app.tenant_id', $1, true)", [@lawyer_b.tenant_id])
      assert_empty @runtime.exec_params("SELECT id FROM public.collection_events WHERE job_id = $1", [@job_b]).to_a
    end
    runtime_as(@session_b) do
      assert_equal [@job_b], @runtime.exec_params(
        "SELECT job_id FROM public.collection_job_executions WHERE job_id = $1", [@job_b]).column_values(0)
      assert_empty @runtime.exec_params("SELECT id FROM public.collection_events WHERE job_id = $1", [@job_a]).to_a
    end
    assert_unavailable { start(@job_b, proof_a) }
    assert_unavailable { finish(@job_a, proof_b) }
  end

  test "claim renew start and finish preserve one immutable pair and a separate succeeded state" do
    before = Time.parse(@collector.exec("SELECT clock_timestamp()::text").getvalue(0, 0))
    claimed = claim(@job_a)
    after = Time.parse(@collector.exec("SELECT clock_timestamp()::text").getvalue(0, 0))
    proof = claimed.fetch("token")
    assert_equal %w[token expires_at state], claimed.keys
    assert_equal "pending", claimed.fetch("state")
    assert_match(/\A[0-9a-f]{64}\z/, proof)
    expiry = Time.parse(claimed.fetch("expires_at"))
    assert_operator expiry, :>=, before + 15.minutes
    assert_operator expiry, :<=, after + 15.minutes
    assert_equal IdentityStore.digest(proof), @migrator.exec_params(
      "SELECT claim_digest FROM public.collection_job_executions WHERE job_id = $1", [@job_a]).getvalue(0, 0)
    assert_equal "pending", execution(@job_a).fetch("state")
    renewed = renew(@job_a, proof)
    assert_operator Time.parse(renewed.fetch("expires_at")), :>, expiry
    first = start(@job_a, proof)
    assert_equal first, start(@job_a, proof)
    assert_equal "running", execution(@job_a).fetch("state")
    completed = finish(@job_a, proof)
    assert_equal completed, finish(@job_a, proof)
    assert_equal first, start(@job_a, proof)
    assert_not_equal first.fetch("id"), completed.fetch("id")
    assert_operator Time.parse(completed.fetch("recorded_at")), :>=, Time.parse(first.fetch("recorded_at"))
    assert_equal %w[started completed], events(@job_a).map { |row| row.fetch("event_type") }
    assert_equal "succeeded", execution(@job_a).fetch("state")
    assert_equal "pending", @despachante.exec_params(
      "SELECT status FROM public.collection_jobs WHERE id = $1", [@job_a]).getvalue(0, 0)
    assert_unavailable { claim(@job_a) }
    assert_unavailable { fail_job(@job_a, proof) }
    assert_operator Time.parse(renew(@job_a, proof).fetch("expires_at")), :>, Time.parse(renewed.fetch("expires_at"))
    assert_equal "succeeded", execution(@job_a).fetch("state")
  end

  test "absent malformed wrong job and unknown proofs return the same refusal without writes" do
    proof = claim(@job_a).fetch("token")
    [nil, "", "not-a-token", "a" * 64].each do |invalid|
      assert_unavailable { start(@job_a, invalid) }
      assert_unavailable { finish(@job_a, invalid) }
      assert_unavailable { renew(@job_a, invalid) }
      assert_unavailable { fail_job(@job_a, invalid) }
    end
    [nil, SecureRandom.uuid, @job_b].each do |unknown|
      assert_unavailable { start(unknown, proof) }
      assert_unavailable { finish(unknown, proof) }
      assert_unavailable { renew(unknown, proof) }
      assert_unavailable { fail_job(unknown, proof) }
    end
    assert_unavailable { claim(nil) }
    assert_unavailable { claim(SecureRandom.uuid) }
    assert_unavailable { claim(@job_a) }
    assert_empty events(@job_a)
    assert_empty events(@job_b)
    assert_equal "pending", execution(@job_a).fetch("state")
    assert_equal "pending", execution(@job_b).fetch("state")
  end

  test "completion requires start and failure records only external state before recovery" do
    proof = claim(@job_a).fetch("token")
    assert_unavailable { finish(@job_a, proof) }
    assert_empty events(@job_a)
    first = start(@job_a, proof)
    assert_equal({ "state" => "failed" }, fail_job(@job_a, proof))
    assert_equal "failed", execution(@job_a).fetch("state")
    assert_equal ["started"], events(@job_a).map { |row| row.fetch("event_type") }
    assert_unavailable { finish(@job_a, proof) }
    assert_unavailable { start(@job_a, proof) }
    recovery = claim(@job_a)
    next_proof = recovery.fetch("token")
    assert_not_equal proof, next_proof
    assert_equal "failed", recovery.fetch("state")
    assert_equal "failed", execution(@job_a).fetch("state")
    assert_equal ["started"], events(@job_a).map { |row| row.fetch("event_type") }
    assert_unavailable { claim(@job_a) }
    assert_unavailable { finish(@job_a, next_proof) }
    renewed = renew(@job_a, next_proof)
    assert_operator Time.parse(renewed.fetch("expires_at")), :>, Time.parse(recovery.fetch("expires_at"))
    assert_equal "failed", execution(@job_a).fetch("state")
    @collector.exec("BEGIN")
    begin
      assert_equal first, start(@job_a, next_proof)
      assert_equal "failed", execution(@job_a).fetch("state"), "recovery start must not publish an uncommitted transition"
    ensure
      @collector.exec("ROLLBACK")
    end
    assert_equal "failed", execution(@job_a).fetch("state")
    assert_equal first, start(@job_a, next_proof)
    assert_equal "running", execution(@job_a).fetch("state")
    assert_equal ["started"], events(@job_a).map { |row| row.fetch("event_type") }
    finish(@job_a, next_proof)
    assert_equal %w[started completed], events(@job_a).map { |row| row.fetch("event_type") }
    assert_equal "succeeded", execution(@job_a).fetch("state")

    before_start = claim(@job_b).fetch("token")
    fail_job(@job_b, before_start)
    assert_equal "failed", execution(@job_b).fetch("state")
    assert_empty events(@job_b)
    before_start_recovery = claim(@job_b)
    assert_equal "failed", before_start_recovery.fetch("state")
    assert_equal "failed", execution(@job_b).fetch("state")
    assert_empty events(@job_b)
    start(@job_b, before_start_recovery.fetch("token"))
    assert_equal "running", execution(@job_b).fetch("state")
    assert_equal ["started"], events(@job_b).map { |row| row.fetch("event_type") }
  end

  test "an expired lease can be reclaimed but never renewed or used by its former holder" do
    proof = claim(@job_a).fetch("token")
    started = start(@job_a, proof)
    assert_unavailable { claim(@job_a) }
    expire_lease(@job_a)
    assert_unavailable { renew(@job_a, proof) }
    assert_unavailable { start(@job_a, proof) }
    assert_unavailable { finish(@job_a, proof) }
    assert_unavailable { fail_job(@job_a, proof) }
    recovery = claim(@job_a)
    replacement = recovery.fetch("token")
    assert_not_equal proof, replacement
    assert_equal "running", recovery.fetch("state")
    assert_equal "running", execution(@job_a).fetch("state")
    assert_unavailable { finish(@job_a, proof) }
    assert_equal started, start(@job_a, replacement)
    finish(@job_a, replacement)
    assert_equal "succeeded", execution(@job_a).fetch("state")
  end

  test "a lost finish response is recoverable after expiry without collecting again or changing confirmed events" do
    proof = claim(@job_a).fetch("token")
    started = start(@job_a, proof)
    completed = finish(@job_a, proof)
    confirmed_events = events(@job_a)
    job_status = @despachante.exec_params(
      "SELECT status FROM public.collection_jobs WHERE id = $1", [@job_a]).getvalue(0, 0)
    assert_unavailable { claim(@job_a) }
    expire_lease(@job_a)
    assert_unavailable { renew(@job_a, proof) }
    assert_unavailable { start(@job_a, proof) }
    assert_unavailable { finish(@job_a, proof) }
    confirmation = claim(@job_a)
    assert_equal "succeeded", confirmation.fetch("state")
    replacement = confirmation.fetch("token")
    assert_not_equal proof, replacement
    assert_equal "succeeded", execution(@job_a).fetch("state")
    assert_equal confirmed_events, events(@job_a)
    assert_unavailable { claim(@job_a) }
    assert_unavailable { renew(@job_a, proof) }
    assert_unavailable { finish(@job_a, proof) }
    assert_unavailable { fail_job(@job_a, replacement) }
    renewed = renew(@job_a, replacement)
    assert_operator Time.parse(renewed.fetch("expires_at")), :>, Time.parse(confirmation.fetch("expires_at"))
    confirmed_execution = execution(@job_a)
    # A succeeded claim is confirmation-only: no external collection is invoked.
    assert_equal completed, finish(@job_a, replacement)
    assert_equal started, start(@job_a, replacement)
    assert_equal completed, finish(@job_a, replacement)
    assert_equal confirmed_execution, execution(@job_a)
    assert_equal confirmed_events, events(@job_a)
    assert_equal job_status, @despachante.exec_params(
      "SELECT status FROM public.collection_jobs WHERE id = $1", [@job_a]).getvalue(0, 0)
  end

  %w[collector_start collector_finish collector_renew collector_fail].each do |operation|
    test "#{operation} revalidates wall clock expiry after waiting for the execution row lock" do
      proof = claim(@job_a).fetch("token")
      start(@job_a, proof) if operation == "collector_finish"
      frozen_events = events(@job_a)
      frozen_state = execution(@job_a).fetch("state")
      result = while_collector_blocked("SELECT * FROM app_private.#{operation}($1, $2)", [@job_a, proof]) do
        expire_lease(@job_a)
      end
      assert_unavailable_error(result)
      assert_equal frozen_events, events(@job_a)
      assert_equal frozen_state, execution(@job_a).fetch("state")
    end
  end

  test "claim uses the clock after its row lock rather than its statement start time" do
    previous = claim(@job_a).fetch("token")
    replacement = while_collector_blocked("SELECT * FROM app_private.collector_claim($1)", [@job_a]) do
      expire_lease(@job_a)
    end
    assert_kind_of Hash, replacement
    assert_not_equal previous, replacement.fetch("token")
    assert_equal "pending", replacement.fetch("state")
    assert_unavailable { start(@job_a, previous) }
    start(@job_a, replacement.fetch("token"))
    assert_equal ["started"], events(@job_a).map { |row| row.fetch("event_type") }
  end

  %w[pending running failed succeeded].each do |state|
    test "concurrent claims preserve #{state} and only one connection receives ownership" do
      unless state == "pending"
        proof = claim(@job_a).fetch("token")
        start(@job_a, proof)
        finish(@job_a, proof) if state == "succeeded"
        state == "failed" ? fail_job(@job_a, proof) : expire_lease(@job_a)
      end
      frozen_events = events(@job_a)
      results = concurrently("SELECT * FROM app_private.collector_claim($1)", [@job_a])
      winners = results.select { |result| result.is_a?(Hash) }
      losers = results.select { |result| result.is_a?(PG::Error) }
      assert_equal 1, winners.length, "one real collector connection must acquire the lease"
      assert_equal 1, losers.length
      assert_unavailable_error(losers.first)
      winner = winners.first
      assert_equal state, winner.fetch("state")
      assert_equal state, execution(@job_a).fetch("state")
      assert_equal frozen_events, events(@job_a)
      if state == "succeeded"
        assert_equal frozen_events.last.slice("id", "recorded_at"), finish(@job_a, winner.fetch("token"))
        assert_equal frozen_events, events(@job_a)
        assert_equal "succeeded", execution(@job_a).fetch("state")
      else
        start(@job_a, winner.fetch("token"))
        assert_equal "running", execution(@job_a).fetch("state")
        assert_equal ["started"], events(@job_a).map { |row| row.fetch("event_type") }
      end
    end
  end

  test "concurrent start and finish calls return their original events without duplication" do
    proof = claim(@job_a).fetch("token")
    starts = concurrently("SELECT * FROM app_private.collector_start($1, $2)", [@job_a, proof])
    assert starts.all? { |result| result.is_a?(Hash) }
    assert_equal 1, starts.uniq.length
    completions = concurrently("SELECT * FROM app_private.collector_finish($1, $2)", [@job_a, proof])
    assert completions.all? { |result| result.is_a?(Hash) }
    assert_equal 1, completions.uniq.length
    assert_equal %w[started completed], events(@job_a).map { |row| row.fetch("event_type") }
    assert_equal "succeeded", execution(@job_a).fetch("state")
  end

  test "rollback restores claim start finish and failure together with their events" do
    @collector.exec("BEGIN")
    provisional = claim(@job_a).fetch("token")
    @collector.exec("ROLLBACK")
    assert_unavailable { start(@job_a, provisional) }
    proof = claim(@job_a).fetch("token")
    @collector.exec("BEGIN")
    start(@job_a, proof)
    finish(@job_a, proof)
    assert_equal "pending", execution(@job_a).fetch("state"), "another connection must not see uncommitted transitions"
    assert_empty events(@job_a)
    @collector.exec("ROLLBACK")
    assert_equal "pending", execution(@job_a).fetch("state")
    assert_empty events(@job_a)
    first = start(@job_a, proof)
    @collector.exec("BEGIN")
    fail_job(@job_a, proof)
    @collector.exec("ROLLBACK")
    assert_equal "running", execution(@job_a).fetch("state")
    assert_equal first, start(@job_a, proof)
    @collector.exec("BEGIN")
    finish(@job_a, proof)
    @collector.exec("ROLLBACK")
    assert_equal "running", execution(@job_a).fetch("state")
    assert_equal ["started"], events(@job_a).map { |row| row.fetch("event_type") }
    finish(@job_a, proof)
    assert_equal "succeeded", execution(@job_a).fetch("state")
  ensure
    @collector.exec("ROLLBACK") if @collector.transaction_status != PG::PQTRANS_IDLE
  end

  test "forced RLS and ACLs deny direct writes row locks truncation and private claim reads" do
    proof = claim(@job_a).fetch("token")
    start(@job_a, proof)
    frozen = events(@job_a)
    %w[collection_events collection_job_executions].each do |table|
      flags = @migrator.exec_params(<<~SQL, ["public.#{table}"]).first
        SELECT relrowsecurity, relforcerowsecurity, pg_get_userbyid(relowner) AS owner
        FROM pg_class WHERE oid = $1::regclass
      SQL
      assert_equal "t", flags.fetch("relrowsecurity")
      assert_equal "t", flags.fetch("relforcerowsecurity")
      assert_equal "advocacia_migrator", flags.fetch("owner")
      [@runtime, @collector, @despachante].each do |connection|
        ["SELECT job_id FROM public.#{table} FOR UPDATE",
          "DELETE FROM public.#{table}", "TRUNCATE public.#{table}"].each do |sql|
          assert_raises(PG::InsufficientPrivilege) { connection.exec(sql) }
        end
      end
    end
    [@runtime, @collector, @despachante].each do |connection|
      assert_raises(PG::InsufficientPrivilege) { connection.exec("UPDATE public.collection_events SET event_type = 'completed'") }
      assert_raises(PG::InsufficientPrivilege) { connection.exec("UPDATE public.collection_job_executions SET state = 'failed'") }
      assert_raises(PG::InsufficientPrivilege) { connection.exec("INSERT INTO public.collection_events DEFAULT VALUES") }
      assert_raises(PG::InsufficientPrivilege) { connection.exec("INSERT INTO public.collection_job_executions DEFAULT VALUES") }
      assert_raises(PG::InsufficientPrivilege) { connection.exec("SELECT claim_digest, lease_expires_at FROM public.collection_job_executions") }
    end
    runtime_as(@session_a) do
      assert_equal PUBLIC_EXECUTION_COLUMNS, @runtime.exec_params(
        "SELECT job_id, tenant_id, state, updated_at FROM public.collection_job_executions WHERE job_id = $1", [@job_a]).fields
      assert_raises(PG::InsufficientPrivilege) do
        @runtime.exec("SELECT * FROM public.collection_job_executions")
      end
    end
    assert_equal frozen, events(@job_a)
    assert_equal "running", execution(@job_a).fetch("state")
  end

  test "composite foreign keys reject an event or execution attributed to another tenant" do
    assert_raises(PG::ForeignKeyViolation) do
      @migrator.exec_params(<<~SQL, [@job_a, @lawyer_b.tenant_id])
        INSERT INTO public.collection_events (job_id, tenant_id, event_type)
        VALUES ($1, $2, 'started')
      SQL
    end
    assert_raises(PG::ForeignKeyViolation) do
      @migrator.exec_params(<<~SQL, [@job_a, @lawyer_b.tenant_id])
        UPDATE public.collection_job_executions SET tenant_id = $2 WHERE job_id = $1
      SQL
    end
    assert_empty events(@job_a)
    assert_equal @lawyer_a.tenant_id, execution(@job_a).fetch("tenant_id")
  end

  private

  def create_job(lawyer)
    @despachante.exec_params("INSERT INTO public.collection_run_audiences (run_id, tenant_id) VALUES ($1, $2)", [@run_id, lawyer.tenant_id])
    insert_job(lawyer)
  end

  def insert_job(lawyer, medium: "D")
    @despachante.exec_params(<<~SQL, [@run_id, lawyer.tenant_id, lawyer.id, medium]).getvalue(0, 0)
      INSERT INTO public.collection_jobs (run_id, tenant_id, entity_type, entity_id, source, court, medium, criteria)
      VALUES ($1, $2, 'lawyer', $3, 'DJEN', 'TJAC', $4, '{"name":"Fixture sem cópia para os marcos"}') RETURNING id
    SQL
  end

  def claim(job_id)
    @collector.exec_params("SELECT * FROM app_private.collector_claim($1)", [job_id]).first
  end

  def renew(job_id, proof)
    @collector.exec_params("SELECT * FROM app_private.collector_renew($1, $2)", [job_id, proof]).first
  end

  def start(job_id, proof)
    @collector.exec_params("SELECT * FROM app_private.collector_start($1, $2)", [job_id, proof]).first
  end

  def finish(job_id, proof)
    @collector.exec_params("SELECT * FROM app_private.collector_finish($1, $2)", [job_id, proof]).first
  end

  def fail_job(job_id, proof)
    @collector.exec_params("SELECT * FROM app_private.collector_fail($1, $2)", [job_id, proof]).first
  end

  def execution(job_id)
    @migrator.exec_params("SELECT job_id, tenant_id, state, updated_at FROM public.collection_job_executions WHERE job_id = $1", [job_id]).first
  end

  def events(job_id)
    @migrator.exec_params(<<~SQL, [job_id]).to_a
      SELECT id, job_id, tenant_id, event_type, recorded_at FROM public.collection_events
      WHERE job_id = $1 ORDER BY recorded_at, id
    SQL
  end

  def expire_lease(job_id)
    # Administrative fixture mutation only; no executor or web role receives UPDATE.
    @migrator.exec_params("UPDATE public.collection_job_executions SET lease_expires_at = clock_timestamp() WHERE job_id = $1", [job_id])
  end

  def runtime_as(token)
    @runtime.exec("BEGIN")
    @runtime.exec_params("SELECT set_config('app.session_hash', $1, true)", [IdentityStore.digest(token)])
    yield
  ensure
    @runtime.exec("ROLLBACK")
  end

  def assert_unavailable
    assert_unavailable_error(assert_raises(PG::InvalidAuthorizationSpecification) { yield })
  end

  def assert_unavailable_error(error)
    assert_instance_of PG::InvalidAuthorizationSpecification, error
    assert_equal "28000", error.result.error_field(PG::Result::PG_DIAG_SQLSTATE)
    assert_equal "Collector operation unavailable", error.result.error_field(PG::Result::PG_DIAG_MESSAGE_PRIMARY)
  end

  def concurrently(sql, parameters)
    ready = Queue.new
    release = Queue.new
    workers = 2.times.map do
      Thread.new do
        Thread.current.report_on_exception = false
        PG.connect(@collector_url) do |connection|
          ready << true
          release.pop
          begin
            connection.exec_params(sql, parameters).first
          rescue PG::Error => error
            error
          end
        end
      end
    end
    Timeout.timeout(15) do
      2.times { ready.pop }
      2.times { release << true }
      workers.map(&:value)
    end
  ensure
    2.times { release << true }
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end

  def while_collector_blocked(sql, parameters)
    pid = Queue.new
    @migrator.exec("BEGIN")
    @migrator.exec_params("SELECT job_id FROM public.collection_job_executions WHERE job_id = $1 FOR UPDATE", [@job_a])
    worker = Thread.new do
      Thread.current.report_on_exception = false
      PG.connect(@collector_url) do |connection|
        pid << connection.backend_pid
        begin
          connection.exec_params(sql, parameters).first
        rescue PG::Error => error
          error
        end
      end
    end
    Timeout.timeout(15) do
      blocked_pid = pid.pop
      loop do
        blocked = @migrator.exec_params(
          "SELECT $1::integer = ANY(pg_blocking_pids($2::integer))", [@migrator.backend_pid, blocked_pid]).getvalue(0, 0)
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
end
