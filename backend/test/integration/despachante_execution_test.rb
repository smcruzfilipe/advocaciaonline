require "test_helper"
require "json"
require "open3"
require "pg"
require "rbconfig"
require "time"
require_relative "../../despachante/run"

class DespachanteExecutionTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  CATALOG = [
    { code: "TJAC", name: "Tribunal de Justiça do Estado do Acre" },
    { code: "TRF1", name: "Tribunal Regional Federal da 1ª Região" }
  ].freeze

  setup do
    @despachante_url = ENV.fetch("DESPACHANTE_DATABASE_URL")
    @database = PG.connect(@despachante_url)
    assert_equal "advocacia_despachante", @database.exec("SELECT current_user").getvalue(0, 0)
    # Reserve unused local dates without deleting immutable plans from other integration tests.
    @date = Date.iso8601(@database.exec(<<~SQL).getvalue(0, 0))
      SELECT COALESCE(MAX(collection_date) + 3, DATE '2060-01-01')::text FROM public.collection_runs
    SQL
    @token, = authenticated_session
    @lawyer = LawyerOnboarding.call(token: @token, input: profile_payload)
  end

  teardown do
    @database&.close
  end

  test "missing or invalid schedule configuration fails before parsing or connecting to the database" do
    unusable_url = "not a libpq connection string"
    invalid_times = [
      [nil, "16:00"], ["04:00", nil], ["", "16:00"], ["04:00", ""],
      ["4:00", "16:00"], ["04:00", "16:00\n"], ["03:59", "16:00"],
      ["04:00", "24:00"], ["04:00", "04:00"], ["16:00", "04:00"]
    ]

    invalid_times.each do |first, second|
      assert_raises(ArgumentError, "invalid schedule must fail independently of database availability") do
        DespachanteRunner.new(despachante_url: unusable_url, first: first, second: second)
      end
    end
    assert_raises(ArgumentError) { DespachanteRunner.new(despachante_url: unusable_url) }
    assert_raises(ArgumentError) { DespachanteRunner.new(despachante_url: unusable_url, first: "04:00") }
    assert_raises(ArgumentError) { DespachanteRunner.new(despachante_url: unusable_url, second: "16:00") }
    assert_empty runs(@date)
  end

  test "an explicit nonempty despachante connection is required without a runtime connection fallback" do
    [nil, "", " "].each do |url|
      assert_raises(ArgumentError) { DespachanteRunner.new(despachante_url: url, first: "04:00", second: "16:00") }
    end
    assert_raises(ArgumentError) { DespachanteRunner.new(first: "04:00", second: "16:00") }
    assert_empty runs(@date)
  end

  test "before the first slot no execution is written and the source catalog is not requested" do
    forbidden_catalog = -> { flunk "no slot is due so no source catalog may be requested" }

    CourtCatalog.stub(:fetch, forbidden_catalog) do
      assert_equal [], runner.run_once(now: utc_on(@date, 6, 59, 59))
    end

    assert_empty runs(@date)
  end

  test "the two scheduled instants create independent durable executions and pending work" do
    first_ids = with_catalog { runner.run_once(now: utc_on(@date, 7)) }

    assert_equal 1, first_ids.length
    first_id = first_ids.first
    assert_real_plan(first_id, date: @date, slot: 1)
    assert_equal [first_id], runs(@date).map { |row| row.fetch("id") }

    both_ids = with_catalog { runner.run_once(now: utc_on(@date, 19)) }

    assert_equal 2, both_ids.length
    assert_equal first_id, both_ids.first
    assert_not_equal first_id, both_ids.last
    assert_real_plan(both_ids.last, date: @date, slot: 2)
    assert_equal both_ids, runs(@date).map { |row| row.fetch("id") }
    assert_equal %w[1 2], runs(@date).map { |row| row.fetch("slot") }
  end

  test "a late first invocation plans both missed current day slots in order without a third execution" do
    ids = with_catalog { runner.run_once(now: utc_on(@date, 22, 15)) }

    assert_equal 2, ids.length
    assert_equal ids, runs(@date).map { |row| row.fetch("id") }
    assert_real_plan(ids.first, date: @date, slot: 1)
    assert_real_plan(ids.last, date: @date, slot: 2)
    assert_empty runs(@date - 1)
  end

  test "a new runner reuses each durable plan without duplicating or extending its frozen work" do
    ids = with_catalog { runner.run_once(now: utc_on(@date, 19)) }
    frozen_jobs = ids.to_h { |id| [id, jobs(id)] }
    DatabaseContext.with_session(@token) do
      PartyMonitoring.create!(tenant_id: @lawyer.tenant_id, name: "Parte criada depois dos planos")
    end

    repeated_ids = with_catalog { runner.run_once(now: utc_on(@date, 22)) }

    assert_equal ids, repeated_ids
    assert_equal ids, runs(@date).map { |row| row.fetch("id") }
    ids.each { |id| assert_equal frozen_jobs.fetch(id), jobs(id) }
    assert_equal %w[planned planned], runs(@date).map { |row| row.fetch("status") }
  end

  test "a failed planning slot remains failed until a later invocation resumes the same execution" do
    unavailable = -> { raise CourtCatalog::Unavailable, "DJEN indisponível" }

    CourtCatalog.stub(:fetch, unavailable) do
      assert_raises(CourtCatalog::Unavailable) { runner.run_once(now: utc_on(@date, 7)) }
    end

    failed_runs = runs(@date)
    assert_equal 1, failed_runs.length
    failed_id = failed_runs.first.fetch("id")
    assert_equal "planning_failed", failed_runs.first.fetch("status")
    assert_empty jobs(failed_id)

    recovered_ids = with_catalog { runner.run_once(now: utc_on(@date, 8)) }

    assert_equal [failed_id], recovered_ids
    assert_real_plan(failed_id, date: @date, slot: 1)
    assert_equal [failed_id], runs(@date).map { |row| row.fetch("id") }
  end

  test "both due slots retain failed executions when one shared catalog request is rate limited" do
    requests = 0
    unavailable = -> do
      requests += 1
      raise CourtCatalog::Unavailable, "HTTP 429"
    end

    CourtCatalog.stub(:fetch, unavailable) do
      assert_raises(CourtCatalog::Unavailable) { runner.run_once(now: utc_on(@date, 19)) }
    end

    failed_runs = runs(@date)
    assert_equal %w[1 2], failed_runs.map { |row| row.fetch("slot") }
    assert_equal %w[planning_failed planning_failed], failed_runs.map { |row| row.fetch("status") }
    assert_equal 2, failed_runs.map { |row| row.fetch("id") }.uniq.length
    failed_runs.each { |row| assert_empty jobs(row.fetch("id")) }
    assert_equal 1, requests, "both failed slots must share the same source error, not issue two requests"
  end

  test "finalized slots remain idempotent while the source is unavailable without another catalog request" do
    ids = with_catalog { runner.run_once(now: utc_on(@date, 19)) }
    frozen_jobs = ids.to_h { |id| [id, jobs(id)] }
    forbidden_catalog = -> { flunk "finalized plans must not resolve the catalog again" }

    CourtCatalog.stub(:fetch, forbidden_catalog) do
      assert_equal ids, runner.run_once(now: utc_on(@date, 20))
    end

    assert_equal ids, runs(@date).map { |row| row.fetch("id") }
    ids.each { |id| assert_equal frozen_jobs.fetch(id), jobs(id) }
  end

  test "the CLI waits sixty seconds after the rate limited response before requesting the catalog again" do
    report = run_cli_with_clock(first: "04:00", second: "16:00",
      now: utc_on(@date, 19), mode: "recover_after_429")

    assert_equal 2, report.fetch("requests").length
    first_request, second_request = report.fetch("requests")
    response_time = Time.iso8601(first_request.fetch("failed_at"))
    retry_time = Time.iso8601(second_request.fetch("requested_at"))
    assert_operator retry_time - response_time, :>=, 60
    first_wait = report.fetch("waits").first
    assert_equal %w[1 2], first_wait.fetch("runs").map { |row| row.fetch("slot") }
    assert_equal %w[planning_failed planning_failed], first_wait.fetch("runs").map { |row| row.fetch("status") }
    assert_includes report.fetch("stderr"), "CourtCatalog::Unavailable"
    assert_equal %w[planned planned], runs(@date).map { |row| row.fetch("status") }
  end

  test "a slot reached during the rate limit cooldown is recorded as failed without a new source request" do
    report = run_cli_with_clock(first: "23:58", second: "23:59",
      now: utc_on(@date + 1, 2, 58, 59), mode: "cooldown_at_midnight")

    assert_equal 1, report.fetch("requests").length
    assert_equal utc_on(@date + 1, 2, 59, 1),
      Time.iso8601(report.fetch("requests").first.fetch("failed_at"))
    failed_runs = runs(@date)
    assert_equal %w[1 2], failed_runs.map { |row| row.fetch("slot") }
    assert_equal %w[planning_failed planning_failed], failed_runs.map { |row| row.fetch("status") }
    failed_runs.each { |row| assert_empty jobs(row.fetch("id")) }
    assert_empty runs(@date + 1)
  end

  test "processing across the last slot boundary does not defer that slot until the next local day" do
    report = run_cli_with_clock(first: "23:58", second: "23:59",
      now: utc_on(@date + 1, 2, 58, 59), mode: "successful_boundary")

    planned_runs = runs(@date)
    assert_equal %w[1 2], planned_runs.map { |row| row.fetch("slot") }
    assert_real_plan(planned_runs.first.fetch("id"), date: @date, slot: 1)
    assert_real_plan(planned_runs.last.fetch("id"), date: @date, slot: 2)
    report.fetch("requests").each do |request|
      assert_operator Time.iso8601(request.fetch("requested_at")), :<, utc_on(@date + 1, 3)
    end
    assert_empty runs(@date + 1)
  end

  test "a catalog response crossing local midnight cannot publish yesterday jobs or start another old slot" do
    following_date = @date + 1
    report = run_cli_with_clock(first: "23:58", second: "23:59",
      now: utc_on(following_date, 2, 59, 59), mode: "successful_midnight")

    assert_equal 1, report.fetch("requests").length
    request = report.fetch("requests").first
    assert_equal utc_on(following_date, 2, 59, 59), Time.iso8601(request.fetch("requested_at"))
    assert_equal utc_on(following_date, 3, 0, 1), Time.iso8601(request.fetch("responded_at"))
    interrupted_runs = runs(@date)
    refute_empty interrupted_runs
    assert interrupted_runs.all? { |row| row.fetch("status") == "interrupted" }
    interrupted_runs.each { |row| assert_empty jobs(row.fetch("id")) }
    assert_empty runs(following_date)
  end

  test "midnight reached after real job inserts rolls them back before publishing the old plan" do
    following_date = @date + 1
    report = run_cli_with_clock(first: "23:58", second: "23:59",
      now: utc_on(following_date, 2, 59, 59), mode: "successful_insert_midnight")

    assert_equal utc_on(following_date, 2, 59, 59), Time.iso8601(report.fetch("inserted_at"))
    assert_equal utc_on(following_date, 3, 0, 1), Time.iso8601(report.fetch("post_insert_at"))
    assert_equal 1, report.fetch("requests").length
    interrupted_runs = runs(@date)
    refute_empty interrupted_runs
    assert interrupted_runs.all? { |row| row.fetch("status") == "interrupted" }
    interrupted_runs.each { |row| assert_empty jobs(row.fetch("id")) }
    assert_empty runs(following_date)
  end

  test "a rate limited response crossing local midnight interrupts old work without another source request" do
    following_date = @date + 1
    report = run_cli_with_clock(first: "23:58", second: "23:59",
      now: utc_on(following_date, 2, 59, 59), mode: "rate_limited_midnight")

    assert_equal 1, report.fetch("requests").length
    assert_equal utc_on(following_date, 3, 0, 1),
      Time.iso8601(report.fetch("requests").first.fetch("failed_at"))
    interrupted_runs = runs(@date)
    refute_empty interrupted_runs
    assert interrupted_runs.all? { |row| row.fetch("status") == "interrupted" }
    interrupted_runs.each { |row| assert_empty jobs(row.fetch("id")) }
    assert_includes report.fetch("stderr"), "CourtCatalog::Unavailable"
    assert_empty runs(following_date)
  end

  test "restart after midnight interrupts previous failed runs before the first slot and only plans the new day" do
    unavailable = -> { raise CourtCatalog::Unavailable, "HTTP 429" }
    CourtCatalog.stub(:fetch, unavailable) do
      assert_raises(CourtCatalog::Unavailable) { runner.run_once(now: utc_on(@date, 19)) }
    end
    failed_runs = runs(@date)
    assert_equal %w[planning_failed planning_failed], failed_runs.map { |row| row.fetch("status") }
    original_ids = failed_runs.map { |row| row.fetch("id") }
    current_date = @date + 1

    cleanup = run_cli_with_clock(first: "04:00", second: "16:00",
      now: utc_on(current_date, 3), mode: "restart_cleanup")

    assert_empty cleanup.fetch("requests"), "startup must retire old failures without consulting yesterday's source"
    interrupted_runs = runs(@date)
    assert_equal original_ids, interrupted_runs.map { |row| row.fetch("id") }
    assert_equal %w[interrupted interrupted], interrupted_runs.map { |row| row.fetch("status") }
    interrupted_runs.each { |row| assert_empty jobs(row.fetch("id")) }
    assert_empty runs(current_date)

    current = run_cli_with_clock(first: "04:00", second: "16:00",
      now: utc_on(current_date, 7), mode: "successful_restart", observed_date: current_date)

    assert_equal 1, current.fetch("requests").length
    assert_equal interrupted_runs, runs(@date)
    current_runs = runs(current_date)
    assert_equal ["1"], current_runs.map { |row| row.fetch("slot") }
    assert_real_plan(current_runs.first.fetch("id"), date: current_date, slot: 1)
    assert_not_includes original_ids, current_runs.first.fetch("id")
  end

  test "UTC date changes do not change the local execution date or recover slots after local midnight" do
    following_utc_date = @date + 1
    ids = with_catalog { runner.run_once(now: utc_on(following_utc_date, 2, 30)) }

    assert_equal 2, ids.length
    assert_real_plan(ids.first, date: @date, slot: 1)
    assert_real_plan(ids.last, date: @date, slot: 2)
    frozen_jobs = ids.to_h { |id| [id, jobs(id)] }
    forbidden_catalog = -> { flunk "local midnight must not resume previous day collection slots" }

    CourtCatalog.stub(:fetch, forbidden_catalog) do
      assert_equal [], runner.run_once(now: utc_on(following_utc_date, 3))
    end

    assert_empty runs(following_utc_date)
    assert_equal ids, runs(@date).map { |row| row.fetch("id") }
    ids.each { |id| assert_equal frozen_jobs.fetch(id), jobs(id) }
  end

  test "a fresh start on a new local day plans only the current due slot and never backfills yesterday" do
    current_date = @date + 1

    ids = with_catalog { runner.run_once(now: utc_on(current_date, 7)) }

    assert_equal 1, ids.length
    assert_real_plan(ids.first, date: current_date, slot: 1)
    assert_empty runs(@date)
    assert_equal [ids.first], runs(current_date).map { |row| row.fetch("id") }
  end

  test "a separate Ruby process plans and resumes both slots without web credentials or a Rails application" do
    IdentityStore.revoke(@token)
    assert_nil IdentityStore.context(@token)

    ids = run_in_separate_process(now: utc_on(@date, 19))

    assert_equal 2, ids.length
    assert_real_plan(ids.first, date: @date, slot: 1)
    assert_real_plan(ids.last, date: @date, slot: 2)
    frozen_jobs = ids.to_h { |id| [id, jobs(id)] }

    assert_equal ids, run_in_separate_process(now: utc_on(@date, 20))
    assert_equal ids, runs(@date).map { |row| row.fetch("id") }
    ids.each { |id| assert_equal frozen_jobs.fetch(id), jobs(id) }
  end

  private

  def runner
    DespachanteRunner.new(despachante_url: @despachante_url, first: "04:00", second: "16:00")
  end

  def utc_on(date, hour, minute = 0, second = 0)
    Time.utc(date.year, date.month, date.day, hour, minute, second)
  end

  def with_catalog(&block)
    CourtCatalog.stub(:fetch, CATALOG, &block)
  end

  def runs(date)
    @database.exec_params(<<~SQL, [date]).to_a
      SELECT id, collection_date::text, slot::text, status
      FROM public.collection_runs WHERE collection_date = $1 ORDER BY slot
    SQL
  end

  def jobs(run_id)
    @database.exec_params(<<~SQL, [run_id, @lawyer.tenant_id]).to_a
      SELECT id, run_id, tenant_id, entity_type, entity_id, source, court, medium, criteria::text, status
      FROM public.collection_jobs WHERE run_id = $1 AND tenant_id = $2 ORDER BY id
    SQL
  end

  def assert_real_plan(run_id, date:, slot:)
    assert_match(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/, run_id)
    expected_run = { "id" => run_id, "collection_date" => date.iso8601, "slot" => slot.to_s, "status" => "planned" }
    assert_includes runs(date), expected_run
    planned_jobs = jobs(run_id)
    assert_equal %w[D D], planned_jobs.map { |job| job.fetch("medium") }.sort
    assert_equal %w[TJAC TRF1], planned_jobs.map { |job| job.fetch("court") }.sort
    planned_jobs.each do |job|
      assert_equal run_id, job.fetch("run_id")
      assert_equal @lawyer.tenant_id, job.fetch("tenant_id")
      assert_equal "lawyer", job.fetch("entity_type")
      assert_equal @lawyer.id, job.fetch("entity_id")
      assert_equal "DJEN", job.fetch("source")
      assert_equal "pending", job.fetch("status")
      assert_equal "Ana de Ávila", JSON.parse(job.fetch("criteria")).fetch("name")
    end
  end

  def run_in_separate_process(now:)
    environment = {
      "DESPACHANTE_DATABASE_URL" => @despachante_url,
      "COLETA_HORARIO_1" => "04:00", "COLETA_HORARIO_2" => "16:00",
      "DATABASE_URL" => nil, "MIGRATION_DATABASE_URL" => nil, "RAILS_ENV" => nil,
      "APP_ORIGIN" => nil, "GOOGLE_CLIENT_ID" => nil, "GOOGLE_CLIENT_SECRET" => nil,
      "SECRET_KEY_BASE" => nil
    }
    script = <<~'RUBY'
      require "bundler/setup"
      require "json"
      require "time"
      require "minitest"
      require "minitest/mock"
      require ARGV.fetch(0)
      if defined?(Rails) && Rails.respond_to?(:application) && Rails.application
        abort "The standalone despachante must not boot the web application."
      end
      runner = DespachanteRunner.new(despachante_url: ENV.fetch("DESPACHANTE_DATABASE_URL"),
        first: ENV.fetch("COLETA_HORARIO_1"), second: ENV.fetch("COLETA_HORARIO_2"))
      catalog = JSON.parse(ARGV.fetch(2), symbolize_names: true)
      ids = CourtCatalog.stub(:fetch, catalog) { runner.run_once(now: Time.iso8601(ARGV.fetch(1))) }
      STDOUT.write(JSON.generate(ids))
    RUBY
    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, "-e", script,
      Rails.root.join("despachante/run.rb").to_s, now.iso8601, JSON.generate(CATALOG), chdir: Rails.root.to_s)
    assert status.success?, "Standalone despachante failed: #{stderr}"
    JSON.parse(stdout)
  end

  def run_cli_with_clock(first:, second:, now:, mode:, observed_date: @date)
    environment = {
      "DESPACHANTE_DATABASE_URL" => @despachante_url,
      "COLETA_HORARIO_1" => first, "COLETA_HORARIO_2" => second,
      "DATABASE_URL" => nil, "MIGRATION_DATABASE_URL" => nil, "RAILS_ENV" => nil,
      "APP_ORIGIN" => nil, "GOOGLE_CLIENT_ID" => nil, "GOOGLE_CLIENT_SECRET" => nil,
      "SECRET_KEY_BASE" => nil
    }
    script = <<~'RUBY'
      require "bundler/setup"
      require "json"
      require "pg"
      require "time"
      require "minitest"
      require "minitest/mock"
      entrypoint, initial_time, local_date, mode, catalog_json = ARGV
      require File.expand_path("../app/services/court_catalog", File.dirname(entrypoint))
      catalog = JSON.parse(catalog_json, symbolize_names: true)
      clock = { wall: Time.iso8601(initial_time), monotonic: 0.0 }
      report = { "requests" => [], "waits" => [] }
      database = PG.connect(ENV.fetch("DESPACHANTE_DATABASE_URL"))
      source = -> do
        throw :finished if report.fetch("requests").length >= 4
        request = { "requested_at" => clock.fetch(:wall).iso8601(6) }
        report.fetch("requests") << request
        if report.fetch("requests").length == 1
          # A real catalog response consumes two simulated seconds, crossing 23:59 in the boundary cases.
          unless mode == "successful_insert_midnight"
            clock[:wall] += 2
            clock[:monotonic] += 2
          end
          request["responded_at"] = clock.fetch(:wall).iso8601(6)
          unless mode.start_with?("successful_")
            request["failed_at"] = clock.fetch(:wall).iso8601(6)
            raise CourtCatalog::Unavailable, "HTTP 429"
          end
        end
        catalog
      end
      wait = proc do |seconds|
        seconds = Float(seconds)
        raise ArgumentError, "the scheduler requested an invalid wait" unless seconds.finite? && seconds >= 0
        rows = database.exec_params(<<~SQL, [local_date]).to_a
          SELECT slot::text, status FROM public.collection_runs WHERE collection_date = $1 ORDER BY slot
        SQL
        report.fetch("waits") << { "at" => clock.fetch(:wall).iso8601(6), "seconds" => seconds, "runs" => rows }
        terminal_status = case mode
        when "successful_midnight", "successful_insert_midnight", "rate_limited_midnight", "restart_cleanup"
          "interrupted"
        when "cooldown_at_midnight" then "planning_failed"
        else "planned"
        end
        expected_count = mode == "successful_restart" ? 1 : 2
        enough_rows = terminal_status == "interrupted" ? !rows.empty? : rows.length == expected_count
        finished = enough_rows && rows.all? { |row| row.fetch("status") == terminal_status }
        throw :finished if finished || report.fetch("waits").length >= 4
        clock[:wall] += seconds
        clock[:monotonic] += seconds
        seconds
      end
      # Replace only time/wait primitives; the actual CLI, despachante, PostgreSQL role and writes remain real.
      Kernel.module_eval do
        define_method(:sleep, &wait)
        private :sleep
      end
      Kernel.define_singleton_method(:sleep, &wait)
      original_clock_gettime = Process.method(:clock_gettime)
      monotonic_clock = ->(clock_id, unit = :float_second) do
        if clock_id == Process::CLOCK_MONOTONIC
          raise ArgumentError, "the controlled clock uses seconds" unless unit == :float_second
          clock.fetch(:monotonic)
        else
          original_clock_gettime.call(clock_id, unit)
        end
      end
      reads = 0
      wall_clock = -> do
        reads += 1
        throw :finished if reads > 100
        clock.fetch(:wall)
      end
      publication_clock = TracePoint.new(:return) do |event|
        next unless event.method_id == :insert_work && event.defined_class.name == "CollectionDespachante"
        next if report.key?("inserted_at")

        # Observe the real INSERT completing, then move only the clocks across midnight before COMMIT.
        report["inserted_at"] = clock.fetch(:wall).iso8601(6)
        clock[:wall] += 2
        clock[:monotonic] += 2
        report["post_insert_at"] = clock.fetch(:wall).iso8601(6)
      end
      publication_clock.enable if mode == "successful_insert_midnight"
      catch(:finished) do
        Time.stub(:now, wall_clock) do
          Process.stub(:clock_gettime, monotonic_clock) do
            CourtCatalog.stub(:fetch, source) do
              $PROGRAM_NAME = entrypoint
              load entrypoint
            end
          end
        end
      end
      publication_clock.disable
      database.close
      STDOUT.write(JSON.generate(report))
    RUBY
    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, "-e", script,
      Rails.root.join("despachante/run.rb").to_s, now.iso8601, observed_date.iso8601, mode, JSON.generate(CATALOG),
      chdir: Rails.root.to_s)
    assert status.success?, "Controlled-clock despachante CLI failed: #{stderr}"
    JSON.parse(stdout).merge("stderr" => stderr)
  end
end
