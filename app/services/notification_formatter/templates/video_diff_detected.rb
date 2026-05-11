# Phase 23 §23d — Notification formatter template.
#
# `video_diff_detected` notifications are emitted by `VideoDiffCheckJob`
# when the daily (or user-triggered) sync detects that the YouTube
# side of a video has diverged from Pito's local row. The notification
# carries the user to `/videos/:slug/diff` for per-field resolution.
#
# Required `event_payload` keys: `video_id`, `video_slug`, `video_title`,
# `diff_id`, `fields` (array of differing field names).
module NotificationFormatter
  module Templates
    class VideoDiffDetected < Base
      def title
        field_count = Array(fetch(:fields)).size
        plural = field_count == 1 ? "field" : "fields"
        "youtube diverged on #{field_count} #{plural}"
      end

      def body
        title_text   = fetch(:video_title, placeholder("video title"))
        field_list   = join_list(fetch(:fields), fallback: "(no fields)")
        "video '#{title_text}' has diverged on: #{field_list}."
      end

      def url
        slug = fetch(:video_slug)
        return nil if slug.blank?

        "/videos/#{slug}/diff"
      end
    end
  end
end
