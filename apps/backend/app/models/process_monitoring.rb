class ProcessMonitoring < ApplicationRecord
  CANONICAL_NUMBER = /\A[0-9]{20}\z/.freeze
  MASKED_NUMBER = /\A[0-9]{7}-[0-9]{2}\.[0-9]{4}\.[0-9]\.[0-9]{2}\.[0-9]{4}\z/.freeze

  belongs_to :tenant
  validates :number, format: { with: CANONICAL_NUMBER }
  validates :active, inclusion: { in: [true, false] }

  def self.canonical_number(value)
    return unless value.is_a?(String)
    return value if CANONICAL_NUMBER.match?(value)
    value.delete("-.") if MASKED_NUMBER.match?(value)
  end
end
