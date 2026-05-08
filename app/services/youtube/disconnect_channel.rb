# Phase 7 — Step C (7c-settings-youtube-ui.md). Disconnect one or
# more channels from their Google OAuth identity.
#
# Steps (atomic in a transaction):
#   1. Snapshot affected_identity_ids = channels.map(&:oauth_identity_id).compact.uniq.
#   2. For each Channel, set `oauth_identity_id: nil`. (Phase 7 Path A2:
#      the legacy `connected` boolean is gone; `oauth_identity_id IS
#      NULL` is the new disconnected state.)
#   3. For each affected identity: if no remaining `Channel` row
#      references it, revoke the Google grant via
#      `Google::RevokeToken.call(identity)` AND destroy the
#      identity row (locked decision 7C-disconnect-lifecycle —
#      destroy the row; the audit trail lives in
#      `youtube_api_calls`, not on the identity row).
module Youtube
  module DisconnectChannel
    Result = Struct.new(:disconnected_channel_ids, :revoked_identity_ids,
                        keyword_init: true)

    module_function

    def call(channel_ids:)
      ids = Array(channel_ids).map(&:to_i).reject(&:zero?).uniq
      return Result.new(disconnected_channel_ids: [], revoked_identity_ids: []) if ids.empty?

      revoked_identity_ids = []
      disconnected_channel_ids = []

      ActiveRecord::Base.transaction do
        channels = Channel.where(id: ids).to_a
        affected_identity_ids = channels.map(&:oauth_identity_id).compact.uniq

        channels.each do |channel|
          channel.update_columns(oauth_identity_id: nil)
          disconnected_channel_ids << channel.id
        end

        affected_identity_ids.each do |identity_id|
          remaining = Channel.unscoped.where(oauth_identity_id: identity_id).count
          next if remaining.positive?

          identity = GoogleIdentity.unscoped.find_by(id: identity_id)
          next if identity.nil?

          # Revoke first, then destroy. RevokeToken swallows the
          # "already revoked" path itself (idempotent locked
          # decision) so destroy proceeds in either branch.
          Google::RevokeToken.call(identity)
          identity.destroy!
          revoked_identity_ids << identity_id
        end
      end

      Result.new(
        disconnected_channel_ids: disconnected_channel_ids,
        revoked_identity_ids: revoked_identity_ids
      )
    end
  end
end
