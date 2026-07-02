# Nightly IGDB refresh job.
#
# Iterates `Game.synced.awaiting_release` and runs `GameIgdbSync.perform_now`
# for each game SEQUENTIALLY so we have a single "done" point for a summary
# Notification. A begin/rescue per game means one failure does not abort the
# rest of the batch.
#
# Scoping (Item 51 — every awaited game re-syncs EVERY night, no stale gate):
#   - `synced`           — `igdb_synced_at` present. Never-synced games are
#     skipped; their only legitimate null window is between `add_from_igdb`
#     and the immediate per-game sync, which the nightly should not race.
#   - `awaiting_release` — settled ONLY by a DAY-precision date in the past
#     ("sync until a fixed clear date"): TBA, future dates, and bare
#     year/quarter/month precisions all keep refreshing — on the game or on
#     ANY platform row (a title out on PS keeps refreshing while its Switch
#     date is open). FULLY RELEASED games' IGDB data is effectively final, so
#     re-fetching them just burns quota; awaited titles still shift (release
#     date slips, precision firms up, platform/genre edits), so those refresh
#     nightly and every sync rewrites the release fields when IGDB changed.
#
# "Changed" detection: `GameIgdbSync` calls `game.update!(igdb_synced_at:
# Time.current, ...)` inside a transaction. We capture `game.updated_at`
# BEFORE the sync call and compare with a reloaded `updated_at` after — any
# DB write (data change OR merely the `igdb_synced_at` stamp) advances
# `updated_at`, so this is a reliable "something was written" signal. A game
# that was never written (e.g. `ValidationError` swallowed by the job) does
# not advance `updated_at`.
#
# Notification is created ONLY IF there is something noteworthy:
# changed games or failures. A completely quiet run (nothing changed, no
# failures) is silent — no Notification is created.
#
# Release-countdown reminders are NOT this job's concern — they are emitted
# DAILY (with concrete dates) by ReleaseCountdownJob. This job's old
# date-less "releasing within 30 days" summary was removed in favour of that.
class GameIgdbNightlyRefresh < ApplicationJob
  queue_as :default

  # 0.9.0 Phase 3 — BULK prefetch: every awaited game's IGDB row + time-to-beat
  # row is fetched in ⌈N/500⌉ bulk queries (2 requests per 500 games instead of
  # 2 per game), then each game syncs from its prefetched payload. If a bulk
  # slice errors (rate limit, 5xx), those games fall back to the per-game
  # fetch inside SyncGame — the optimization can never break the nightly.
  BULK_SLICE = 500

  def perform
    checked        = 0
    changed        = []
    failures       = []

    upcoming_games = Game.synced.awaiting_release.to_a
    prefetched     = prefetch(upcoming_games.map(&:igdb_id).compact)

    upcoming_games.each do |game|
      checked += 1
      before_updated_at = game.updated_at

      begin
        GameIgdbSync.perform_now(game.id, prefetched: prefetched&.dig(game.igdb_id))

        after_updated_at = Game.where(id: game.id).pick(:updated_at)
        if after_updated_at && after_updated_at > before_updated_at
          changed << game.title
        end
      rescue StandardError => e
        Rails.logger.error("[GameIgdbNightlyRefresh] game id=#{game.id} (#{game.title}) failed: #{e.class}: #{e.message}")
        failures << { title: game.title, error: "#{e.class}: #{e.message}" }
      end
    end

    return if changed.none? && failures.none?

    Pito::Notifications::Source::NightlyGamesSync.report!(
      checked:       checked,
      changed:       changed,
      failures:      failures,
      releasing_30d: []
    )
  end

  private

  # igdb_id → { game_json:, ttb_json: } for every id a bulk slice answered.
  # A failed slice logs and contributes nothing — its games sync per-game.
  def prefetch(igdb_ids)
    client = Game::Igdb::Client.new
    igdb_ids.each_slice(BULK_SLICE).each_with_object({}) do |slice, map|
      games = client.fetch_games_by_ids(slice).index_by { |row| row["id"] }
      ttbs  = client.fetch_time_to_beats_by_game_ids(slice).group_by { |row| row["game_id"] }

      slice.each do |igdb_id|
        map[igdb_id] = { game_json: games[igdb_id], ttb_json: ttbs[igdb_id] || [] }
      end
    rescue StandardError => e
      Rails.logger.warn("[GameIgdbNightlyRefresh] bulk prefetch failed for #{slice.size} ids (#{e.class}: #{e.message}) — falling back to per-game fetches")
    end
  end
end
