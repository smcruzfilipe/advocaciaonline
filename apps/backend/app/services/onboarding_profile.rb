class OnboardingProfile
  include ActiveModel::Validations

  FIELDS = %w[full_name office_name primary_oab secondary_oabs].freeze
  attr_reader :full_name, :office_name, :registrations
  validate :validate_input

  def initialize(input)
    @input = input
    @registrations = []
  end

  private

  def validate_input
    @registrations = []
    unless @input.is_a?(Hash) && (@input.keys - FIELDS).empty?
      errors.add(:base, "Envie somente os campos do perfil profissional.")
      return
    end
    @full_name = normalized_name(@input["full_name"])
    errors.add(:full_name, "Informe seu nome completo.") if @full_name.blank?
    office = @input["office_name"]
    if !office.nil? && !office.is_a?(String)
      errors.add(:office_name, "Informe o nome do escritório como texto.")
    end
    @office_name = normalized_name(office).presence
    add_oab(@input["primary_oab"], :primary_oab, primary: true)
    secondary = @input.fetch("secondary_oabs", [])
    if secondary.is_a?(Array)
      secondary.each { |oab| add_oab(oab, :secondary_oabs, primary: false) }
    else
      errors.add(:secondary_oabs, "Envie uma lista de inscrições secundárias.")
    end
    pairs = @registrations.map { |oab| oab.values_at(:number, :uf) }
    errors.add(:secondary_oabs, "Não repita o mesmo número de OAB e UF.") if pairs.uniq.size != pairs.size
  end

  def normalized_name(value)
    value.is_a?(String) ? value.gsub(/[[:space:]]+/, " ").strip : nil
  end

  def add_oab(value, field, primary:)
    unless value.is_a?(Hash) && value.keys.sort == %w[number uf] &&
        value["number"].is_a?(String) && value["uf"].is_a?(String)
      errors.add(field, "Informe número textual e UF da OAB.")
      return
    end
    number = value.fetch("number").gsub(/\A[[:space:]]+|[[:space:]]+\z/, "")
    uf = value.fetch("uf").strip.upcase
    errors.add(field, "Informe o número da OAB.") if number.empty?
    errors.add(field, "Informe uma UF brasileira válida.") unless OabRegistration::UFS.include?(uf)
    @registrations << { number: number, uf: uf, primary: primary }
  end
end
