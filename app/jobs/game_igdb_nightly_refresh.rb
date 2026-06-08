# Phase 14 §1 — nightly IGDB refresh job.
#
# Iterates `Game.synced.stale.upcoming` and enqueues a `GameIgdbSync` per
# game, spaced ~300ms apart so the IGDB rate limit (4 req/s) is comfortably
# respected even before the in-process limiter engages.
#
# Scoping:
#   - `synced`   — `igdb_synced_at` present. Never-synced games are skipped;
#     their only legitimate null window is between `add_from_igdb` and the
#     immediate per-game sync, which the nightly should not race.
#   - `stale`    — `igdb_synced_at < 7.days.ago`.
#   - `upcoming` — release in the future / unreleased (videos plan Phase 8).
#     RELEASED games' IGDB data is effectively final, so re-fetching them
#     weekly just burns quota; only unreleased titles still shift (release
#     date slips, platform/genre edits), so we refresh those alone.
class GameIgdbNightlyRefresh < ApplicationJob
  queue_as :default

  def perform
    Game.synced.stale.upcoming.find_each do |game|
      GameIgdbSync.perform_later(game.id)
      sleep 0.3
    end
  end
end
