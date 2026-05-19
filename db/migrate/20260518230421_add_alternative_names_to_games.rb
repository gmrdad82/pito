# 2026-05-19 — IGDB-sourced alternate names (`alternative_names`).
#
# IGDB exposes an `alternative_names` resource on every game (array
# of `{id, name, comment}` objects). Examples that motivate the
# column for Pito:
#
#   - Street Fighter 6 → "SF6", "SFVI", "ストリートファイター6"
#   - Final Fantasy VII Rebirth → "FF7 Rebirth", "FFVII Rebirth"
#   - The Legend of Zelda: Tears of the Kingdom → "TotK", "Zelda TotK"
#
# We persist these into a Postgres `text[]` column on `games` so the
# omnisearch Postgres fallback can `ILIKE` against alt-name tokens
# without an extra join, and so `Meilisearch::GameIndexer` can push
# the same list into the search document as another searchable
# attribute.
#
# Defaults to an empty array + NOT NULL so the column shape is stable
# regardless of whether IGDB ever returns alt names for a given row.
# The GIN index supports both array-membership (`= ANY(...)`) and the
# `unnest(...) ILIKE` pattern the omnisearch fallback uses.
class AddAlternativeNamesToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :alternative_names, :text, array: true, default: [], null: false
    add_index :games, :alternative_names, using: :gin
  end
end
