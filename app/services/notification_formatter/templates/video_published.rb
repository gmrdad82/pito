# Phase 16 §2 — Notification formatter.
#
# Template for the `video_published` notification kind. Spec 02 §
# "Per-event-type template specifications".
#
# Required `event_payload` keys: `video_id`, `video_title`,
# `channel_id`, `channel_title`, `published_at`, `watch_url`.
module NotificationFormatter
  module Templates
    class VideoPublished < Base
      def title
        "published: #{fetch(:video_title, placeholder('video title'))}"
      end

      def body
        title_text   = fetch(:video_title, placeholder("video title"))
        channel_text = fetch(:channel_title, placeholder("channel title"))
        watch_url    = fetch(:watch_url)

        if watch_url.present?
          "#{channel_text} just published #{title_text}. " \
            "[watch on youtube](#{watch_url})."
        else
          "#{channel_text} just published #{title_text}."
        end
      end

      def url
        video_id = fetch(:video_id)
        return nil if video_id.blank?

        "/videos/#{video_id}"
      end
    end
  end
end
