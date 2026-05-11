# Phase 13.2 — Analytics sync engine. Pure-function query builder for
# the YouTube Analytics v2 `reports.query` endpoint.
#
# Each public method returns a kwargs hash that
# `Google::Apis::YoutubeAnalyticsV2::YouTubeAnalyticsService#query_report`
# accepts directly: `ids:`, `start_date:`, `end_date:`, `metrics:`,
# `dimensions:`, `filters:`, `sort:`, `max_results:`. Strings, not
# arrays — the API gem joins comma-separated metrics / dimensions
# itself but we pre-join here so the audit row gets a stable shape.
#
# Mutual-exclusion rules (Note 3 §"Mutual-exclusion gotchas"):
#
# 1. `liveOrOnDemand` + `averageViewPercentage` cannot coexist. C1/V1
#    omit `liveOrOnDemand`. C2/V2 omit it.
# 2. `day` + `month` cannot coexist as time dimensions.
# 3. V7 (audience retention) requires a single video filter.
# 4. C3 / V5 / V6 require `sort` + `maxResults` caps.
#
# Monetization-enabled mode appends the revenue metrics; otherwise
# omits.
module Youtube
  class AnalyticsQueryBuilder
    # Window enum values from spec 01.
    WINDOWS = %w[7d 28d 90d lifetime].freeze

    # C1/V1 daily metric set. Note 3 §C1/§V1.
    DAILY_METRICS = %w[
      views
      estimatedMinutesWatched
      estimatedRedMinutesWatched
      averageViewDuration
      likes
      dislikes
      comments
      shares
      subscribersGained
      subscribersLost
      videosAddedToPlaylists
      videosRemovedFromPlaylists
      videoThumbnailImpressions
      cardImpressions
      cardClicks
      cardTeaserImpressions
      cardTeaserClicks
      engagedViews
      redViews
    ].freeze

    DAILY_REVENUE_METRICS = %w[
      estimatedRevenue
      estimatedAdRevenue
      estimatedRedPartnerRevenue
      grossRevenue
      adImpressions
      monetizedPlaybacks
    ].freeze

    # C2/V2 window-summary metric set: shares the daily metric set plus
    # the four non-summable Studio-faithful ratios.
    WINDOW_RATIO_METRICS = %w[
      averageViewPercentage
      videoThumbnailImpressionsClickRate
      cardClickRate
      cardTeaserClickRate
    ].freeze

    WINDOW_REVENUE_METRICS = %w[
      cpm
      playbackBasedCpm
    ].freeze

    # Note 3 §C3 / §V5: the Analytics API caps `maxResults` at 200 for
    # paginated reports. The default for top-videos is 50.
    TOP_VIDEOS_DEFAULT_LIMIT = 50
    TOP_VIDEOS_MAX_LIMIT = 200

    class << self
      # ----- Channel queries ------------------------------------------------

      # C1 — channel daily.
      def channel_daily_params(channel_youtube_id:, from:, to:, monetization_enabled: false)
        guard_time_dimensions!(time_dim: "day")
        metrics = DAILY_METRICS.dup
        metrics.concat(DAILY_REVENUE_METRICS) if monetization_enabled
        {
          ids: "channel==#{channel_youtube_id}",
          start_date: format_date(from),
          end_date: format_date(to),
          metrics: metrics.join(","),
          dimensions: "day"
        }
      end

      # C2 — channel window summary. `window` is one of WINDOWS; the
      # builder computes `(window_start, window_end)` against `today_pt`.
      def channel_window_summary_params(channel_youtube_id:, window:, today:, monetization_enabled: false)
        from, to = window_range(window, today)
        metrics = (DAILY_METRICS + WINDOW_RATIO_METRICS).uniq
        if monetization_enabled
          metrics.concat(DAILY_REVENUE_METRICS)
          metrics.concat(WINDOW_REVENUE_METRICS)
        end
        {
          ids: "channel==#{channel_youtube_id}",
          start_date: format_date(from),
          end_date: format_date(to),
          metrics: metrics.uniq.join(",")
        }
      end

      # C3 — top videos for a channel-window.
      def top_videos_params(channel_youtube_id:, window:, today:, limit: TOP_VIDEOS_DEFAULT_LIMIT)
        if limit < 1 || limit > TOP_VIDEOS_MAX_LIMIT
          raise ArgumentError, "limit must be between 1 and #{TOP_VIDEOS_MAX_LIMIT}"
        end

        from, to = window_range(window, today)
        {
          ids: "channel==#{channel_youtube_id}",
          start_date: format_date(from),
          end_date: format_date(to),
          metrics: %w[views estimatedMinutesWatched averageViewDuration averageViewPercentage subscribersGained likes comments].join(","),
          dimensions: "video",
          sort: "-estimatedMinutesWatched",
          max_results: limit
        }
      end

      # C4 — channel geography. Builder method exists; the client method
      # is a NotImplementedError stub per the master-agent decision (no
      # `channel_daily_by_country` table in spec 01).
      def channel_geography_params(channel_youtube_id:, from:, to:)
        {
          ids: "channel==#{channel_youtube_id}",
          start_date: format_date(from),
          end_date: format_date(to),
          metrics: %w[views estimatedMinutesWatched averageViewDuration averageViewPercentage].join(","),
          dimensions: "country"
        }
      end

      # C5 — channel demographics. Builder method exists; client method
      # is a stub per the master-agent decision.
      def channel_demographics_params(channel_youtube_id:, from:, to:)
        {
          ids: "channel==#{channel_youtube_id}",
          start_date: format_date(from),
          end_date: format_date(to),
          metrics: "viewerPercentage",
          dimensions: "ageGroup,gender"
        }
      end

      # ----- Video queries --------------------------------------------------

      # V1 — video daily.
      def video_daily_params(video_youtube_id:, from:, to:, monetization_enabled: false)
        guard_time_dimensions!(time_dim: "day")
        metrics = DAILY_METRICS.dup
        metrics.concat(DAILY_REVENUE_METRICS) if monetization_enabled
        {
          ids: "channel==MINE",
          start_date: format_date(from),
          end_date: format_date(to),
          metrics: metrics.join(","),
          dimensions: "day",
          filters: "video==#{video_youtube_id}"
        }
      end

      # V2 — video window summary.
      def video_window_summary_params(video_youtube_id:, window:, today:, monetization_enabled: false)
        from, to = window_range(window, today)
        metrics = (DAILY_METRICS + WINDOW_RATIO_METRICS).uniq
        if monetization_enabled
          metrics.concat(DAILY_REVENUE_METRICS)
          metrics.concat(WINDOW_REVENUE_METRICS)
        end
        {
          ids: "channel==MINE",
          start_date: format_date(from),
          end_date: format_date(to),
          metrics: metrics.uniq.join(","),
          filters: "video==#{video_youtube_id}"
        }
      end

      # V3 — video by country.
      def video_by_country_params(video_youtube_id:, from:, to:)
        {
          ids: "channel==MINE",
          start_date: format_date(from),
          end_date: format_date(to),
          metrics: %w[views estimatedMinutesWatched averageViewDuration averageViewPercentage].join(","),
          dimensions: "country",
          filters: "video==#{video_youtube_id}"
        }
      end

      # V4 — video by device type (single dimension).
      def video_by_device_type_params(video_youtube_id:, from:, to:)
        {
          ids: "channel==MINE",
          start_date: format_date(from),
          end_date: format_date(to),
          metrics: %w[views estimatedMinutesWatched averageViewDuration averageViewPercentage].join(","),
          dimensions: "deviceType",
          filters: "video==#{video_youtube_id}"
        }
      end

      # V4 — video by operating system (separate query — single dimension).
      def video_by_operating_system_params(video_youtube_id:, from:, to:)
        {
          ids: "channel==MINE",
          start_date: format_date(from),
          end_date: format_date(to),
          metrics: %w[views estimatedMinutesWatched averageViewDuration averageViewPercentage].join(","),
          dimensions: "operatingSystem",
          filters: "video==#{video_youtube_id}"
        }
      end

      # V5 — video by traffic source.
      def video_by_traffic_source_params(video_youtube_id:, from:, to:)
        {
          ids: "channel==MINE",
          start_date: format_date(from),
          end_date: format_date(to),
          metrics: %w[views estimatedMinutesWatched videoThumbnailImpressions videoThumbnailImpressionsClickRate].join(","),
          dimensions: "insightTrafficSourceType",
          filters: "video==#{video_youtube_id}"
        }
      end

      # V6 — video by subscribed status.
      def video_by_subscribed_status_params(video_youtube_id:, from:, to:)
        {
          ids: "channel==MINE",
          start_date: format_date(from),
          end_date: format_date(to),
          metrics: %w[views estimatedMinutesWatched averageViewPercentage].join(","),
          dimensions: "subscribedStatus",
          filters: "video==#{video_youtube_id}"
        }
      end

      # V7 — audience retention. Single-video filter required.
      def video_retention_params(video_youtube_id:)
        if video_youtube_id.is_a?(Array)
          raise ArgumentError, "audience-retention queries require a single video filter"
        end
        if video_youtube_id.to_s.include?(",")
          raise ArgumentError, "audience-retention queries require a single video filter"
        end

        {
          ids: "channel==MINE",
          start_date: "2005-02-14", # YouTube launch date — covers lifetime.
          end_date: format_date(Date.current),
          metrics: %w[audienceWatchRatio relativeRetentionPerformance startedWatching stoppedWatching].join(","),
          dimensions: "elapsedVideoTimeRatio",
          filters: "video==#{video_youtube_id}"
        }
      end

      # V8 — video demographics.
      def video_demographics_params(video_youtube_id:, from:, to:)
        {
          ids: "channel==MINE",
          start_date: format_date(from),
          end_date: format_date(to),
          metrics: "viewerPercentage",
          dimensions: "ageGroup,gender",
          filters: "video==#{video_youtube_id}"
        }
      end

      # Phase 26 §01g — viewer-time buckets. Day-of-week x hour-of-day
      # viewer distribution for a single video. YouTube returns the
      # values in UTC bucket; the user-tz rollup happens at query
      # time in `Analytics::ViewerTimeRollup`.
      def video_viewer_time_params(video_youtube_id:, from:, to:)
        {
          ids: "channel==MINE",
          start_date: format_date(from),
          end_date: format_date(to),
          metrics: %w[views estimatedMinutesWatched].join(","),
          dimensions: "day,hour",
          filters: "video==#{video_youtube_id}"
        }
      end

      # ----- Mutual exclusion guards ---------------------------------------

      def assert_compatible!(metrics:, dimensions: nil)
        metrics_arr = Array(metrics).flat_map { |m| m.to_s.split(",") }.map(&:strip)
        dims_arr = Array(dimensions).flat_map { |d| d.to_s.split(",") }.map(&:strip)

        if dims_arr.include?("liveOrOnDemand") && metrics_arr.include?("averageViewPercentage")
          raise ArgumentError,
                "mutually exclusive: liveOrOnDemand + averageViewPercentage cannot coexist"
        end
        if dims_arr.include?("day") && dims_arr.include?("month")
          raise ArgumentError,
                "mutually exclusive: day + month cannot coexist as time dimensions"
        end
      end

      # Resolve a window enum to a [start_date, end_date] tuple anchored
      # at `today` (the orchestrator passes today_pt).
      def window_range(window, today)
        case window.to_s
        when "7d"       then [ today - 7,  today - 1 ]
        when "28d"      then [ today - 28, today - 1 ]
        when "90d"      then [ today - 90, today - 1 ]
        when "lifetime" then [ Date.new(2005, 2, 14), today - 1 ]
        else
          raise ArgumentError, "unknown window: #{window.inspect}"
        end
      end

      private

      def format_date(date)
        date = Date.parse(date.to_s) unless date.respond_to?(:strftime)
        date.strftime("%Y-%m-%d")
      end

      def guard_time_dimensions!(time_dim:)
        # Currently a structural placeholder — the public methods only
        # ever pass one of "day" / "month" as `time_dim`. Reserved for
        # future use if a method ever combines the two.
        nil
      end
    end
  end
end
