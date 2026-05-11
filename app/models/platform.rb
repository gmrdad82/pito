# Phase 14 §1 / Phase 27 §1a — IGDB-sourced platform reference table.
#
# Originally a Phase 14 thin row keyed by `igdb_id` and populated lazily
# during game sync. Phase 27 §1a hardens it into the canonical platform
# reference:
#
#   - `slug` is NOT NULL + unique with FriendlyId (slugged + history) so
#     URLs and filter chips can route by stable names (`/games?owned_on=ps5`).
#   - `igdb_id` is nullable so manual seeds (PS5, Switch 2, Steam, GOG,
#     Epic) can pre-exist before any IGDB sync.
#   - The legacy `:games_owning` association (driven by the now-dropped
#     `games.platform_owned_id` FK) is gone — ownership routes through
#     the new `:game_platform_ownerships` join table.
#   - `:games_available` (formerly `:games` via the multi-valued
#     "ships on" join `game_platforms`) is renamed so the new canonical
#     `:games` association — through `:game_platform_ownerships` —
#     can carry the project's preferred plural meaning ("games we own
#     on this platform").
#
# Default sort is alphabetical by `name` everywhere; callers that want
# a different order chain `.reorder(...)` explicitly.
class Platform < ApplicationRecord
  extend FriendlyId
  friendly_id :slug_candidates, use: %i[slugged history finders]

  # "Ships on" join (multi-valued IGDB-driven set). Populated by
  # `Igdb::SyncGame#sync_platforms`. Renamed from `:games` so the
  # ownership-through-join can claim the plural `:games` name.
  has_many :game_platforms, dependent: :destroy
  has_many :games_available, through: :game_platforms, source: :game

  # Ownership join (Phase 27 §1a). `:restrict_with_error` enforces the
  # spec rule: platforms with active ownerships cannot be destroyed.
  # The IGDB platform sync upserts but never deletes; restrict is the
  # belt-and-suspenders barrier in case a caller bypasses the sync.
  has_many :game_platform_ownerships, dependent: :restrict_with_error
  has_many :games, through: :game_platform_ownerships

  validates :name, presence: true, length: { maximum: 255 }
  validates :slug, presence: true, uniqueness: true
  validates :igdb_id, uniqueness: { allow_nil: true },
                      numericality: { only_integer: true, greater_than: 0, allow_nil: true }

  default_scope { order(:name) }

  # FriendlyId — name-derived slug + history-on-rename. Mirrors the
  # Collection / Project / Bundle / MilestoneRule pattern via
  # `Pito::SlugBuilder`.
  def slug_limit
    80
  end

  def slug_candidates
    [
      normalized_name_slug,
      [ normalized_name_slug, id ].compact.reject(&:blank?).join("-"),
      "platform-#{id}"
    ]
  end

  def should_generate_new_friendly_id?
    will_save_change_to_name? || super
  end

  def normalize_friendly_id(value)
    Pito::SlugBuilder.build(value.to_s, limit: slug_limit).presence ||
      "platform-#{id || SecureRandom.hex(4)}"
  end

  private

  def normalized_name_slug
    Pito::SlugBuilder.build(name.to_s, limit: slug_limit)
  end
end
