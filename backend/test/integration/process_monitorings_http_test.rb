require "test_helper"

class ProcessMonitoringsHttpTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  COLLECTION_PATH = "/api/monitorings/processes".freeze
  MASKED_NUMBER = "0001234-56.2024.8.01.0001".freeze
  CANONICAL_NUMBER = "00012345620248010001".freeze
  OTHER_MASKED_NUMBER = "0009999-88.2024.8.01.0002".freeze
  OTHER_NUMBER = "00099998820248010002".freeze
  CATALOG = [
    { code: "PJeCor", name: "Corregedorias" },
    { code: "TJAC", name: "Tribunal de Justiça do Estado do Acre" },
    { code: "TRF1", name: "Tribunal Regional Federal da 1ª Região" }
  ].freeze

  setup do
    https!
    host! URI(AppSettings.origin).host
    assert_equal "advocacia_runtime", ApplicationRecord.connection.select_value("SELECT current_user")
    @token, @csrf = authenticated_session
    @tenant_id = LawyerOnboarding.call(token: @token, input: profile_payload).tenant_id
    cookies[ApplicationController::SESSION_COOKIE] = @token
  end

  test "creates a masked CNJ and reads its canonical number with leading zeros through both endpoints" do
    with_catalog do
      created = create_process({ number: MASKED_NUMBER })
      assert_process(created, number: CANONICAL_NUMBER, courts: nil)

      get resource_path(created)

      assert_response :ok
      assert_equal created, response.parsed_body
      assert_equal "application/json", response.media_type
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_saved_processes([created])
    end
  end

  test "accepts exactly twenty ASCII digits as text without losing zeros or imposing a checksum" do
    with_catalog do
      created = create_process({ number: "00000000000000000001", courts: nil })

      assert_process(created, number: "00000000000000000001", courts: nil)
      get resource_path(created)
      assert_response :ok
      assert_equal created, response.parsed_body
      assert_saved_processes([created])
    end
  end

  [[MASKED_NUMBER, CANONICAL_NUMBER], [CANONICAL_NUMBER, MASKED_NUMBER]].each do |first, duplicate|
    test "treats #{first} followed by #{duplicate} as one tenant target irrespective of court filters" do
      with_catalog do
        original = create_process({ number: first, courts: ["TJAC"] })

        post COLLECTION_PATH, params: { number: duplicate, courts: ["TRF1"] },
          as: :json, headers: write_headers

        assert_api_error(:conflict)
        assert_saved_processes([original])
      end
    end
  end

  test "an inactive process still reserves its canonical number and is reactivated instead of duplicated" do
    with_catalog do
      original = create_process({ number: MASKED_NUMBER, courts: ["TJAC"] })
      patch resource_path(original), params: { active: false }, as: :json, headers: write_headers
      assert_response :ok
      inactive = response.parsed_body
      assert_process(inactive, id: original.fetch("id"), courts: ["TJAC"], active: false)

      post COLLECTION_PATH, params: { number: CANONICAL_NUMBER, courts: ["TRF1"] },
        as: :json, headers: write_headers
      assert_api_error(:conflict)
      assert_saved_processes([inactive])

      patch resource_path(original), params: { active: true }, as: :json, headers: write_headers
      assert_response :ok
      assert_equal original, response.parsed_body
      assert_saved_processes([original])
    end
  end

  test "a missing number is rejected without creating a process" do
    with_catalog do
      post COLLECTION_PATH, params: { courts: ["TJAC"] }, as: :json, headers: write_headers

      assert_api_error(:unprocessable_entity)
      assert_saved_processes([])
    end
  end

  {
    "null" => nil,
    "boolean" => false,
    "JSON number" => 12345678901234567890,
    "array" => [CANONICAL_NUMBER],
    "object" => { value: CANONICAL_NUMBER },
    "empty text" => "",
    "whitespace" => " \t\n",
    "nineteen digits" => CANONICAL_NUMBER[1..],
    "twenty one digits" => "0#{CANONICAL_NUMBER}",
    "letter" => "0001234A620248010001",
    "leading space" => " #{CANONICAL_NUMBER}",
    "trailing space" => "#{CANONICAL_NUMBER} ",
    "trailing newline" => "#{CANONICAL_NUMBER}\n",
    "embedded space" => "0001234 5620248010001",
    "dots instead of the required hyphen" => "0001234.56.2024.8.01.0001",
    "hyphens instead of the required dots" => "0001234-56-2024-8-01-0001",
    "missing separator" => "000123456.2024.8.01.0001",
    "wrong separator positions" => "000123-456.2024.8.01.0001",
    "extra separator" => "0001234--56.2024.8.01.0001",
    "slash separators" => "0001234/56/2024/8/01/0001",
    "Unicode hyphen" => "0001234−56.2024.8.01.0001",
    "fullwidth digits" => CANONICAL_NUMBER.tr("0123456789", "０１２３４５６７８９"),
    "Arabic Indic digits" => CANONICAL_NUMBER.tr("0123456789", "٠١٢٣٤٥٦٧٨٩")
  }.each do |description, number|
    test "rejects #{description} on creation and editing without changing a saved process" do
      with_catalog do
        original = create_process({ number: MASKED_NUMBER, courts: ["TJAC"] })

        post COLLECTION_PATH, params: { number: number }, as: :json, headers: write_headers
        assert_api_error(:unprocessable_entity)

        patch resource_path(original), params: { number: number, courts: ["TRF1"], active: false },
          as: :json, headers: write_headers
        assert_api_error(:unprocessable_entity)

        get resource_path(original)
        assert_response :ok
        assert_equal original, response.parsed_body
        assert_saved_processes([original])
      end
    end
  end

  test "an omitted filter and JSON null both mean all courts rather than a saved snapshot of the catalog" do
    with_catalog do
      omitted = create_process({ number: MASKED_NUMBER })
      explicit_null = create_process({ number: OTHER_NUMBER, courts: nil })

      assert_process(omitted, courts: nil)
      assert_process(explicit_null, number: OTHER_NUMBER, courts: nil)
      assert_saved_processes([omitted, explicit_null])
    end
  end

  test "accepts catalog codes literally and deduplicates an explicit nonempty selection" do
    with_catalog do
      created = create_process({ number: MASKED_NUMBER, courts: ["TJAC", "PJeCor", "TJAC"] })

      assert_process(created, courts: ["PJeCor", "TJAC"])
      get resource_path(created)
      assert_response :ok
      assert_equal created, response.parsed_body
      assert_saved_processes([created])
    end
  end

  {
    "empty array" => [],
    "scalar string" => "TJAC",
    "number" => 1,
    "boolean" => false,
    "object" => { code: "TJAC" },
    "null element" => [nil],
    "boolean element" => [false],
    "numeric element" => [1],
    "object element" => [{ code: "TJAC" }],
    "nested array" => [["TJAC"]],
    "empty code" => [""],
    "blank code" => [" "],
    "unknown code" => ["NOT-OFFERED"],
    "lowercase alias" => ["tjac"],
    "changed mixed case code" => ["PJECOR"],
    "padded code" => [" TJAC "],
    "mixed valid and invalid codes" => ["TJAC", "NOT-OFFERED"]
  }.each do |description, courts|
    test "rejects a court filter with #{description} on creation and editing without partial changes" do
      with_catalog do
        original = create_process({ number: MASKED_NUMBER, courts: ["TJAC"] })

        post COLLECTION_PATH, params: { number: OTHER_NUMBER, courts: courts },
          as: :json, headers: write_headers
        assert_api_error(:unprocessable_entity)

        patch resource_path(original), params: { number: OTHER_NUMBER, courts: courts, active: false },
          as: :json, headers: write_headers
        assert_api_error(:unprocessable_entity)
        assert_saved_processes([original])
      end
    end
  end

  test "a code absent from a successful empty catalog is invalid rather than a source outage" do
    with_catalog([]) do
      post COLLECTION_PATH, params: { number: MASKED_NUMBER, courts: ["TJAC"] },
        as: :json, headers: write_headers

      assert_api_error(:unprocessable_entity)
      assert_saved_processes([])
    end
  end

  test "catalog unavailability prevents creating a process with an explicit selection" do
    with_unavailable_catalog do
      post COLLECTION_PATH, params: { number: MASKED_NUMBER, courts: ["TJAC"] },
        as: :json, headers: write_headers

      assert_api_error(:service_unavailable)
    end
    with_catalog { assert_saved_processes([]) }
  end

  test "catalog unavailability prevents editing an explicit selection and rolls back every changed field" do
    original = with_catalog { create_process({ number: MASKED_NUMBER, courts: ["TJAC"] }) }

    with_unavailable_catalog do
      patch resource_path(original), params: { number: OTHER_NUMBER, courts: ["TRF1"], active: false },
        as: :json, headers: write_headers
      assert_api_error(:service_unavailable)
    end

    with_catalog do
      get resource_path(original)
      assert_response :ok
      assert_equal original, response.parsed_body
      assert_saved_processes([original])
    end
  end

  test "a catalog outage does not prevent all-court creation or clearing a filter to null" do
    with_unavailable_catalog do
      omitted = create_process({ number: MASKED_NUMBER })
      explicit_null = create_process({ number: OTHER_NUMBER, courts: nil })
      assert_process(omitted, courts: nil)
      assert_process(explicit_null, number: OTHER_NUMBER, courts: nil)
      assert_saved_processes([omitted, explicit_null])
    end

    selected = with_catalog do
      create_process({ number: "00077776620248010003", courts: ["TJAC"] })
    end
    with_unavailable_catalog do
      patch resource_path(selected), params: { courts: nil }, as: :json, headers: write_headers

      assert_response :ok
      assert_process(response.parsed_body, id: selected.fetch("id"),
        number: "00077776620248010003", courts: nil)
      get resource_path(selected)
      assert_response :ok
      assert_nil response.parsed_body.fetch("courts")
    end
  end

  test "reads and edits without a courts field preserve the selection during a catalog outage" do
    original = with_catalog { create_process({ number: MASKED_NUMBER, courts: ["TJAC"] }) }

    with_unavailable_catalog do
      get resource_path(original)
      assert_response :ok
      assert_equal original, response.parsed_body
      assert_saved_processes([original])

      patch resource_path(original), params: { number: OTHER_MASKED_NUMBER, active: false },
        as: :json, headers: write_headers
      assert_response :ok
      edited = response.parsed_body
      assert_process(edited, id: original.fetch("id"), number: OTHER_NUMBER, courts: ["TJAC"], active: false)
      assert_saved_processes([edited])

      patch resource_path(original), params: { active: true }, as: :json, headers: write_headers
      assert_response :ok
      assert_process(response.parsed_body, id: original.fetch("id"), number: OTHER_NUMBER, courts: ["TJAC"])
    end
  end

  test "a selected court disappearing from the catalog never silently broadens an existing filter" do
    original = with_catalog { create_process({ number: MASKED_NUMBER, courts: ["TJAC"] }) }

    with_catalog(CATALOG.reject { |court| court.fetch(:code) == "TJAC" }) do
      get resource_path(original)
      assert_response :ok
      assert_equal original, response.parsed_body
      assert_saved_processes([original])

      patch resource_path(original), params: { number: OTHER_MASKED_NUMBER },
        as: :json, headers: write_headers
      assert_response :ok
      edited = response.parsed_body
      assert_process(edited, id: original.fetch("id"), number: OTHER_NUMBER, courts: ["TJAC"])

      patch resource_path(original), params: { courts: ["TJAC"] }, as: :json, headers: write_headers
      assert_api_error(:unprocessable_entity)
      assert_saved_processes([edited])
    end

    with_catalog do
      get resource_path(original)
      assert_response :ok
      assert_process(response.parsed_body, id: original.fetch("id"), number: OTHER_NUMBER, courts: ["TJAC"])
    end
  end

  test "editing the number and filter preserves identity and supports deactivation and reactivation" do
    with_catalog do
      original = create_process({ number: MASKED_NUMBER, courts: ["TJAC"] })

      patch resource_path(original), params: { number: OTHER_MASKED_NUMBER, courts: ["TRF1", "PJeCor", "TRF1"] },
        as: :json, headers: write_headers
      assert_response :ok
      edited = response.parsed_body
      assert_process(edited, id: original.fetch("id"), number: OTHER_NUMBER, courts: ["PJeCor", "TRF1"])
      assert_saved_processes([edited])

      patch resource_path(original), params: { active: false }, as: :json, headers: write_headers
      assert_response :ok
      inactive = response.parsed_body
      assert_process(inactive, id: original.fetch("id"), number: OTHER_NUMBER,
        courts: ["PJeCor", "TRF1"], active: false)
      get resource_path(original)
      assert_response :ok
      assert_equal inactive, response.parsed_body
      assert_saved_processes([inactive])

      patch resource_path(original), params: { number: OTHER_NUMBER, active: true, courts: nil },
        as: :json, headers: write_headers
      assert_response :ok
      reactivated = response.parsed_body
      assert_process(reactivated, id: original.fetch("id"), number: OTHER_NUMBER, courts: nil)
      assert_saved_processes([reactivated])
    end
  end

  [true, false].each do |target_active|
    test "editing cannot take a canonical number reserved by another process with active #{target_active}" do
      with_catalog do
        reserved = create_process({ number: MASKED_NUMBER, courts: ["TJAC"] })
        unless target_active
          patch resource_path(reserved), params: { active: false }, as: :json, headers: write_headers
          assert_response :ok
          reserved = response.parsed_body
        end
        original = create_process({ number: OTHER_NUMBER, courts: ["TRF1"] })

        patch resource_path(original), params: { number: MASKED_NUMBER, courts: nil, active: false },
          as: :json, headers: write_headers

        assert_api_error(:conflict)
        assert_saved_processes([reserved, original])
      end
    end
  end

  test "the same canonical number is independent in different tenants and client tenant IDs never choose the owner" do
    second_token, second_csrf = authenticated_session
    second_tenant = LawyerOnboarding.call(token: second_token, input: profile_payload).tenant_id

    with_catalog do
      first = create_process({ number: MASKED_NUMBER, tenant_id: second_tenant })
      assert_process(first, tenant_id: @tenant_id)

      cookies[ApplicationController::SESSION_COOKIE] = second_token
      second = create_process({ number: CANONICAL_NUMBER, tenant_id: @tenant_id }, csrf: second_csrf)
      assert_process(second, tenant_id: second_tenant)
      assert_not_equal first.fetch("id"), second.fetch("id")
      get COLLECTION_PATH, params: { tenant_id: @tenant_id }
      assert_collection_response([second])

      patch resource_path(second), params: { tenant_id: @tenant_id, active: false },
        as: :json, headers: write_headers(second_csrf)
      assert_response :ok
      assert_process(response.parsed_body, id: second.fetch("id"), tenant_id: second_tenant, active: false)

      cookies[ApplicationController::SESSION_COOKIE] = @token
      get COLLECTION_PATH, params: { tenant_id: second_tenant }
      assert_collection_response([first])
      get resource_path(first), params: { tenant_id: second_tenant }
      assert_response :ok
      assert_equal first, response.parsed_body
    end
  end

  test "cross-tenant resource IDs cannot be read edited deactivated or reactivated even with the owning tenant ID" do
    second_token, second_csrf = authenticated_session
    second_tenant = LawyerOnboarding.call(token: second_token, input: profile_payload).tenant_id

    with_catalog do
      first = create_process({ number: MASKED_NUMBER, courts: ["TJAC"] })
      cookies[ApplicationController::SESSION_COOKIE] = second_token
      second = create_process({ number: OTHER_NUMBER, courts: ["TRF1"] }, csrf: second_csrf)

      [[second_token, second_csrf, first, second], [@token, @csrf, second, first]].each do |token, csrf, foreign, own|
        cookies[ApplicationController::SESSION_COOKIE] = token
        get resource_path(foreign), params: { tenant_id: foreign.fetch("tenant_id") }
        assert_api_error(:not_found)

        [{ number: "00077776620248010003", courts: nil }, { active: false }, { active: true }].each do |changes|
          patch resource_path(foreign), params: changes.merge(tenant_id: foreign.fetch("tenant_id")),
            as: :json, headers: write_headers(csrf)
          assert_api_error(:not_found)
        end
        assert_saved_processes([own])
      end

      cookies[ApplicationController::SESSION_COOKIE] = second_token
      get resource_path(second)
      assert_response :ok
      assert_process(response.parsed_body, id: second.fetch("id"), tenant_id: second_tenant,
        number: OTHER_NUMBER, courts: ["TRF1"])
      assert_saved_processes([second])
      cookies[ApplicationController::SESSION_COOKIE] = @token
      assert_saved_processes([first])
    end
  end

  test "missing and invented sessions cannot list read create or patch using client tenant claims" do
    with_catalog do
      original = create_process({ number: MASKED_NUMBER })

      [nil, SecureRandom.urlsafe_base64(32)].each do |token|
        cookies[ApplicationController::SESSION_COOKIE] = token
        assert_all_routes_unauthorized(original)
      end

      cookies[ApplicationController::SESSION_COOKIE] = @token
      assert_saved_processes([original])
    end
  end

  test "a revoked session immediately loses every process route despite retaining its CSRF and tenant ID" do
    with_catalog do
      original = create_process({ number: MASKED_NUMBER })
      IdentityStore.revoke(@token)

      assert_all_routes_unauthorized(original)
      assert_nil IdentityStore.context(@token)
    end
  end

  test "POST and PATCH require the current session CSRF token and the exact same origin" do
    _, foreign_csrf = authenticated_session
    invalid_headers = [
      { "Origin" => AppSettings.origin },
      { "Origin" => AppSettings.origin, "X-CSRF-Token" => SecureRandom.urlsafe_base64(32) },
      { "Origin" => AppSettings.origin, "X-CSRF-Token" => foreign_csrf },
      { "Origin" => "https://attacker.test", "X-CSRF-Token" => @csrf },
      { "X-CSRF-Token" => @csrf }
    ]

    with_catalog do
      original = create_process({ number: MASKED_NUMBER, courts: ["TJAC"] })

      invalid_headers.each do |headers|
        post COLLECTION_PATH, params: { number: OTHER_NUMBER, tenant_id: @tenant_id },
          as: :json, headers: headers
        assert_api_error(:forbidden, code: "invalid_csrf")

        patch resource_path(original), params: { number: OTHER_NUMBER, courts: nil, active: false },
          as: :json, headers: headers
        assert_api_error(:forbidden, code: "invalid_csrf")
        assert_saved_processes([original])
      end
    end
  end

  test "an authenticated session without onboarding cannot borrow a tenant or operate on its process" do
    with_catalog do
      original = create_process({ number: MASKED_NUMBER })
      token, csrf = authenticated_session
      cookies[ApplicationController::SESSION_COOKIE] = token
      assert_nil IdentityStore.context(token).fetch("tenant_id")

      get COLLECTION_PATH, params: { tenant_id: @tenant_id }
      assert_api_error(:not_found, code: "onboarding_required")
      get resource_path(original), params: { tenant_id: @tenant_id }
      assert_api_error(:not_found, code: "onboarding_required")
      post COLLECTION_PATH, params: { number: OTHER_NUMBER, tenant_id: @tenant_id },
        as: :json, headers: write_headers(csrf)
      assert_api_error(:not_found, code: "onboarding_required")
      patch resource_path(original), params: { active: false, tenant_id: @tenant_id },
        as: :json, headers: write_headers(csrf)
      assert_api_error(:not_found, code: "onboarding_required")
      assert_nil IdentityStore.context(token).fetch("tenant_id")

      cookies[ApplicationController::SESSION_COOKIE] = @token
      assert_saved_processes([original])
    end
  end

  private

  def with_catalog(catalog = CATALOG)
    CourtCatalog.stub(:fetch, catalog) { yield }
  end

  def with_unavailable_catalog
    failure = ->(*_args, **_options) { raise CourtCatalog::Unavailable, "DJEN unavailable" }
    CourtCatalog.stub(:fetch, failure) { yield }
  end

  def write_headers(csrf = @csrf)
    { "Origin" => AppSettings.origin, "X-CSRF-Token" => csrf }
  end

  def resource_path(process)
    "#{COLLECTION_PATH}/#{process.fetch('id')}"
  end

  def create_process(input, csrf: @csrf)
    post COLLECTION_PATH, params: input, as: :json, headers: write_headers(csrf)
    assert_response :created
    assert_equal "application/json", response.media_type
    body = response.parsed_body
    assert_process_shape(body)
    body
  end

  def assert_process_shape(body)
    assert_equal %w[active courts id number tenant_id], body.keys.sort
    %w[id tenant_id number].each do |key|
      assert_kind_of String, body.fetch(key)
      assert_not_empty body.fetch(key)
    end
    assert_match(/\A[0-9]{20}\z/, body.fetch("number"))
    assert_includes [true, false], body.fetch("active")
    courts = body.fetch("courts")
    return if courts.nil?

    assert_kind_of Array, courts
    assert_not_empty courts
    courts.each { |code| assert_kind_of String, code }
    assert_equal courts.uniq, courts
  end

  def assert_process(body, id: nil, tenant_id: @tenant_id, number: CANONICAL_NUMBER, courts: nil, active: true)
    assert_process_shape(body)
    assert_equal id, body.fetch("id") if id
    assert_equal tenant_id, body.fetch("tenant_id")
    assert_equal number, body.fetch("number")
    assert_equal active, body.fetch("active")
    if courts.nil?
      assert_nil body.fetch("courts")
    else
      assert_equal courts.sort, body.fetch("courts").sort
    end
  end

  def assert_collection_response(expected)
    assert_response :ok
    assert_equal "application/json", response.media_type
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal ["processes"], response.parsed_body.keys
    actual = response.parsed_body.fetch("processes")
    assert_kind_of Array, actual
    actual.each { |process| assert_process_shape(process) }
    assert_equal expected.sort_by { |process| process.fetch("id") },
      actual.sort_by { |process| process.fetch("id") }
  end

  def assert_saved_processes(expected)
    get COLLECTION_PATH
    assert_collection_response(expected)
  end

  def assert_api_error(status, code: nil)
    assert_response status
    assert_equal "application/json", response.media_type
    assert_equal ["error"], response.parsed_body.keys
    assert_kind_of Hash, response.parsed_body.fetch("error")
    assert_equal code, response.parsed_body.dig("error", "code") if code
  end

  def assert_all_routes_unauthorized(original)
    get COLLECTION_PATH, params: { tenant_id: @tenant_id }
    assert_api_error(:unauthorized, code: "authentication_required")
    get resource_path(original), params: { tenant_id: @tenant_id }
    assert_api_error(:unauthorized, code: "authentication_required")
    post COLLECTION_PATH, params: { number: OTHER_NUMBER, tenant_id: @tenant_id },
      as: :json, headers: write_headers
    assert_api_error(:unauthorized, code: "authentication_required")
    patch resource_path(original), params: { active: false, tenant_id: @tenant_id },
      as: :json, headers: write_headers
    assert_api_error(:unauthorized, code: "authentication_required")
  end
end
