require "minitest/autorun"
require "date"
require "json"
require "pg"
require "stringio"
require_relative "../lib/stf/processor"
require_relative "../lib/stf/worker"
require_relative "../lib/stf/http"

class ProcessorTest < Minitest::Test
  class ControlledHttp
    attr_reader :requests

    def initialize(before_request, responses, after_request = nil)
      @before_request, @responses, @after_request = before_request, responses, after_request
      @requests = []
    end

    def get(url)
      @before_request.call
      @requests << url
      response = @responses.shift or raise "unexpected request"
      raise response if response.is_a?(Exception)
      @after_request&.call
      STF::Http::Response.new(body: response.b, url: url)
    end
  end

  def setup
    @admin = PG.connect(ENV.fetch("PROCESSADOR_TEST_ADMIN_DATABASE_URL"))
    @date = STF::Processor::TIMEZONE.now.to_date
    @tenant = scalar("INSERT INTO public.tenants (created_at, updated_at) VALUES (now(), now()) RETURNING id")
    @party = scalar("INSERT INTO public.party_monitorings (tenant_id, name, canonical_name, created_at, updated_at) VALUES ($1, 'Maria Silva', 'maria silva', now(), now()) RETURNING id", [@tenant])
    created = @admin.exec_params("INSERT INTO public.collection_runs (collection_date, slot, status, created_at, updated_at) VALUES ($1, 1, 'planned', now(), now()) ON CONFLICT DO NOTHING RETURNING id", [@date.iso8601])
    @created_run = created.ntuples == 1
    @run = scalar("SELECT id FROM public.collection_runs WHERE collection_date = $1 AND slot = 1", [@date.iso8601])
    @admin.exec_params("INSERT INTO public.collection_run_audiences (run_id, tenant_id) VALUES ($1, $2)", [@run, @tenant])
    @job = scalar("INSERT INTO public.collection_jobs (run_id, tenant_id, entity_type, entity_id, source, court, medium, criteria, created_at, updated_at) VALUES ($1, $2, 'party', $3, 'STF', 'STF', 'A', $4::jsonb, now(), now()) RETURNING id", [@run, @tenant, @party, JSON.generate("name" => "Maria Silva")])
    @responses = []
    @date_source = -> { @date }
    @capture_times = []
    @http_factory = ->(callback) { @http = ControlledHttp.new(callback, @responses, @after_request) }
  end

  def teardown
    return unless @admin && @tenant
    %w[stf_capture_links collection_communication_links collection_job_results collection_job_failures collection_events collection_job_executions collection_jobs collection_communications stf_captures collection_run_audiences party_monitorings].each do |table|
      @admin.exec_params("DELETE FROM public.#{table} WHERE tenant_id = $1", [@tenant])
    end
    @admin.exec_params("DELETE FROM public.tenants WHERE id = $1", [@tenant])
    @admin.exec_params("DELETE FROM public.collection_runs WHERE id = $1 AND NOT EXISTS (SELECT 1 FROM public.collection_run_audiences WHERE run_id = $1)", [@run]) if @created_run
  ensure
    @admin&.close
  end

  def test_persists_only_today_and_replays_without_source_access
    @responses.concat([discovery, movements])
    result = processor.call(@job)
    assert_equal "succeeded", result.fetch("state")
    assert_equal "andamentos", result.fetch("source_path")
    rows = @admin.exec_params("SELECT payload FROM public.collection_communications WHERE tenant_id = $1", [@tenant]).to_a
    assert_equal 1, rows.size
    payload = JSON.parse(rows.first.fetch("payload"))
    assert_equal @date.iso8601, payload.fetch("stf").fetch("data_andamento")
    assert_equal "https://portal.stf.jus.br/processos/downloadPeca.asp?id=1", payload.fetch("stf").fetch("links").first.fetch("url")
    metadata = JSON.parse(scalar("SELECT process_data FROM public.stf_captures WHERE tenant_id = $1", [@tenant]))
    assert_equal 1, @capture_times.size
    assert_equal @capture_times.first.iso8601, metadata.fetch("capturado_em")
    assert_equal metadata.fetch("capturado_em"), payload.fetch("stf").fetch("capturado_em")
    assert_equal "01882631920261000000", payload.fetch("numero_processo")
    requests = @http.requests.dup
    @admin.exec_params("UPDATE public.collection_job_executions SET lease_expires_at = clock_timestamp() - interval '1 second' WHERE job_id = $1", [@job])
    assert_equal "succeeded", processor.call(@job).fetch("state")
    assert_equal requests, @http.requests
    assert_equal "1", scalar("SELECT count(*)::text FROM public.collection_communications WHERE tenant_id = $1", [@tenant])
  end

  def test_no_eligible_processes_are_success_with_no_captures
    @responses << JSON.generate("totalDePaginas" => 0, "totalDeRegistros" => 0, "partes" => [])
    result = processor.call(@job)
    assert_equal "succeeded", result.fetch("state")
    assert_equal 0, result.fetch("matched_count")
    assert_equal "0", scalar("SELECT count(*)::text FROM public.stf_captures WHERE tenant_id = $1", [@tenant])
  end

  def test_masked_private_process_is_ineligible_without_fetching_movements
    response = JSON.parse(discovery)
    response.fetch("partes").first.merge!("processoPublicidade" => "Sigiloso", "processoNumeroUnico" => "***", "processoIdentificacao" => nil)
    @responses << JSON.generate(response)
    result = processor.call(@job)
    assert_equal "succeeded", result.fetch("state")
    assert_equal 0, result.fetch("eligible_process_count")
    assert_equal 1, @http.requests.size
    assert_equal "0", scalar("SELECT count(*)::text FROM public.stf_captures WHERE tenant_id = $1", [@tenant])
  end

  def test_unknown_publicity_fails_instead_of_empty_success
    response = JSON.parse(discovery)
    response.fetch("partes").first.delete("processoPublicidade")
    @responses << JSON.generate(response)
    assert_equal "failed", processor.call(@job).fetch("state")
    assert_equal 1, @http.requests.size
    assert_equal "0", scalar("SELECT count(*)::text FROM public.collection_job_results WHERE job_id = $1", [@job])
  end

  def test_public_process_without_cnj_preserves_identity_and_movement_links
    response = JSON.parse(discovery)
    response.fetch("partes").first["processoNumeroUnico"] = nil
    @responses.concat([JSON.generate(response), movements])
    assert_equal "succeeded", processor.call(@job).fetch("state")
    metadata = JSON.parse(scalar("SELECT process_data FROM public.stf_captures WHERE tenant_id = $1", [@tenant]))
    assert_nil metadata.fetch("cnj")
    assert_equal 7728350, metadata.fetch("incidente")
    assert_equal "Rcl", metadata.fetch("classe")
    assert_equal "Rcl 101463", metadata.fetch("identificacao")
    assert_equal "Público", metadata.fetch("publicidade")
    payload = JSON.parse(scalar("SELECT payload FROM public.collection_communications WHERE tenant_id = $1", [@tenant]))
    assert_equal "https://portal.stf.jus.br/processos/downloadPeca.asp?id=1", payload.fetch("stf").fetch("links").first.fetch("url")
    assert_equal @job, scalar("SELECT job_id FROM public.stf_capture_links WHERE tenant_id = $1", [@tenant])
  end

  def test_day_change_interrupts_before_second_request_and_never_commits_partial_data
    @responses << discovery
    @after_request = -> { @date_source = -> { @date + 1 } }
    result = processor.call(@job)
    assert_equal "failed", result.fetch("state")
    assert_equal "interrupted", scalar("SELECT code FROM public.collection_job_failures WHERE job_id = $1", [@job])
    assert_equal 1, @http.requests.length
    assert_equal "0", scalar("SELECT count(*)::text FROM public.stf_captures WHERE tenant_id = $1", [@tenant])
  end

  def test_source_error_is_failure_not_empty_success
    @responses << STF::SourceUnavailable.new("unavailable")
    assert_equal "failed", processor.call(@job).fetch("state")
    assert_equal "source_unavailable", scalar("SELECT code FROM public.collection_job_failures WHERE job_id = $1", [@job])
    assert_equal "0", scalar("SELECT count(*)::text FROM public.collection_job_results WHERE job_id = $1", [@job])
  end

  def test_eligible_process_without_today_events_preserves_empty_capture
    @responses.concat([discovery, movements.gsub(@date.strftime('%d/%m/%Y'), (@date - 1).strftime('%d/%m/%Y'))])
    result = processor.call(@job)
    assert_equal "succeeded", result.fetch("state")
    assert_equal 0, result.fetch("matched_count")
    assert_equal 1, result.fetch("eligible_process_count")
    assert_equal "1", scalar("SELECT count(*)::text FROM public.stf_captures WHERE tenant_id = $1", [@tenant])
    assert_equal "0", scalar("SELECT count(*)::text FROM public.collection_communications WHERE tenant_id = $1", [@tenant])
    metadata = JSON.parse(scalar("SELECT process_data FROM public.stf_captures WHERE tenant_id = $1", [@tenant]))
    assert_equal "01882631920261000000", metadata.fetch("cnj")
    assert_equal 1, @capture_times.size
    assert_equal @capture_times.first.iso8601, metadata.fetch("capturado_em")
    assert_equal "Sim", metadata.fetch("em_tramitacao")
    assert_equal "Público", metadata.fetch("publicidade")
    assert_equal @job, scalar("SELECT job_id FROM public.stf_capture_links WHERE tenant_id = $1", [@tenant])
  end

  def test_each_process_uses_its_own_capture_time_for_empty_and_nonempty_items
    response = JSON.parse(discovery)
    response["partes"] << response.fetch("partes").first.merge(
      "processoId" => 7728351, "processoNumeroUnico" => "0188263-19.2026.1.00.0001")
    response["totalDeRegistros"] = 2
    yesterday = movements.gsub(@date.strftime('%d/%m/%Y'), (@date - 1).strftime('%d/%m/%Y'))
    @responses.concat([JSON.generate(response), movements, yesterday])

    assert_equal "succeeded", processor.call(@job).fetch("state")
    assert_equal 2, @capture_times.size
    rows = @admin.exec_params("SELECT incidente, process_data FROM public.stf_captures WHERE tenant_id = $1 ORDER BY incidente", [@tenant]).to_a
    assert_equal [7728350, 7728351], rows.map { |row| row.fetch("incidente").to_i }
    rows.each_with_index do |row, index|
      assert_equal @capture_times[index].iso8601, JSON.parse(row.fetch("process_data")).fetch("capturado_em")
    end
    payload = JSON.parse(scalar("SELECT payload FROM public.collection_communications WHERE tenant_id = $1", [@tenant]))
    assert_equal @capture_times.first.iso8601, payload.fetch("stf").fetch("capturado_em")
  end

  def test_day_change_after_last_response_prevents_commit
    @responses.concat([discovery, movements])
    calls = 0
    @after_request = -> { calls += 1; @date_source = -> { @date + 1 } if calls == 2 }
    assert_equal "failed", processor.call(@job).fetch("state")
    assert_equal "interrupted", scalar("SELECT code FROM public.collection_job_failures WHERE job_id = $1", [@job])
    assert_equal "0", scalar("SELECT count(*)::text FROM public.stf_captures WHERE tenant_id = $1", [@tenant])
  end

  def test_lost_lease_stops_before_next_request_without_recording_failure
    @responses << discovery
    @after_request = -> {
      @admin.exec_params("UPDATE public.collection_job_executions SET lease_expires_at = clock_timestamp() - interval '1 second' WHERE job_id = $1", [@job])
    }
    assert_raises(STF::LeaseLost) { processor.call(@job) }
    assert_equal 1, @http.requests.length
    assert_equal "0", scalar("SELECT count(*)::text FROM public.collection_job_failures WHERE job_id = $1", [@job])
    assert_equal "0", scalar("SELECT count(*)::text FROM public.stf_captures WHERE tenant_id = $1", [@tenant])
  end

  def test_worker_selects_and_processes_a_real_queued_stf_job
    guard = PG.connect(ENV.fetch("PROCESSADOR_TEST_ADMIN_DATABASE_URL"))
    guard.exec("BEGIN")
    guard.exec_params("SELECT job_id FROM public.collection_job_executions WHERE job_id <> $1::uuid FOR UPDATE", [@job])
    @responses.concat([discovery, movements])
    output = StringIO.new
    worker = STF::Worker.new(database_url: ENV.fetch("PROCESSADOR_DATABASE_URL"), processor: processor, output: output)
    assert_equal "succeeded", worker.run_once.fetch("state")
    assert_equal "succeeded", JSON.parse(output.string).fetch("state")
    assert_equal "1", scalar("SELECT count(*)::text FROM public.collection_communications WHERE tenant_id = $1", [@tenant])
  ensure
    guard&.exec("ROLLBACK")
    guard&.close
  end

  private

  def scalar(sql, params = [])
    @admin.exec_params(sql, params).getvalue(0, 0)
  end

  def processor
    STF::Processor.new(database_url: ENV.fetch("PROCESSADOR_DATABASE_URL"), http_factory: @http_factory,
      date_source: -> { @date_source.call }, time_source: -> { Time.now.utc.tap { |time| @capture_times << time } })
  end

  def discovery
    JSON.generate("totalDePaginas" => 1, "totalDeRegistros" => 1, "partes" => [{
      "pessoaNome" => "Maria Silva", "processoId" => 7728350, "processoIdentificacao" => "Rcl 101463",
      "processoNumeroUnico" => "0188263-19.2026.1.00.0000", "processoEmTramitacao" => "Sim", "processoPublicidade" => "Público"
    }])
  end

  def movements
    <<~HTML
      <div class="processo-andamentos"><ul>
        <li><div class="andamento-item"><div class="andamento-detalhe">
          <div class="andamento-data">#{@date.strftime('%d/%m/%Y')}</div><div class="andamento-nome">Juntada</div>
          <div class="andamento-docs"><a href="downloadPeca.asp?id=1">Certidão</a></div>
          <div class="col-md-9 p-0">Certidão</div></div></div></li>
        <li><div class="andamento-item"><div class="andamento-detalhe">
          <div class="andamento-data">#{(@date - 1).strftime('%d/%m/%Y')}</div><div class="andamento-nome">Ontem</div>
          <div class="col-md-9 p-0">Outro dia</div></div></div></li>
      </ul></div>
    HTML
  end
end
