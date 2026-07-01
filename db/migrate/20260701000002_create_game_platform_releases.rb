# frozen_string_literal: true

# Item 24: per-platform release dates. IGDB gives a release date PER platform
# (PlayStation / Switch / Xbox / Steam); pito now stores one row per platform
# group per game, each with the same component shape as Game
# (year/quarter/month/day + a derived lower-bound date). The single
# games.release_* columns remain as a derived "earliest across platforms" for
# scopes/sorting; these rows drive the show-game display + release countdowns.
#
# Distinct rows are kept even when several platforms share the same date — the
# same-date collapse happens only at render (owner: "keep distinct values per
# platform, clobber them when rendering").
class CreateGamePlatformReleases < ActiveRecord::Migration[8.1]
  def change
    create_table :game_platform_releases do |t|
      t.references :game, null: false, foreign_key: true
      t.string  :platform_token, null: false
      t.integer :release_year
      t.integer :release_quarter
      t.integer :release_month
      t.integer :release_day
      t.date    :release_date

      t.timestamps
    end

    # One row per (game, platform group). Enforces integrity at the DB level;
    # the model layer validates the token value + component consistency (UX).
    add_index :game_platform_releases, %i[game_id platform_token],
              unique: true, name: "index_game_platform_releases_on_game_and_platform"

    # Countdown + earliest-date queries scan by release_date.
    add_index :game_platform_releases, :release_date
  end
end
