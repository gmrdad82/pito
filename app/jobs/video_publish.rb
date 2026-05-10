# Phase 12 — wraps the video publish-state transition. Distinct from
# VideoSyncBack because it has additional invariants (the four
# pre-publish booleans must be true) and because it stamps the
# `pre_publish_checked_at` timestamp atomically with the
# privacy_status flip.
#
# In the steady state the controller `#publish` / `#schedule` actions
# perform this synchronously (no enqueue) so the user sees the badge
# update in the same response. The Sidekiq job entry point is reserved
# for MCP-driven flows and any future scheduler that needs to fire a
# pre-checked publish in the background.
class VideoPublish
  include Sidekiq::Job

  sidekiq_options queue: "default", retry: 3

  # `target_privacy_status` may be "public" / "unlisted".
  # `publish_at_iso8601` may be nil (publish flow) or an ISO 8601 string
  # (schedule flow).
  def perform(video_id, target_privacy_status, publish_at_iso8601 = nil)
    video = Video.find_by(id: video_id)
    return unless video

    return unless video.pre_publish_complete?

    if publish_at_iso8601.present?
      video.update!(
        publish_at: Time.iso8601(publish_at_iso8601),
        privacy_status: :private
      )
    else
      video.update!(privacy_status: target_privacy_status)
    end

    # The Video model's after_update_commit hook enqueues VideoSyncBack
    # automatically when writable fields change.
  end
end
