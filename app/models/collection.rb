# Phase 4 §3.2 — Collection groups Games. Phase 8 — install-wide
# (no tenant scope).
class Collection < ApplicationRecord
  # Phase 20 — friendly URLs. Name-derived slug + history-on-rename.
  extend FriendlyId
  friendly_id :slug_candidates, use: %i[slugged history finders]

  has_many :games, dependent: :nullify

  validates :name, presence: true, length: { maximum: 255 }

  attribute :name, :string, default: "Untitled collection"

  # Phase 20 — friendly URLs.
  def slug_limit
    80
  end

  def slug_candidates
    [
      normalized_name_slug,
      [ normalized_name_slug, id ].compact.reject(&:blank?).join("-"),
      "collection-#{id}"
    ]
  end

  def should_generate_new_friendly_id?
    will_save_change_to_name? || super
  end

  def normalize_friendly_id(value)
    Pito::SlugBuilder.build(value.to_s, limit: slug_limit).presence ||
      "collection-#{id || SecureRandom.hex(4)}"
  end

  private

  def normalized_name_slug
    Pito::SlugBuilder.build(name.to_s, limit: slug_limit)
  end
end
