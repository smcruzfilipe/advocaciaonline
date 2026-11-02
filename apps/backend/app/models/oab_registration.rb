class OabRegistration < ApplicationRecord
  UFS = %w[AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO].freeze

  belongs_to :lawyer
  belongs_to :tenant
  validates :number, presence: true
  validates :uf, inclusion: { in: UFS }
end
