# frozen_string_literal: true

# Stage 1 master: nightly sync orchestrator, scheduled at 1:00 UTC (full run,
# with IGDB) and again at 13:00 UTC (igdb-skipped) per P20.
#
# Fans out atomic per-entity jobs in dependency order:
#
#   1. Channel metadata sync — `ChannelSync.perform_later(channel.id)` for
#      every channel with an active (non-reauth) YoutubeConnection.
#      `ChannelSync` is already turn-less (fetches + persists, no broadcast).
#
#   2. Video sync — `VideoSyncJob.perform_later(channel.id)` for the same
#      connected channels: imports new/private uploads AND reconciles attribute
#      updates + hard-deletes of removed uploads (`VideoLibrary#sync`). The job
#      emits its own per-channel `VideoSync` Notification, so this master does
#      NOT itself report video-sync progress.
#
#   3. Game IGDB refresh — `GameIgdbNightlyRefresh.perform_later` (the
#      existing nightly job that fans out `GameIgdbSync` per stale game).
#      Skipped when `igdb: false` is passed (the 13:00 midday sync passes
#      this — channel + video sync run 2×/day, IGDB upcoming-game refresh
#      stays nightly-only).
#
# This master is intentionally thin — it only enqueues by ID. All heavy
# work happens inside the atomic leaf jobs. Analytics is a separate future
# nightly job and is NOT included here.
#
# Scheduled via config/recurring.yml at "0 1 * * *" (full) and "0 13 * * *"
# (igdb-skipped) (UTC).
class NightlySyncJob < ApplicationJob
  queue_as :default

  def perform(igdb: true)
    connected_channels.find_each do |channel|
      # 1. Channel metadata (turn-less, no broadcast)
      ::ChannelSync.perform_later(channel.id)

      # 2. Video sync — import new/private uploads + reconcile updates/deletions
      ::VideoSyncJob.perform_later(channel.id)
    end

    # 3. Game IGDB stale-refresh fan-out (nightly only, unless skipped)
    ::GameIgdbNightlyRefresh.perform_later if igdb
  end

  private

  def connected_channels
    ::Channel
      .joins(:youtube_connection)
      .where(youtube_connections: { needs_reauth: false })
  end
end
