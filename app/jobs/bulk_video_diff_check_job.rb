# Phase 23 — Step 23d (Video Sync + Diff Dialog).
#
# Fan-out scheduler. Picks every Video whose channel has an active
# `youtube_connection` and enqueues a `VideoDiffCheckJob` for each.
#
# The per-video jobs are staggered across the day to spread quota
# burn across the YouTube `videos.list` daily budget (10,000 units;
# `videos.list` is 1 unit per call, so 10,000 videos / day fits
# headroom even with other API usage).
#
# `STAGGER_WINDOW_SECONDS` controls the stagger window. Defaults to
# 4 hours (14,400 seconds) — every video gets a `perform_in` offset
# uniformly distributed in [0, window). With 500 videos that's one
# call every ~28 seconds. With 5000 it's one every ~3 seconds — still
# well under YouTube's per-second rate limit.
class BulkVideoDiffCheckJob
  include Sidekiq::Job

  sidekiq_options queue: "default", retry: 2

  STAGGER_WINDOW_SECONDS = 4 * 60 * 60

  def perform
    scope = Video.joins(:channel)
                 .where.not(channels: { youtube_connection_id: nil })
                 .order(:id)

    total = scope.count
    enqueued = 0
    return if total.zero?

    window = STAGGER_WINDOW_SECONDS
    scope.find_each.with_index do |video, idx|
      offset = (window.to_f * idx / total).floor
      VideoDiffCheckJob.perform_in(offset, video.id)
      enqueued += 1
    end

    Rails.logger.info("BulkVideoDiffCheckJob: enqueued #{enqueued} VideoDiffCheckJob runs " \
                      "across #{window}s window")
    enqueued
  end
end
