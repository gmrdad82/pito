# Phase 4 §3.2 — Collection groups Games. Tenant-scoped.
class Collection < ApplicationRecord
  belongs_to :tenant

  has_many :games, dependent: :nullify

  validates :name, presence: true, length: { maximum: 255 }

  attribute :name, :string, default: "Untitled collection"
end
