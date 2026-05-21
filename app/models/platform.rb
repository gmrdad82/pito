# Phase 14 §1 / Phase 27 §1a — IGDB-sourced platform reference table.
#
# Originally a Phase 14 thin row keyed by `igdb_id` and populated lazily
# during game sync. Phase 27 §1a hardens it into the canonical platform
# reference:
#
#   - `slug` is NOT NULL + unique with FriendlyId (slugged + history) so
#     URLs and filter chips can route by stable names (`/games?owned_on=ps`).
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

  # Phase 27 follow-up (2026-05-11) — canonical platform display labels.
  #
  # The canonical platforms the project tracks ownership against
  # (per user direction, ordered by the project's display preference).
  # Maps the seed `slug` to the canonical short label rendered on the
  # game show page and anywhere else the project renders platform sets.
  #
  # 2026-05-19 lock: chip / filter / display tokens align with the
  # canonical Platform slugs (`ps5`, `switch2`, `steam`, `xbox`) —
  # NOT the prior family-collapsed `ps` / `switch` abstractions.
  #
  # Phase 27 v2 spec 06 (2026-05-17 PC store collapse) — `gog` and
  # `epic` were collapsed into `steam`. The three PC stores share the
  # single `steam` slug + Steam logo; the chip surface, the logo
  # surface, and the data model all converge on `steam` for PC. `xbox`
  # is kept as a known canonical short label for any future console
  # ownership work, but no chip / logo currently surfaces it.
  CANONICAL_SHORT_NAMES = {
    "ps5"     => "PS5",
    "switch2" => "Switch2",
    "steam"   => "Steam",
    "xbox"    => "Xbox"
  }.freeze

  CANONICAL_SLUGS = CANONICAL_SHORT_NAMES.keys.freeze

  # Phase 27 v2 spec 06 — IGDB canonical platform NAMES → display label.
  #
  # The filter-row chips, the detail-page platform list, the platform-
  # logo helper's `alt` attribute, and any other surface that renders a
  # platform name routes through this map. IGDB ships `"Nintendo Switch
  # 2"` (with a space) — the project shortens it to `"Switch"` (no
  # generation digit) since the chip / filter surface treats the
  # Switch family as one unit.
  #
  # Lookup is name-keyed because the surfaces that render display labels
  # consume `Platform#name` (the IGDB-imported string) rather than the
  # slug. The slug map `CANONICAL_SHORT_NAMES` above stays as the slug-
  # keyed canonical lookup used by the seed rows and `canonical?`.
  #
  # The map carries entries for the three short labels rendered on the
  # filter row and the detail page: `Switch2`, `PS5`, `Steam`. GoG +
  # Epic were collapsed into Steam in the 2026-05-17 contract change;
  # any IGDB platform name not in this map falls through to itself per
  # `display_label`. 2026-05-19 lock: short labels are slug-direct
  # (`PS5`, `Switch2`) — NOT family-collapsed (`PS`, `Switch`).
  PLATFORM_LABELS = {
    "Nintendo Switch 2" => "Switch2",
    "PlayStation 5"     => "PS5",
    "Steam"             => "Steam"
  }.freeze

  # Phase 27 v2 spec 06 — single source of truth for the IGDB name →
  # display label translation. Returns the short label when the IGDB
  # name is in `PLATFORM_LABELS`, otherwise returns the input verbatim
  # (callers may receive an IGDB platform name we don't override).
  def self.display_label(name)
    PLATFORM_LABELS[name.to_s] || name.to_s
  end

  # IGDB platform IDs → canonical slug. Used by the display helper to
  # canonicalise an IGDB-imported `Platform` row (which carries a
  # verbose `name` like "PlayStation 5", "Xbox Series X|S",
  # "Nintendo Switch 2") into one of the six canonical short labels.
  #
  # Xbox One (49) and Xbox Series X|S (169) both collapse to "Xbox" —
  # the project does not distinguish console generations at the
  # ownership level.
  IGDB_ID_TO_CANONICAL_SLUG = {
    167 => "ps5",
    48  => "ps4",
    508 => "switch2",
    130 => "switch1",
    49  => "xbox",
    169 => "xbox"
  }.freeze

  scope :canonical, -> { unscoped.where(slug: CANONICAL_SLUGS).order(:slug) }

  # "Ships on" join (multi-valued IGDB-driven set). Populated by
  # `Game::Igdb::SyncGame#sync_platforms`. Renamed from `:games` so the
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
  # Project / Bundle / MilestoneRule pattern via `Pito::SlugBuilder`.
  # Canonical short label for this platform. Returns the project's
  # locked short name (`PS`, `Switch`, `Steam`, `Xbox`) when the
  # row matches one of the canonical slugs OR
  # when its `igdb_id` aliases to a canonical slug. Returns `nil`
  # otherwise — callers decide whether to fall back to `name` or
  # drop the platform from display.
  def canonical_short_name
    canonical_slug = CANONICAL_SHORT_NAMES.key?(slug) ? slug : IGDB_ID_TO_CANONICAL_SLUG[igdb_id]
    CANONICAL_SHORT_NAMES[canonical_slug]
  end

  def canonical?
    canonical_short_name.present?
  end

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
