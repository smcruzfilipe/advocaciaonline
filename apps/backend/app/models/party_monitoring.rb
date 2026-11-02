class PartyMonitoring < ApplicationRecord
  MAX_CANONICAL_NAME_BYTES = 2_000

  belongs_to :tenant
  attr_readonly :id, :tenant_id

  before_validation :normalize_name, if: :will_save_change_to_name?
  validates :name, presence: true
  validates :active, inclusion: { in: [true, false] }
  validate :canonical_name_size

  private

  def canonical_name_size
    return if canonical_name.nil? || canonical_name.bytesize <= MAX_CANONICAL_NAME_BYTES

    errors.add(:name, "O nome normalizado deve ter no máximo 2.000 bytes.")
  end

  def normalize_name
    return unless name.is_a?(String)

    self.name = name.gsub(/[[:space:]]+/, " ").strip
    # NFD removes only canonical diacritics; punctuation is not transliterated.
    # https://docs.ruby-lang.org/en/4.0/String.html#method-i-unicode_normalize
    # https://docs.ruby-lang.org/en/4.0/language/case_mapping_rdoc.html
    self.canonical_name = name.unicode_normalize(:nfd).gsub(/\p{M}/, "").downcase(:fold)
  end
end
