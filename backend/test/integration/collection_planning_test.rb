require "test_helper"
require "pg"
require "timeout"
require_relative "../../despachante/collection_despachante"

class CollectionPlanningTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  CATALOG = [
    { code: "TJAC", name: "Tribunal de Justiça do Estado do Acre" },
    { code: "TRF1", name: "Tribunal Regional Federal da 1ª Região" }
  ].freeze
  CNJ = "00012345620248010001".freeze
  OTHER_CNJ = "00099998820248010002".freeze

  setup do
    assert_equal "advocacia_runtime", ApplicationRecord.connection.select_value("SELECT current_user")
    @despachante_url = ENV.fetch("DESPACHANTE_DATABASE_URL")
    @database = PG.connect(@despachante_url)
    assert_equal "advocacia_despachante", @database.exec("SELECT current_user").getvalue(0, 0)
    # Existing integration fixtures are committed; use an unused day without wall-clock sleeps or deleting history.
    @date = Date.iso8601(@database.exec(<<~SQL).getvalue(0, 0))
      SELECT COALESCE(MAX(collection_date) + 1, DATE '2040-01-01')::text FROM public.collection_runs
    SQL
    @now = Time.utc(@date.year, @date.month, @date.day, 7)
  end

  teardown do
    @database&.close
  end

  test "the real despachante login is isolated non bypass and cannot change tenant registrations" do
    role = @database.exec(<<~SQL).first
      SELECT rolname, rolsuper, rolbypassrls, rolcreatedb, rolcreaterole, rolreplication,
        pg_has_role(current_user, 'advocacia_migrator', 'MEMBER') AS migrator_member
      FROM pg_roles WHERE rolname = current_user
    SQL
    assert_equal "advocacia_despachante", role.fetch("rolname")
    %w[rolsuper rolbypassrls rolcreatedb rolcreaterole rolreplication migrator_member].each do |flag|
      assert_equal "f", role.fetch(flag), flag
    end
    assert_equal false, ApplicationRecord.connection.select_value(
      "SELECT pg_has_role(current_user, 'advocacia_despachante', 'MEMBER')")

    %w[tenants lawyers oab_registrations party_monitorings process_monitorings collection_jobs].each do |table|
      flags = @database.exec_params(<<~SQL, ["public.#{table}"]).first
        SELECT relrowsecurity, relforcerowsecurity, pg_get_userbyid(relowner) AS owner
        FROM pg_class WHERE oid = $1::regclass
      SQL
      assert_equal "t", flags.fetch("relrowsecurity"), table
      assert_equal "t", flags.fetch("relforcerowsecurity"), table
      assert_not_includes %w[advocacia_runtime advocacia_despachante], flags.fetch("owner"), table
      assert_equal "f", @database.exec_params(
        "SELECT has_table_privilege(current_user, $1, 'TRUNCATE')", ["public.#{table}"]).getvalue(0, 0), table
    end
    %w[lawyers oab_registrations party_monitorings process_monitorings].each do |table|
      assert_equal "f", @database.exec_params(
        "SELECT has_table_privilege(current_user, $1, 'INSERT,UPDATE,DELETE')", ["public.#{table}"]).getvalue(0, 0), table
    end
    assert_raises(PG::InsufficientPrivilege) { @database.exec("SELECT * FROM app_private.sessions") }
  end

  test "plans durable separate tenant entity court and D E work without a human session" do
    token_a, lawyer_a = create_lawyer
    token_b, lawyer_b = create_lawyer(name: "Bruno Lima", number: "00999", uf: "RO", secondary_oabs: [])
    party_a = create_party(token_a, name: "José, da Silva")
    process_a = create_process(token_a, courts: ["TJAC"])
    create_party(token_a, name: "Parte desativada", active: false)
    create_process(token_a, number: OTHER_CNJ, active: false)
    party_b = create_party(token_b, name: "José, da Silva", courts: ["TRF1"])
    process_b = create_process(token_b)
    create_party(token_b, name: "Outra parte desativada", active: false)
    create_process(token_b, number: OTHER_CNJ, courts: ["TJAC"], active: false)
    IdentityStore.revoke(token_a)
    IdentityStore.revoke(token_b)
    assert_nil IdentityStore.context(token_a)
    assert_nil IdentityStore.context(token_b)
    assert_equal [], Lawyer.pluck(:id)

    run_id = with_catalog { despachante.plan(slot: 1, now: @now) }

    assert_run(run_id, slot: 1, status: "planned")
    assert_tenant_work(run_id, lawyer_a.tenant_id, [
      ["lawyer", lawyer_a.id, %w[TJAC TRF1], lawyer_criteria],
      ["party", party_a.id, %w[TJAC TRF1], { "name" => "José, da Silva" }],
      ["process", process_a.id, ["TJAC"], { "number" => CNJ }]
    ])
    assert_tenant_work(run_id, lawyer_b.tenant_id, [
      ["lawyer", lawyer_b.id, %w[TJAC TRF1], { "name" => "Bruno Lima", "oabs" => [{ "number" => "00999", "uf" => "RO" }] }],
      ["party", party_b.id, ["TRF1"], { "name" => "José, da Silva" }],
      ["process", process_b.id, %w[TJAC TRF1], { "number" => CNJ }]
    ])
    PG.connect(@despachante_url) do |reopened|
      assert_equal run_id, reopened.exec_params(
        "SELECT id FROM public.collection_runs WHERE id = $1", [run_id]).getvalue(0, 0)
      assert_equal 10, reopened.exec_params(
        "SELECT count(*) FROM public.collection_jobs WHERE run_id = $1 AND tenant_id = $2",
        [run_id, lawyer_a.tenant_id]).getvalue(0, 0).to_i
    end
    assert_equal [], Lawyer.pluck(:id)
  end

  test "resolves current catalog at planning time without expanding a saved unavailable selection" do
    token, lawyer = create_lawyer
    all_party = create_party(token, name: "Todos os tribunais")
    selected_party = create_party(token, name: "Tribunal indisponível", courts: ["TRF1"])
    selected_process = create_process(token, courts: ["TRF1"])
    mixed_process = create_process(token, number: OTHER_CNJ, courts: %w[TJAC TRF1])

    first_id = with_catalog([CATALOG.first]) { despachante.plan(slot: 1, now: @now) }

    assert_tenant_work(first_id, lawyer.tenant_id, [
      ["lawyer", lawyer.id, ["TJAC"], lawyer_criteria],
      ["party", all_party.id, ["TJAC"], { "name" => "Todos os tribunais" }],
      ["process", mixed_process.id, ["TJAC"], { "number" => OTHER_CNJ }]
    ])
    DatabaseContext.with_session(token) do
      assert_nil all_party.reload.courts
      assert_equal ["TRF1"], selected_party.reload.courts
      assert_equal ["TRF1"], selected_process.reload.courts
      assert_equal %w[TJAC TRF1], mixed_process.reload.courts
    end

    changed_catalog = [CATALOG.last, { code: "PJeCor", name: "Corregedorias" }]
    second_id = with_catalog(changed_catalog) { despachante.plan(slot: 2, now: @now + 12.hours) }

    assert_not_equal first_id, second_id
    assert_tenant_work(second_id, lawyer.tenant_id, [
      ["lawyer", lawyer.id, %w[TRF1 PJeCor], lawyer_criteria],
      ["party", all_party.id, %w[TRF1 PJeCor], { "name" => "Todos os tribunais" }],
      ["party", selected_party.id, ["TRF1"], { "name" => "Tribunal indisponível" }],
      ["process", selected_process.id, ["TRF1"], { "number" => CNJ }],
      ["process", mixed_process.id, ["TRF1"], { "number" => OTHER_CNJ }]
    ])
  end

  test "freezes names OAB CNJ and links when source profiles are edited or deactivated" do
    token, lawyer = create_lawyer
    party = create_party(token, name: "José, da Silva", courts: ["TJAC"])
    process = create_process(token)
    first_id = with_catalog { despachante.plan(slot: 1, now: @now) }
    assert_tenant_work(first_id, lawyer.tenant_id, [
      ["lawyer", lawyer.id, %w[TJAC TRF1], lawyer_criteria],
      ["party", party.id, ["TJAC"], { "name" => "José, da Silva" }],
      ["process", process.id, %w[TJAC TRF1], { "number" => CNJ }]
    ])
    frozen_work = jobs(first_id, tenant_id: lawyer.tenant_id)

    DatabaseContext.with_session(token) do
      party.update!(name: "Nome novo", courts: ["TRF1"], active: false)
      process.update!(number: OTHER_CNJ, courts: ["TRF1"], active: false)
    end
    edit_profile_fixture(token, lawyer.id)

    assert_equal frozen_work, jobs(first_id, tenant_id: lawyer.tenant_id)
    second_id = with_catalog { despachante.plan(slot: 2, now: @now + 12.hours) }
    assert_not_equal first_id, second_id
    assert_tenant_work(second_id, lawyer.tenant_id, [
      ["lawyer", lawyer.id, %w[TJAC TRF1], {
        "name" => "Ana Nova", "oabs" => [
          { "number" => "000007-Z", "uf" => "AC" },
          { "number" => "Ab.09-X", "uf" => "DF" }
        ]
      }]
    ])
    assert_equal frozen_work, jobs(first_id, tenant_id: lawyer.tenant_id)
  end

  test "replanning the same date and slot reuses the durable plan while another slot and day are independent" do
    token, lawyer = create_lawyer
    original = create_party(token, name: "Parte original")
    first_id = with_catalog { despachante.plan(slot: 1, now: @now) }
    original_work = jobs(first_id)
    DatabaseContext.with_session(token) { original.update!(active: false) }
    added = create_party(token, name: "Parte criada depois", courts: ["TJAC"])

    repeated_id = with_catalog([]) { CollectionDespachante.new(url: @despachante_url).plan(slot: 1, now: @now + 1.hour) }

    assert_equal first_id, repeated_id
    assert_equal original_work, jobs(first_id)
    assert_run(repeated_id, slot: 1, status: "planned")
    assert_equal "1", @database.exec_params(
      "SELECT count(*) FROM public.collection_runs WHERE collection_date = $1 AND slot = 1", [@date]).getvalue(0, 0)

    second_id = with_catalog { despachante.plan(slot: 2, now: @now + 12.hours) }
    assert_not_equal first_id, second_id
    assert_run(second_id, slot: 2, status: "planned")
    assert_tenant_work(second_id, lawyer.tenant_id, [
      ["lawyer", lawyer.id, %w[TJAC TRF1], lawyer_criteria],
      ["party", added.id, ["TJAC"], { "name" => "Parte criada depois" }]
    ])
    next_day_id = with_catalog { despachante.plan(slot: 1, now: @now + 1.day) }
    assert_not_includes [first_id, second_id], next_day_id
    assert_equal (@date + 1).iso8601, planned_run(next_day_id).fetch("collection_date")
    assert_equal original_work, jobs(first_id)
  end

  test "catalog failure leaves a recoverable failed execution and never a complete or no work plan" do
    _, lawyer = create_lawyer
    unavailable = -> { raise CourtCatalog::Unavailable, "DJEN indisponível" }

    CourtCatalog.stub(:fetch, unavailable) do
      assert_raises(CourtCatalog::Unavailable) { despachante.plan(slot: 1, now: @now) }
    end

    failed = @database.exec_params(
      "SELECT id, status FROM public.collection_runs WHERE collection_date = $1 AND slot = $2", [@date, 1]).to_a
    assert_equal 1, failed.length
    failed_id = failed.first.fetch("id")
    assert_equal "planning_failed", failed.first.fetch("status")
    assert_empty jobs(failed_id)

    recovered_id = with_catalog { despachante.plan(slot: 1, now: @now + 1.hour) }

    assert_equal failed_id, recovered_id
    assert_run(recovered_id, slot: 1, status: "planned")
    assert_tenant_work(recovered_id, lawyer.tenant_id, [
      ["lawyer", lawyer.id, %w[TJAC TRF1], lawyer_criteria]
    ])
    recovered_work = jobs(recovered_id)
    assert_equal recovered_id, with_catalog { despachante.plan(slot: 1, now: @now + 2.hours) }
    assert_equal recovered_work, jobs(recovered_id)
  end

  test "a successfully resolved empty catalog records no eligible work rather than zero publications" do
    token, = create_lawyer
    create_party(token, name: "Sem tribunal disponível")
    create_process(token)

    run_id = with_catalog([]) { despachante.plan(slot: 1, now: @now) }

    assert_run(run_id, slot: 1, status: "no_work")
    assert_empty jobs(run_id)
    assert_equal run_id, with_catalog { despachante.plan(slot: 1, now: @now + 1.hour) }
    assert_run(run_id, slot: 1, status: "no_work")
    assert_empty jobs(run_id)
  end

  test "the execution date is Sao Paulo current day even across the UTC date boundary" do
    _, lawyer = create_lawyer
    following_utc_day = @date + 1
    now = Time.utc(following_utc_day.year, following_utc_day.month, following_utc_day.day, 2, 30)

    run_id = Time.use_zone("Pacific/Auckland") do
      with_catalog { despachante.plan(slot: 2, now: now) }
    end

    assert_run(run_id, slot: 2, status: "planned")
    assert_tenant_work(run_id, lawyer.tenant_id, [["lawyer", lawyer.id, %w[TJAC TRF1], lawyer_criteria]])
  end

  test "web sessions can only read their jobs and cannot read global executions or assume the despachante role" do
    token_a, lawyer_a = create_lawyer
    token_b, lawyer_b = create_lawyer(name: "Bruno Lima")
    run_id = with_catalog { despachante.plan(slot: 1, now: @now) }
    connection = ApplicationRecord.connection
    quoted_id = connection.quote(run_id)
    query = "SELECT DISTINCT tenant_id FROM public.collection_jobs WHERE run_id = #{quoted_id}"
    assert_equal [], connection.select_values(query)

    [[token_a, lawyer_a], [token_b, lawyer_b]].each do |token, lawyer|
      DatabaseContext.with_session(token) do
        assert_equal [lawyer.tenant_id], connection.select_values(query)
        connection.execute("SELECT set_config('app.tenant_id', #{connection.quote(lawyer_a.tenant_id)}, true)")
        connection.execute("SELECT set_config('app.despachante', 'true', true)")
        assert_equal [lawyer.tenant_id], connection.select_values(query)
        assert_runtime_permission_denied { connection.execute("SELECT * FROM public.collection_runs") }
        assert_runtime_permission_denied { connection.execute("SET LOCAL ROLE advocacia_despachante") }
        assert_runtime_permission_denied do
          connection.execute("INSERT INTO public.collection_runs (collection_date, slot, status) VALUES (DATE '#{@date + 1}', 1, 'planned')")
        end
        assert_runtime_permission_denied do
          connection.execute("UPDATE public.collection_jobs SET criteria = '{}'::jsonb WHERE run_id = #{quoted_id}")
        end
      end
      assert_equal [], connection.select_values(query)
    end
  end

  test "runtime and migration credentials cannot plan all tenants even with an authenticated web session" do
    token, = create_lawyer
    create_lawyer(name: "Bruno Lima")

    DatabaseContext.with_session(token) do
      [ENV.fetch("DATABASE_URL"), ENV.fetch("MIGRATION_DATABASE_URL")].each do |url|
        assert_raises(SecurityError) do
          with_catalog { CollectionDespachante.new(url: url).plan(slot: 1, now: @now) }
        end
      end
    end

    assert_empty @database.exec_params(
      "SELECT id FROM public.collection_runs WHERE collection_date = $1", [@date]).to_a
  end

  test "despachante entrypoint accepts neither a human token nor a client tenant selector" do
    token, lawyer = create_lawyer

    assert_raises(ArgumentError) { CollectionDespachante.new(url: @despachante_url, token: token) }
    assert_raises(ArgumentError) { despachante.plan(slot: 1, now: @now, token: token) }
    assert_raises(ArgumentError) { despachante.plan(slot: 1, now: @now, tenant_id: lawyer.tenant_id) }
    assert_empty @database.exec_params(
      "SELECT id FROM public.collection_runs WHERE collection_date = $1", [@date]).to_a
  end

  test "the despachante cannot rewrite or delete frozen criteria or entity ownership after committing work" do
    _, lawyer = create_lawyer
    run_id = with_catalog { despachante.plan(slot: 1, now: @now) }
    frozen_work = jobs(run_id, tenant_id: lawyer.tenant_id)
    refute_empty frozen_work
    job_id = frozen_work.first.fetch("id")

    [
      "UPDATE public.collection_jobs SET criteria = '{}'::jsonb WHERE id = $1",
      "UPDATE public.collection_jobs SET tenant_id = gen_random_uuid() WHERE id = $1",
      "UPDATE public.collection_jobs SET entity_id = gen_random_uuid() WHERE id = $1",
      "UPDATE public.collection_jobs SET run_id = gen_random_uuid() WHERE id = $1",
      "DELETE FROM public.collection_jobs WHERE id = $1"
    ].each do |sql|
      assert_raises(PG::InsufficientPrivilege) { @database.exec_params(sql, [job_id]) }
    end
    assert_equal frozen_work, jobs(run_id, tenant_id: lawyer.tenant_id)
  end

  test "concurrent despachantes publish one complete durable plan for the same date and slot" do
    token_a, lawyer_a = create_lawyer
    token_b, lawyer_b = create_lawyer
    party_a = create_party(token_a, name: "Parte concorrente A", courts: ["TJAC"])
    process_a = create_process(token_a)
    party_b = create_party(token_b, name: "Parte concorrente B")
    process_b = create_process(token_b, courts: ["TRF1"])
    entered_catalog = Queue.new
    release_catalog = Queue.new
    workers = []
    result_ids = nil
    catalog = lambda do
      entered_catalog << true
      release_catalog.pop
      CATALOG
    end

    CourtCatalog.stub(:fetch, catalog) do
      begin
        result_ids = Timeout.timeout(30) do
          workers = 2.times.map do
            Thread.new do
              Thread.current.report_on_exception = false
              CollectionDespachante.new(url: @despachante_url).plan(slot: 1, now: @now)
            end
          end
          2.times { entered_catalog.pop }
          assert workers.all?(&:alive?), "Both independent despachantes must reach the catalog barrier before release"
          2.times { release_catalog << true }
          workers.map(&:value)
        end
      ensure
        2.times { release_catalog << true }
        workers.each { |worker| worker.kill if worker.alive? }
        workers.each(&:join)
      end
    end

    assert_equal 1, result_ids.uniq.length
    run_id = result_ids.first
    assert_run(run_id, slot: 1, status: "planned")
    assert_tenant_work(run_id, lawyer_a.tenant_id, [
      ["lawyer", lawyer_a.id, %w[TJAC TRF1], lawyer_criteria],
      ["party", party_a.id, ["TJAC"], { "name" => "Parte concorrente A" }],
      ["process", process_a.id, %w[TJAC TRF1], { "number" => CNJ }]
    ])
    assert_tenant_work(run_id, lawyer_b.tenant_id, [
      ["lawyer", lawyer_b.id, %w[TJAC TRF1], lawyer_criteria],
      ["party", party_b.id, %w[TJAC TRF1], { "name" => "Parte concorrente B" }],
      ["process", process_b.id, ["TRF1"], { "number" => CNJ }]
    ])
    assert_equal [run_id], @database.exec_params(
      "SELECT id FROM public.collection_runs WHERE collection_date = $1 AND slot = $2", [@date, 1]).map { |row| row.fetch("id") }
    assert_empty @database.exec_params(<<~SQL, [run_id]).to_a
      SELECT tenant_id, entity_type, entity_id, source, court, medium
      FROM public.collection_jobs WHERE run_id = $1
      GROUP BY tenant_id, entity_type, entity_id, source, court, medium HAVING count(*) > 1
    SQL
  end

  test "a late catalog failure cannot overwrite the complete plan published by another worker" do
    token, lawyer = create_lawyer
    party = create_party(token, name: "Parte preservada", courts: ["TJAC"])
    process = create_process(token)
    entered_failing_catalog = Queue.new
    release_failure = Queue.new
    workers = []
    run_id = nil
    published_work = nil
    catalog = lambda do
      if Thread.current[:late_catalog_failure]
        entered_failing_catalog << true
        release_failure.pop
        raise CourtCatalog::Unavailable, "Resposta tardia: DJEN indisponível"
      end
      CATALOG
    end

    CourtCatalog.stub(:fetch, catalog) do
      begin
        Timeout.timeout(30) do
          failing_worker = Thread.new do
            Thread.current.report_on_exception = false
            Thread.current[:late_catalog_failure] = true
            CollectionDespachante.new(url: @despachante_url).plan(slot: 1, now: @now)
          end
          workers << failing_worker
          entered_failing_catalog.pop
          winning_worker = Thread.new do
            Thread.current.report_on_exception = false
            CollectionDespachante.new(url: @despachante_url).plan(slot: 1, now: @now)
          end
          workers << winning_worker
          run_id = winning_worker.value
          assert_run(run_id, slot: 1, status: "planned")
          published_work = jobs(run_id)
          assert_tenant_work(run_id, lawyer.tenant_id, [
            ["lawyer", lawyer.id, %w[TJAC TRF1], lawyer_criteria],
            ["party", party.id, ["TJAC"], { "name" => "Parte preservada" }],
            ["process", process.id, %w[TJAC TRF1], { "number" => CNJ }]
          ])

          release_failure << true
          assert_equal run_id, failing_worker.value
        end
      ensure
        release_failure << true
        workers.each { |worker| worker.kill if worker.alive? }
        workers.each(&:join)
      end
    end

    assert_run(run_id, slot: 1, status: "planned")
    assert_equal published_work, jobs(run_id)
    assert_equal [run_id], @database.exec_params(
      "SELECT id FROM public.collection_runs WHERE collection_date = $1 AND slot = $2", [@date, 1]).map { |row| row.fetch("id") }
  end

  %w[lawyer party process].each do |entity_type|
    test "database rejects a #{entity_type} work item linked to another tenant while accepting its actual owner" do
      token_a, lawyer_a = create_lawyer
      token_b, lawyer_b = create_lawyer
      entity_a, entity_b, criteria = case entity_type
      when "lawyer"
        [lawyer_a, lawyer_b, lawyer_criteria]
      when "party"
        [create_party(token_a, name: "Parte vinculada"), create_party(token_b, name: "Parte vinculada"),
          { "name" => "Parte vinculada" }]
      when "process"
        [create_process(token_a), create_process(token_b), { "number" => CNJ }]
      end
      run_id = @database.exec_params(<<~SQL, [@date, 1]).getvalue(0, 0)
        INSERT INTO public.collection_runs (collection_date, slot, status)
        VALUES ($1, $2, 'planning_failed') RETURNING id
      SQL
      @database.exec_params(<<~SQL, [run_id, lawyer_a.tenant_id])
        INSERT INTO public.collection_run_audiences (run_id, tenant_id) VALUES ($1, $2)
      SQL
      insert_job = <<~SQL
        INSERT INTO public.collection_jobs (run_id, tenant_id, entity_type, entity_id, source, court, medium, criteria)
        VALUES ($1, $2, $3, $4, 'DJEN', 'TJAC', 'D', $5::jsonb) RETURNING id
      SQL
      valid_id = @database.exec_params(insert_job,
        [run_id, lawyer_a.tenant_id, entity_type, entity_a.id, JSON.generate(criteria)]).getvalue(0, 0)
      assert_equal [valid_id], jobs(run_id).map { |job| job.fetch("id") }

      @database.exec("BEGIN")
      begin
        assert_raises(PG::ForeignKeyViolation) do
          @database.exec_params(insert_job,
            [run_id, lawyer_a.tenant_id, entity_type, entity_b.id, JSON.generate(criteria)])
        end
      ensure
        @database.exec("ROLLBACK")
      end

      assert_equal [valid_id], jobs(run_id).map { |job| job.fetch("id") }
      assert_empty @database.exec_params(
        "SELECT id FROM public.collection_jobs WHERE run_id = $1 AND entity_id = $2", [run_id, entity_b.id]).to_a
    end
  end

  private

  def despachante
    CollectionDespachante.new(url: @despachante_url)
  end

  def with_catalog(catalog = CATALOG, &block)
    CourtCatalog.stub(:fetch, catalog, &block)
  end

  def create_lawyer(name: "Ana de Ávila", number: "001234-A", uf: "SP", secondary_oabs: [{ "number" => "00a-B", "uf" => "RJ" }])
    token, = authenticated_session
    input = profile_payload.merge("full_name" => name, "primary_oab" => { "number" => number, "uf" => uf },
      "secondary_oabs" => secondary_oabs)
    [token, LawyerOnboarding.call(token: token, input: input)]
  end

  def create_party(token, name:, courts: nil, active: true)
    DatabaseContext.with_session(token) do
      PartyMonitoring.create!(tenant_id: IdentityStore.context(token).fetch("tenant_id"), name: name,
        courts: courts, active: active)
    end
  end

  def create_process(token, number: CNJ, courts: nil, active: true)
    DatabaseContext.with_session(token) do
      ProcessMonitoring.create!(tenant_id: IdentityStore.context(token).fetch("tenant_id"), number: number,
        courts: courts, active: active)
    end
  end

  def lawyer_criteria
    { "name" => "Ana de Ávila", "oabs" => [
      { "number" => "001234-A", "uf" => "SP" }, { "number" => "00a-B", "uf" => "RJ" }
    ] }
  end

  def planned_run(id)
    @database.exec_params(
      "SELECT id, collection_date::text, slot::text, status FROM public.collection_runs WHERE id = $1", [id]).first
  end

  def assert_run(id, slot:, status:)
    assert_match(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/, id)
    assert_equal({ "id" => id, "collection_date" => @date.iso8601, "slot" => slot.to_s, "status" => status }, planned_run(id))
  end

  def jobs(run_id, tenant_id: nil)
    sql = <<~SQL
      SELECT id, run_id, tenant_id, entity_type, entity_id, source, court, medium, criteria::text, status
      FROM public.collection_jobs WHERE run_id = $1
    SQL
    values = [run_id]
    if tenant_id
      sql += " AND tenant_id = $2"
      values << tenant_id
    end
    @database.exec_params("#{sql} ORDER BY id", values).map do |row|
      row["criteria"] = JSON.parse(row.fetch("criteria"))
      row.fetch("criteria")["oabs"]&.sort_by! { |oab| [oab.fetch("number"), oab.fetch("uf")] }
      row
    end
  end

  def assert_tenant_work(run_id, tenant_id, entities)
    expected = entities.flat_map do |type, entity_id, courts, criteria|
      criteria["oabs"]&.sort_by! { |oab| [oab.fetch("number"), oab.fetch("uf")] }
      courts.product(%w[D E]).map do |court, medium|
        { "run_id" => run_id, "tenant_id" => tenant_id, "entity_type" => type, "entity_id" => entity_id,
          "source" => "DJEN", "court" => court, "medium" => medium, "criteria" => criteria, "status" => "pending" }
      end
    end
    actual = jobs(run_id, tenant_id: tenant_id)
    actual.each { |row| assert_match(/\A[0-9a-f-]{36}\z/, row.fetch("id")) }
    order = ->(row) { row.values_at("entity_type", "entity_id", "court", "medium") }
    assert_equal expected.sort_by(&order), actual.map { |row| row.except("id") }.sort_by(&order)
  end

  def assert_runtime_permission_denied
    error = assert_raises(ActiveRecord::StatementInvalid) do
      ApplicationRecord.transaction(requires_new: true) { yield }
    end
    assert_instance_of PG::InsufficientPrivilege, error.cause
  end

  def edit_profile_fixture(token, lawyer_id)
    # Fixture mutation only: neither the web nor despachante login gains profile UPDATE privileges.
    PG.connect(ENV.fetch("MIGRATION_DATABASE_URL")) do |connection|
      assert_equal "advocacia_migrator", connection.exec("SELECT current_user").getvalue(0, 0)
      connection.transaction do
        connection.exec_params("SELECT set_config('app.session_hash', $1, true)", [IdentityStore.digest(token)])
        assert_equal 1, connection.exec_params(
          "UPDATE public.lawyers SET full_name = $1 WHERE id = $2", ["Ana Nova", lawyer_id]).cmd_tuples
        assert_equal 1, connection.exec_params(
          'UPDATE public.oab_registrations SET number = $1, uf = $2 WHERE lawyer_id = $3 AND "primary"',
          ["000007-Z", "AC", lawyer_id]).cmd_tuples
        assert_equal 1, connection.exec_params(
          'UPDATE public.oab_registrations SET number = $1, uf = $2 WHERE lawyer_id = $3 AND NOT "primary"',
          ["Ab.09-X", "DF", lawyer_id]).cmd_tuples
      end
    end
  end
end
