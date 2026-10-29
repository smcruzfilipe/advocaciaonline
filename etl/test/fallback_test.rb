require "date"
require "json"
require "minitest/autorun"
require "minitest/mock"
require "socket"
require "tempfile"
require "time"
require "tmpdir"
require "uri"
require_relative "../lib/processador/http"
require_relative "../lib/processador/fallback"

module ControlledDjen
  LAWYER_NAME = "Guilherme Curcelli Guimarães".freeze
  QUERY_DATE = Date.new(2026, 10, 29)

  def publication(id)
    {
      "id" => id,
      "hash" => "publication-#{id}",
      "siglaTribunal" => "TJAC",
      "numero_processo" => "00000000000000000001",
      "texto" => "Intimação de #{LAWYER_NAME}: <script>não executar</script>",
      "destinatarioadvogados" => [{ "advogado" => {
        "nome" => LAWYER_NAME, "numero_oab" => "00123", "uf_oab" => "SP"
      } }],
      "campo_desconhecido" => { "preservar" => [nil, false, 7] }
    }
  end

  def page(items, count: items.length, status: "success")
    { body: JSON.generate("status" => status, "count" => count, "items" => items) }
  end

  def with_server(responses)
    server = TCPServer.new("127.0.0.1", 0)
    origin = "http://127.0.0.1:#{server.addr[1]}"
    requests = []
    worker = Thread.new do
      index = 0
      loop do
        socket = server.accept
        begin
          request_line = socket.gets("\r\n")
          method, target, = request_line.split(" ")
          headers = {}
          while (line = socket.gets("\r\n")) && line != "\r\n"
            key, value = line.split(":", 2)
            headers[key.downcase] = value.strip
          end
          requests << { method: method, target: target, headers: headers }
          response = responses.fetch(index, { status: 500, body: "Unexpected request" })
          index += 1
          sleep(response.fetch(:delay, 0))
          if response.key?(:raw)
            socket.write(response.fetch(:raw))
          else
            body = response.fetch(:body, "").b
            response_headers = {
              "Content-Type" => "application/json",
              "Content-Length" => response.fetch(:length, body.bytesize).to_s,
              "Connection" => "close"
            }.merge(response.fetch(:headers, {}))
            socket.write("HTTP/1.1 #{response.fetch(:status, 200)} Response\r\n")
            response_headers.each { |key, value| socket.write("#{key}: #{value}\r\n") }
            socket.write("\r\n")
            socket.write(body)
          end
        ensure
          socket.close
        end
      end
    end
    worker.report_on_exception = false
    yield origin, requests
  ensure
    worker&.kill
    worker&.value
    server&.close
  end

  def http_for(origin, **options)
    Processador::Http.new(test_origin: origin, open_timeout: 1, read_timeout: 1,
      write_timeout: 1, **options)
  end

  def source_for(origin, http: http_for(origin))
    Processador::Fallback.new(http: http, base_url: "#{origin}/api/v1/")
  end

  def query_items(source, medium: "D")
    source.each(court: "TJAC", date: QUERY_DATE, medium: medium).to_a
  end
end

