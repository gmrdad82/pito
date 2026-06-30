# Replaces the Path A2 placeholder no-op with the real
# fetch + persist path. One call to `Channel::Youtube::Client#fetch_channel`,
# one transaction to cache the normalized hash + stamp `last_synced_at`.
#
# Error posture (uniform with VideoRemoteStatusSync):
#   - RecordInvalid (API returned a value that fails a Channel
#     validator — e.g. a 101-char title) → re-raise; transaction rolls
#     back so the channel keeps its prior state and `last_synced_at`
#     stays unchanged.
#   - Channel deleted between enqueue and perform / channel without a
#     `youtube_connection_id` → no-op.
#
# After a successful field update, enqueues ChannelAvatarJob and
# ChannelBannerJob so every sync also refreshes the locally-cached
# avatar and banner images (digest-gated inside each Ingest service —
# unchanged bytes are a no-op). This mirrors ChannelInfoJob's behavior
# on OAuth connect and ensures banners are refreshed on `sync channels`.
class ChannelSync < ApplicationJob
  queue_as :default

  # Columns on the `channels` table that `fetch_channel` can populate.
  # Sliced from the normalized hash before `update!` so non-column keys
  # returned by `normalize_channel_item` (avatar_url, banner_url, etc.)
  # never raise ActiveRecord::UnknownAttributeError.
  SYNC_COLUMNS = %i[title handle description video_count].freeze

  def perform(channel_id)
    channel = Channel.find_by(id: channel_id)
    return unless channel
    return if channel.youtube_connection_id.nil?

    client = Channel::Youtube::Client.new(channel.youtube_connection)

    begin
      normalized = client.fetch_channel(channel)
    rescue Channel::Youtube::PermanentError => e
      Rails.logger.warn(
        "[ChannelSync] permanent error for channel=#{channel.id}: #{e.class}: #{e.message}"
      )
      return
    end

    Channel.transaction do
      channel.update!(normalized.slice(*SYNC_COLUMNS).merge(last_synced_at: Time.current))
    end

    # Refresh locally-cached avatar and banner off the sync path so CDN
    # latency never blocks the field update. Each Ingest is digest-gated —
    # unchanged images are a cheap no-op.
    ChannelAvatarJob.perform_later(channel.id, normalized[:avatar_url]) if normalized[:avatar_url].present?
    ChannelBannerJob.perform_later(channel.id, normalized[:banner_url]) if normalized[:banner_url].present?
  end
end
