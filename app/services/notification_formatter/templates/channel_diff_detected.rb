# Phase 7.5 §11i — Notification formatter template.
#
# `channel_diff_detected` notifications are emitted by
# `ChannelDiffCheckJob` when the daily cron (or user-triggered
# `[sync]`) finds the YouTube side of a channel has diverged from
# Pito's local row. The notification carries the user to
# `/channels/:slug/diff` for per-field resolution.
#
# Required `event_payload` keys: `channel_id`, `channel_slug`,
# `channel_title`, `channel_url`, `diff_id`, `fields`.
module NotificationFormatter
  module Templates
    class ChannelDiffDetected < Base
      def title
        field_count = Array(fetch(:fields)).size
        plural = field_count == 1 ? "field" : "fields"
        "youtube diverged on #{field_count} channel #{plural}"
      end

      def body
        label      = fetch(:channel_title, placeholder("channel title"))
        field_list = join_list(fetch(:fields), fallback: "(no fields)")
        "channel '#{label}' has diverged on: #{field_list}."
      end

      def url
        slug = fetch(:channel_slug)
        return nil if slug.blank?

        "/channels/#{slug}/diff"
      end
    end
  end
end
