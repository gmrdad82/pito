# Phase 13.3 — Cross-video local rollups (the four Q14 charts).
#
# Per spec 01 master-agent decision: computed at query time, no
# dedicated tables. Each rollup returns a Hash so the chart partials
# can render directly without a downstream service.
#
# Every rollup pulls medians (not means) when the spec asks for it,
# so a single outlier video doesn't dominate the bucket.
module Analytics
  class CrossVideoLocals
    # When-to-publish: median first-7d views by `published_at`
    # day-of-week + hour. Bucket label is `"Mon 14"`, value is
    # the median over all videos in that bucket. Scoped to videos
    # that have a 7d window summary row.
    def when_to_publish
      summaries = VideoWindowSummary
        .where(window: "7d")
        .joins(:video)
        .where.not(videos: { published_at: nil })
        .pluck(Arel.sql("videos.published_at"), :views)

      buckets = summaries.group_by do |published_at, _views|
        "#{published_at.in_time_zone.strftime('%a')} #{published_at.in_time_zone.hour.to_s.rjust(2, '0')}"
      end

      buckets.transform_values { |pairs| median(pairs.map { |_, views| views.to_i }) }
    end

    # Best-duration: median 28d views by duration bucket. Bucket
    # boundaries are 0-60s, 1-5min, 5-15min, 15min+ per the spec
    # test list.
    DURATION_BUCKETS = [
      { label: "0-60s",  min: 0,    max: 60 },
      { label: "1-5min", min: 61,   max: 300 },
      { label: "5-15min", min: 301, max: 900 },
      { label: "15min+", min: 901,  max: nil }
    ].freeze

    def best_duration
      pairs = VideoWindowSummary
        .where(window: "28d")
        .joins(:video)
        .where.not(videos: { duration_seconds: nil })
        .pluck(Arel.sql("videos.duration_seconds"), :estimated_minutes_watched)

      DURATION_BUCKETS.each_with_object({}) do |bucket, acc|
        bucket_pairs = pairs.select do |duration, _|
          duration >= bucket[:min] && (bucket[:max].nil? || duration <= bucket[:max])
        end
        acc[bucket[:label]] = median(bucket_pairs.map { |_, value| value.to_i })
      end
    end

    # Topics-that-work: median 28d views grouped by `category_id`.
    def topics_that_work
      pairs = VideoWindowSummary
        .where(window: "28d")
        .joins(:video)
        .where.not(videos: { category_id: nil })
        .pluck(Arel.sql("videos.category_id"), :views)

      pairs.group_by(&:first).transform_values do |group|
        median(group.map { |_, views| views.to_i })
      end
    end

    # Thumbnail-decay: per-video CTR over the configured windows,
    # surfacing the videos whose CTR is declining (most-recent window
    # CTR < earliest window CTR). Returns a Hash keyed by the video's
    # display label to a single CTR delta number — negative deltas
    # represent decay.
    DECAY_THRESHOLD = -0.001 # CTR drops by 0.1 percentage point or more

    def thumbnail_decay
      summaries = VideoWindowSummary
        .where(window: %w[7d 28d 90d])
        .order(:video_id)
        .group_by(&:video_id)

      videos_by_id = Video
        .where(id: summaries.keys)
        .index_by(&:id)

      summaries.each_with_object({}) do |(video_id, rows), acc|
        sorted = rows.sort_by { |row| %w[lifetime 90d 28d 7d].index(row.window) }
        first  = sorted.first
        last   = sorted.last
        next unless first && last

        first_ctr = first.video_thumbnail_impressions_click_rate.to_f
        last_ctr  = last.video_thumbnail_impressions_click_rate.to_f
        delta = last_ctr - first_ctr
        next unless delta <= DECAY_THRESHOLD

        video = videos_by_id[video_id]
        next unless video

        label = video.title.presence || video.youtube_video_id || "video #{video.id}"
        acc[label] = delta
      end
    end

    # Public for tests — encodes the rule "negative delta beyond the
    # threshold counts as declining."
    def declining?(delta)
      delta <= DECAY_THRESHOLD
    end

    private

    def median(values)
      return 0 if values.empty?
      sorted = values.sort
      mid = sorted.length / 2
      if sorted.length.odd?
        sorted[mid].to_i
      else
        ((sorted[mid - 1] + sorted[mid]) / 2.0).to_i
      end
    end
  end
end
