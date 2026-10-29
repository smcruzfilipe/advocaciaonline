require "date"
require "digest"
require "json"
require "pg"
require "stringio"
require "open3"
require "rbconfig"
require "timeout"
require "zip"
require_relative "fallback_test"
require_relative "../lib/processador/runner"
require_relative "../lib/processador/worker"

class RunnerIntegrationTest < Minitest::Test
  include ControlledDjen

  def setup
    @admin = PG.connect(ENV.fetch("PROCESSADOR_TEST_ADMIN_DATABASE_URL"))
    # Rails and ETL share the integration database. Keep pre-existing work
    # intact but locked out of this test's global SKIP LOCKED selection.
    @queue_guard = PG.connect(ENV.fetch("PROCESSADOR_TEST_ADMIN_DATABASE_URL"))
    @queue_guard.exec("BEGIN")
    @queue_guard.exec("SELECT job_id FROM public.collection_job_executions FOR UPDATE")
    @date = Processador::Runner::TIMEZONE.now.to_date
    @tenant = scalar("INSERT INTO public.tenants (created_at, updated_at) VALUES (now(), now()) RETURNING id")
    @admin.transaction do
      @lawyer = scalar("INSERT INTO public.lawyers (tenant_id, full_name, created_at, updated_at) VALUES ($1, $2, now(), now()) RETURNING id", [@tenant, LAWYER_NAME])
      @admin.exec_params("INSERT INTO public.oab_registrations (tenant_id, lawyer_id, number, uf, \"primary\", created_at, updated_at) VALUES ($1, $2, '0001', 'SP', true, now(), now())", [@tenant, @lawyer])
    end
    @created_runs = []
    @party = scalar("INSERT INTO public.party_monitorings (tenant_id, name, canonical_name, created_at, updated_at) VALUES ($1, 'Parte Exemplo', 'parte exemplo', now(), now()) RETURNING id", [@tenant])
    @process = scalar("INSERT INTO public.process_monitorings (tenant_id, number, created_at, updated_at) VALUES ($1, '00000010020268260001', now(), now()) RETURNING id", [@tenant])
    @run = run_for(@date)
  end

  def teardown
    return unless @admin && @tenant

    %w[collection_communication_links collection_job_results collection_job_failures collection_events collection_job_executions collection_jobs collection_run_audiences collection_communications party_monitorings process_monitorings oab_registrations lawyers].each do |table|
      @admin.exec_params("DELETE FROM public.#{table} WHERE tenant_id = $1", [@tenant])
    end
    @admin.exec_params("DELETE FROM public.tenants WHERE id = $1", [@tenant])
    @created_runs&.each { |run| @admin.exec_params("DELETE FROM public.collection_runs WHERE id = $1 AND NOT EXISTS (SELECT 1 FROM public.collection_run_audiences WHERE run_id = $1)", [run]) }
  ensure
    @admin&.close
    @queue_guard&.exec("ROLLBACK")
    @queue_guard&.close
  end

  def test_caderno_matches_three_entities_and_preserves_the_publication_with_all_links
    jobs = [
      job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] }),
      job("party", @party, { "name" => "Parte Exemplo" }),
      job("process", @process, { "number" => "00000010020268260001" })
    ]
    pub = publication(101).merge("texto" => "<p>Guilherme&nbsp;Curcelli Guimarães &amp; partes<br>Intimação</p><script>não executar</script>",
      "destinatarios" => [{ "nome" => "Parte Exemplo" }], "numero_processo" => "00000010020268260001")
    zip = zip_with([pub])
    responses = []
    with_server(responses) do |origin, requests|
      metadata = { "status" => "Processado", "url" => "#{origin}/caderno.zip",
        "hash" => Digest::SHA256.hexdigest(zip), "numero_paginas" => 2, "total_comunicacoes" => 1 }
      jobs.each { responses << { body: JSON.generate(metadata) } << { body: zip } }
      jobs.each { |id| assert_equal "succeeded", runner(origin).call(id).fetch("state") }
      assert_equal 6, requests.length
      assert requests.select { |request| request[:target].include?("/caderno/") }.all? { |request| request[:target].include?(@date.iso8601) }
    end
    rows = @admin.exec_params("SELECT payload FROM public.collection_communications WHERE tenant_id = $1", [@tenant])
    assert_equal 1, rows.ntuples
    assert_equal pub.fetch("texto"), JSON.parse(rows.first.fetch("payload")).fetch("texto")
    assert_equal "3", scalar("SELECT count(*)::text FROM public.collection_communication_links WHERE tenant_id = $1", [@tenant])
  end

  def test_caderno_then_api_preserves_first_html_and_links_both_monitorings
    first_job = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] })
    second_run = run_for(@date, slot: 2)
    second_job = job("party", @party, { "name" => "Parte Exemplo" }, run: second_run)
    first = publication(120).merge("texto" => "<p>Primeira &amp; versão</p><script>não executar</script>",
      "destinatarios" => [{ "nome" => "Parte Exemplo" }])
    later = first.merge("texto" => "<p>Versão posterior da API</p>")
    zip = zip_with([first])
    responses = []
    with_server(responses) do |origin, _requests|
      responses.concat([
        { body: JSON.generate("status" => "Processado", "url" => "#{origin}/caderno.zip",
          "hash" => Digest::SHA256.hexdigest(zip), "numero_paginas" => 2, "total_comunicacoes" => 1) },
        { body: zip }, page([later]), page([])
      ])
      assert_equal "caderno", runner(origin).call(first_job).fetch("source_path")
      assert_equal "fallback", runner(origin).call(second_job).fetch("source_path")
    end
    rows = @admin.exec_params("SELECT id, payload FROM public.collection_communications WHERE tenant_id = $1", [@tenant]).to_a
    assert_equal 1, rows.length
    assert_equal first.fetch("texto"), JSON.parse(rows.first.fetch("payload")).fetch("texto")
    links = @admin.exec_params("SELECT job_id FROM public.collection_communication_links WHERE tenant_id = $1 AND communication_id = $2",
      [@tenant, rows.first.fetch("id")]).column_values(0)
    assert_equal [first_job, second_job].sort, links.sort
  end

  def test_failed_caderno_uses_all_fallback_pages_and_same_current_date
    id = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] })
    item = publication(202).merge("texto" => "<p>Texto&nbsp;válido &amp; público</p><script>não executar</script>")
    responses = Array.new(3) { { body: JSON.generate("status" => "Cancelado") } } +
      [page([item], count: 999), page([publication(203)], count: 0), page([])]
    with_server(responses) do |origin, requests|
      result = runner(origin).call(id)
      assert_equal "succeeded", result.fetch("state")
      assert_equal "fallback", result.fetch("source_path")
      fallback = requests.select { |request| request[:target].start_with?("/api/v1/comunicacao?") }
      assert_equal 3, fallback.length
      fallback.each_with_index do |request, index|
        query = URI.decode_www_form(URI.parse(request.fetch(:target)).query).to_h
        assert_equal @date.iso8601, query.fetch("dataDisponibilizacaoInicio")
        assert_equal @date.iso8601, query.fetch("dataDisponibilizacaoFim")
        assert_equal (index + 1).to_s, query.fetch("pagina")
        refute query.key?("nomeAdvogado")
      end
    end
    stored = @admin.exec_params("SELECT payload FROM public.collection_communications WHERE tenant_id = $1 ORDER BY source_id", [@tenant]).to_a
    assert_equal 2, stored.length
    assert_equal "Texto válido & público", JSON.parse(stored.first.fetch("payload")).fetch("texto")
  end

  def test_empty_is_success_but_exhausted_source_is_failure_without_completed_event
    empty_job = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] }, medium: "D")
    failed_job = job("party", @party, { "name" => "Parte Exemplo" })
    responses = [ { body: JSON.generate("status" => "Sem comunicações", "total_comunicacoes" => 0, "numero_paginas" => 0) },
      { body: JSON.generate("status" => "Cancelado") }, { status: 503, body: "indisponível" } ]
    with_server(responses) do |origin, _requests|
      instance = runner(origin, attempts: 1)
      assert_equal "succeeded", instance.call(empty_job).fetch("state")
      assert_equal "failed", instance.call(failed_job).fetch("state")
    end
    assert_equal "0", scalar("SELECT matched_count::text FROM public.collection_job_results WHERE job_id = $1", [empty_job])
    assert_equal "source_unavailable", scalar("SELECT code FROM public.collection_job_failures WHERE job_id = $1", [failed_job])
    assert_equal ["started"], @admin.exec_params("SELECT event_type FROM public.collection_events WHERE job_id = $1 ORDER BY event_type", [failed_job]).column_values(0)
  end

  def test_yesterday_is_interrupted_without_request_or_started_event
    old_run = run_for(@date - 1)
    id = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] }, run: old_run)
    with_server([]) do |origin, requests|
      assert_equal "failed", runner(origin).call(id).fetch("state")
      assert_empty requests
    end
    assert_equal "interrupted", scalar("SELECT code FROM public.collection_job_failures WHERE job_id = $1", [id])
    assert_equal "0", scalar("SELECT count(*)::text FROM public.collection_events WHERE job_id = $1", [id])
  end

  def test_failed_later_fallback_page_discards_partial_matches_before_retrying_from_page_one
    id = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] })
    responses = Array.new(3) { { body: JSON.generate("status" => "Cancelado") } } +
      [page([publication(301)]), { status: 503 }, page([publication(302)]), page([])]
    with_server(responses) do |origin, requests|
      assert_equal "succeeded", runner(origin).call(id).fetch("state")
      pages = requests.filter_map do |request|
        target = request.fetch(:target)
        URI.decode_www_form(URI.parse(target).query).to_h["pagina"] if target.start_with?("/api/v1/comunicacao?")
      end
      assert_equal %w[1 2 1 2], pages
    end
    assert_equal ["302"], @admin.exec_params("SELECT source_id::text FROM public.collection_communications WHERE tenant_id = $1", [@tenant]).column_values(0)
  end

  def test_reclaimed_in_flight_attempt_is_consumed_and_followed_by_next_attempt
    id = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] })
    PG.connect(ENV.fetch("PROCESSADOR_DATABASE_URL")) do |processor|
      token = processor.exec_params("SELECT token FROM app_private.processor_claim($1::uuid)", [id]).getvalue(0, 0)
      processor.exec_params("SELECT * FROM app_private.processor_start($1::uuid, $2::text)", [id, token])
      processor.exec_params("SELECT app_private.processor_attempt_begin($1::uuid, $2::text, 3)", [id, token])
    end
    @admin.exec_params("UPDATE public.collection_job_executions SET lease_expires_at = clock_timestamp() - interval '1 second' WHERE job_id = $1", [id])
    with_server([{ body: JSON.generate("status" => "Sem comunicações", "total_comunicacoes" => 0) }]) do |origin, requests|
      assert_equal "succeeded", runner(origin).call(id).fetch("state")
      assert_equal 1, requests.length
    end
    assert_equal "2", scalar("SELECT caderno_attempts::text FROM public.collection_job_executions WHERE job_id = $1", [id])
  end

  def test_midnight_after_metadata_prevents_zip_download_for_the_previous_day
    id = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] })
    responses = []
    with_server(responses) do |origin, requests|
      responses << { body: JSON.generate("status" => "Processado", "url" => "#{origin}/caderno.zip") }
      calls = 0
      clock = -> { calls += 1; calls <= 3 ? @date : @date + 1 }
      assert_equal "failed", runner(origin, date_source: clock).call(id).fetch("state")
      assert_equal 1, requests.length
      assert_includes requests.first.fetch(:target), "/api/v1/caderno/"
    end
    assert_equal "interrupted", scalar("SELECT code FROM public.collection_job_failures WHERE job_id = $1", [id])
    assert_equal "0", scalar("SELECT count(*)::text FROM public.collection_communications WHERE tenant_id = $1", [@tenant])
  end

  def test_successful_fallback_page_honors_retry_after_before_requesting_the_next_page
    id = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] })
    responses = [{ body: JSON.generate("status" => "Cancelado") },
      page([publication(401)]).merge(headers: { "Retry-After" => "1" }), page([])]
    with_server(responses) do |origin, requests|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      assert_equal "succeeded", runner(origin, attempts: 1).call(id).fetch("state")
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      assert_operator elapsed, :>=, 0.9
      assert_equal 3, requests.length
    end
  end

  def test_database_rejection_records_processing_failure_without_completing_the_job
    id = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] })
    item = publication(402).merge("campo_desconhecido" => "\u0000")
    responses = [{ body: JSON.generate("status" => "Cancelado") }, page([item]), page([])]
    with_server(responses) do |origin, _requests|
      result = runner(origin, attempts: 1).call(id)
      assert_equal "failed", result.fetch("state")
      assert_equal "processing_failed", result.fetch("code")
    end
    assert_equal "0", scalar("SELECT count(*)::text FROM public.collection_communications WHERE tenant_id = $1", [@tenant])
    assert_equal ["started"], @admin.exec_params("SELECT event_type FROM public.collection_events WHERE job_id = $1", [id]).column_values(0)
  end

  def test_large_retry_after_is_preserved_until_the_collection_day_changes
    id = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] })
    calls = 0
    clock = -> { calls += 1; calls <= 3 ? @date : @date + 1 }
    with_server([{ status: 503, headers: { "Retry-After" => "2147483648" } }]) do |origin, requests|
      assert_equal "failed", runner(origin, date_source: clock).call(id).fetch("state")
      assert_equal 1, requests.length
    end
    assert_equal "interrupted", scalar("SELECT code FROM public.collection_job_failures WHERE job_id = $1", [id])
  end

  def test_second_slot_uses_paginated_api_directly_and_sanitizes_its_text
    run = run_for(@date, slot: 2)
    id = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] }, run: run)
    item = publication(501).merge("texto" => "<p>Texto&nbsp;da API &amp; parte</p><script>remover</script>")
    with_server([page([item]), page([])]) do |origin, requests|
      assert_equal "succeeded", runner(origin).call(id).fetch("state")
      assert_equal 2, requests.length
      assert requests.all? { |request| request.fetch(:target).start_with?("/api/v1/comunicacao?") }
    end
    assert_equal "Texto da API & parte", JSON.parse(scalar("SELECT payload::text FROM public.collection_communications WHERE tenant_id = $1", [@tenant])).fetch("texto")
  end

  def test_claimed_runner_uses_the_selected_lease_without_claiming_again
    id = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] })
    claim = PG.connect(ENV.fetch("PROCESSADOR_DATABASE_URL")) do |processor|
      processor.exec("SELECT * FROM app_private.processor_next()").first
    end
    assert_equal id, claim.fetch("job_id")
    with_server([{ body: JSON.generate("status" => "Sem comunicações", "total_comunicacoes" => 0) }]) do |origin, requests|
      assert_equal "succeeded", runner(origin).call_claimed(id, claim.fetch("token"), claim.fetch("state")).fetch("state")
      assert_equal 1, requests.length
    end
    assert_equal "1", scalar("SELECT count(*)::text FROM public.collection_events WHERE job_id = $1 AND event_type = 'completed'", [id])
  end

  def test_worker_automatically_processes_both_slots_and_keeps_the_original_publication_and_links
    first = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] })
    second = job("party", @party, { "name" => "Parte Exemplo" }, run: run_for(@date, slot: 2))
    item = publication(601).merge("texto" => "<p>Intimação original</p>", "destinatarios" => [{ "nome" => "Parte Exemplo" }])
    zip = zip_with([item])
    output = StringIO.new
    responses = []
    with_server(responses) do |origin, requests|
      responses.concat([
        { body: JSON.generate("status" => "Processado", "url" => "#{origin}/caderno.zip",
          "hash" => Digest::SHA256.hexdigest(zip), "numero_paginas" => 2, "total_comunicacoes" => 1) },
        { body: zip }, page([item.merge("texto" => "Versão posterior")]), page([])
      ])
      worker = worker_for(origin, output: output)
      assert_equal "caderno", worker.run_once.fetch("source_path")
      assert_equal "fallback", worker.run_once.fetch("source_path")
      assert_nil worker.run_once
      assert_equal 4, requests.length
    end
    assert_equal %w[succeeded succeeded], output.string.lines.map { |line| JSON.parse(line).fetch("state") }
    assert_equal item.fetch("texto"), JSON.parse(scalar("SELECT payload::text FROM public.collection_communications WHERE tenant_id = $1", [@tenant])).fetch("texto")
    assert_equal [first, second].sort, @admin.exec_params("SELECT job_id FROM public.collection_communication_links WHERE tenant_id = $1", [@tenant]).column_values(0).sort
  end

  def test_two_workers_consume_different_jobs_without_duplicate_results_or_events
    ids = [job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] }),
      job("party", @party, { "name" => "Parte Exemplo" })]
    responses = Array.new(2) { { body: JSON.generate("status" => "Sem comunicações", "total_comunicacoes" => 0) } }
    with_server(responses) do |origin, requests|
      start = Queue.new
      workers = 2.times.map do
        Thread.new { start.pop; worker_for(origin).run_once }
      end
      workers.each { |thread| thread.report_on_exception = false }
      2.times { start << true }
      assert_equal %w[succeeded succeeded], workers.map { |thread| thread.value.fetch("state") }
      assert_equal 2, requests.length
      assert_nil worker_for(origin).run_once
    ensure
      workers&.each { |thread| thread.kill; thread.join }
    end
    ids.each do |id|
      assert_equal "1", scalar("SELECT count(*)::text FROM public.collection_job_results WHERE job_id = $1", [id])
      assert_equal %w[completed started], @admin.exec_params("SELECT event_type FROM public.collection_events WHERE job_id = $1 ORDER BY event_type", [id]).column_values(0)
    end
  end

  def test_worker_interrupts_old_work_but_leaves_future_jobs_and_active_leases_untouched
    old = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] }, run: run_for(@date - 1))
    future = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] }, run: run_for(@date + 1))
    active = job("party", @party, { "name" => "Parte Exemplo" })
    PG.connect(ENV.fetch("PROCESSADOR_DATABASE_URL")) do |processor|
      processor.exec_params("SELECT * FROM app_private.processor_claim($1::uuid)", [active])
    end
    with_server([]) do |origin, requests|
      worker = worker_for(origin)
      assert_equal "interrupted", worker.run_once.fetch("code")
      assert_nil worker.run_once
      assert_empty requests
    end
    assert_equal "interrupted", scalar("SELECT code FROM public.collection_job_failures WHERE job_id = $1", [old])
    assert_equal "0", scalar("SELECT count(*)::text FROM public.collection_events WHERE job_id = $1", [old])
    [future, active].each do |id|
      assert_equal "pending", scalar("SELECT state FROM public.collection_job_executions WHERE job_id = $1", [id])
      assert_equal "0", scalar("SELECT count(*)::text FROM public.collection_job_failures WHERE job_id = $1", [id])
    end
  end

  def test_worker_interrupts_an_abandoned_previous_day_attempt_without_retrying_the_source
    id = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] }, run: run_for(@date - 1))
    PG.connect(ENV.fetch("PROCESSADOR_DATABASE_URL")) do |processor|
      token = processor.exec_params("SELECT token FROM app_private.processor_claim($1::uuid)", [id]).getvalue(0, 0)
      processor.exec_params("SELECT * FROM app_private.processor_start($1::uuid, $2::text)", [id, token])
      # Simulate a request that started before midnight; the public function
      # correctly refuses to begin a new attempt for yesterday.
      @admin.exec_params(<<~SQL, [id])
        UPDATE public.collection_job_executions SET caderno_attempts = 1,
          attempt_in_flight = true, attempt_started_at = clock_timestamp() - interval '1 day'
        WHERE job_id = $1
      SQL
    end
    expire_lease(id)
    with_server([]) do |origin, requests|
      assert_equal "interrupted", worker_for(origin).run_once.fetch("code")
      assert_empty requests
    end
    assert_equal "1", scalar("SELECT caderno_attempts::text FROM public.collection_job_executions WHERE job_id = $1", [id])
    assert_equal ["started"], @admin.exec_params("SELECT event_type FROM public.collection_events WHERE job_id = $1", [id]).column_values(0)
  end

  def test_worker_resumes_an_abandoned_current_day_attempt_after_restart
    id = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] })
    PG.connect(ENV.fetch("PROCESSADOR_DATABASE_URL")) do |processor|
      claim = processor.exec("SELECT * FROM app_private.processor_next()").first
      processor.exec_params("SELECT * FROM app_private.processor_start($1::uuid, $2::text)", [id, claim.fetch("token")])
      processor.exec_params("SELECT app_private.processor_attempt_begin($1::uuid, $2::text, 3)", [id, claim.fetch("token")])
    end
    expire_lease(id)
    with_server([{ body: JSON.generate("status" => "Sem comunicações", "total_comunicacoes" => 0) }]) do |origin, requests|
      assert_equal "succeeded", worker_for(origin).run_once.fetch("state")
      assert_equal 1, requests.length
    end
    assert_equal "2", scalar("SELECT caderno_attempts::text FROM public.collection_job_executions WHERE job_id = $1", [id])
    assert_equal %w[completed started], @admin.exec_params("SELECT event_type FROM public.collection_events WHERE job_id = $1 ORDER BY event_type", [id]).column_values(0)
  end

  def test_worker_preserves_exhaustion_when_restarting_an_abandoned_last_fallback_attempt
    id = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] })
    PG.connect(ENV.fetch("PROCESSADOR_DATABASE_URL")) do |processor|
      token = processor.exec("SELECT * FROM app_private.processor_next()").first.fetch("token")
      processor.exec_params("SELECT * FROM app_private.processor_start($1::uuid, $2::text)", [id, token])
      processor.exec_params("SELECT app_private.processor_attempt_begin($1::uuid, $2::text, 1)", [id, token])
      processor.exec_params("SELECT app_private.processor_attempt_failed($1::uuid, $2::text, 0, 1, 1, 1)", [id, token])
      processor.exec_params("SELECT app_private.processor_attempt_begin($1::uuid, $2::text, 1)", [id, token])
    end
    expire_lease(id)
    with_server([]) do |origin, requests|
      assert_equal "source_unavailable", worker_for(origin, attempts: 1).run_once.fetch("code")
      assert_empty requests
    end
    assert_equal "1", scalar("SELECT fallback_attempts::text FROM public.collection_job_executions WHERE job_id = $1", [id])
    assert_equal "0", scalar("SELECT count(*)::text FROM public.collection_job_results WHERE job_id = $1", [id])
  end

  def test_expired_selected_lease_never_contacts_the_source_and_is_recovered_by_the_next_worker
    id = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] })
    claim = PG.connect(ENV.fetch("PROCESSADOR_DATABASE_URL")) { |processor| processor.exec("SELECT * FROM app_private.processor_next()").first }
    expire_lease(id)
    with_server([{ body: JSON.generate("status" => "Sem comunicações", "total_comunicacoes" => 0) }]) do |origin, requests|
      assert_raises(Processador::Runner::LeaseLost) { runner(origin).call_claimed(id, claim.fetch("token"), claim.fetch("state")) }
      assert_empty requests
      assert_equal "0", scalar("SELECT count(*)::text FROM public.collection_job_failures WHERE job_id = $1", [id])
      assert_equal "succeeded", worker_for(origin).run_once.fetch("state")
    end
  end

  def test_worker_keeps_consuming_after_real_source_failure
    failed = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] })
    succeeded = job("party", @party, { "name" => "Parte Exemplo" }, run: run_for(@date, slot: 2))
    responses = [{ body: JSON.generate("status" => "Cancelado") }, { status: 503 }, page([])]
    output = StringIO.new
    with_server(responses) do |origin, requests|
      worker = worker_for(origin, attempts: 1, output: output)
      assert_equal "source_unavailable", worker.run_once.fetch("code")
      assert_equal "succeeded", worker.run_once.fetch("state")
      assert_nil worker.run_once
      assert_equal 3, requests.length
    end
    assert_equal %w[failed succeeded], output.string.lines.map { |line| JSON.parse(line).fetch("state") }
    assert_equal "0", scalar("SELECT count(*)::text FROM public.collection_job_results WHERE job_id = $1", [failed])
    assert_equal "0", scalar("SELECT matched_count::text FROM public.collection_job_results WHERE job_id = $1", [succeeded])
  end

  def test_later_slot_recovers_the_same_lawyer_after_exhaustion_without_historical_collection
    criteria = { "name" => LAWYER_NAME, "oabs" => [] }
    failed = job("lawyer", @lawyer, criteria)
    recovered = job("lawyer", @lawyer, criteria, run: run_for(@date, slot: 2))
    item = publication(603).merge("texto" => "<p>Publicação &amp; recuperação</p><script>remover</script>")
    responses = Array.new(3) { { body: JSON.generate("status" => "Cancelado") } } +
      Array.new(3) { { status: 503 } } + [page([item]), page([])]

    with_server(responses) do |origin, requests|
      worker = worker_for(origin)
      assert_equal "source_unavailable", worker.run_once.fetch("code")
      assert_equal "succeeded", worker.run_once.fetch("state")
      assert_nil worker.run_once
      assert_equal 8, requests.length
      assert requests.first(3).all? { |request| request[:target].include?("/caderno/TJAC/#{@date.iso8601}/D") }
      requests.drop(3).each do |request|
        params = URI.decode_www_form(URI.parse(request.fetch(:target)).query).to_h
        assert_equal @date.iso8601, params.fetch("dataDisponibilizacaoInicio")
        assert_equal @date.iso8601, params.fetch("dataDisponibilizacaoFim")
        assert_equal "D", params.fetch("meio")
      end
    end
    assert_equal "source_unavailable", scalar("SELECT code FROM public.collection_job_failures WHERE job_id = $1", [failed])
    assert_equal "0", scalar("SELECT count(*)::text FROM public.collection_job_results WHERE job_id = $1", [failed])
    assert_equal "1", scalar("SELECT matched_count::text FROM public.collection_job_results WHERE job_id = $1", [recovered])
    assert_equal "1", scalar("SELECT count(*)::text FROM public.collection_communications WHERE tenant_id = $1", [@tenant])
    assert_equal [recovered], @admin.exec_params("SELECT job_id FROM public.collection_communication_links WHERE tenant_id = $1", [@tenant]).column_values(0)
    assert_equal "Publicação & recuperação", JSON.parse(scalar("SELECT payload::text FROM public.collection_communications WHERE tenant_id = $1", [@tenant])).fetch("texto")
    attempts = @admin.exec_params("SELECT caderno_attempts, fallback_attempts FROM public.collection_job_executions WHERE job_id = $1", [failed]).first
    assert_equal({ "caderno_attempts" => "3", "fallback_attempts" => "3" }, attempts)
  end

  def test_worker_records_real_database_processing_failure_and_continues_without_partial_results
    failed = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] })
    succeeded = job("party", @party, { "name" => "Parte Exemplo" }, run: run_for(@date, slot: 2))
    zip = zip_with([publication(602).merge("campo_desconhecido" => "\u0000")])
    responses = []
    with_server(responses) do |origin, requests|
      responses.concat([
        { body: JSON.generate("status" => "Processado", "url" => "#{origin}/caderno.zip",
          "hash" => Digest::SHA256.hexdigest(zip), "numero_paginas" => 2, "total_comunicacoes" => 1) },
        { body: zip }, page([])
      ])
      worker = worker_for(origin)
      assert_equal "processing_failed", worker.run_once.fetch("code")
      assert_equal "succeeded", worker.run_once.fetch("state")
      assert_equal 3, requests.length
    end
    assert_equal "0", scalar("SELECT count(*)::text FROM public.collection_communications WHERE tenant_id = $1", [@tenant])
    assert_equal "0", scalar("SELECT count(*)::text FROM public.collection_job_results WHERE job_id = $1", [failed])
    assert_equal "succeeded", scalar("SELECT state FROM public.collection_job_executions WHERE job_id = $1", [succeeded])
  end

  def test_continuous_worker_waits_between_real_empty_selections
    waits = []
    stop = Class.new(StandardError)
    sleeper = ->(seconds) { waits << seconds; raise stop if waits.length == 2 }
    worker = Processador::Worker.new(database_url: ENV.fetch("PROCESSADOR_DATABASE_URL"),
      output: StringIO.new, errors: StringIO.new, sleeper: sleeper)
    assert_raises(stop) { worker.run }
    assert_equal [5, 5], waits
  end

  def test_worker_does_not_swallow_fatal_connection_errors
    settings = PG.connect(ENV.fetch("PROCESSADOR_DATABASE_URL")) { |processor| processor.conninfo_hash.reject { |_key, value| value.nil? || value.empty? } }
    settings["dbname"] = "nonexistent_processor_database_#{Process.pid}"
    worker = Processador::Worker.new(database_url: settings, output: StringIO.new, errors: StringIO.new)
    assert_raises(PG::ConnectionBad) { worker.run }
  end

  def test_worker_losing_its_lease_during_processing_does_not_commit_or_fail_the_job
    id = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] })
    errors = StringIO.new
    output = StringIO.new
    responses = [{ body: JSON.generate("status" => "Sem comunicações", "total_comunicacoes" => 0), delay: 0.3 },
      { body: JSON.generate("status" => "Sem comunicações", "total_comunicacoes" => 0) }]
    with_server(responses) do |origin, requests|
      processing = Thread.new { worker_for(origin, output: output, errors: errors).run_once }
      processing.report_on_exception = false
      Timeout.timeout(5) { sleep(0.01) until requests.length == 1 }
      expire_lease(id)
      assert_nil processing.value
      assert_empty output.string
      assert_includes errors.string, "Processador::Runner::LeaseLost"
      assert_equal "running", scalar("SELECT state FROM public.collection_job_executions WHERE job_id = $1", [id])
      assert_equal "0", scalar("SELECT count(*)::text FROM public.collection_job_failures WHERE job_id = $1", [id])
      assert_equal "0", scalar("SELECT count(*)::text FROM public.collection_job_results WHERE job_id = $1", [id])
      assert_equal "succeeded", worker_for(origin).run_once.fetch("state")
    ensure
      processing&.kill
      processing&.join
    end
  end

  def test_worker_connection_loss_is_fatal_and_a_new_worker_recovers_the_abandoned_job
    id = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] })
    settings = PG.connect(ENV.fetch("PROCESSADOR_DATABASE_URL")) { |processor| processor.conninfo_hash.reject { |_key, value| value.nil? || value.empty? } }
    settings["application_name"] = "processor_disconnect_#{Process.pid}"
    responses = [{ body: JSON.generate("status" => "Sem comunicações", "total_comunicacoes" => 0), delay: 0.3 },
      { body: JSON.generate("status" => "Sem comunicações", "total_comunicacoes" => 0) }]
    with_server(responses) do |origin, requests|
      instance = Processador::Runner.new(database_url: settings, http: http_for(origin), base_url: "#{origin}/api/v1",
        backoff_first: 1, backoff_second: 1)
      worker = Processador::Worker.new(database_url: settings, runner: instance, output: StringIO.new, errors: StringIO.new)
      processing = Thread.new do
        worker.run_once
      rescue PG::Error => error
        error
      end
      processing.report_on_exception = false
      Timeout.timeout(5) { sleep(0.01) until requests.length == 1 || !processing.alive? }
      assert_equal 1, requests.length, "worker stopped before requesting source: #{processing.value.inspect unless processing.alive?}"
      disconnected = @admin.exec_params("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name = $1", [settings.fetch("application_name")])
      assert_operator disconnected.ntuples, :>=, 1
      assert_kind_of PG::Error, processing.value
      assert_equal "running", scalar("SELECT state FROM public.collection_job_executions WHERE job_id = $1", [id])
      assert_equal "0", scalar("SELECT count(*)::text FROM public.collection_job_results WHERE job_id = $1", [id])
      expire_lease(id)
      assert_equal "succeeded", worker_for(origin).run_once.fetch("state")
      assert_equal 2, requests.length
    ensure
      processing&.kill
      processing&.join
    end
    assert_equal "2", scalar("SELECT caderno_attempts::text FROM public.collection_job_executions WHERE job_id = $1", [id])
  end

  def test_cli_without_uuid_really_consumes_old_work_and_stays_running
    id = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] }, run: run_for(@date - 1))
    Open3.popen3(RbConfig.ruby, File.expand_path("../bin/processador", __dir__)) do |stdin, stdout, stderr, process|
      stdin.close
      result = JSON.parse(Timeout.timeout(10) { stdout.gets } || flunk("worker exited before processing: #{stderr.read}"))
      assert_equal({ "state" => "failed", "code" => "interrupted" }, result)
      assert process.alive?, "worker must stay available for the next scheduled job"
      assert_equal "interrupted", scalar("SELECT code FROM public.collection_job_failures WHERE job_id = $1", [id])
    ensure
      if process&.alive?
        Process.kill("TERM", process.pid)
        process.value
      end
    end
  end

  def test_cli_still_accepts_an_explicit_job_uuid
    id = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] }, run: run_for(@date - 1))
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, File.expand_path("../bin/processador", __dir__), id)
    assert_equal({ "state" => "failed", "code" => "interrupted" }, JSON.parse(stdout))
    assert_equal 1, status.exitstatus
    assert_empty stderr
  end

  def test_cli_missing_configuration_exits_unsuccessfully_instead_of_waiting
    stdout, stderr, status = Open3.capture3({ "PROCESSADOR_DATABASE_URL" => nil },
      RbConfig.ruby, File.expand_path("../bin/processador", __dir__))
    assert_equal 1, status.exitstatus
    assert_empty stdout
    assert_includes stderr, "PROCESSADOR_DATABASE_URL"
  end

  private

  def worker_for(origin, attempts: 3, output: StringIO.new, errors: StringIO.new)
    Processador::Worker.new(database_url: ENV.fetch("PROCESSADOR_DATABASE_URL"),
      runner: runner(origin, attempts: attempts), output: output, errors: errors)
  end

  def expire_lease(id)
    @admin.exec_params("UPDATE public.collection_job_executions SET lease_expires_at = clock_timestamp() - interval '1 second' WHERE job_id = $1", [id])
  end

  def scalar(sql, params = [])
    @admin.exec_params(sql, params).getvalue(0, 0)
  end

  def run_for(date, slot: 1)
    created = @admin.exec_params("INSERT INTO public.collection_runs (collection_date, slot, status, created_at, updated_at) VALUES ($1, $2, 'planned', now(), now()) ON CONFLICT DO NOTHING RETURNING id", [date.iso8601, slot])
    @created_runs << created.getvalue(0, 0) if created.ntuples == 1
    run = scalar("SELECT id FROM public.collection_runs WHERE collection_date = $1 AND slot = $2", [date.iso8601, slot])
    @admin.exec_params("INSERT INTO public.collection_run_audiences (run_id, tenant_id) VALUES ($1, $2) ON CONFLICT DO NOTHING", [run, @tenant])
    run
  end

  def job(type, entity, criteria, medium: "D", run: @run)
    scalar(<<~SQL, [run, @tenant, type, entity, medium, JSON.generate(criteria)])
      INSERT INTO public.collection_jobs (run_id, tenant_id, entity_type, entity_id, source, court, medium, criteria, created_at, updated_at)
      VALUES ($1, $2, $3, $4, 'DJEN', 'TJAC', $5, $6::jsonb, now(), now()) RETURNING id
    SQL
  end

  def runner(origin, attempts: 3, date_source: -> { Processador::Runner::TIMEZONE.now.to_date })
    http = Processador::Http.new(test_origin: origin, open_timeout: 2, read_timeout: 2, write_timeout: 2)
    Processador::Runner.new(database_url: ENV.fetch("PROCESSADOR_DATABASE_URL"), http: http,
      base_url: "#{origin}/api/v1", attempts: attempts, backoff_first: 1, backoff_second: 1, date_source: date_source)
  end

  def zip_with(items)
    Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("page1.json")
      zip.write(JSON.generate("items" => items))
      zip.put_next_entry("page2.json")
      zip.write(JSON.generate("items" => []))
    end.string
  end
end
