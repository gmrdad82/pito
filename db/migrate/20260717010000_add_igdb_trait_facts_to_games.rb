# frozen_string_literal: true

# IGDB fact columns feeding the derived-trait flip (traits-design.md L6):
# `game_modes` / `hypes` / `age_ratings` were verified absent from
# Game::Igdb::Client::GAME_FIELDS and the schema on 2026-07-17 — this
# migration + the client/mapper changes alongside it add the sync, so
# `multiplayer` / `single_player` / `hyped` / `family_friendly` can move
# from `source: classified` to `source: derived` in config/pito/traits.yml.
#
# Storage mirrors the table's existing conventions:
#   - `game_modes` — text[] default [] NOT NULL, same shape as `themes` /
#     `platforms` (a flat list of IGDB display-name strings); GIN index
#     mirrors the `themes` / `player_perspectives` precedent (cheap to carry
#     from day one, same rationale as the `traits` GIN index added in
#     20260717000001_add_traits_to_games.rb).
#   - `hypes` — plain nullable integer, unprefixed (mirrors
#     `aggregated_rating_count` / `total_rating_count`: no local column
#     collision, so the IGDB field name is used verbatim). IGDB's
#     pre-release follow count.
#   - `age_ratings` — jsonb default {} NOT NULL, `{"ESRB"=>"E10+",
#     "PEGI"=>"7", ...}` (organization name => rating text). A hash (not a
#     single scalar) because IGDB rates one game across MULTIPLE
#     organizations simultaneously; jsonb mirrors the `traits` column's
#     shape/GIN-index precedent rather than inventing a new pattern.
#
# Additive, default-safe, single deploy — no backfill phase here.
# Existing games keep {}/[]/nil until their next IGDB re-sync (see the
# "Backfill" note in traits-design.md's deploy notes for the one-time sweep
# that populates these columns for already-synced games).
class AddIgdbTraitFactsToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :game_modes, :text, default: [], null: false, array: true
    add_column :games, :hypes, :integer
    add_column :games, :age_ratings, :jsonb, default: {}, null: false

    add_index :games, :game_modes, using: :gin
    add_index :games, :age_ratings, using: :gin
  end
end
