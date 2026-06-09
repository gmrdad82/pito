# Phase 14 §1 — nightly IGDB refresh job.
#
# Iterates `Game.synced.stale.upcoming` and runs `GameIgdbSync.perform_now`
# for each game SEQUENTIALLY so we have a single "done" point for a summary
# Notification. A begin/rescue per game means one failure does not abort the
# rest of the batch.
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
#
# "Changed" detection: `GameIgdbSync` calls `game.update!(igdb_synced_at:
# Time.current, ...)` inside a transaction. We capture `game.updated_at`
# BEFORE the sync call and compare with a reloaded `updated_at` after — any
# DB write (data change OR merely the `igdb_synced_at` stamp) advances
# `updated_at`, so this is a reliable "something was written" signal. A game
# that was never written (e.g. `ValidationError` swallowed by the job) does
# not advance `updated_at`.
#
# After the loop ONE Notification is always created summarising the run
# via `Pito::Notifications::Source::NightlyGamesSync.report!`.
class GameIgdbNightlyRefresh < ApplicationJob
  queue_as :default

  def perform
    checked  = 0
    updated  = 0
    changed_titles = []
    failures = []

    Game.synced.stale.upcoming.find_each do |game|
      checked += 1
      before_updated_at = game.updated_at

      begin
        GameIgdbSync.perform_now(game.id)

        after_updated_at = Game.where(id: game.id).pick(:updated_at)
        if after_updated_at && after_updated_at > before_updated_at
          updated += 1
          changed_titles << game.title
        end
      rescue StandardError => e
        Rails.logger.error("[GameIgdbNightlyRefresh] game id=#{game.id} (#{game.title}) failed: #{e.class}: #{e.message}")
        failures << { title: game.title, error: "#{e.class}: #{e.message}" }
      end
    end

    Pito::Notifications::Source::NightlyGamesSync.report!(
      checked: checked,
      updated: updated,
      changed_titles: changed_titles,
      failures: failures
    )
  end
end
