class AuthorizationPolicy
  GROUP_OPERATIONS = %w[consultar_monitoramentos consultar_comunicacoes consultar_dashboard
    cadastrar_monitoramento editar_monitoramento desativar_monitoramento consultar_agenda
    cadastrar_compromisso remarcar_compromisso cancelar_compromisso].freeze
  OWNER_ONLY_OPERATIONS = %w[convidar_usuario consultar_usuarios alterar_validade_credencial
    revogar_credencial renovar_credencial consultar_grupos administrar_grupos consultar_escrevente
    configurar_agenda].freeze
  OPERATIONS = (GROUP_OPERATIONS + OWNER_ONLY_OPERATIONS).freeze
  DEFAULT_READ_OPERATIONS = %w[consultar_monitoramentos consultar_comunicacoes consultar_dashboard].freeze
  RULE_FIELDS = %w[operation effect court].freeze
  EFFECTS = %w[allow deny].freeze

  # Callers supply a currently valid identity and groups from the same trusted tenant.
  def self.allowed?(owner:, groups:, operation:, court: nil)
    return false unless owner == true || owner == false
    return false unless OPERATIONS.include?(operation)
    return false if operation == "consultar_comunicacoes" && !valid_court?(court)
    return false unless valid_groups?(groups)
    return true if owner
    return false if OWNER_ONLY_OPERATIONS.include?(operation)
    return DEFAULT_READ_OPERATIONS.include?(operation) if groups.empty?

    allowed = false
    groups.each do |rules|
      rules.each do |rule|
        next unless rule["operation"] == operation && (rule["court"].nil? || rule["court"] == court)
        return false if rule["effect"] == "deny"
        allowed = true
      end
    end
    allowed
  end

  def self.valid_groups?(groups)
    groups.is_a?(Array) && groups.all? do |rules|
      rules.is_a?(Array) && rules.all? { |rule| valid_rule?(rule) }
    end
  end

  def self.valid_rule?(rule)
    return false unless rule.is_a?(Hash) && rule.size == RULE_FIELDS.size &&
      RULE_FIELDS.all? { |field| rule.key?(field) }
    return false unless OPERATIONS.include?(rule["operation"]) && EFFECTS.include?(rule["effect"])

    # A nil court covers every tribunal only for communications; other operations are tenant-scoped.
    rule["court"].nil? || (rule["operation"] == "consultar_comunicacoes" && valid_court?(rule["court"]))
  end

  def self.valid_court?(court)
    court.is_a?(String) && !court.strip.empty?
  end

  private_class_method :valid_groups?, :valid_rule?, :valid_court?
end
