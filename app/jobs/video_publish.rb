# Wraps the video publish-state transition. Distinct from
# VideoRemoteStatusSync because it has additional invariants (the four
# pre-publish booleans must be true) and because it stamps the
# `pre_publish_checked_at` timestamp atomically with the
# privacy_status flip.
#
# In the steady state the controller `#publish` / `#schedule` actions
# perform this synchronously (no enqueue) so the user sees the badge
# update in the same response. The job entry point is reserved
# for any future scheduler that needs to fire a
# pre-checked publish in the background.
class VideoPublish < ApplicationJob
  queue_as :default

  # `target_privacy_status` may be "public" / "unlisted".
  # `publish_at_iso8601` may be nil (publish flow) or an ISO 8601 string
  # (schedule flow).
  def perform(video_id, target_privacy_status, publish_at_iso8601 = nil)
    video = Video.find_by(id: video_id)
    return unless video

    return unless video.pre_publish_complete?

    if publish_at_iso8601.present?
      # The job receives an absolute ISO 8601 instant
      # (`Time.iso8601` requires the offset suffix). Storage is always
      # UTC; the rendered user-local clock is reconstructed at render
      # time via `ScheduledPublishHelper#render_publish_at_for_user`.
      # `Time.iso8601` raises on a tz-less input — that contract is
      # enforced upstream by the controller, which already converts
      # user-local picker input to UTC before enqueueing.
      utc_instant = Time.iso8601(publish_at_iso8601).utc
      log_tz_observability(video, utc_instant)
      video.update!(
        publish_at: utc_instant,
        privacy_status: :private
      )
    else
      video.update!(privacy_status: target_privacy_status)
    end

    # This job only flips local publish state. Pushing the new
    # privacy_status / publish_at to YouTube is a separate, explicit step:
    # the confirmation executor enqueues VideoRemoteStatusSync after the
    # local update. There is no model-level after_update_commit hook.
  end

  private

  # Observability — log the channel's owning user's
  # time_zone alongside the UTC instant so post-hoc debugging can
  # confirm the user-tz the picker rendered against. The user-tz at
  # job-fire time may differ from the user-tz at schedule time (the
  # user changed zones between scheduling and firing); the stored
  # UTC instant is the source of truth — the log line documents the
  # render-time context.
  def log_tz_observability(video, utc_instant)
    Rails.logger.info(
      "VideoPublish video_id=#{video.id} publish_at_utc=#{utc_instant.iso8601}"
    )
  rescue StandardError => e
    # Logging must never raise — defensive.
    Rails.logger.warn("VideoPublish log_tz_observability failed: #{e.message}")
  end
end
