# Phase 16 §1 — Notifications data model + delivery channels.
#
# Source helper for the "video published outside pito" case. Phase 12's
# VideoSyncBack observes a row with `privacy_status` public/unlisted,
# `published_at` set, AND `pre_publish_checked_at IS NULL` (the user
# never ran the pito checklist). This is informational — pito does NOT
# block external publish.
#
# Idempotent on `("video_pre_publish_check_missed", "missed-check-#{id}")`.
module NotificationSource
  module VideoPrePublishCheckMissed
    EVENT_TYPE = "video_pre_publish_check_missed"

    module_function

    # @param video [Video]
    # @return [Notification]
    def report!(video)
      missing = missing_checks_for(video)
      payload = NotificationPayloadBuilder.build(
        event_type: EVENT_TYPE,
        overrides: {
          title: "pre-publish check skipped: #{video.title.presence || video.youtube_video_id}",
          body: "this video is published but the pito pre-publish checklist never ran.",
          url: "/videos/#{video.id}/edit",
          event_payload: {
            "video_id" => video.id,
            "video_title" => video.title,
            "missing_checks" => missing
          }
        }
      )

      Notification.find_or_create_by!(
        event_type: EVENT_TYPE,
        dedup_key: "missed-check-#{video.id}"
      ) do |n|
        n.kind = :video_pre_publish_check_missed
        n.severity = :info
        n.title = payload[:title]
        n.body = payload[:body]
        n.url = payload[:url]
        n.event_payload = payload[:event_payload]
        n.fires_at = Time.current
      end
    end

    def missing_checks_for(video)
      [].tap do |list|
        list << "game"            unless video.pre_publish_game_ok
        list << "age"             unless video.pre_publish_age_ok
        list << "paid_promotion"  unless video.pre_publish_paid_promotion_ok
        list << "end_screen"      unless video.pre_publish_end_screen_ok
      end
    end
  end
end
