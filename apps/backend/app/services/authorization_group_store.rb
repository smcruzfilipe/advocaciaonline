require "json"

# All methods run inside DatabaseContext.with_session. The runtime only calls
# fixed SQL interfaces; membership and tenant authority never come from arguments.
class AuthorizationGroupStore
  class InvalidInput < StandardError; end
  class NotFound < StandardError; end
  class Forbidden < StandardError; end
  class Conflict < StandardError; end

  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
  COURT = /\A[A-Za-z][A-Za-z0-9]{1,31}\z/

  def self.catalog
    perform("catalog")
  end

  def self.list_groups
    perform("list")
  end

  def self.find_group(group_id:)
    perform("show", group_id: identifier(group_id))
  end

  def self.create_group(name:)
    raise InvalidInput unless name.is_a?(String)
    perform("create", input: { "name" => name })
  end

  def self.update_group(group_id:, name:)
    raise InvalidInput unless name.is_a?(String)
    perform("update", group_id: identifier(group_id), input: { "name" => name })
  end

  def self.destroy_group(group_id:)
    perform("destroy", group_id: identifier(group_id))
  end

  def self.create_rule(group_id:, input:)
    perform("create_rule", group_id: identifier(group_id), input: rule_input(input, creating: true))
  end

  def self.update_rule(group_id:, rule_id:, input:)
    attributes = rule_input(input, creating: false).merge("rule_id" => identifier(rule_id))
    perform("update_rule", group_id: identifier(group_id), input: attributes)
  end

  def self.destroy_rule(group_id:, rule_id:)
    perform("destroy_rule", group_id: identifier(group_id), input: { "rule_id" => identifier(rule_id) })
  end

  def self.assign_membership_group(membership_id:, group_id:)
    perform("assign_membership", group_id: identifier(group_id), input: { "membership_id" => identifier(membership_id) })
  end

  def self.remove_membership_group(membership_id:, group_id:)
    perform("remove_membership", group_id: identifier(group_id), input: { "membership_id" => identifier(membership_id) })
  end

  def self.session_group_rules
    execute("SELECT app_private.session_group_rules() AS result", [])
  end

  def self.identifier(value)
    raise InvalidInput unless value.is_a?(String) && UUID.match?(value)
    value
  end
  private_class_method :identifier

  def self.rule_input(input, creating:)
    raise InvalidInput unless input.is_a?(Hash) && input.any? && (input.keys - %w[operation effect court]).empty?
    raise InvalidInput if creating && !%w[operation effect].all? { |key| input.key?(key) }
    if input.key?("operation")
      raise InvalidInput unless AuthorizationPolicy::GROUP_OPERATIONS.include?(input["operation"])
    end
    raise InvalidInput if input.key?("effect") && !%w[allow deny].include?(input["effect"])
    court = input["court"]
    if !court.nil?
      raise InvalidInput unless court.is_a?(String) && COURT.match?(court)
      raise InvalidInput if input.key?("operation") && input["operation"] != "consultar_comunicacoes"
      raise InvalidInput unless CourtCatalog.fetch.any? { |entry| entry.fetch(:code) == court }
    end
    input
  end
  private_class_method :rule_input

  def self.perform(action, group_id: nil, input: {})
    values = [action, group_id, JSON.generate(input)]
    binds = values.each_with_index.map do |value, index|
      ActiveRecord::Relation::QueryAttribute.new("argument_#{index}", value, ActiveRecord::Type::String.new)
    end
    execute("SELECT app_private.manage_authorization_groups($1::text, $2::uuid, $3::jsonb) AS result", binds)
  end
  private_class_method :perform

  def self.execute(sql, binds)
    connection = ApplicationRecord.connection
    DatabaseContext.assert_runtime!(connection)
    # A rejected SQL mutation rolls back its savepoint before callers can inspect
    # unchanged state; an uncaught error still rolls back an enclosing invitation.
    value = ApplicationRecord.transaction(requires_new: true) do
      connection.uncached { connection.exec_query(sql, "Authorization groups", binds).first.fetch("result") }
    end
    value.is_a?(String) ? JSON.parse(value) : value
  rescue ActiveRecord::StatementInvalid => error
    state = error.cause.result&.error_field(PG::Result::PG_DIAG_SQLSTATE) if error.cause.is_a?(PG::Error)
    case state
    when "42501" then raise Forbidden
    when "P0002" then raise NotFound
    when "23505" then raise Conflict
    when "22023", "22P02", "23514", "23502" then raise InvalidInput
    else raise
    end
  end
  private_class_method :execute
end
