# Phase 23 — Step 23a + 23d (Video Sync + Diff Dialog).
#
# Accepts a single `video_id` arg for targeted re-checks
# (called from the user-triggered `[sync]` path); without args, the
# bulk fan-out scheduler walks the catalogue.
#
# Per-video sequence:
#   1. Resolve Video + connected YoutubeConnection. Skip with a
#      log entry when either is missing.
#   2. Call `Channel::Youtube::Client#videos_list` (1 unit) for
#      `snippet,status,contentDetails,statistics`.
#   3. Run `Channel::Youtube::DiffComputer`.
#   4. Persist via `Channel::Youtube::VideoDiffPersister`. Empty diff stamps
#      `last_diff_checked_at` and returns nil.
#   5. On a non-empty diff, enqueue a `Notification` row with
#      `kind: video_diff_detected, severity: info` (Phase 16 surface).
#
# Quota / auth / 5xx errors raised by `Channel::Youtube::Client` re-raise so
# the retry policy handles backoff. The job intentionally does
# NOT catch them — silent quota exhaustion would hide a real problem.
class VideoDiffCheckJob < ApplicationJob
  queue_as :default

  def perform(video_id)
    video = Video.find_by(id: video_id)
    unless video
      Rails.logger.warn("VideoDiffCheckJob: video##{video_id} not found; skipping")
      return
    end

    connection = video.channel.youtube_connection
    unless connection
      Rails.logger.warn("VideoDiffCheckJob: video##{video.id} channel has no youtube_connection; skipping")
      return
    end

    if connection.needs_reauth?
      Rails.logger.warn("VideoDiffCheckJob: video##{video.id} connection needs re-auth; skipping")
      return
    end

    response = Channel::Youtube::Client.new(connection).videos_list(
      ids: [ video.youtube_video_id ],
      parts: %i[snippet status contentDetails statistics]
    )

    item = Array(response[:items]).first
    unless item
      Rails.logger.warn("VideoDiffCheckJob: video##{video.id} not found on YouTube (id=#{video.youtube_video_id})")
      return
    end

    diff_hash = Channel::Youtube::DiffComputer.call(video, item)
    diff = Channel::Youtube::VideoDiffPersister.call(
      video: video,
      diff_hash: diff_hash
    )

    if diff
      emit_diff_notification(video, diff)
    end

    diff
  end

  private

  # Phase 16 §1 — Notification row. `dedup_key` is keyed on the
  # video + the open diff so re-runs of the check job that find the
  # same payload don't double-emit. The unique partial index on
  # `notifications.dedup_key` enforces this at the DB level.
  def emit_diff_notification(video, diff)
    Notification.create!(
      kind: :video_diff_detected,
      event_type: "video_diff_detected",
      severity: :info,
      title: "youtube diverged on #{diff.fields.size} field#{'s' if diff.fields.size != 1}",
      body: "video '#{video.title.presence || video.youtube_video_id}' " \
            "has #{diff.fields.size} pending diff field#{'s' if diff.fields.size != 1}.",
      url: "/videos/#{video.to_param}/diff",
      fires_at: Time.current,
      dedup_key: "video_diff:#{video.id}:#{diff.id}",
      event_payload: {
        video_id: video.id,
        video_slug: video.to_param,
        video_title: video.title,
        diff_id: diff.id,
        fields: diff.fields
      }
    )
  rescue ActiveRecord::RecordNotUnique
    # Idempotency net for the dedup_key unique partial index. A
    # concurrent run that won the insert race already wrote the
    # notification; nothing more to do.
    nil
  end
end