class FallbackTest < Minitest::Test
  include ControlledDjen

  def test_reads_full_and_partial_pages_until_valid_empty_items_without_using_count
    first = (1..100).map { |id| publication(id) }
    second = [publication(101), publication(102)]
    third = [publication(103)]
    responses = [page(first, count: 0), page(second, count: 10_000),
      page(third, count: "not a total"), page([], count: 99)]

    with_server(responses) do |origin, requests|
      assert_equal first + second + third, query_items(source_for(origin))
      assert_equal %w[1 2 3 4], requests.map { |request|
        URI.decode_www_form(URI(request.fetch(:target)).query).to_h.fetch("pagina")
      }
    end
  end

  def test_empty_first_page_is_success_even_when_count_is_nonzero
    with_server([page([], count: 500)]) do |origin, requests|
      assert_empty query_items(source_for(origin))
      assert_equal 1, requests.length
    end
  end

  def test_uses_only_court_d_medium_same_day_and_pagination_filters
    with_server([page([publication(1)]), page([])]) do |origin, requests|
      assert_equal [publication(1)], query_items(source_for(origin))
      requests.each_with_index do |request, index|
        target = URI(request.fetch(:target))
        assert_equal "GET", request.fetch(:method)
        assert_equal "/api/v1/comunicacao", target.path
        assert_equal({
          "siglaTribunal" => "TJAC", "meio" => "D",
          "dataDisponibilizacaoInicio" => "2026-10-29",
          "dataDisponibilizacaoFim" => "2026-10-29",
          "pagina" => (index + 1).to_s, "itensPorPagina" => "100"
        }, URI.decode_www_form(target.query).to_h)
      end
    end
  end


  def test_rejects_error_or_unknown_status_even_with_http_200_and_empty_items
    [nil, "error", "fail", "pending", "SUCCESS", false].each do |status|
      with_server([page([], status: status).merge(headers: { "Retry-After" => "81" })]) do |origin, _|
        error = assert_raises(Processador::SourceError) { query_items(source_for(origin)) }
        assert_equal 81, error.retry_after
      end
    end
  end

  def test_rejects_missing_status_instead_of_accepting_empty_items
    with_server([{ body: JSON.generate("items" => []) }]) do |origin, _|
      assert_raises(Processador::SourceError) { query_items(source_for(origin)) }
    end
  end

  def test_rejects_missing_or_non_array_items
    [nil, {}, "", false, 0].each do |items|
      with_server([page(items, count: 0)]) do |origin, _|
        assert_raises(Processador::SourceError) { query_items(source_for(origin)) }
      end
    end
    with_server([{ body: JSON.generate("status" => "success", "count" => 0) }]) do |origin, _|
      assert_raises(Processador::SourceError) { query_items(source_for(origin)) }
    end
  end

  def test_validates_every_item_before_emitting_any_item_from_its_page
    [nil, [], "publication", 1, false].each do |invalid|
      with_server([page([publication(1), invalid])]) do |origin, _|
        collected = []
        assert_raises(Processador::SourceError) do
          source_for(origin).each(court: "TJAC", date: QUERY_DATE, medium: "D") { |item| collected << item }
        end
        assert_empty collected
      end
    end
  end

  def test_http_failure_on_later_page_is_not_successful_partial_collection
    with_server([page([publication(1)]),
      { status: 503, body: LAWYER_NAME, headers: { "Retry-After" => "181" } }]) do |origin, requests|
      collected = []
      error = assert_raises(Processador::SourceError) do
        source_for(origin).each(court: "TJAC", date: QUERY_DATE, medium: "D") { |item| collected << item }
      end
      assert_equal [publication(1)], collected
      assert_equal 181, error.retry_after
      assert_equal 2, requests.length
      refute_includes error.full_message, LAWYER_NAME
    end
  end

  def test_invalid_json_on_later_page_is_a_failure
    with_server([page([publication(1)]), { body: "{invalid JSON" }]) do |origin, _|
      assert_raises(Processador::SourceError) { query_items(source_for(origin)) }
    end
  end

  def test_a_new_attempt_starts_at_page_one_after_a_later_page_failure
    with_server([page([publication(1)]), { status: 500 }, page([])]) do |origin, requests|
      source = source_for(origin)
      assert_raises(Processador::SourceError) { query_items(source) }
      assert_empty query_items(source)
      assert_equal %w[1 2 1], requests.map { |request|
        URI.decode_www_form(URI(request.fetch(:target)).query).to_h.fetch("pagina")
      }
    end
  end

  def test_does_not_accept_entity_filters_or_base_url_query_parameters
    with_server([page([])]) do |origin, requests|
      source = source_for(origin)
      assert_raises(ArgumentError) do
        source.each(court: "TJAC", date: QUERY_DATE, medium: "D", nomeAdvogado: LAWYER_NAME).to_a
      end
      assert_raises(Processador::SourceError) do
        Processador::Fallback.new(http: http_for(origin), base_url: "#{origin}/api/v1?nomeAdvogado=Guilherme")
      end
      assert_empty requests
    end
  end

  def test_rejects_invalid_medium_date_or_court_before_requesting_the_source
    with_server([]) do |origin, requests|
      source = source_for(origin)
      [["TJAC", QUERY_DATE, "X"], ["TJAC", QUERY_DATE, "E"], ["TJAC", "2026-10-29", "D"],
        [nil, QUERY_DATE, "D"], ["", QUERY_DATE, "D"]].each do |court, date, medium|
        assert_raises(Processador::SourceError) do
          source.each(court: court, date: date, medium: medium).to_a
        end
      end
      assert_empty requests
    end
  end
