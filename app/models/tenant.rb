class Tenant < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :channels, dependent: :destroy

  validates :name, presence: true, length: { in: 3..30 }
end
