require "date"
require "digest"
require "json"
require "pg"
require "stringio"
require "zip"
require_relative "fallback_test"
require_relative "../lib/processador/runner"

class RunnerIntegrationTest < Minitest::Test
  include ControlledDjen

  def setup
    @admin = PG.connect(ENV.fetch("PROCESSADOR_TEST_ADMIN_DATABASE_URL"))
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
  end

  def test_caderno_matches_three_entities_and_persists_one_sanitized_communication_with_all_links
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
    text = JSON.parse(rows.first.fetch("payload")).fetch("texto")
    assert_includes text, "Guilherme Curcelli Guimarães & partes"
    assert_includes text, "Intimação"
    refute_includes text, "não executar"
    refute_includes text, "<p>"
    assert_equal "3", scalar("SELECT count(*)::text FROM public.collection_communication_links WHERE tenant_id = $1", [@tenant])
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
    failed_job = job("lawyer", @lawyer, { "name" => LAWYER_NAME, "oabs" => [] }, medium: "E")
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

  private

  def scalar(sql, params = [])
    @admin.exec_params(sql, params).getvalue(0, 0)
  end

  def run_for(date)
    created = @admin.exec_params("INSERT INTO public.collection_runs (collection_date, slot, status, created_at, updated_at) VALUES ($1, 1, 'planned', now(), now()) ON CONFLICT DO NOTHING RETURNING id", [date.iso8601])
    @created_runs << created.getvalue(0, 0) if created.ntuples == 1
    run = scalar("SELECT id FROM public.collection_runs WHERE collection_date = $1 AND slot = 1", [date.iso8601])
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
