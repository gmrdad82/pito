# Phase 27 — 01d. Display mode switcher + three modes on `/games`.
#
# Persist the authenticated user's `/games` display-mode choice
# (`grid`, `list`, `shelves_by_letter`). Default `grid` (0) — the
# existing surface stays the default for every user. URL param
# `?display=` may override per-request but never overwrites the
# persisted preference unless the user clicks a switcher button
# (which routes through `Users::GamesPreferencesController#update`).
#
# No index — the column is read off `Current.user` per request, never
# the target of a lookup or join.
class AddPreferredGamesDisplayModeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :preferred_games_display_mode, :integer,
               null: false, default: 0
  end
end
