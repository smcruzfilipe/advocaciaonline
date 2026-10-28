require "digest"

# The runtime cannot read the identity/session tables. Only fixed, narrowly scoped
# SQL functions are callable; a bearer hash, not a caller-supplied tenant, resolves membership.
class IdentityStore
  class AuthenticationRejected < StandardError; end
  FUNCTIONS = %w[start_login consume_login authenticate_google session_context claim_tenant revoke_session].freeze

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.call(function, *values)
    raise ArgumentError, "Unknown identity operation" unless FUNCTIONS.include?(function)
    connection = ApplicationRecord.connection
    DatabaseContext.assert_runtime!(connection)
    binds = values.each_with_index.map do |value, index|
      ActiveRecord::Relation::QueryAttribute.new("argument_#{index}", value, ActiveRecord::Type::String.new)
    end
    placeholders = values.each_index.map { |index| "$#{index + 1}::text" }.join(", ")
    connection.exec_query("SELECT * FROM app_private.#{function}(#{placeholders})", "Identity operation", binds).first
  end

  def self.authenticate(subject:, email:, token:, csrf:)
    call("authenticate_google", subject, email, digest(token), csrf)
  rescue ActiveRecord::StatementInvalid => error
    if error.cause.is_a?(PG::Error) && error.cause.result&.error_field(PG::Result::PG_DIAG_SQLSTATE) == "28000"
      raise AuthenticationRejected
    end
    raise
  end

  def self.context(token)
    return if token.blank?
    call("session_context", digest(token))
  end

  def self.revoke(token)
    call("revoke_session", digest(token)) if token.present?
  end
end
