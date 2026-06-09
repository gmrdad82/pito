# frozen_string_literal: true

# Chat-initiated full sync: channel fields + stats AND all video fields + stats.
#
# For each scoped channel:
#   1. `ChannelSync.perform_now(channel_id)` — channel fields
#   2. `Channel::Youtube::StatsFetcher.call(channel)` — channel stats
#   3. `NightlyVideoSyncJob.perform_now(channel_id)` — all video fields + stats
#
# Counts total videos after sync, then broadcasts ONE Standard summary message.
#
# `channel_ids` empty = all connected channels.
# `scope_label` is the human-readable string used in the summary copy.
class SyncChannelVideosJob < ApplicationJob
  queue_as :default

  def perform(channel_ids, scope_label, conversation_id: nil)
    channels    = resolve_channels(channel_ids)
    total_count = 0

    channels.each do |channel|
      sync_channel_fields(channel)
      sync_channel_stats(channel)
      NightlyVideoSyncJob.perform_now(channel.id)
      total_count += channel.videos.reload.count
    end

    return unless conversation_id.present?

    conversation = ::Conversation.find_by(id: conversation_id)
    return unless conversation

    broadcaster = Pito::Stream::Broadcaster.new(conversation:)

    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :slash,
      input_text: "/sync channel with videos #{scope_label}".strip
    )

    summary_text = Pito::Copy.render(
      "pito.copy.sync.channel_videos_done",
      { scope: scope_label, count: total_count }
    )

    broadcaster.emit(
      turn:,
      kind:    :system,
      payload: { "text" => summary_text }
    )

    broadcaster.complete_turn(turn:)
  rescue StandardError => e
    Rails.logger.error("[SyncChannelVideosJob] failed for scope=#{scope_label}: #{e.class}: #{e.message}")
  end

  private

  def resolve_channels(channel_ids)
    ids = Array(channel_ids).map(&:to_i).select(&:positive?)
    if ids.empty?
      ::Channel.joins(:youtube_connection)
               .where(youtube_connections: { needs_reauth: false })
    else
      ::Channel.where(id: ids)
    end
  end

  def sync_channel_fields(channel)
    ChannelSync.perform_now(channel.id)
  rescue StandardError => e
    Rails.logger.error("[SyncChannelVideosJob] fields sync failed for channel=#{channel.id}: #{e.class}: #{e.message}")
  end

  def sync_channel_stats(channel)
    stats = ::Channel::Youtube::StatsFetcher.call(channel)
    ::Pito::Stats.set(channel, :subscribers, stats[:subscriber_count])
    ::Pito::Stats.set(channel, :views,       stats[:view_count])
    channel.update_columns(last_synced_at: stats[:last_synced_at])
  rescue StandardError => e
    Rails.logger.error("[SyncChannelVideosJob] stats sync failed for channel=#{channel.id}: #{e.class}: #{e.message}")
  end
end
