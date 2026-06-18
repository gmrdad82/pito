# frozen_string_literal: true

# Chat-initiated newer-only YouTube video import for a channel scope.
#
# Emits ONE enhanced result message per channel (including channels that need reauth).
# For healthy channels runs `NightlyVideoSyncJob.perform_now(channel_id)`
# and counts newly created videos by comparing before/after. For reauth
# channels emits a per-channel reauth prompt without running an import.
#
# `channel_ids` empty = all channels with a youtube_connection (including
# those with needs_reauth: true — they get a reauth message, not an import).
# `scope_label` is the human-readable string used in the turn input text.
#
# NOTE: NightlyVideoSyncJob is a full upsert, not strictly "newer-only"; however
# it is digest-gated and only re-embeds on actual field changes, so repeated
# runs are safe and effectively additive (new records are created, unchanged
# ones are skipped). Using it here avoids duplicating YouTube API code.
class ChatImportVideosJob < ApplicationJob
  queue_as :default

  def perform(channel_ids, scope_label, conversation_id: nil)
    return unless conversation_id.present?

    conversation = ::Conversation.find_by(id: conversation_id)
    return unless conversation

    broadcaster = Pito::Stream::Broadcaster.new(conversation:)

    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :slash,
      input_text: "/import videos #{scope_label}".strip
    )

    resolve_channels(channel_ids).each do |channel|
      begin
        message =
          if channel.youtube_connection&.needs_reauth?
            Pito::Copy.render(
              "pito.copy.import_videos.per_channel_reauth",
              { handle: channel.at_handle }
            )
          else
            count_before = channel.videos.count
            NightlyVideoSyncJob.perform_now(channel.id)
            count_after = channel.videos.reload.count
            new_count   = [ count_after - count_before, 0 ].max
            Pito::Copy.render(
              "pito.copy.import_videos.per_channel_done",
              { handle: channel.at_handle, count: new_count }
            )
          end

        broadcaster.emit(turn:, kind: :enhanced, payload: { "text" => message })
      rescue StandardError => e
        Rails.logger.error(
          "[ChatImportVideosJob] channel #{channel.id} failed: #{e.class}: #{e.message}"
        )
      end
    end

    broadcaster.complete_turn(turn:)
  rescue StandardError => e
    Rails.logger.error("[ChatImportVideosJob] failed for scope=#{scope_label}: #{e.class}: #{e.message}")
  end

  private

  def resolve_channels(channel_ids)
    ids = Array(channel_ids).map(&:to_i).select(&:positive?)
    if ids.empty?
      ::Channel.joins(:youtube_connection).order(:title)
    else
      ::Channel.where(id: ids).order(:title)
    end
  end
end
