# Phase 7.5 — Step 11i (Daily Channel Diff-Check + Resolution).
#
# Persists the output of `Channels::DiffComputer` into a
# `ChannelDiff` row. Idempotent: if an open diff already exists for
# the channel, the payload is refreshed in place (no new row spawned).
# On empty diff, any prior open diff is auto-closed (cron pass found
# the sides converged) and `nil` is returned.
#
# Returns:
#   * The persisted `ChannelDiff` row when a non-empty diff exists.
#   * `nil` when the diff is empty (no open diff after the run).
#
# Idempotency posture:
#
#   - Re-run with same field set → row's `field_diffs` + `detected_at`
#     are refreshed; no new row.
#   - Re-run with empty field set (sides agreed) → existing open row
#     auto-closes with `resolution_payload = { "auto_closed" => true }`.
#   - Race between two concurrent cron passes → partial unique index
#     on `(channel_id) WHERE resolved_at IS NULL` guarantees one open
#     row at most; the loser's `INSERT` raises `RecordNotUnique`,
#     which the persister rescues and retries as an UPDATE.
module Channels
  module DiffPersister
    module_function

    def call(channel:, field_diffs:, detected_at: Time.current)
      existing_open = ChannelDiff.unresolved.find_by(channel_id: channel.id)

      if field_diffs.blank?
        # No diff this pass. Auto-close any prior open row.
        if existing_open
          existing_open.update!(
            resolved_at: detected_at,
            resolution_payload: { "auto_closed" => true }
          )
        end
        return nil
      end

      if existing_open
        existing_open.update!(field_diffs: field_diffs, detected_at: detected_at)
        return existing_open
      end

      begin
        ChannelDiff.create!(
          channel: channel,
          field_diffs: field_diffs,
          detected_at: detected_at
        )
      rescue ActiveRecord::RecordNotUnique
        # Race: a concurrent pass beat us to the INSERT. Re-fetch and
        # update in place. Per the partial unique index contract,
        # exactly one open row now exists.
        existing = ChannelDiff.unresolved.find_by!(channel_id: channel.id)
        existing.update!(field_diffs: field_diffs, detected_at: detected_at)
        existing
      end
    end
  end
end
