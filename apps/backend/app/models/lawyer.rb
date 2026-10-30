class Lawyer < ApplicationRecord
  belongs_to :tenant
  has_many :oab_registrations, inverse_of: :lawyer
  validates :full_name, presence: true
end
