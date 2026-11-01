require "test_helper"
require "timeout"

class FirstAccessInvitationsTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @admin = PG.connect(ENV.fetch("MIGRATION_DATABASE_URL"))
    @runtime = PG.connect(ENV.fetch("DATABASE_URL"))
    assert_equal "advocacia_migrator", @admin.exec("SELECT current_user").getvalue(0, 0)
    assert_equal "advocacia_runtime", @runtime.exec("SELECT current_user").getvalue(0, 0)
    @prefix = "first-access-#{SecureRandom.hex(12)}"
    @email = "#{@prefix}@example.test"
    @ids = []
    @tenants = []
    @admin_id = identity("#{@prefix}-admin@example.test")
    @admin.exec_params("INSERT INTO app_private.platform_administrator(identity_id) VALUES ($1)", [@admin_id])
    @admin_session = session(@admin_id)
  end

  teardown do
    if @admin
      @admin.exec_params("DELETE FROM app_private.first_access_invitations WHERE email LIKE $1", ["#{@prefix}%"])
      @tenants.each do |tenant, session_hash|
        @admin.transaction do |db|
          db.exec_params("SELECT set_config('app.session_hash', $1, true)", [session_hash])
          db.exec_params("DELETE FROM public.tenants WHERE id=$1", [tenant])
          db.exec_params("UPDATE app_private.sessions SET selected_membership_id=NULL WHERE selected_membership_id IN (SELECT id FROM app_private.tenant_memberships WHERE tenant_id=$1)", [tenant])
          db.exec_params("DELETE FROM app_private.tenant_memberships WHERE tenant_id=$1", [tenant])
        end
      end
      @ids.each do |id|
        %w[first_access_grants platform_recovery_challenges platform_recovery_codes platform_administrator password_resets password_challenges sessions password_credentials].each do |table|
          @admin.exec_params("DELETE FROM app_private.#{table} WHERE identity_id = $1", [id])
        end
        @admin.exec_params("DELETE FROM app_private.identities WHERE id = $1", [id])
      end
    end
    @runtime&.close
    @admin&.close
  end

  test "administrative functions require current platform authority and protect tables and secrets" do
    ordinary = identity("#{@prefix}-member@example.test")
    member_session = session(ordinary)
    %w[first_access_invitations first_access_preparations first_access_grants].each do |table|
      %w[SELECT INSERT UPDATE DELETE].each do |privilege|
        assert_equal "f", @runtime.exec_params("SELECT has_table_privilege(current_user, $1, $2)", ["app_private.#{table}", privilege]).getvalue(0, 0)
      end
    end
    %w[first_access_admin_list first_access_admin_issue first_access_admin_link first_access_admin_reissue first_access_inspect first_access_prepare first_access_prepared first_access_consume].each do |function|
      assert_equal "0", @admin.exec_params(<<~SQL, [function]).getvalue(0, 0)
        SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        CROSS JOIN LATERAL aclexplode(p.proacl) a
        WHERE n.nspname='app_private' AND p.proname=$1 AND a.grantee=0 AND a.privilege_type='EXECUTE'
      SQL
    end
    assert_raises(PG::InvalidAuthorizationSpecification) { call("first_access_admin_list", digest) }
    assert_raises(PG::InsufficientPrivilege) { call("first_access_admin_list", member_session) }
    invitation = issue
    id = invitation.fetch("id")
    %w[first_access_admin_link first_access_admin_reissue].each do |name|
      extra = name.end_with?("reissue") ? [digest, "cipher"] : []
      assert_raises(PG::InsufficientPrivilege) { call(name, member_session, id, *extra) }
      assert_raises(PG::InvalidAuthorizationSpecification) { call(name, digest, id, *extra) }
    end
    assert_raises(PG::InsufficientPrivilege) { call("first_access_admin_issue", member_session, "#{@prefix}-other@example.test", digest, "cipher") }
    assert_equal %w[created_at email expires_at id], invitation.keys.sort
    assert_equal %w[created_at email expires_at id], call("first_access_admin_list", @admin_session).first.keys.sort
  end

  test "issue normalizes and rejects duplicates, invalid email, disabled and owner identities" do
    result = issue(email: "  #{@email.upcase}  ")
    assert_equal @email, result.fetch("email")
    assert_raises(PG::ObjectNotInPrerequisiteState) { issue }
    assert_raises(PG::InvalidParameterValue) { issue(email: "invalid") }
    disabled = identity("#{@prefix}-disabled@example.test")
    @admin.exec_params("UPDATE app_private.identities SET disabled_at=clock_timestamp() WHERE id=$1", [disabled])
    assert_raises(PG::ObjectNotInPrerequisiteState) { issue(email: "#{@prefix}-disabled@example.test") }
  end

  test "copy and reissue keep the same link until atomic replacement removes the preparation" do
    token = digest
    original = issue(token: token)
    challenge = digest
    call("first_access_prepare", token, challenge, "password-hash", "encrypted-secret")
    link = call("first_access_admin_link", @admin_session, original.fetch("id")).first
    assert_equal token, link.fetch("token_hash")
    assert_equal "cipher", link.fetch("token_ciphertext")
    assert_equal original.fetch("expires_at"), link.fetch("expires_at")
    replacement_token = digest
    replacement = call("first_access_admin_reissue", @admin_session, original.fetch("id"), replacement_token, "new-cipher").first
    refute_equal original.fetch("id"), replacement.fetch("id")
    assert_empty call("first_access_inspect", token)
    assert_empty call("first_access_prepared", token, challenge)
    assert_empty call("first_access_admin_link", @admin_session, original.fetch("id"))
    assert_equal replacement_token, call("first_access_admin_link", @admin_session, replacement.fetch("id")).first.fetch("token_hash")
  end

  test "reissue rollback restores the old link and preparation" do
    token, challenge, replacement = digest, digest, digest
    invitation = issue(token: token)
    call("first_access_prepare", token, challenge, "hash", "secret")
    @runtime.exec("BEGIN")
    call("first_access_admin_reissue", @admin_session, invitation.fetch("id"), replacement, "new-cipher")
    @runtime.exec("ROLLBACK")
    assert_equal token, call("first_access_admin_link", @admin_session, invitation.fetch("id")).first.fetch("token_hash")
    assert_equal "hash", call("first_access_prepared", token, challenge).first.fetch("password_hash")
    assert_empty call("first_access_inspect", replacement)
  ensure
    @runtime.exec("ROLLBACK") if @runtime && @runtime.transaction_status != PG::PQTRANS_IDLE
  end

  test "reissue rejects an identity disabled after issuance and preserves the invitation and preparation" do
    token, challenge, replacement = digest, digest, digest
    invitation = issue(token: token)
    call("first_access_prepare", token, challenge, "hash", "secret")
    ident = identity(@email)
    @admin.exec_params("UPDATE app_private.identities SET disabled_at=clock_timestamp() WHERE id=$1", [ident])
    assert_raises(PG::ObjectNotInPrerequisiteState) do
      call("first_access_admin_reissue", @admin_session, invitation.fetch("id"), replacement, "new-cipher")
    end
    assert_equal token, call("first_access_admin_link", @admin_session, invitation.fetch("id")).first.fetch("token_hash")
    assert_equal "1", @admin.exec_params("SELECT count(*) FROM app_private.first_access_preparations WHERE invitation_id=$1", [invitation.fetch("id")]).getvalue(0, 0)
    assert_empty call("first_access_inspect", replacement)
  end

  test "owner is denied issuance and a tenant claimed after issuance blocks consumption" do
    ident = identity(@email)
    signed_in = session(ident)
    token = digest
    invitation = issue(token: token)
    make_owner(ident, signed_in)
    assert_raises(PG::ObjectNotInPrerequisiteState) do
      call("first_access_admin_reissue", @admin_session, invitation.fetch("id"), digest, "new-cipher")
    end
    assert_equal token, call("first_access_admin_link", @admin_session, invitation.fetch("id")).first.fetch("token_hash")
    assert_raises(PG::ObjectNotInPrerequisiteState) { call("first_access_consume", token, signed_in) }
    assert_raises(PG::InsufficientPrivilege) { call("first_access_admin_list", signed_in) }
    @admin.exec_params("DELETE FROM app_private.first_access_invitations WHERE email=$1", [@email])
    assert_raises(PG::ObjectNotInPrerequisiteState) { issue }
  end

  test "simultaneous issuance creates exactly one invitation" do
    ready, start = Queue.new, Queue.new
    workers = 2.times.map do
      Thread.new do
        PG.connect(ENV.fetch("DATABASE_URL")) do |db|
          db.exec("SET statement_timeout='10s'")
          ready << true
          start.pop
          begin
            db.exec_params("SELECT * FROM app_private.first_access_admin_issue($1,$2,$3,$4)", [@admin_session, @email, digest, "cipher"])
            :created
          rescue PG::ObjectNotInPrerequisiteState
            :conflict
          end
        end
      end
    end
    Timeout.timeout(15) do
      2.times { ready.pop }
      2.times { start << true }
      assert_equal [:conflict, :created], workers.map(&:value).sort
    end
  ensure
    2.times { start << true } if start
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end

  test "preparation is replaceable and creates no identity, grant, session or reset" do
    token = digest
    issue(token: token)
    first, second = digest, digest
    call("first_access_prepare", token, first, "hash-one", "secret-one")
    call("first_access_prepare", token, second, "hash-two", "secret-two")
    assert_empty call("first_access_prepared", token, first)
    row = call("first_access_prepared", token, second).first
    assert_equal @email, row.fetch("email")
    assert_equal "hash-two", row.fetch("password_hash")
    assert_equal "secret-two", row.fetch("totp_secret")
    assert_equal "0", @admin.exec_params("SELECT count(*) FROM app_private.identities WHERE verified_email=$1", [@email]).getvalue(0, 0)
    @admin.exec_params("UPDATE app_private.first_access_preparations SET expires_at=clock_timestamp() WHERE challenge_hash=$1", [second])
    assert_empty call("first_access_prepared", token, second)
  end

  test "deadline is strict and expired rows are purged; restore deletes only invitations" do
    token = digest
    invitation = issue(token: token)
    challenge = digest
    call("first_access_prepare", token, challenge, "hash", "secret")
    @admin.exec_params("UPDATE app_private.first_access_invitations SET expires_at=clock_timestamp() WHERE id=$1", [invitation.fetch("id")])
    assert_empty call("first_access_admin_link", @admin_session, invitation.fetch("id"))
    assert_equal "0", @admin.exec_params("SELECT count(*) FROM app_private.first_access_invitations WHERE id=$1", [invitation.fetch("id")]).getvalue(0, 0)
    assert_empty call("first_access_inspect", token)
    assert_empty call("first_access_prepared", token, challenge)
    assert_equal "0", @admin.exec_params("SELECT count(*) FROM app_private.first_access_preparations WHERE invitation_id=$1", [invitation.fetch("id")]).getvalue(0, 0)
    ident = identity("#{@prefix}-granted@example.test")
    @admin.exec_params("INSERT INTO app_private.first_access_grants(identity_id) VALUES ($1)", [ident])
    issue
    @admin.exec_params("DELETE FROM app_private.first_access_invitations WHERE email=$1", [@email])
    assert_equal "1", @admin.exec_params("SELECT count(*) FROM app_private.first_access_grants WHERE identity_id=$1", [ident]).getvalue(0, 0)
    assert_raises(PG::InsufficientPrivilege) { @runtime.exec("DELETE FROM app_private.first_access_invitations") }
  end

  test "expired preparation reissue and consume commit removal without granting access" do
    ident = identity(@email)
    signed_in = session(ident)
    %w[first_access_prepare first_access_admin_reissue first_access_consume].each do |operation|
      token = digest
      invitation = issue(token: token)
      @admin.exec_params("UPDATE app_private.first_access_invitations SET expires_at=clock_timestamp() WHERE id=$1", [invitation.fetch("id")])
      arguments = case operation
      when "first_access_prepare" then [token, digest, "hash", "secret"]
      when "first_access_admin_reissue" then [@admin_session, invitation.fetch("id"), digest, "cipher"]
      when "first_access_consume" then [token, signed_in]
      end
      assert_empty call(operation, *arguments)
      assert_equal "0", @admin.exec_params("SELECT count(*) FROM app_private.first_access_invitations WHERE id=$1", [invitation.fetch("id")]).getvalue(0, 0)
      assert_equal "0", @admin.exec_params("SELECT count(*) FROM app_private.first_access_grants WHERE identity_id=$1", [ident]).getvalue(0, 0)
    end
  end

  test "consume enforces identity and confirmed MFA, supports rollback and prevents replay" do
    ident = identity(@email)
    token = digest
    issue(token: token)
    other = identity("#{@prefix}-other@example.test")
    assert_equal "t", call("first_access_inspect", token).first.fetch("requires_login")
    assert_raises(PG::NoDataFound) { call("first_access_consume", token, session(other)) }
    assert_raises(PG::InvalidAuthorizationSpecification) { call("first_access_consume", token, digest) }
    own = session(ident)
    @admin.exec_params("UPDATE app_private.password_credentials SET totp_confirmed=false WHERE identity_id=$1", [ident])
    assert_raises(PG::NoDataFound) { call("first_access_consume", token, own) }
    @admin.exec_params("UPDATE app_private.password_credentials SET totp_confirmed=true WHERE identity_id=$1", [ident])
    @runtime.exec("BEGIN")
    assert_equal ident, call("first_access_consume", token, own).first.fetch("identity_id")
    @runtime.exec("ROLLBACK")
    assert_equal "0", @admin.exec_params("SELECT count(*) FROM app_private.first_access_grants WHERE identity_id=$1", [ident]).getvalue(0, 0)
    assert_equal ident, call("first_access_consume", token, own).first.fetch("identity_id")
    assert_empty call("first_access_consume", token, own)
  ensure
    @runtime.exec("ROLLBACK") if @runtime && @runtime.transaction_status != PG::PQTRANS_IDLE
  end

  test "concurrent consumes have one winner" do
    ident = identity(@email)
    token = digest
    issue(token: token)
    signed_in = session(ident)
    ready, start = Queue.new, Queue.new
    workers = 2.times.map do
      Thread.new do
        PG.connect(ENV.fetch("DATABASE_URL")) do |db|
          db.exec("SET statement_timeout='10s'")
          ready << true
          start.pop
          result = db.exec_params("SELECT * FROM app_private.first_access_consume($1,$2)", [token, signed_in])
          result.ntuples == 1 ? :success : :unavailable
        end
      end
    end
    Timeout.timeout(15) do
      2.times { ready.pop }
      2.times { start << true }
      assert_equal [:success, :unavailable], workers.map(&:value).sort
      assert_equal "1", @admin.exec_params("SELECT count(*) FROM app_private.first_access_grants WHERE identity_id=$1", [ident]).getvalue(0, 0)
      assert_equal "0", @admin.exec_params("SELECT count(*) FROM app_private.first_access_invitations WHERE token_hash=$1", [token]).getvalue(0, 0)
    end
  ensure
    2.times { start << true } if start
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end

  private

  def digest
    SecureRandom.hex(32)
  end

  def identity(email)
    id = @admin.exec_params("INSERT INTO app_private.identities(verified_email) VALUES ($1) RETURNING id", [email]).getvalue(0, 0)
    @ids << id
    @admin.exec_params("INSERT INTO app_private.password_credentials(identity_id,password_hash,totp_secret,totp_confirmed) VALUES ($1,'hash','secret',true)", [id])
    id
  end

  def make_owner(ident, session_hash)
    tenant = SecureRandom.uuid
    @admin.transaction do |db|
      membership = db.exec_params(<<~SQL, [tenant, ident]).getvalue(0, 0)
        INSERT INTO app_private.tenant_memberships(tenant_id,identity_id,role,accepted_at)
        VALUES ($1,$2,'owner',clock_timestamp()) RETURNING id
      SQL
      db.exec_params("UPDATE app_private.sessions SET selected_membership_id=$1 WHERE session_hash=$2", [membership, session_hash])
      db.exec_params("SELECT set_config('app.session_hash',$1,true)", [session_hash])
      db.exec_params("INSERT INTO public.tenants(id,created_at,updated_at) VALUES ($1,clock_timestamp(),clock_timestamp())", [tenant])
    end
    @tenants << [tenant, session_hash]
  end

  def session(id)
    hash = digest
    @admin.exec_params("INSERT INTO app_private.sessions(session_hash,identity_id,csrf_token,expires_at) VALUES ($1,$2,'csrf',clock_timestamp()+interval '1 hour')", [hash, id])
    hash
  end

  def call(name, *args)
    placeholders = args.each_index.map { |i| "$#{i + 1}" }.join(",")
    @runtime.exec_params("SELECT * FROM app_private.#{name}(#{placeholders})", args).to_a
  end

  def issue(email: @email, token: digest)
    call("first_access_admin_issue", @admin_session, email, token, "cipher").first
  end
end
