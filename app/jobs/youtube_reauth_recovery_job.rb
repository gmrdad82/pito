# frozen_string_literal: true

# Auto-retry after a successful REAUTH.
#
# While a connection is flagged `needs_reauth`, almost nothing FAILS — the
# scheduled passes (NightlySyncJob / VideoStatsSnapshotJob /
# AchievementsRefreshJob) and the chat fills all SKIP flagged channels, so the
# work simply doesn't happen and data goes stale until the next scheduled run
# (up to ~24h). Only mid-run token deaths land in SolidQueue's failed
# executions. This job — enqueued by the OAuth callback the moment
# `needs_reauth` flips back off — closes both gaps immediately:
#
#   1. requeues ALL SolidQueue failed executions (owner: all, not just
#      auth-classed — `/jobs requeue all` semantics, via Pito::Jobs::RequeueFailed);
#   2. fans out the skipped per-channel nightly pair (ChannelSync + VideoSyncJob)
#      for the connection's channels;
#   3. runs the global stats + achievements passes (they filter `needs_reauth`
#      themselves — now unflagged, they cover the recovered channels).
#
# NO notification (owner: the reauth notice already exists). Old chat cards
# with n/a cells are out of scope — re-running the command is cheap with the
# 0.9.0 caches.
class YoutubeReauthRecoveryJob < ApplicationJob
  queue_as :default

  def perform(connection_id)
    connection = YoutubeConnection.find_by(id: connection_id)
    return unless connection
    return if connection.needs_reauth # re-flagged since enqueue — nothing to recover

    requeued = Pito::Jobs::RequeueFailed.call(target: "all")

    connection.channels.find_each do |channel|
      ::ChannelSync.perform_later(channel.id)
      ::VideoSyncJob.perform_later(channel.id)
    end

    ::VideoStatsSnapshotJob.perform_later
    ::AchievementsRefreshJob.perform_later

    Rails.logger.info(
      "[YoutubeReauthRecoveryJob] connection=#{connection.id} requeued=#{requeued} " \
      "channels=#{connection.channels.count}"
    )
  end
end
