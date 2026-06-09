# frozen_string_literal: true

# Chat-initiated YouTube channel fields + stats sync for a channel scope.
#
# For each scoped channel:
#   1. Calls `ChannelSync.perform_now(channel_id)` to refresh channel fields
#      (title, description, thumbnail, etc.) from YouTube.
#   2. Calls `Channel::Youtube::StatsFetcher.call(channel)` to refresh
#      subscriber + view counts via Pito::Stats.
#
# Then broadcasts ONE Standard summary message to the conversation.
#
# `channel_ids` empty = all connected channels.
# `scope_label` is the human-readable string used in the summary copy.
class SyncChannelJob < ApplicationJob
  queue_as :default

  def perform(channel_ids, scope_label, conversation_id: nil)
    channels = resolve_channels(channel_ids)

    channels.each do |channel|
      sync_channel_fields(channel)
      sync_channel_stats(channel)
    end

    return unless conversation_id.present?

    conversation = ::Conversation.find_by(id: conversation_id)
    return unless conversation

    broadcaster = Pito::Stream::Broadcaster.new(conversation:)

    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :slash,
      input_text: "/sync channel #{scope_label}".strip
    )

    summary_text = Pito::Copy.render(
      "pito.copy.sync.channel_done",
      { scope: scope_label }
    )

    broadcaster.emit(
      turn:,
      kind:    :system,
      payload: { "text" => summary_text }
    )

    broadcaster.complete_turn(turn:)
  rescue StandardError => e
    Rails.logger.error("[SyncChannelJob] failed for scope=#{scope_label}: #{e.class}: #{e.message}")
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
    Rails.logger.error("[SyncChannelJob] fields sync failed for channel=#{channel.id}: #{e.class}: #{e.message}")
  end

  def sync_channel_stats(channel)
    stats = ::Channel::Youtube::StatsFetcher.call(channel)
    ::Pito::Stats.set(channel, :subscribers, stats[:subscriber_count])
    ::Pito::Stats.set(channel, :views,       stats[:view_count])
    channel.update_columns(last_synced_at: stats[:last_synced_at])
  rescue StandardError => e
    Rails.logger.error("[SyncChannelJob] stats sync failed for channel=#{channel.id}: #{e.class}: #{e.message}")
  end
end
