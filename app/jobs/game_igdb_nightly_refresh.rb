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
# "Changed" detection (1.0.0 G25 — release dates ONLY): the notification is
# about UPCOMING games, so a game is reported only when its RELEASE data
# moved — the game-level components (year/quarter/month/day/date) or any
# per-platform release row. Each game's release signature is captured before
# the sync and compared against a fresh load after it. Ratings, covers, and
# other IGDB drift still WRITE (and deliberately touch `updated_at`, busting
# the 0.9.0 caches) but never appear in the report. (The previous
# `updated_at`-advanced heuristic conflated those writes — and the cover
# re-attach touch — with real changes: "checked 60, updated 49" with zero
# release movement.)
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
      before_signature = release_signature(game)

      begin
        GameIgdbSync.perform_now(game.id, prefetched: prefetched&.dig(game.igdb_id))

        fresh = Game.find(game.id)
        changed << fresh.title if release_signature(fresh) != before_signature
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

  # Everything release-related about a game, comparable before/after a sync:
  # the game-level date components plus every per-platform release row. Reads
  # the association fresh from the DB (the callers pass either an un-loaded
  # record or a newly-found one), so a stale cache can never mask a change.
  def release_signature(game)
    [
      game.release_year, game.release_quarter, game.release_month,
      game.release_day, game.release_date,
      game.platform_releases.order(:platform_token).map do |rel|
        [ rel.platform_token, rel.release_year, rel.release_quarter, rel.release_month, rel.release_day ]
      end
    ]
  end

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
