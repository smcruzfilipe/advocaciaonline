require "test_helper"
require "digest"

class PartyMonitoringsHttpTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    https!
    host! URI(AppSettings.origin).host
    assert_equal "advocacia_runtime", ApplicationRecord.connection.select_value("SELECT current_user")
  end

  test "creates reads and lists a party with normalized whitespace and preserved spelling" do
    _, csrf, lawyer = sign_in_lawyer

    with_catalog do
      post "/api/monitorings/parties", params: { name: "  José,\t da\n Silva  " },
        as: :json, headers: write_headers(csrf)

      assert_response :created
      assert_equal "application/json", response.media_type
      assert_equal "no-store", response.headers["Cache-Control"]
      party = response.parsed_body
      assert_party(party, tenant_id: lawyer.tenant_id, name: "José, da Silva")

      assert_equal party, read_party(party.fetch("id"))
      assert_equal [party], listed_parties
    end
  end

  test "an explicit null court filter has the same all-courts meaning as an omitted filter" do
    _, csrf, lawyer = sign_in_lawyer

    with_catalog do
      omitted = create_party("José da Silva", csrf: csrf)
      explicit_null = create_party("Maria da Silva", csrf: csrf, courts: nil)

      assert_party(omitted, tenant_id: lawyer.tenant_id, name: "José da Silva")
      assert_party(explicit_null, tenant_id: lawyer.tenant_id, name: "Maria da Silva")
      assert_equal explicit_null, read_party(explicit_null.fetch("id"))
      assert_equal [omitted, explicit_null].sort_by { |party| party.fetch("id") },
        listed_parties.sort_by { |party| party.fetch("id") }
    end
  end

  {
    "missing" => {},
    "null" => { name: nil },
    "empty" => { name: "" },
    "whitespace only" => { name: " \t\r\n " },
    "numeric" => { name: 123 },
    "boolean" => { name: false },
    "array" => { name: ["José da Silva"] },
    "object" => { name: { full_name: "José da Silva" } }
  }.each do |description, input|
    test "rejects a #{description} party name without creating a monitoring" do
      _, csrf, = sign_in_lawyer

      with_catalog do
        post "/api/monitorings/parties", params: input, as: :json, headers: write_headers(csrf)

        assert_api_error :unprocessable_entity
        assert_empty listed_parties
      end
    end
  end

  test "a very large low-compressibility name is rejected on creation without changing existing parties" do
    _, csrf, = sign_in_lawyer

    with_catalog do
      original = create_party("José da Silva", csrf: csrf, courts: ["TJAC"])
      post "/api/monitorings/parties",
        params: { name: deterministic_party_name(blocks: 256), courts: ["TRF1"] },
        as: :json, headers: write_headers(csrf)

      assert_api_error :unprocessable_entity
      assert_equal original, read_party(original.fetch("id"))
      assert_equal [original], listed_parties
    end
  end

  test "a very large low-compressibility edited name returns validation error and preserves every field" do
    _, csrf, = sign_in_lawyer

    with_catalog do
      original = create_party("José da Silva", csrf: csrf, courts: ["TJAC"])
      patch "/api/monitorings/parties/#{original.fetch('id')}",
        params: { name: deterministic_party_name(blocks: 256), courts: ["TRF1"], active: false },
        as: :json, headers: write_headers(csrf)

      assert_api_error :unprocessable_entity
      assert_equal original, read_party(original.fetch("id"))
      assert_equal [original], listed_parties
    end
  end

  test "a reasonable low-compressibility name remains accepted for creation and editing" do
    _, csrf, lawyer = sign_in_lawyer
    name = deterministic_party_name(blocks: 3)

    with_catalog do
      original = create_party(name, csrf: csrf, courts: ["TJAC"])
      assert_party(original, tenant_id: lawyer.tenant_id, name: name, courts: ["TJAC"])
      assert_equal original, read_party(original.fetch("id"))

      edited_name = name.sub(/\AParte/, "Outra")
      patch "/api/monitorings/parties/#{original.fetch('id')}", params: { name: edited_name },
        as: :json, headers: write_headers(csrf)

      assert_response :ok
      edited = response.parsed_body
      assert_party(edited, tenant_id: lawyer.tenant_id, name: edited_name, courts: ["TJAC"], id: original.fetch("id"))
      assert_equal edited, read_party(original.fetch("id"))
      assert_equal [edited], listed_parties
    end
  end

  test "canonical names conflict regardless of case accents excess whitespace or court selection" do
    _, csrf, = sign_in_lawyer

    with_catalog do
      original = create_party("José da Silva", csrf: csrf, courts: ["TJAC"])
      ["JOSE DA SILVA", " \t jose  da\n silva ", "Jose\u0301 da Silva"].each do |duplicate_name|
        post "/api/monitorings/parties", params: { name: duplicate_name, courts: ["TRF1"] },
          as: :json, headers: write_headers(csrf)

        assert_api_error :conflict
        assert_equal original, read_party(original.fetch("id"))
        assert_equal [original], listed_parties
      end
    end
  end

  test "punctuation and additional name components distinguish separate party targets" do
    _, csrf, = sign_in_lawyer
    names = ["José da Silva", "José, da Silva", "José-da-Silva", "José da Silva Filho"]

    with_catalog do
      parties = names.map { |name| create_party(name, csrf: csrf) }

      assert_equal names.length, parties.map { |party| party.fetch("id") }.uniq.length
      assert_equal names.sort, listed_parties.map { |party| party.fetch("name") }.sort
    end
  end

  test "a deactivated canonical name still conflicts and must be reactivated rather than recreated" do
    _, csrf, lawyer = sign_in_lawyer

    with_catalog do
      original = create_party("José da Silva", csrf: csrf, courts: ["TJAC"])
      patch "/api/monitorings/parties/#{original.fetch('id')}", params: { active: false },
        as: :json, headers: write_headers(csrf)
      assert_response :ok
      inactive = response.parsed_body
      assert_party(inactive, tenant_id: lawyer.tenant_id, name: "José da Silva",
        courts: ["TJAC"], active: false, id: original.fetch("id"))

      post "/api/monitorings/parties", params: { name: "JOSE DA SILVA", courts: ["TRF1"] },
        as: :json, headers: write_headers(csrf)

      assert_api_error :conflict
      assert_equal inactive, read_party(original.fetch("id"))
      assert_equal [inactive], listed_parties

      patch "/api/monitorings/parties/#{original.fetch('id')}", params: { active: true },
        as: :json, headers: write_headers(csrf)
      assert_response :ok
      assert_equal original, response.parsed_body
      assert_equal original, read_party(original.fetch("id"))
      assert_equal [original], listed_parties
    end
  end

  test "the same canonical name belongs independently to different authenticated tenants" do
    first_token, first_csrf, first_lawyer = sign_in_lawyer

    with_catalog do
      first = create_party("José da Silva", csrf: first_csrf, courts: ["TJAC"])
      second_token, second_csrf, second_lawyer = sign_in_lawyer
      second = create_party("JOSE DA SILVA", csrf: second_csrf, courts: ["TRF1"])
      assert_not_equal first.fetch("id"), second.fetch("id")
      assert_not_equal first_lawyer.tenant_id, second_lawyer.tenant_id
      assert_party(second, tenant_id: second_lawyer.tenant_id, name: "JOSE DA SILVA", courts: ["TRF1"])
      assert_equal [second], listed_parties(tenant_id: first_lawyer.tenant_id)

      cookies[ApplicationController::SESSION_COOKIE] = first_token
      assert_equal [first], listed_parties(tenant_id: second_lawyer.tenant_id)
      assert_equal first, read_party(first.fetch("id"), tenant_id: second_lawyer.tenant_id)

      cookies[ApplicationController::SESSION_COOKIE] = second_token
      assert_equal [second], listed_parties
      assert_equal second, read_party(second.fetch("id"))
    end
  end

  test "court selections contain supported literal codes and repeated codes are stored only once" do
    _, csrf, lawyer = sign_in_lawyer

    with_catalog do
      party = create_party("José da Silva", csrf: csrf, courts: ["TRF1", "PJeCor", "TJAC", "TRF1"])

      assert_party(party, tenant_id: lawyer.tenant_id, name: "José da Silva", courts: ["TRF1", "PJeCor", "TJAC"])
      assert_equal party, read_party(party.fetch("id"))
      assert_equal [party], listed_parties
    end
  end

  {
    "empty array" => [],
    "unknown code" => ["NOT-OFFERED"],
    "supported and unknown codes" => ["TJAC", "NOT-OFFERED"],
    "changed code case" => ["tjac"],
    "string instead of array" => "TJAC",
    "object instead of array" => { code: "TJAC" },
    "null entry" => [nil],
    "numeric entry" => [123],
    "object entry" => [{ code: "TJAC" }],
    "blank code" => [" "]
  }.each do |description, courts|
    test "rejects a court filter with #{description} without saving a party" do
      _, csrf, = sign_in_lawyer

      with_catalog do
        post "/api/monitorings/parties", params: { name: "José da Silva", courts: courts },
          as: :json, headers: write_headers(csrf)

        assert_api_error :unprocessable_entity
        assert_empty listed_parties
      end
    end
  end

  test "an empty available catalog does not make an explicit court selection supported" do
    _, csrf, = sign_in_lawyer

    with_catalog([]) do
      post "/api/monitorings/parties", params: { name: "José da Silva", courts: ["TJAC"] },
        as: :json, headers: write_headers(csrf)

      assert_api_error :unprocessable_entity
      assert_empty listed_parties
      all_courts = create_party("José da Silva", csrf: csrf)
      assert_nil all_courts.fetch("courts")
    end
  end

  test "catalog failure prevents creating an explicitly filtered party and permits a later retry" do
    _, csrf, = sign_in_lawyer

    with_unavailable_catalog do
      post "/api/monitorings/parties", params: { name: "José da Silva", courts: ["TJAC"] },
        as: :json, headers: write_headers(csrf)

      assert_api_error :service_unavailable
      assert_empty listed_parties
    end

    with_catalog do
      party = create_party("José da Silva", csrf: csrf, courts: ["TJAC"])
      assert_equal [party], listed_parties
    end
  end

  test "edits normalize the displayed name retain identity and may keep the same canonical key" do
    _, csrf, lawyer = sign_in_lawyer

    with_catalog do
      original = create_party("José da Silva", csrf: csrf, courts: ["TJAC"])
      patch "/api/monitorings/parties/#{original.fetch('id')}",
        params: { name: "  JOSE\tDA\nSILVA  " }, as: :json, headers: write_headers(csrf)

      assert_response :ok
      edited = response.parsed_body
      assert_party(edited, tenant_id: lawyer.tenant_id, name: "JOSE DA SILVA", courts: ["TJAC"], id: original.fetch("id"))
      assert_equal edited, read_party(original.fetch("id"))
      assert_equal [edited], listed_parties
    end
  end

  test "renaming to another inactive canonical target conflicts without partially editing any fields" do
    _, csrf, = sign_in_lawyer

    with_catalog do
      reserved = create_party("José da Silva", csrf: csrf)
      patch "/api/monitorings/parties/#{reserved.fetch('id')}", params: { active: false },
        as: :json, headers: write_headers(csrf)
      assert_response :ok
      inactive = response.parsed_body
      original = create_party("Maria da Silva", csrf: csrf, courts: ["TJAC"])

      patch "/api/monitorings/parties/#{original.fetch('id')}",
        params: { name: "JOSE DA SILVA", courts: ["TRF1"], active: false },
        as: :json, headers: write_headers(csrf)

      assert_api_error :conflict
      assert_equal original, read_party(original.fetch("id"))
      assert_equal inactive, read_party(reserved.fetch("id"))
      assert_equal [original, inactive].sort_by { |party| party.fetch("id") },
        listed_parties.sort_by { |party| party.fetch("id") }
    end
  end

  test "a blank edited name is rejected without changing the existing target" do
    _, csrf, = sign_in_lawyer

    with_catalog do
      original = create_party("José da Silva", csrf: csrf, courts: ["TJAC"])
      patch "/api/monitorings/parties/#{original.fetch('id')}",
        params: { name: " \t\n ", courts: ["TRF1"], active: false },
        as: :json, headers: write_headers(csrf)

      assert_api_error :unprocessable_entity
      assert_equal original, read_party(original.fetch("id"))
      assert_equal [original], listed_parties
    end
  end

  test "an edit can replace deduplicate or explicitly clear its court filter" do
    _, csrf, lawyer = sign_in_lawyer

    with_catalog do
      original = create_party("José da Silva", csrf: csrf, courts: ["TJAC"])
      patch "/api/monitorings/parties/#{original.fetch('id')}",
        params: { name: "  Maria\t da  Silva ", courts: ["TRF1", "PJeCor", "TRF1"] },
        as: :json, headers: write_headers(csrf)
      assert_response :ok
      selected = response.parsed_body
      assert_party(selected, tenant_id: lawyer.tenant_id, name: "Maria da Silva",
        courts: ["TRF1", "PJeCor"], id: original.fetch("id"))
      assert_equal selected, read_party(original.fetch("id"))

      patch "/api/monitorings/parties/#{original.fetch('id')}", params: { courts: nil },
        as: :json, headers: write_headers(csrf)
      assert_response :ok
      all_courts = response.parsed_body
      assert_party(all_courts, tenant_id: lawyer.tenant_id, name: "Maria da Silva", id: original.fetch("id"))
      assert_equal all_courts, read_party(original.fetch("id"))
      assert_equal [all_courts], listed_parties
    end
  end

  test "an invalid edited court selection cannot partially rename or deactivate the target" do
    _, csrf, = sign_in_lawyer

    with_catalog do
      original = create_party("José da Silva", csrf: csrf, courts: ["TJAC"])
      [[], ["NOT-OFFERED"], ["TRF1", "NOT-OFFERED"]].each do |invalid_courts|
        patch "/api/monitorings/parties/#{original.fetch('id')}",
          params: { name: "Maria da Silva", courts: invalid_courts, active: false },
          as: :json, headers: write_headers(csrf)

        assert_api_error :unprocessable_entity
        assert_equal original, read_party(original.fetch("id"))
        assert_equal [original], listed_parties
      end
    end
  end

  test "catalog failure prevents all fields of an explicitly filtered edit from being saved" do
    _, csrf, = sign_in_lawyer
    original = nil
    with_catalog { original = create_party("José da Silva", csrf: csrf, courts: ["TJAC"]) }

    with_unavailable_catalog do
      patch "/api/monitorings/parties/#{original.fetch('id')}",
        params: { name: "Maria da Silva", courts: ["TRF1"], active: false },
        as: :json, headers: write_headers(csrf)

      assert_api_error :service_unavailable
      assert_equal original, read_party(original.fetch("id"))
      assert_equal [original], listed_parties
    end

    with_catalog do
      patch "/api/monitorings/parties/#{original.fetch('id')}",
        params: { name: "Maria da Silva", courts: ["TRF1"], active: false },
        as: :json, headers: write_headers(csrf)
      assert_response :ok
      edited = response.parsed_body
      assert_equal original.fetch("id"), edited.fetch("id")
      assert_equal "Maria da Silva", edited.fetch("name")
      assert_equal ["TRF1"], edited.fetch("courts")
      assert_equal false, edited.fetch("active")
      assert_equal edited, read_party(original.fetch("id"))
    end
  end

  test "a saved unavailable code is preserved on reads and edits which omit the filter" do
    _, csrf, lawyer = sign_in_lawyer
    original = nil
    with_catalog { original = create_party("José da Silva", csrf: csrf, courts: ["TJAC"]) }

    with_catalog(available_courts.reject { |court| court.fetch(:code) == "TJAC" }) do
      assert_equal original, read_party(original.fetch("id"))
      assert_equal [original], listed_parties
    end

    with_unavailable_catalog do
      assert_equal original, read_party(original.fetch("id"))
      assert_equal [original], listed_parties
      patch "/api/monitorings/parties/#{original.fetch('id')}",
        params: { name: "Maria da Silva", active: false }, as: :json, headers: write_headers(csrf)
      assert_response :ok
      inactive = response.parsed_body
      assert_party(inactive, tenant_id: lawyer.tenant_id, name: "Maria da Silva", courts: ["TJAC"],
        active: false, id: original.fetch("id"))
      assert_equal inactive, read_party(original.fetch("id"))
      assert_equal [inactive], listed_parties
    end
  end

  test "nonboolean active values cannot change a party" do
    _, csrf, = sign_in_lawyer

    with_catalog do
      original = create_party("José da Silva", csrf: csrf)
      [nil, "false", 0, [], {}].each do |invalid_active|
        patch "/api/monitorings/parties/#{original.fetch('id')}",
          params: { active: invalid_active, name: "Maria da Silva" }, as: :json, headers: write_headers(csrf)

        assert_api_error :unprocessable_entity
        assert_equal original, read_party(original.fetch("id"))
      end
    end
  end

  test "client supplied IDs and tenant claims cannot assign or transfer ownership" do
    first_token, first_csrf, first_lawyer = sign_in_lawyer

    with_catalog do
      first = create_party("José da Silva", csrf: first_csrf)
      _, second_csrf, second_lawyer = sign_in_lawyer
      post "/api/monitorings/parties",
        params: { id: first.fetch("id"), tenant_id: first_lawyer.tenant_id, name: "Maria da Silva" },
        as: :json, headers: write_headers(second_csrf)
      assert_response :created
      second = response.parsed_body
      assert_not_equal first.fetch("id"), second.fetch("id")
      assert_party(second, tenant_id: second_lawyer.tenant_id, name: "Maria da Silva")

      patch "/api/monitorings/parties/#{second.fetch('id')}",
        params: { id: first.fetch("id"), tenant_id: first_lawyer.tenant_id, name: "Maria Lima" },
        as: :json, headers: write_headers(second_csrf)
      assert_response :ok
      edited = response.parsed_body
      assert_party(edited, tenant_id: second_lawyer.tenant_id, name: "Maria Lima", id: second.fetch("id"))
      assert_equal [edited], listed_parties(tenant_id: first_lawyer.tenant_id)

      cookies[ApplicationController::SESSION_COOKIE] = first_token
      assert_equal first, read_party(first.fetch("id"))
      assert_equal [first], listed_parties(tenant_id: second_lawyer.tenant_id)
    end
  end

  test "knowing another tenants party ID and tenant ID never authorizes reads or changes" do
    owner_token, owner_csrf, owner = sign_in_lawyer

    with_catalog do
      original = create_party("José da Silva", csrf: owner_csrf, courts: ["TJAC"])
      _, attacker_csrf, = sign_in_lawyer

      get "/api/monitorings/parties/#{original.fetch('id')}", params: { tenant_id: owner.tenant_id }
      assert_api_error :not_found
      patch "/api/monitorings/parties/#{original.fetch('id')}",
        params: { tenant_id: owner.tenant_id, name: "Intruder", courts: ["TRF1"], active: false },
        as: :json, headers: write_headers(attacker_csrf)
      assert_api_error :not_found
      assert_empty listed_parties(tenant_id: owner.tenant_id)

      cookies[ApplicationController::SESSION_COOKIE] = owner_token
      assert_equal original, read_party(original.fetch("id"))
      assert_equal [original], listed_parties
    end
  end

  test "unknown party IDs are not found and PATCH never creates a new target" do
    _, csrf, = sign_in_lawyer

    with_catalog do
      id = SecureRandom.uuid
      get "/api/monitorings/parties/#{id}"
      assert_api_error :not_found
      patch "/api/monitorings/parties/#{id}", params: { name: "José da Silva", active: true },
        as: :json, headers: write_headers(csrf)
      assert_api_error :not_found
      assert_empty listed_parties
    end
  end

  %w[missing invalid revoked].each do |session_state|
    test "a #{session_state} session cannot list read create or edit parties using client claims" do
      subject = SecureRandom.uuid
      owner_token, csrf, lawyer = sign_in_lawyer(subject: subject)

      with_catalog do
        original = create_party("José da Silva", csrf: csrf)
        case session_state
        when "missing"
          cookies.delete(ApplicationController::SESSION_COOKIE)
        when "invalid"
          cookies[ApplicationController::SESSION_COOKIE] = SecureRandom.urlsafe_base64(32)
        when "revoked"
          IdentityStore.revoke(owner_token)
        end
        claims = { tenant_id: lawyer.tenant_id, subject: subject }

        get "/api/monitorings/parties", params: claims
        assert_api_error :unauthorized, code: "authentication_required"
        get "/api/monitorings/parties/#{original.fetch('id')}", params: claims
        assert_api_error :unauthorized, code: "authentication_required"
        post "/api/monitorings/parties", params: claims.merge(name: "Unauthorized target"),
          as: :json, headers: write_headers(csrf)
        assert_api_error :unauthorized, code: "authentication_required"
        patch "/api/monitorings/parties/#{original.fetch('id')}",
          params: claims.merge(name: "Intruder", active: false), as: :json, headers: write_headers(csrf)
        assert_api_error :unauthorized, code: "authentication_required"

        owner_token, = authenticated_session(subject: subject) if session_state == "revoked"
        cookies[ApplicationController::SESSION_COOKIE] = owner_token
        assert_equal original, read_party(original.fetch("id"))
        assert_equal [original], listed_parties
      end
    end
  end

  test "a session without onboarding cannot claim another tenants party or create its own tenant" do
    owner_token, owner_csrf, owner = sign_in_lawyer

    with_catalog do
      original = create_party("José da Silva", csrf: owner_csrf)
      token, csrf = authenticated_session
      cookies[ApplicationController::SESSION_COOKIE] = token
      claims = { tenant_id: owner.tenant_id }

      get "/api/monitorings/parties", params: claims
      assert_api_error :not_found, code: "onboarding_required"
      get "/api/monitorings/parties/#{original.fetch('id')}", params: claims
      assert_api_error :not_found, code: "onboarding_required"
      post "/api/monitorings/parties", params: claims.merge(name: "Unauthorized target"),
        as: :json, headers: write_headers(csrf)
      assert_api_error :not_found, code: "onboarding_required"
      patch "/api/monitorings/parties/#{original.fetch('id')}", params: claims.merge(active: false),
        as: :json, headers: write_headers(csrf)
      assert_api_error :not_found, code: "onboarding_required"
      assert_nil IdentityStore.context(token).fetch("tenant_id")

      cookies[ApplicationController::SESSION_COOKIE] = owner_token
      assert_equal original, read_party(original.fetch("id"))
      assert_equal [original], listed_parties
    end
  end

  ["missing token", "wrong token", "another sessions token", "cross origin", "missing origin"].each do |description|
    test "#{description} cannot create rename or deactivate a party" do
      _, csrf, = sign_in_lawyer
      _, other_csrf = authenticated_session
      headers = case description
      when "missing token" then { "Origin" => AppSettings.origin }
      when "wrong token" then write_headers(SecureRandom.urlsafe_base64(32))
      when "another sessions token" then write_headers(other_csrf)
      when "cross origin" then write_headers(csrf).merge("Origin" => "https://attacker.test")
      when "missing origin" then { "X-CSRF-Token" => csrf }
      end

      with_catalog do
        original = create_party("José da Silva", csrf: csrf, courts: ["TJAC"])
        post "/api/monitorings/parties", params: { name: "Unauthorized target", courts: ["TRF1"] },
          as: :json, headers: headers
        assert_api_error :forbidden, code: "invalid_csrf"
        patch "/api/monitorings/parties/#{original.fetch('id')}",
          params: { name: "Intruder", courts: ["TRF1"], active: false }, as: :json, headers: headers
        assert_api_error :forbidden, code: "invalid_csrf"

        assert_equal original, read_party(original.fetch("id"))
        assert_equal [original], listed_parties
      end
    end
  end

  private

  def deterministic_party_name(blocks:)
    "Parte " + Array.new(blocks) { |index| Digest::SHA256.hexdigest("party-name-size-#{index}") }.join
  end

  def sign_in_lawyer(subject: SecureRandom.uuid)
    token, csrf = authenticated_session(subject: subject)
    lawyer = LawyerOnboarding.call(token: token, input: profile_payload)
    cookies[ApplicationController::SESSION_COOKIE] = token
    [token, csrf, lawyer]
  end

  def write_headers(csrf)
    { "Origin" => AppSettings.origin, "X-CSRF-Token" => csrf }
  end

  def available_courts
    [
      { code: "TJAC", name: "Tribunal de Justiça do Estado do Acre" },
      { code: "TRF1", name: "Tribunal Regional Federal da 1ª Região" },
      { code: "PJeCor", name: "Corregedorias" }
    ]
  end

  def with_catalog(courts = available_courts, &block)
    CourtCatalog.stub(:fetch, courts, &block)
  end

  def with_unavailable_catalog(&block)
    failure = -> { raise CourtCatalog::Unavailable, "DJEN indisponível" }
    CourtCatalog.stub(:fetch, failure, &block)
  end

  def create_party(name, csrf:, courts: :omitted)
    input = { name: name }
    input[:courts] = courts unless courts == :omitted
    post "/api/monitorings/parties", params: input, as: :json, headers: write_headers(csrf)
    assert_response :created
    response.parsed_body
  end

  def read_party(id, **claims)
    get "/api/monitorings/parties/#{id}", params: claims
    assert_response :ok
    response.parsed_body
  end

  def listed_parties(**claims)
    get "/api/monitorings/parties", params: claims
    assert_response :ok
    body = response.parsed_body
    assert_equal ["parties"], body.keys
    assert_kind_of Array, body.fetch("parties")
    body.fetch("parties")
  end

  def assert_party(body, tenant_id:, name:, courts: nil, active: true, id: nil)
    assert_equal %w[active courts id name tenant_id], body.keys.sort
    assert_kind_of String, body.fetch("id")
    refute_empty body.fetch("id")
    assert_equal id, body.fetch("id") if id
    assert_equal tenant_id, body.fetch("tenant_id")
    assert_equal name, body.fetch("name")
    assert_equal active, body.fetch("active")
    if courts.nil?
      assert_nil body.fetch("courts")
    else
      assert_equal courts.sort, body.fetch("courts").sort
    end
  end

  def assert_api_error(status, code: nil)
    assert_response status
    assert_equal "application/json", response.media_type
    assert_equal ["error"], response.parsed_body.keys
    assert_kind_of Hash, response.parsed_body.fetch("error")
    assert_equal code, response.parsed_body.dig("error", "code") if code
  end
end
