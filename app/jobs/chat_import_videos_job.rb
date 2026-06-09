# frozen_string_literal: true

# Chat-initiated newer-only YouTube video import for a channel scope.
#
# For each scoped channel runs `NightlyVideoSyncJob.perform_now(channel_id)`
# which fetches the full upload playlist and upserts new/changed videos.
# We track the count of newly created videos by comparing before/after, then
# broadcast ONE Standard summary message ("Imported N new videos on @chan").
#
# `channel_ids` empty = all connected channels.
# `scope_label` is the human-readable string used in the summary copy.
#
# NOTE: NightlyVideoSyncJob is a full upsert, not strictly "newer-only"; however
# it is digest-gated and only re-embeds on actual field changes, so repeated
# runs are safe and effectively additive (new records are created, unchanged
# ones are skipped). Using it here avoids duplicating YouTube API code.
class ChatImportVideosJob < ApplicationJob
  queue_as :default

  def perform(channel_ids, scope_label, conversation_id: nil)
    channels    = resolve_channels(channel_ids)
    total_new   = 0

    channels.each do |channel|
      count_before = channel.videos.count
      NightlyVideoSyncJob.perform_now(channel.id)
      count_after = channel.videos.reload.count
      total_new  += [ count_after - count_before, 0 ].max
    end

    return unless conversation_id.present?

    conversation = ::Conversation.find_by(id: conversation_id)
    return unless conversation

    broadcaster = Pito::Stream::Broadcaster.new(conversation:)

    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :slash,
      input_text: "/import videos #{scope_label}".strip
    )

    summary_text = Pito::Copy.render(
      "pito.copy.import_videos.done",
      { scope: scope_label, count: total_new }
    )

    broadcaster.emit(
      turn:,
      kind:    :system,
      payload: { "text" => summary_text }
    )

    broadcaster.complete_turn(turn:)
  rescue StandardError => e
    Rails.logger.error("[ChatImportVideosJob] failed for scope=#{scope_label}: #{e.class}: #{e.message}")
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