end

class ProcessadorHttpTest < Minitest::Test
  include ControlledDjen


  def test_invalid_json_or_root_shape_is_sanitized_and_preserves_retry_after
    ["{\"nome\":\"#{LAWYER_NAME}\",", "[]", "null", '"text"', "false"].each do |body|
      with_server([{ body: body, headers: { "Retry-After" => "37" } }]) do |origin, _|
        error = assert_raises(Processador::SourceError) { http_for(origin).get_json("#{origin}/json?secret=token") }
        assert_equal 37, error.retry_after
        assert_nil error.cause
        refute_includes error.full_message, LAWYER_NAME
        refute_includes error.full_message, "secret=token"
      end
    end
  end

  def test_http_errors_preserve_integer_retry_after_including_zero
    [0, 120].each do |seconds|
      with_server([{ status: 429, headers: { "Retry-After" => seconds.to_s } }]) do |origin, _|
        error = assert_raises(Processador::SourceError) { http_for(origin).get_json("#{origin}/json") }
        assert_equal seconds, error.retry_after
      end
    end
  end

  def test_http_date_retry_after_is_rounded_up_and_never_negative
    now = Time.utc(2026, 10, 29, 12, 0, 0) + 0.5
    [[Time.utc(2026, 10, 29, 12, 2, 1).httpdate, 121],
      [Time.utc(2026, 10, 29, 11).httpdate, 0]].each do |header, expected|
      with_server([{ status: 503, headers: { "Retry-After" => header } }]) do |origin, _|
        Time.stub(:now, now) do
          error = assert_raises(Processador::SourceError) { http_for(origin).get_json("#{origin}/json") }
          assert_equal expected, error.retry_after
        end
      end
    end
  end

  def test_invalid_retry_after_is_absent_and_does_not_leak_from_previous_request
    with_server([{ status: 429, headers: { "Retry-After" => "90" } },
      { status: 503 }, { status: 503, headers: { "Retry-After" => "-1" } },
      { status: 503, headers: { "Retry-After" => "1.5" } },
      { status: 503, headers: { "Retry-After" => "tomorrow" } }]) do |origin, _|
      http = http_for(origin)
      assert_equal 90, assert_raises(Processador::SourceError) { http.get_json("#{origin}/json") }.retry_after
      4.times do
        assert_nil assert_raises(Processador::SourceError) { http.get_json("#{origin}/json") }.retry_after
      end
    end
  end

  def test_does_not_follow_redirects_or_accept_partial_http_success
    [206, 302].each do |status|
      with_server([{ status: status, body: '{}', headers: {
        "Location" => "http://169.254.169.254/private?signature=secret", "Retry-After" => "19"
      } }]) do |origin, requests|
        error = assert_raises(Processador::SourceError) { http_for(origin).get_json("#{origin}/json") }
        assert_equal 19, error.retry_after
        assert_equal 1, requests.length
        refute_includes error.full_message, "signature=secret"
      end
    end
  end

  def test_rejects_truncated_content_length_even_if_received_json_is_valid
    with_server([{ body: '{}', length: 500 }]) do |origin, _|
      assert_raises(Processador::SourceError) { http_for(origin).get_json("#{origin}/json") }
    end
  end

  def test_rejects_unterminated_chunked_body
    raw = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n2\r\n{}\r\n"
    with_server([{ raw: raw }]) do |origin, _|
      assert_raises(Processador::SourceError) { http_for(origin).get_json("#{origin}/json") }
    end
  end

  def test_read_timeout_becomes_a_source_error_without_automatic_retry
    with_server([{ body: '{}', delay: 0.3 }]) do |origin, requests|
      error = assert_raises(Processador::SourceError) do
        http_for(origin, read_timeout: 0.02).get_json("#{origin}/json?signature=secret")
      end
      assert_nil error.cause
      assert_equal 1, requests.length
      refute_includes error.full_message, "signature=secret"
    end
  end

  def test_download_preserves_binary_bytes_returns_block_result_and_cleans_tempfile
    binary = "PK\x00\xff\x80\n".b * 20_000
    with_server([{ body: binary, headers: { "Content-Type" => "application/zip" } }]) do |origin, _|
      path = nil
      result = http_for(origin).download("#{origin}/package?signature=secret") do |temporary_path|
        path = temporary_path
        assert_equal binary, File.binread(path)
        assert_equal 0o600, File.stat(path).mode & 0o777
        :processed
      end
      assert_equal :processed, result
      refute File.exist?(path)
    end
  end

  def test_download_cleans_tempfile_and_does_not_wrap_a_consumer_error
    with_server([{ body: "zip bytes" }]) do |origin, _|
      path = nil
      failure = ArgumentError.new("consumer failed")
      error = assert_raises(ArgumentError) do
        http_for(origin).download("#{origin}/package") do |temporary_path|
          path = temporary_path
          raise failure
        end
      end
      assert_same failure, error
      assert_equal "consumer failed", error.message
      refute File.exist?(path)
    end
  end

  def test_failed_download_never_yields_and_removes_the_partially_written_tempfile
    Dir.mktmpdir("processador-download-test") do |directory|
      create = Tempfile.method(:create)
      redirected_create = ->(basename, &block) { create.call(basename, directory, &block) }
      Tempfile.stub(:create, redirected_create) do
        with_server([{ body: "incomplete", length: 100, headers: { "Retry-After" => "41" } }]) do |origin, _|
          error = assert_raises(Processador::SourceError) do
            http_for(origin).download("#{origin}/package?signature=secret") { flunk "Incomplete download yielded" }
          end
          assert_equal 41, error.retry_after
          assert_empty Dir.children(directory)
          assert_nil error.cause
        end
      end
    end
  end

  def test_download_rejects_http_failure_and_preserves_retry_after
    with_server([{ status: 503, headers: { "Retry-After" => "73" } }]) do |origin, _|
      error = assert_raises(Processador::SourceError) do
        http_for(origin).download("#{origin}/package") { flunk "Failed HTTP download yielded" }
      end
      assert_equal 73, error.retry_after
    end
  end

  def test_default_transport_rejects_insecure_private_reserved_or_credentialed_urls
    urls = ["http://example.com/file", "file:///etc/passwd", "https://127.0.0.1/file",
      "https://10.0.0.1/file", "https://169.254.169.254/file", "https://100.64.0.1/file",
      "https://192.0.2.1/file", "https://224.0.0.1/file", "https://[::1]/file",
      "https://[::ffff:127.0.0.1]/file", "https://[fc00::1]/file",
      "https://user:secret@example.com/file", "https://example.com:8443/file",
      "https://example.com/file#fragment", "not a url"]
    http = Processador::Http.new
    urls.each do |url|
      error = assert_raises(Processador::SourceError, url) { http.get_json(url) }
      assert_nil error.cause
      refute_includes error.full_message, "user:secret"
    end
  end

  def test_rejects_mixed_public_and_private_dns_answers_before_connecting
    Resolv.stub(:getaddresses, ["93.184.216.34", "127.0.0.1"]) do
      assert_raises(Processador::SourceError) { Processador::Http.new.get_json("https://public.example/file") }
    end
  end

  def test_test_origin_exception_is_exact_and_not_a_blanket_http_or_private_network_bypass
    with_server([{ body: '{}' }]) do |origin, requests|
      http = http_for(origin)
      assert_equal({}, http.get_json("#{origin}/json"))
      ["http://127.0.0.2:#{URI(origin).port}/json", "http://127.0.0.1:1/json",
        "http://localhost:#{URI(origin).port}/json", "http://169.254.169.254/json"].each do |url|
        assert_raises(Processador::SourceError) { http.get_json(url) }
      end
      assert_equal 1, requests.length
    end
  end

  def test_rejects_test_origins_with_credentials_path_query_or_fragment
    ["http://user:password@localhost", "http://localhost/path", "http://localhost?query=1",
      "http://localhost#fragment", "file:///tmp", "not a url"].each do |origin|
      assert_raises(ArgumentError) { Processador::Http.new(test_origin: origin) }
    end
  end
end
