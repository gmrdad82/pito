# Phase 27 v2 spec 05 — drops `users.preferred_games_display_mode`.
#
# The `/games` page collapses to a single layout (shelves-by-letter) per
# spec 05. The display-mode switcher, the three per-mode partials, the
# `Users::GamesPreferencesController`, and the persisted user preference
# all retire together. The column held an integer enum
# (`grid: 0`, `list: 1`, `shelves_by_letter: 2`); dropping it is a one-way
# change for production data — any saved bookmarks to
# `/games?display=<mode>` 200 just fine (the controller ignores the
# param now) but the persisted preference is gone.
#
# `down` re-adds the column with the same shape so a rollback restores
# the historical default (`0` / `grid`); restoring user-specific values
# would require a separate backfill from a snapshot, which is out of
# scope for the rollback path.
class DropPreferredGamesDisplayModeFromUsers < ActiveRecord::Migration[8.1]
  def up
    remove_column :users, :preferred_games_display_mode
  end

  def down
    add_column :users, :preferred_games_display_mode, :integer,
               default: 0, null: false
  end
end
