# Phase 14 §1 polish (2026-05-10) — `games.resyncing` mutex flag.
#
# Backs the async resync flow on the game show page. The boolean
# is flipped to `true` when `GameIgdbSync` starts work and back to
# `false` in an `ensure` block, so the show page can swap the
# `[resync]` link for an animated indicator and refuse duplicate
# enqueues while one is in flight.
#
# `null: false, default: false` so existing rows backfill atomically;
# no follow-up backfill migration is needed.
class AddResyncingToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :resyncing, :boolean, null: false, default: false
  end
end
