# Phase 9 — GoogleIdentity → YoutubeConnection rename (ADR 0006).
# Disconnect one or more channels from their YoutubeConnection.
#
# Steps (atomic in a transaction):
#   1. Snapshot affected_connection_ids = channels.map(&:youtube_connection_id).compact.uniq.
#   2. For each Channel, set `youtube_connection_id: nil`. (Phase 7 Path A2:
#      the legacy `connected` boolean is gone; `youtube_connection_id IS
#      NULL` is the disconnected state.)
#   3. For each affected connection: if no remaining `Channel` row
#      references it, revoke the Google grant via
#      `Google::RevokeToken.call(connection)` AND destroy the
#      connection row (locked decision 7C-disconnect-lifecycle —
#      destroy the row; the audit trail lives in
#      `youtube_api_calls`, not on the connection row).
class Channel
  module Youtube
    module DisconnectChannel
      Result = Struct.new(:disconnected_channel_ids, :revoked_connection_ids,
                          keyword_init: true)

      module_function

      def call(channel_ids:)
        ids = Array(channel_ids).map(&:to_i).reject(&:zero?).uniq
        return Result.new(disconnected_channel_ids: [], revoked_connection_ids: []) if ids.empty?

        revoked_connection_ids = []
        disconnected_channel_ids = []

        ActiveRecord::Base.transaction do
          channels = Channel.where(id: ids).to_a
          affected_connection_ids = channels.map(&:youtube_connection_id).compact.uniq

          channels.each do |channel|
            channel.update_columns(youtube_connection_id: nil)
            disconnected_channel_ids << channel.id
          end

          affected_connection_ids.each do |connection_id|
            remaining = Channel.unscoped.where(youtube_connection_id: connection_id).count
            next if remaining.positive?

            connection = YoutubeConnection.unscoped.find_by(id: connection_id)
            next if connection.nil?

            # Revoke first, then destroy. RevokeToken swallows the
            # "already revoked" path itself (idempotent locked
            # decision) so destroy proceeds in either branch.
            Google::RevokeToken.call(connection)
            connection.destroy!
            revoked_connection_ids << connection_id
          end
        end

        Result.new(
          disconnected_channel_ids: disconnected_channel_ids,
          revoked_connection_ids: revoked_connection_ids
        )
      end
    end
  end
end
