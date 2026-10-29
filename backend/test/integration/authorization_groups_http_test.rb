require "test_helper"
require "pg"

class AuthorizationGroupsHttpTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    https!
    host! URI(AppSettings.origin).host
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    assert_equal "advocacia_migrator", @admin.exec("SELECT current_user").getvalue(0, 0)
  end

  teardown { @admin&.close }

  test "owner creates lists edits and removes groups and rules without delegating administration" do
    token, csrf, = sign_in_owner
    get "/api/authorization/catalog"
    assert_response :ok
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_includes response.parsed_body.fetch("operations"), { "operation" => "consultar_agenda", "scope" => "tenant" }
    post "/api/authorization/groups", params: { name: "Consulta TJSP" }, as: :json, headers: write_headers(csrf)
    assert_response :created
    group = response.parsed_body
    id = group.fetch("id")
    assert_equal [], group.fetch("rules")
    get "/api/authorization/groups"
    assert_response :ok
    assert_equal [group], response.parsed_body.fetch("groups")
    CourtCatalog.stub(:fetch, [{ code: "TJSP", name: "São Paulo" }]) do
      post "/api/authorization/groups/#{id}/rules", params: {
        operation: "consultar_comunicacoes", effect: "allow", court: "TJSP"
      }, as: :json, headers: write_headers(csrf)
    end
    assert_response :created
    rule_id = response.parsed_body.fetch("rules").sole.fetch("id")
    patch "/api/authorization/groups/#{id}/rules/#{rule_id}", params: { effect: "deny" }, as: :json, headers: write_headers(csrf)
    assert_response :ok
    assert_equal "deny", response.parsed_body.fetch("rules").sole.fetch("effect")
    patch "/api/authorization/groups/#{id}", params: { name: "Restrito TJSP" }, as: :json, headers: write_headers(csrf)
    assert_response :ok
    assert_equal "Restrito TJSP", response.parsed_body.fetch("name")
    delete "/api/authorization/groups/#{id}/rules/#{rule_id}", headers: write_headers(csrf)
    assert_response :ok
    assert_empty response.parsed_body.fetch("rules")
    delete "/api/authorization/groups/#{id}", headers: write_headers(csrf)
    assert_response :no_content
    get "/api/authorization/groups/#{id}"
    assert_response :not_found
    get "/api/authorization/groups"
    assert_empty response.parsed_body.fetch("groups")
    assert IdentityStore.context(token)
  end

  test "owner assigns and removes pending memberships but never memberships from another tenant" do
    _, csrf, lawyer = sign_in_owner
    group = create_group(csrf, "Equipe")
    pending = pending_membership(lawyer.tenant_id)
    put "/api/authorization/groups/#{group.fetch('id')}/memberships/#{pending}", headers: write_headers(csrf)
    assert_response :ok
    assert_equal [pending], response.parsed_body.fetch("membership_ids")
    delete "/api/authorization/groups/#{group.fetch('id')}/memberships/#{pending}", headers: write_headers(csrf)
    assert_response :ok
    assert_empty response.parsed_body.fetch("membership_ids")
    other_token, = authenticated_session
    other_lawyer = LawyerOnboarding.call(token: other_token, input: profile_payload)
    foreign_membership = pending_membership(other_lawyer.tenant_id)
    put "/api/authorization/groups/#{group.fetch('id')}/memberships/#{foreign_membership}", headers: write_headers(csrf)
    assert_response :not_found
    get "/api/authorization/groups/#{group.fetch('id')}"
    assert_empty response.parsed_body.fetch("membership_ids")
  end

  test "team member cannot enumerate or mutate owner administration despite a group grant" do
    _, csrf, lawyer = sign_in_owner
    group = create_group(csrf, "Permissões operacionais")
    member, member_csrf = authenticated_session
    identity = IdentityStore.context(member).fetch("identity_id")
    membership = @admin.exec_params(<<~SQL, [lawyer.tenant_id, identity, "#{identity}@example.test"]).getvalue(0, 0)
      INSERT INTO app_private.tenant_memberships(tenant_id, identity_id, role, invited_email, accepted_at, credential_started_at)
      VALUES ($1, $2, 'member', $3, clock_timestamp(), clock_timestamp()) RETURNING id
    SQL
    @admin.exec_params("UPDATE app_private.sessions SET selected_membership_id = $1 WHERE session_hash = $2", [membership, IdentityStore.digest(member)])
    cookies[ApplicationController::SESSION_COOKIE] = member
    get "/api/authorization/groups"
    assert_response :forbidden
    get "/api/authorization/catalog"
    assert_response :forbidden
    get "/api/authorization/groups/#{group.fetch('id')}"
    assert_response :forbidden
    post "/api/authorization/groups", params: { name: "Escalada" }, as: :json, headers: write_headers(member_csrf)
    assert_response :forbidden
    delete "/api/authorization/groups/#{group.fetch('id')}", headers: write_headers(member_csrf)
    assert_response :forbidden
  end

  test "foreign tenant identifiers cannot reveal or mutate groups or their rules" do
    first_token, first_csrf, first_lawyer = sign_in_owner
    group = create_group(first_csrf, "Primeiro tenant")
    post "/api/authorization/groups/#{group.fetch('id')}/rules", params: {
      operation: "consultar_agenda", effect: "allow"
    }, as: :json, headers: write_headers(first_csrf)
    assert_response :created
    rule = response.parsed_body.fetch("rules").sole
    _, second_csrf, = sign_in_owner
    get "/api/authorization/groups", params: { tenant_id: first_lawyer.tenant_id }
    assert_response :ok
    assert_empty response.parsed_body.fetch("groups")
    get "/api/authorization/groups/#{group.fetch('id')}"
    assert_response :not_found
    patch "/api/authorization/groups/#{group.fetch('id')}", params: { name: "Invadido" }, as: :json, headers: write_headers(second_csrf)
    assert_response :not_found
    delete "/api/authorization/groups/#{group.fetch('id')}/rules/#{rule.fetch('id')}", headers: write_headers(second_csrf)
    assert_response :not_found
    cookies[ApplicationController::SESSION_COOKIE] = first_token
    get "/api/authorization/groups/#{group.fetch('id')}"
    assert_equal "Primeiro tenant", response.parsed_body.fetch("name")
    assert_equal [rule], response.parsed_body.fetch("rules")
  end

  test "mutations require origin csrf and JSON and reject invalid input without storing it" do
    _, csrf, lawyer = sign_in_owner
    post "/api/authorization/groups", params: { name: "Sem CSRF" }, as: :json
    assert_response :forbidden
    post "/api/authorization/groups", params: { name: "Origem hostil" }, as: :json,
      headers: { "Origin" => "https://attacker.example", "X-CSRF-Token" => csrf }
    assert_response :forbidden
    post "/api/authorization/groups", params: { name: "Formulário" }, headers: write_headers(csrf)
    assert_response :unsupported_media_type
    [{ name: "" }, { name: "x" * 121 }, { name: [] }, { name: "Tenant forjado", tenant_id: lawyer.tenant_id }].each do |input|
      post "/api/authorization/groups", params: input, as: :json, headers: write_headers(csrf)
      assert_response :unprocessable_entity
    end
    group = create_group(csrf, "Validação")
    [
      { operation: "administrar_usuarios", effect: "allow" },
      { operation: "consultar_dashboard", effect: "deny", court: "TJSP" },
      { operation: "consultar_agenda", effect: true },
      { operation: "consultar_agenda", effect: "allow", membership_id: SecureRandom.uuid }
    ].each do |input|
      post "/api/authorization/groups/#{group.fetch('id')}/rules", params: input, as: :json, headers: write_headers(csrf)
      assert_response :unprocessable_entity
    end
    delete "/api/authorization/groups/#{group.fetch('id')}"
    assert_response :forbidden
    get "/api/authorization/groups/#{group.fetch('id')}"
    assert_empty response.parsed_body.fetch("rules")
    post "/api/authorization/groups", params: { name: "validação" }, as: :json, headers: write_headers(csrf)
    assert_response :conflict
  end

  test "anonymous and revoked sessions cannot administer groups" do
    get "/api/authorization/groups"
    assert_response :unauthorized
    token, csrf, = sign_in_owner
    IdentityStore.revoke(token)
    post "/api/authorization/groups", params: { name: "Sessão revogada" }, as: :json, headers: write_headers(csrf)
    assert_response :unauthorized
  end

  private

  def sign_in_owner
    token, csrf = authenticated_session
    lawyer = LawyerOnboarding.call(token: token, input: profile_payload)
    cookies[ApplicationController::SESSION_COOKIE] = token
    [token, csrf, lawyer]
  end

  def write_headers(csrf)
    { "Origin" => AppSettings.origin, "X-CSRF-Token" => csrf }
  end

  def create_group(csrf, name)
    post "/api/authorization/groups", params: { name: name }, as: :json, headers: write_headers(csrf)
    assert_response :created
    response.parsed_body
  end

  def pending_membership(tenant)
    @admin.exec_params(<<~SQL, [tenant, "#{SecureRandom.uuid}@example.test"]).getvalue(0, 0)
      INSERT INTO app_private.tenant_memberships(tenant_id, role, invited_email, credential_started_at)
      VALUES ($1, 'member', $2, clock_timestamp()) RETURNING id
    SQL
  end
end
