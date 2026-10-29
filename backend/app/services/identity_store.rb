require "digest"

# The runtime cannot read the identity/session tables. Only fixed, narrowly scoped
# SQL functions are callable; a bearer hash, not a caller-supplied tenant, resolves membership.
class IdentityStore
  class AuthenticationRejected < StandardError; end
  class AccessDenied < StandardError; end
  class InvalidInput < StandardError; end
  class NotFound < StandardError; end
  class Conflict < StandardError; end
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
  FUNCTIONS = %w[start_login consume_login authenticate_google session_identity session_context
    claim_tenant revoke_session require_owner available_memberships select_membership
    list_team_credentials create_team_credential change_credential_validity renew_team_credential
    revoke_team_credential reissue_team_invitation accept_team_invitation].freeze

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.call(function, *values)
    call_all(function, *values).first
  end

  def self.call_all(function, *values)
    raise ArgumentError, "Unknown identity operation" unless FUNCTIONS.include?(function)
    connection = ApplicationRecord.connection
    DatabaseContext.assert_runtime!(connection)
    binds = values.each_with_index.map do |value, index|
      ActiveRecord::Relation::QueryAttribute.new("argument_#{index}", value, ActiveRecord::Type::String.new)
    end
    placeholders = values.each_index.map { |index| "$#{index + 1}::text" }.join(", ")
    connection.exec_query("SELECT * FROM app_private.#{function}(#{placeholders})", "Identity operation", binds).to_a
  rescue ActiveRecord::StatementInvalid => error
    state = error.cause.is_a?(PG::Error) && error.cause.result&.error_field(PG::Result::PG_DIAG_SQLSTATE)
    case state
    when "28000" then raise AuthenticationRejected, "Authentication required", cause: nil
    when "42501" then raise AccessDenied, "Access denied", cause: nil
    when "P0002" then raise NotFound, "Resource unavailable", cause: nil
    when "55000", "23505" then raise Conflict, "Credential state conflict", cause: nil
    when "22023", "22P02", "22003", "22008" then raise InvalidInput, "Invalid credential input", cause: nil
    else raise
    end
  end

  def self.authenticate(subject:, email:, token:, csrf:)
    call("authenticate_google", subject, email, digest(token), csrf)
  end

  def self.context(token)
    return if token.blank?
    call("session_context", digest(token))
  end

  def self.revoke(token)
    call("revoke_session", digest(token)) if token.present?
  end

  def self.session_identity(token)
    call("session_identity", digest(token)) if token.present?
  end

  def self.memberships(token)
    DatabaseContext.with_session(token) { call_all("available_memberships") }
  end

  def self.select_membership(token:, membership_id:)
    validate_id!(membership_id)
    DatabaseContext.with_session(token) do
      call("select_membership", membership_id)
      context(token) || raise(AccessDenied, "Membership unavailable")
    end
  end

  def self.team_credentials(token)
    owner_operation(token) { call_all("list_team_credentials") }
  end

  def self.create_credential(token:, email:, validity_days:, group_ids: [], smtp: nil)
    validate_validity!(validity_days)
    email = normalize_invited_email!(email)
    unless group_ids.is_a?(Array) && group_ids.all? { |id| id.is_a?(String) && UUID.match?(id) }
      raise InvalidInput, "Invalid groups"
    end
    require_top_level_transaction!
    invitation_token = SecureRandom.urlsafe_base64(32)
    credential = owner_operation(token) do
      credential = call("create_team_credential", email, validity_days, digest(invitation_token))
      group_ids.uniq.each do |group_id|
        AuthorizationGroupStore.assign_membership_group(membership_id: credential.fetch("id"), group_id: group_id)
      end
      credential
    end
    deliver_invitation(credential, invitation_token, smtp)
    credential
  end

  def self.change_validity(token:, membership_id:, validity_days:)
    validate_id!(membership_id)
    validate_validity!(validity_days)
    owner_operation(token) { call("change_credential_validity", membership_id, validity_days) }
  end

  def self.renew_credential(token:, membership_id:)
    validate_id!(membership_id)
    owner_operation(token) { call("renew_team_credential", membership_id) }
  end

  def self.revoke_credential(token:, membership_id:)
    validate_id!(membership_id)
    owner_operation(token) { call("revoke_team_credential", membership_id) }
  end

  def self.reissue_invitation(token:, membership_id:, smtp: nil)
    validate_id!(membership_id)
    require_top_level_transaction!
    invitation_token = SecureRandom.urlsafe_base64(32)
    credential = owner_operation(token) { call("reissue_team_invitation", membership_id, digest(invitation_token)) }
    deliver_invitation(credential, invitation_token, smtp)
    credential
  end

  def self.accept_invitation(token:, invitation_token:)
    unless invitation_token.is_a?(String) && invitation_token.match?(/\A[A-Za-z0-9_-]{43}\z/)
      raise InvalidInput, "Invalid invitation"
    end
    DatabaseContext.with_session(token) { call("accept_team_invitation", digest(invitation_token)) }
  end

  def self.owner_operation(token)
    DatabaseContext.with_session(token) do
      call("require_owner")
      result = yield
      call("require_owner")
      result
    end
  end
  private_class_method :owner_operation

  def self.require_top_level_transaction!
    if ApplicationRecord.connection.transaction_open?
      raise ActiveRecord::ActiveRecordError, "Invitation issuance must commit before delivery; enclosing transactions are not supported"
    end
  end
  private_class_method :require_top_level_transaction!

  def self.deliver_invitation(credential, invitation_token, smtp)
    TeamInvitationMailer.deliver!(email: credential.fetch("invited_email"), token: invitation_token,
      origin: AppSettings.origin, smtp: smtp || AppSettings.smtp)
  end
  private_class_method :deliver_invitation

  def self.normalize_invited_email!(email)
    TeamInvitationMailer.normalize_recipient!(email)
  rescue ArgumentError
    raise InvalidInput, "Invalid invitation recipient", cause: nil
  end
  private_class_method :normalize_invited_email!

  def self.validate_id!(value)
    raise InvalidInput, "Invalid membership" unless value.is_a?(String) && UUID.match?(value)
  end
  private_class_method :validate_id!

  def self.validate_validity!(value)
    return if value.nil? || (value.is_a?(Integer) && value.positive? && value <= 2_147_483_647)
    raise InvalidInput, "Validity must be null or a positive integer number of days"
  end
  private_class_method :validate_validity!
end
