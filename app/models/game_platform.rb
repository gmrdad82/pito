# Phase 14 §1 — Game ↔ Platform join.
#
# `platforms_available` on Game routes through this join. The
# `platform_owned_id` on Game is a separate FK (single-valued
# "platform the user owns the copy on"); this join carries the
# multi-valued "platforms the game ships on" set.
#
# 2026-05-18 FN2 — `source` column (`"igdb"` default, `"user"` for
# rows the user manually added via the ownership-matrix `[owned]` /
# `[played]` toggles on `/games/:id` when IGDB had not listed the
# platform). Conflict rule: first writer wins; the IGDB sync MUST
# NOT downgrade a `"user"` row to `"igdb"`. The controller upsert in
# `Games::OwnershipTogglesController#ensure_user_added_platform_availability!`
# is no-op when a row already exists (regardless of `source`), and
# the IGDB sync's `first_or_create!` in `Igdb::SyncGame#sync_platforms`
# preserves the existing row when present.
class GamePlatform < ApplicationRecord
  SOURCES = %w[igdb user].freeze

  belongs_to :game
  belongs_to :platform

  validates :game_id, uniqueness: { scope: :platform_id }
  validates :source, inclusion: { in: SOURCES }

  scope :from_igdb, -> { where(source: "igdb") }
  scope :from_user, -> { where(source: "user") }
end
