class Tenant < ApplicationRecord
  has_one :lawyer, inverse_of: :tenant
end
