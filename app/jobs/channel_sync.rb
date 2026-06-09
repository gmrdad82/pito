# Phase 7.5 §11a — replaces the Path A2 placeholder no-op with the real
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
class ChannelSync < ApplicationJob
  queue_as :default

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
      channel.update!(normalized.merge(last_synced_at: Time.current))
    end
  end
end
