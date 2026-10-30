require "test_helper"
require "net/http"
require "stringio"

class CourtCatalogHttpTest < ActionDispatch::IntegrationTest
  setup do
    https!
    host! URI(AppSettings.origin).host
    Rails.cache.clear
  end

  test "catalog requires a valid server-side session rather than client identity claims" do
    with_djen_response(body: JSON.generate(official_grouped_catalog)) do
      get "/api/courts", params: { tenant_id: SecureRandom.uuid, subject: "claimed-identity" }
      assert_response :unauthorized
      assert_equal "authentication_required", response.parsed_body.dig("error", "code")

      cookies[ApplicationController::SESSION_COOKIE] = SecureRandom.urlsafe_base64(32)
      get "/api/courts"
      assert_response :unauthorized

      token, = authenticated_session
      cookies[ApplicationController::SESSION_COOKIE] = token
      IdentityStore.revoke(token)
      get "/api/courts"
      assert_response :unauthorized
    end
  end

  test "a session without onboarding receives the observed UF grouped official catalog" do
    sign_in

    with_djen_response(body: JSON.generate(official_grouped_catalog)) do
      get "/api/courts"
    end

    assert_response :ok
    assert_equal "application/json", response.media_type
    assert_equal expected_catalog, response.parsed_body
  end

  test "the flat catalog documented by the official OpenAPI has the same public representation" do
    sign_in
    flat_catalog = [
      { "id" => 1, "sigla" => "TRF1", "nome" => "Tribunal Regional Federal da 1ª Região", "jurisdicao" => "Federal" },
      { "sigla" => "TRE-AC", "nome" => "Tribunal Regional Eleitoral do Acre" },
      { "sigla" => "PJeCor", "nome" => "Corregedorias" },
      { "sigla" => "TJAC", "nome" => "Tribunal de Justiça do Estado do Acre" },
      { "sigla" => "TRF1", "nome" => "Tribunal Regional Federal da 1ª Região" }
    ]

    with_djen_response(body: JSON.generate(flat_catalog)) do
      get "/api/courts"
    end

    assert_response :ok
    assert_equal expected_catalog, response.parsed_body
  end

  test "group and institution order do not affect literal codes deduplication or result order" do
    sign_in
    reordered = official_grouped_catalog.reverse.map do |group|
      group.merge("instituicoes" => group.fetch("instituicoes").reverse)
    end

    [official_grouped_catalog, reordered].each do |catalog|
      Rails.cache.clear
      with_djen_response(body: JSON.generate(catalog)) do
        get "/api/courts"
      end

      assert_response :ok
      assert_equal expected_catalog, response.parsed_body
    end
  end

  test "a valid empty official catalog is a successful empty result" do
    sign_in

    with_djen_response(body: "[]") do
      get "/api/courts"
    end

    assert_response :ok
    assert_equal({ "courts" => [] }, response.parsed_body)
  end

  [302, 429, 503].each do |status|
    test "official HTTP #{status} is unavailable rather than an invented empty catalog" do
      sign_in

      with_djen_response(body: JSON.generate(official_grouped_catalog), status: status) do
        get "/api/courts"
      end

      assert_catalog_unavailable
    end
  end

  [SocketError, Net::ReadTimeout, Errno::ECONNRESET, OpenSSL::SSL::SSLError].each do |error_class|
    test "official transport failure #{error_class} returns unavailable" do
      sign_in
      failing_transport = ->(*_args, **_options) { raise error_class, "DJEN connection failed" }

      Net::HTTP.stub(:start, failing_transport) do
        get "/api/courts"
      end

      assert_catalog_unavailable
    end
  end

  { "truncated JSON" => '[{"uf":"AC","instituicoes":' }.each do |description, body|
    test "official #{description} is unavailable rather than a successful empty catalog" do
      sign_in

      with_djen_response(body: body) do
        get "/api/courts"
      end

      assert_catalog_unavailable
    end
  end

  {
    "object root" => { "courts" => [] },
    "nonarray institutions" => [{ "uf" => "AC", "instituicoes" => {} }],
    "nonobject institution" => [{ "uf" => "AC", "instituicoes" => [nil] }],
    "numeric code" => [{ "sigla" => 123, "nome" => "Tribunal" }],
    "blank name" => [{ "sigla" => "TJAC", "nome" => " " }]
  }.each do |description, invalid_catalog|
    test "official catalog with #{description} returns unavailable" do
      sign_in

      with_djen_response(body: JSON.generate(invalid_catalog)) do
        get "/api/courts"
      end

      assert_catalog_unavailable
    end
  end

  test "one invalid institution makes a grouped catalog unavailable instead of silently dropping it" do
    sign_in
    catalog = official_grouped_catalog
    catalog.first.fetch("instituicoes") << { "nome" => "Instituição sem sigla" }

    with_djen_response(body: JSON.generate(catalog)) do
      get "/api/courts"
    end

    assert_catalog_unavailable
  end

  private

  def sign_in
    token, = authenticated_session
    cookies[ApplicationController::SESSION_COOKIE] = token
  end

  # Reduced sample observed at the official endpoint on 2026-10-28; national UF is empty,
  # PJeCor has mixed case and TRF1 appears under multiple states.
  # https://comunicaapi.pje.jus.br/api/v1/comunicacao/tribunal
  # Flat alternative: https://comunicaapi.pje.jus.br/swagger/djen.yml
  def official_grouped_catalog
    [
      { "uf" => "", "nomeEstado" => "Nacional", "instituicoes" => [
        { "sigla" => "PJeCor", "nome" => "Corregedorias", "dataUltimoEnvio" => "28/10/2026" }
      ] },
      { "uf" => "AM", "nomeEstado" => "Amazonas", "instituicoes" => [
        { "sigla" => "TRF1", "nome" => "Tribunal Regional Federal da 1ª Região", "dataUltimoEnvio" => "28/10/2026" }
      ] },
      { "uf" => "AC", "nomeEstado" => "Acre", "instituicoes" => [
        { "sigla" => "TRF1", "nome" => "Tribunal Regional Federal da 1ª Região", "dataUltimoEnvio" => "28/10/2026" },
        { "sigla" => "TRE-AC", "nome" => "Tribunal Regional Eleitoral do Acre", "dataUltimoEnvio" => "03/08/2026" },
        { "sigla" => "TJAC", "nome" => "Tribunal de Justiça do Estado do Acre", "dataUltimoEnvio" => "28/10/2026" }
      ] }
    ]
  end

  def expected_catalog
    { "courts" => [
      { "code" => "PJeCor", "name" => "Corregedorias" },
      { "code" => "TJAC", "name" => "Tribunal de Justiça do Estado do Acre" },
      { "code" => "TRE-AC", "name" => "Tribunal Regional Eleitoral do Acre" },
      { "code" => "TRF1", "name" => "Tribunal Regional Federal da 1ª Região" }
    ] }
  end

  def assert_catalog_unavailable
    assert_response :service_unavailable
    assert_equal "application/json", response.media_type
    assert response.parsed_body.key?("error"), "Unavailable catalogs must expose an error"
    refute response.parsed_body.key?("courts"), "Source failures must not masquerade as a catalog"
  end

  # Only the external HTTP boundary is replaced; parsing, transformation, authentication
  # and the application endpoint remain real. Wire responses support streamed and plain reads.
  def with_djen_response(body:, status: 200)
    wire = "HTTP/1.1 #{status} DJEN\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}"
    transport = Object.new
    transport.define_singleton_method(:request) do |request, &callback|
      unless request.method == "GET" && request.path == "/api/v1/comunicacao/tribunal"
        raise ArgumentError, "Unexpected external DJEN request"
      end
      socket = Net::BufferedIO.new(StringIO.new(wire))
      external_response = Net::HTTPResponse.read_new(socket)
      external_response.reading_body(socket, true) { callback&.call(external_response) }
      external_response
    end
    start = lambda do |host, port, **options, &callback|
      unless host == "comunicaapi.pje.jus.br" && port == 443 && options[:use_ssl]
        raise ArgumentError, "Unexpected external DJEN endpoint"
      end
      callback.call(transport)
    end

    Net::HTTP.stub(:start, start) { yield }
  end
end
