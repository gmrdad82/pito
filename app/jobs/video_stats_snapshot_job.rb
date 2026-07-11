# frozen_string_literal: true

# Intraday stats-only snapshot for existing videos.
#
# Runs at 09:00 and 17:00 UTC (see config/recurring.yml); the 01:00 full sync
# via NightlySyncJob / NightlyVideoSyncJob covers the third daily slot.
#
# Lightweight by design — NO playlist fetch, NO video upsert, NO re-embed:
#   1. Iterate every connected (non-reauth) channel.
#   2. Take `channel.videos.pluck(:youtube_video_id)`.
#   3. Batch in slices of ≤50 (YouTube videos.list hard cap = 1 quota unit/call).
#   4. Call `client.videos_list(ids: batch, parts: %i[statistics])`.
#   5. Write view / like / comment counts into `Pito::Stats`.
#
# A client error on one channel is rescued + logged so a single API failure
# never aborts the run for other channels.
class VideoStatsSnapshotJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 50

  def perform
    connected_channels.find_each do |channel|
      sync_channel(channel)
    end

    enqueue_rollups
  end

  private

  # After every intraday pass, re-materialize the DERIVED entity stats
  # (channel likes; game views+likes) so the list surfaces read fresh
  # `Pito::Stats` rows instead of live-summing videos at render.
  def enqueue_rollups
    connected_channels.pluck(:id).each { |id| ::ChannelStatsRefreshJob.perform_later(id) }
    ::VideoGameLink.distinct.pluck(:game_id).each { |id| ::GameStatsRefreshJob.perform_later(id) }
  end

  def connected_channels
    ::Channel
      .joins(:youtube_connection)
      .where(youtube_connections: { needs_reauth: false })
  end

  def sync_channel(channel)
    video_ids = channel.videos.pluck(:youtube_video_id).compact
    return if video_ids.empty?

    connection = channel.youtube_connection
    client = ::Channel::Youtube::Client.new(connection)

    video_ids.each_slice(BATCH_SIZE) do |batch|
      response = client.videos_list(ids: batch, parts: %i[statistics])
      Array(response[:items]).each { |item| write_stats(item) }
    end
  rescue StandardError => e
    Rails.logger.error(
      "VideoStatsSnapshotJob: failed for channel=#{channel.id}: " \
      "#{e.class}: #{e.message}"
    )
  end

  def write_stats(item)
    video = ::Video.find_by(youtube_video_id: item[:id])
    return unless video

    stats = item[:statistics] || {}

    ::Pito::Stats.set(video, :views,    stats[:view_count]&.to_i    || 0)
    ::Pito::Stats.set(video, :likes,    stats[:like_count]&.to_i    || 0)
    ::Pito::Stats.set(video, :comments, stats[:comment_count]&.to_i || 0)
  rescue StandardError => e
    Rails.logger.error(
      "VideoStatsSnapshotJob: failed to write stats for video=#{item[:id]}: " \
      "#{e.class}: #{e.message}"
    )
  end
end
