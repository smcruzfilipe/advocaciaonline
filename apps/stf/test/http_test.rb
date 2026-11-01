require "minitest/autorun"
require "minitest/mock"
require "net/http"
require_relative "../lib/stf/http"

class HttpTest < Minitest::Test
  class Connection
    attr_accessor :use_ssl, :verify_mode, :open_timeout, :read_timeout, :write_timeout, :max_retries
    attr_reader :requests

    def initialize(*responses)
      @responses = responses
      @requests = []
    end

    def request(request)
      @requests << request
      response = @responses.shift
      raise response if response.is_a?(Exception)
      yield response
    end
  end

  def response(type, code, headers: {}, chunks: [])
    result = type.new("1.1", code, "response")
    headers.each { |name, value| result[name] = value }
    result.define_singleton_method(:read_body) { |&block| chunks.each(&block) }
    result
  end

  def with_connections(*connections)
    addresses = []
    factory = lambda do |host, port, proxy|
      addresses << [host, port, proxy]
      connections.shift || raise("unexpected network request")
    end
    Net::HTTP.stub(:new, factory) { yield addresses }
  end

  def test_returns_streamed_body_and_configures_secure_bounded_connection
    connection = Connection.new(response(Net::HTTPOK, "200", chunks: ["abc", "def"]))
    calls = 0
    with_connections(connection) do |addresses|
      result = STF::Http.new(before_request: -> { calls += 1 }).get("https://digital.stf.jus.br/example?q=1")
      assert_equal "abcdef", result
      assert_equal [["digital.stf.jus.br", 443, nil]], addresses
    end
    assert_equal 1, calls
    assert connection.use_ssl
    assert_equal OpenSSL::SSL::VERIFY_PEER, connection.verify_mode
    assert_operator connection.open_timeout, :>, 0
    assert_operator connection.read_timeout, :>, 0
    assert_operator connection.write_timeout, :>, 0
    assert_equal 0, connection.max_retries
    assert_equal "/example?q=1", connection.requests.first.path
    assert_equal "identity", connection.requests.first["accept-encoding"]
  end

  def test_follows_relative_and_allowed_cross_host_redirects_with_callback_each_time
    first = Connection.new(response(Net::HTTPFound, "302", headers: {"location" => "/next"}))
    second = Connection.new(response(Net::HTTPMovedPermanently, "301", headers: {"location" => "https://digital.stf.jus.br/final"}))
    third = Connection.new(response(Net::HTTPOK, "200", chunks: ["ok"]))
    calls = 0
    with_connections(first, second, third) do |addresses|
      assert_equal "ok", STF::Http.new(before_request: -> { calls += 1 }).get("https://portal.stf.jus.br/start")
      assert_equal ["portal.stf.jus.br", "portal.stf.jus.br", "digital.stf.jus.br"], addresses.map(&:first)
    end
    assert_equal 3, calls
    assert_equal "/next", second.requests.first.path
  end

  def test_rejects_untrusted_addresses_before_network_or_callback
    calls = 0
    http = STF::Http.new(before_request: -> { calls += 1 })
    with_connections do
      ["http://portal.stf.jus.br/", "https://portal.stf.jus.br.evil.test/", "https://evil.test/",
       "https://user@portal.stf.jus.br/", "https://portal.stf.jus.br:444/", "not a url"].each do |url|
        assert_raises(STF::InvalidSource) { http.get(url) }
      end
    end
    assert_equal 0, calls
  end

  def test_rejects_unsafe_redirect_without_another_request
    ["http://portal.stf.jus.br/", "https://evil.test/", "//evil.test/path", "http://["].each do |location|
      connection = Connection.new(response(Net::HTTPFound, "302", headers: {"location" => location}))
      calls = 0
      with_connections(connection) do
        assert_raises(STF::InvalidSource) do
          STF::Http.new(before_request: -> { calls += 1 }).get("https://portal.stf.jus.br/start")
        end
      end
      assert_equal 1, calls
    end
  end

  def test_rejects_missing_redirect_location_and_redirect_loops
    no_location = Connection.new(response(Net::HTTPFound, "302"))
    with_connections(no_location) do
      assert_raises(STF::InvalidSource) { STF::Http.new.get("https://portal.stf.jus.br/start") }
    end
    connections = Array.new(STF::Http::MAX_REDIRECTS + 1) do
      Connection.new(response(Net::HTTPFound, "302", headers: {"location" => "/start"}))
    end
    with_connections(*connections) do
      assert_raises(STF::InvalidSource) { STF::Http.new.get("https://portal.stf.jus.br/start") }
    end
  end

  def test_limits_body_even_when_content_length_is_absent_or_untrue
    [response(Net::HTTPOK, "200", chunks: ["a" * STF::Http::MAX_BYTES, "b"]),
     response(Net::HTTPOK, "200", headers: {"content-length" => "1"}, chunks: ["a" * (STF::Http::MAX_BYTES + 1)]),
     response(Net::HTTPOK, "200", headers: {"content-length" => (STF::Http::MAX_BYTES + 1).to_s})].each do |oversized|
      with_connections(Connection.new(oversized)) do
        assert_raises(STF::InvalidSource) { STF::Http.new.get("https://portal.stf.jus.br/") }
      end
    end
    with_connections(Connection.new(response(Net::HTTPOK, "200", chunks: ["a" * STF::Http::MAX_BYTES]))) do
      assert_equal STF::Http::MAX_BYTES, STF::Http.new.get("https://portal.stf.jus.br/").bytesize
    end
  end

  def test_rejects_unsolicited_compression
    compressed = response(Net::HTTPOK, "200", headers: {"content-encoding" => "gzip"})
    with_connections(Connection.new(compressed)) do
      assert_raises(STF::InvalidSource) { STF::Http.new.get("https://portal.stf.jus.br/") }
    end
  end

  def test_timeout_while_streaming_is_unavailable_without_retry
    interrupted_response = response(Net::HTTPOK, "200")
    interrupted_response.define_singleton_method(:read_body) { raise Net::ReadTimeout }
    connection = Connection.new(interrupted_response)
    with_connections(connection) do
      assert_raises(STF::SourceUnavailable) { STF::Http.new.get("https://portal.stf.jus.br/") }
    end
    assert_equal 1, connection.requests.length
  end

  def test_callback_can_interrupt_before_redirect_request
    connection = Connection.new(response(Net::HTTPFound, "302", headers: {"location" => "/next"}))
    calls = 0
    with_connections(connection) do
      assert_raises(STF::Interrupted) do
        STF::Http.new(before_request: -> { calls += 1; raise STF::Interrupted if calls == 2 }).get("https://portal.stf.jus.br/")
      end
    end
    assert_equal 2, calls
    assert_equal 1, connection.requests.length
  end

  def test_http_errors_and_transport_failures_are_unavailable_and_are_not_retried
    [response(Net::HTTPForbidden, "403"), response(Net::HTTPInternalServerError, "500"),
     Net::ReadTimeout.new, SocketError.new("dns"), OpenSSL::SSL::SSLError.new("tls")].each do |failure|
      connection = Connection.new(failure)
      with_connections(connection) do
        assert_raises(STF::SourceUnavailable) { STF::Http.new.get("https://portal.stf.jus.br/") }
      end
      assert_equal 1, connection.requests.length
    end
  end

  def test_callback_interruption_is_not_translated_or_retried
    with_connections do
      assert_raises(STF::Interrupted) do
        STF::Http.new(before_request: -> { raise STF::Interrupted, "lease perdida" }).get("https://portal.stf.jus.br/")
      end
    end
  end
end
