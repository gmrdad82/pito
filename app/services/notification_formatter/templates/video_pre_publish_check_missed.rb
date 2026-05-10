# Phase 16 §2 — Notification formatter.
#
# Template for the `video_pre_publish_check_missed` notification kind.
#
# Required `event_payload` keys: `video_id`, `video_title`,
# `missing_checks` (array of "game" / "age" / "paid_promotion" /
# "end_screen").
module NotificationFormatter
  module Templates
    class VideoPrePublishCheckMissed < Base
      def title
        "missed pre-publish check: #{fetch(:video_title, placeholder('video title'))}"
      end

      def body
        title_text = fetch(:video_title, placeholder("video title"))
        missing    = join_list(fetch(:missing_checks), fallback: placeholder("missing checks"))
        edit_path  = url || "/videos"

        "#{title_text} went public without ticking: #{missing}. " \
          "[review](#{edit_path})."
      end

      def url
        video_id = fetch(:video_id)
        return nil if video_id.blank?

        "/videos/#{video_id}/edit"
      end
    end
  end
end
