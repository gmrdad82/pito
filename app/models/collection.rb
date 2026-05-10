# Phase 4 §3.2 — Collection groups Games. Phase 8 — install-wide
# (no tenant scope).
class Collection < ApplicationRecord
  has_many :games, dependent: :nullify

  validates :name, presence: true, length: { maximum: 255 }

  attribute :name, :string, default: "Untitled collection"
end
