# frozen_string_literal: true

# Chat-initiated bulk YouTube video sync for a channel scope.
#
# For each scoped channel runs `NightlyVideoSyncJob.perform_now(channel_id)`
# (the pure data path — no broadcaster, no turn), counts synced videos, then
# broadcasts ONE Standard summary message to the conversation.
#
# `channel_ids` empty = all connected channels.
# `scope_label` is the human-readable string used in the summary copy.
class SyncVideosJob < ApplicationJob
  queue_as :default

  def perform(channel_ids, scope_label, conversation_id: nil)
    channels = resolve_channels(channel_ids)
    total    = 0

    channels.each do |channel|
      count_before = channel.videos.count
      NightlyVideoSyncJob.perform_now(channel.id)
      count_after  = channel.videos.reload.count
      total += count_after # report final video count (synced, not just new)
    end

    return unless conversation_id.present?

    conversation = ::Conversation.find_by(id: conversation_id)
    return unless conversation

    broadcaster = Pito::Stream::Broadcaster.new(conversation:)

    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :slash,
      input_text: "/sync videos #{scope_label}".strip
    )

    summary_text = Pito::Copy.render(
      "pito.copy.sync.videos_done",
      { scope: scope_label, count: total }
    )

    broadcaster.emit(
      turn:,
      kind:    :system,
      payload: { "text" => summary_text }
    )

    broadcaster.complete_turn(turn:)
  rescue StandardError => e
    Rails.logger.error("[SyncVideosJob] failed for scope=#{scope_label}: #{e.class}: #{e.message}")
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
end
