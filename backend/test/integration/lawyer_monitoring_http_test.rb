require "test_helper"

class LawyerMonitoringHttpTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    https!
    host! URI(AppSettings.origin).host
    assert_equal "advocacia_runtime", ApplicationRecord.connection.select_value("SELECT current_user")
  end

  test "returns the existing lawyer identity and all current OABs without copying the profile" do
    token, = authenticated_session
    input = profile_payload.merge("secondary_oabs" => [
      { "number" => "00a-B", "uf" => "rj" },
      { "number" => "001234-A", "uf" => "mg" }
    ])
    lawyer = LawyerOnboarding.call(token: token, input: input)
    original_ids = profile_record_ids(token)
    cookies[ApplicationController::SESSION_COOKIE] = token

    get "/api/monitorings/lawyer"

    assert_response :ok
    assert_equal "application/json", response.media_type
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_lawyer_payload(lawyer, full_name: "Ana de Ávila", oabs: [
      { "number" => "001234-A", "uf" => "SP" },
      { "number" => "00a-B", "uf" => "RJ" },
      { "number" => "001234-A", "uf" => "MG" }
    ])
    assert_equal original_ids, profile_record_ids(token)

    update_profile_fixture(token, lawyer.id)

    get "/api/monitorings/lawyer"

    assert_response :ok
    assert_lawyer_payload(lawyer, full_name: "Ana de Ávila Lima", oabs: [
      { "number" => "001234-A", "uf" => "SP" },
      { "number" => "009999-B", "uf" => "RJ" },
      { "number" => "001234-A", "uf" => "MG" }
    ])
    assert_equal original_ids, profile_record_ids(token)
    assert_equal 0, Lawyer.count
    assert_equal 0, OabRegistration.count
  end

  test "each tenant receives only its own lawyer and forged tenant queries cannot switch identity" do
    first_token, = authenticated_session
    second_token, = authenticated_session
    first = LawyerOnboarding.call(token: first_token, input: profile_payload)
    second = LawyerOnboarding.call(token: second_token, input: profile_payload.merge(
      "full_name" => "Bruno Lima",
      "primary_oab" => { "number" => "000777-B", "uf" => "MG" },
      "secondary_oabs" => []
    ))
    assert_not_equal first.id, second.id
    assert_not_equal first.tenant_id, second.tenant_id
    DatabaseContext.with_session(first_token) { assert_nil Lawyer.find_by(id: second.id) }
    DatabaseContext.with_session(second_token) { assert_nil Lawyer.find_by(id: first.id) }

    cookies[ApplicationController::SESSION_COOKIE] = first_token
    get "/api/monitorings/lawyer", params: { tenant_id: second.tenant_id }
    assert_response :ok
    assert_lawyer_payload(first, full_name: "Ana de Ávila", oabs: [
      { "number" => "001234-A", "uf" => "SP" },
      { "number" => "00a-B", "uf" => "RJ" }
    ])
    first_body = response.parsed_body

    cookies[ApplicationController::SESSION_COOKIE] = second_token
    get "/api/monitorings/lawyer", params: { tenant_id: first.tenant_id }
    assert_response :ok
    assert_lawyer_payload(second, full_name: "Bruno Lima", oabs: [
      { "number" => "000777-B", "uf" => "MG" }
    ])

    cookies[ApplicationController::SESSION_COOKIE] = first_token
    get "/api/monitorings/lawyer"
    assert_response :ok
    assert_equal first_body, response.parsed_body
    assert_equal 0, Lawyer.count
    assert_equal 0, OabRegistration.count
  end

  test "an absent session cannot read a lawyer using a tenant query" do
    token, = authenticated_session
    lawyer = LawyerOnboarding.call(token: token, input: profile_payload)

    get "/api/monitorings/lawyer", params: { tenant_id: lawyer.tenant_id }

    assert_response :unauthorized
    assert_equal "authentication_required", response.parsed_body.dig("error", "code")
    refute response.parsed_body.key?("id")
    refute response.parsed_body.key?("oabs")
  end

  test "a revoked session immediately loses access to its existing lawyer" do
    token, = authenticated_session
    lawyer = LawyerOnboarding.call(token: token, input: profile_payload)
    cookies[ApplicationController::SESSION_COOKIE] = token
    IdentityStore.revoke(token)

    get "/api/monitorings/lawyer", params: { tenant_id: lawyer.tenant_id }

    assert_response :unauthorized
    assert_equal "authentication_required", response.parsed_body.dig("error", "code")
    assert_nil IdentityStore.context(token)
    refute response.parsed_body.key?("id")
    refute response.parsed_body.key?("oabs")
  end

  test "an authenticated session without onboarding has no lawyer even when another tenant is requested" do
    onboarded_token, = authenticated_session
    other_lawyer = LawyerOnboarding.call(token: onboarded_token, input: profile_payload)
    token, = authenticated_session
    cookies[ApplicationController::SESSION_COOKIE] = token
    assert_nil IdentityStore.context(token).fetch("tenant_id")

    get "/api/monitorings/lawyer", params: { tenant_id: other_lawyer.tenant_id }

    assert_response :not_found
    assert_equal "onboarding_required", response.parsed_body.dig("error", "code")
    refute response.parsed_body.key?("id")
    refute response.parsed_body.key?("oabs")
    assert_nil IdentityStore.context(token).fetch("tenant_id")
    DatabaseContext.with_session(token) do
      assert_equal 0, Tenant.count
      assert_equal 0, Lawyer.count
      assert_equal 0, OabRegistration.count
    end
  end

  private

  def assert_lawyer_payload(lawyer, full_name:, oabs:)
    body = response.parsed_body
    assert_equal %w[full_name id oabs tenant_id], body.keys.sort
    assert_equal lawyer.id, body.fetch("id")
    assert_equal lawyer.tenant_id, body.fetch("tenant_id")
    assert_equal full_name, body.fetch("full_name")
    actual_oabs = body.fetch("oabs")
    actual_oabs.each { |oab| assert_equal %w[number uf], oab.keys.sort }
    assert_equal oabs.sort_by { |oab| [oab.fetch("uf"), oab.fetch("number")] },
      actual_oabs.sort_by { |oab| [oab.fetch("uf"), oab.fetch("number")] }
    assert_equal actual_oabs.uniq, actual_oabs
  end

  def update_profile_fixture(token, lawyer_id)
    # Fixture control only; application requests keep DATABASE_URL / advocacia_runtime.
    connection = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    assert_equal "advocacia_migrator", connection.exec("SELECT current_user").getvalue(0, 0)
    connection.transaction do
      connection.exec_params("SELECT set_config('app.session_hash', $1, true)", [IdentityStore.digest(token)])
      assert_equal 1, connection.exec_params(
        "UPDATE lawyers SET full_name = $1 WHERE id = $2", ["Ana de Ávila Lima", lawyer_id]
      ).cmd_tuples
      assert_equal 1, connection.exec_params(
        "UPDATE oab_registrations SET number = $1 WHERE lawyer_id = $2 AND uf = $3",
        ["009999-B", lawyer_id, "RJ"]
      ).cmd_tuples
    end
  ensure
    connection&.close
  end

  def profile_record_ids(token)
    DatabaseContext.with_session(token) do
      [Tenant.order(:id).pluck(:id), Lawyer.order(:id).pluck(:id), OabRegistration.order(:id).pluck(:id)]
    end
  end
end
