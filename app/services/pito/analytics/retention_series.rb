# frozen_string_literal: true

module Pito
  module Analytics
    # Computes the views-weighted average audience-retention curve for a scope.
    #
    # Retention is ALWAYS lifetime — the shift+space period window is ignored.
    # The YouTube Analytics API for retention is single-video (no batch), so we
    # fetch one retention curve per video and cache each in AnalyticsPrimitive
    # (report: "retention") with a ~1h TTL (since the window always ends today
    # and is therefore never finalized).
    #
    # Averaging rule:
    #   vid level    → the video's own retention curve (trivially "averaged")
    #   game level   → views-weighted average of the game's linked videos' curves
    #   channel level→ views-weighted average of ALL channel videos' curves
    #                  (the first N videos, capped by CHANNEL_VIDEO_LIMIT)
    #
    # Views weighting: each video's total views for the PERIOD window are fetched
    # via the scalars primitives (already warm from the scaffold computation, so
    # no extra YouTube API call is needed in practice). The retention curve is
    # averaged at each elapsedVideoTimeRatio bucket.
    #
    # Return shape:
    #   result.series    # => [98.0, 95.2, …]  audienceWatchRatio × 100, per ratio bucket
    #   result.total_pct # => 45.2             mean retention %, across all buckets
    #
    #   Pito::Analytics::RetentionSeries.for(groups:, window:)
    module RetentionSeries
      # Lifetime start: YouTube was founded in 2005-02-14; using Jan 1 is safe.
      LIFETIME_START = Date.new(2005, 1, 1)

      # Cap on videos fetched at channel level (avoids unbounded API calls).
      CHANNEL_VIDEO_LIMIT = 50

      Result = Data.define(:series, :total_pct, :rel_performance)

      # Internal struct returned by parse_curve (and fetch_curve).
      ParsedCurve = Data.define(:curve, :rel_performance)

      # Slim struct with the interface Primitives.store / AnalyticsPrimitive expect.
      # Expiry goes through the ONE Window policy point (token "lifetime" → 24h
      # tier; never re-derive TTLs locally — 0.9.0 Phase 2).
      LifetimeWindow = Struct.new(:start_date, :end_date, :token) do
        def expires_at_for(now:, live_ttl: nil)
          Pito::Analytics::Window.expires_at_for(end_date:, now:, token:, live_ttl:)
        end
      end

      module_function

      # @param groups         [Array<[Channel, Array<String>|:channel]>]
      # @param window         [Pito::Analytics::Window]   for the views-weight scalars
      # @param reference_date [Date]                       "today" for the lifetime window
      # @param now            [Time]                       for cache TTL
      # @return [Result]
      def for(groups:, window:, reference_date: Date.current, now: Time.current)
        lifetime_window = LifetimeWindow.new(LIFETIME_START, reference_date, "lifetime")

        # Expand to per-video (channel, vid_id, views_weight) triples.
        triples = expand_to_triples(groups:, window:)
        return empty_result if triples.empty?

        curves     = {}
        benchmarks = {}
        weights    = {}

        triples.each do |channel, vid_id, views|
          parsed = fetch_curve(channel:, video_id: vid_id, lifetime_window:, now:)
          next if parsed.curve.empty?

          curves[vid_id]     = parsed.curve
          benchmarks[vid_id] = parsed.rel_performance
          weights[vid_id]    = views.to_i
        end

        return empty_result if curves.empty?

        weighted   = views_weighted_average(curves, weights)
        series_pct = weighted.map { |r| (r * 100).round(2) }
        total_pct  = series_pct.empty? ? 0.0 : (series_pct.sum / series_pct.size.to_f).round(2)

        rel_perf = if benchmarks.any? { |_, rp| rp.any? }
          views_weighted_benchmark(benchmarks, weights)
        else
          nil
        end

        Result.new(series: series_pct, total_pct:, rel_performance: rel_perf)
      end

      # ── helpers (module_function so they're testable as RetentionSeries.method) ─

      # Expand groups to (channel, youtube_video_id, views) triples.
      # For channel-level groups (:channel subject) we query the DB for the
      # channel's videos; for vid/game groups the IDs are already in subjects.
      def expand_to_triples(groups:, window:)
        # Build per-video groups first (channel level → DB lookup).
        expanded = []
        groups.each do |channel, subjects|
          if subjects == :channel
            vids   = ::Video.where(channel:).where.not(youtube_video_id: nil)
                            .limit(CHANNEL_VIDEO_LIMIT).to_a
            vid_ids = vids.filter_map(&:youtube_video_id)
            next if vid_ids.empty?

            expanded << [ channel, vid_ids ]
          else
            vid_ids = Array(subjects).select { |id| id.is_a?(String) && id.present? }
            expanded << [ channel, vid_ids ] unless vid_ids.empty?
          end
        end

        return [] if expanded.empty?

        # Fetch scalars for period-window views weighting (warm cache from scaffold).
        scalars_map = Pito::Analytics::Primitives.fetch(groups: expanded, window:, report: "scalars")

        expanded.flat_map do |channel, vid_ids|
          vid_ids.map do |vid_id|
            row    = scalars_map[vid_id] || {}
            views  = (row["views"] || row[:views]).to_i
            [ channel, vid_id, views ]
          end
        end
      end

      # Fetch (and cache) the retention curve for a single video.
      # Returns a ParsedCurve, or one with empty arrays on error.
      def fetch_curve(channel:, video_id:, lifetime_window:, now:)
        warm = AnalyticsPrimitive.find_by(
          video_youtube_id: video_id,
          report:           "retention",
          start_date:       lifetime_window.start_date,
          end_date:         lifetime_window.end_date
        )
        data = warm&.live? ? warm.metrics : fetch_and_store(channel:, video_id:, lifetime_window:, now:)

        parse_curve(data)
      rescue StandardError
        ParsedCurve.new(curve: [], rel_performance: [])
      end

      # Call the YouTube Analytics API for a single video's retention and persist.
      def fetch_and_store(channel:, video_id:, lifetime_window:, now:)
        client = ::Channel::Youtube::AnalyticsClient.new(channel.youtube_connection)
        data = client.retention(
          channel_id: channel.youtube_channel_id,
          start_date: lifetime_window.start_date,
          end_date:   lifetime_window.end_date,
          video:      video_id
        )
        store_primitive(video_id:, lifetime_window:, data:, now:)
        data
      end

      # Persist retention data in AnalyticsPrimitive (mirrors Primitives.store logic).
      def store_primitive(video_id:, lifetime_window:, data:, now:)
        normalized = normalize_data(data)
        row = AnalyticsPrimitive.find_or_initialize_by(
          video_youtube_id: video_id,
          report:           "retention",
          start_date:       lifetime_window.start_date,
          end_date:         lifetime_window.end_date
        )
        row.assign_attributes(
          period_token: lifetime_window.token,
          metrics:      normalized,
          fetched_at:   now,
          expires_at:   lifetime_window.expires_at_for(now:)
        )
        row.save!
        row
      rescue ActiveRecord::RecordNotUnique
        AnalyticsPrimitive.find_by!(
          video_youtube_id: video_id,
          report:           "retention",
          start_date:       lifetime_window.start_date,
          end_date:         lifetime_window.end_date
        )
      end

      # Extract audienceWatchRatio + relativeRetentionPerformance from raw retention data.
      # Returns ParsedCurve.new(curve: Array<Float>, rel_performance: Array<Float>).
      # Handles symbol keys (fresh API) and string keys (from DB cache).
      def parse_curve(data)
        return ParsedCurve.new(curve: [], rel_performance: []) unless data.is_a?(Array)

        curve    = []
        rel_perf = []
        data.each do |row|
          next unless row.is_a?(Hash)

          ratio = row[:audience_watch_ratio] || row["audience_watch_ratio"]
          rp    = row[:relative_retention_performance] || row["relative_retention_performance"]
          next if ratio.nil?

          curve    << ratio.to_f
          rel_perf << rp.to_f unless rp.nil?
        end
        ParsedCurve.new(curve:, rel_performance: rel_perf)
      end

      # Compute the views-weighted average retention curve across multiple videos.
      # All curves are linearly interpolated to the longest length for alignment.
      def views_weighted_average(curves, weights)
        target_length = curves.values.map(&:size).max.to_i
        return [] if target_length.zero?

        total_views = weights.values.sum.to_f

        result = Array.new(target_length, 0.0)
        curves.each do |vid_id, curve|
          w       = total_views > 0 ? weights[vid_id].to_f / total_views : (1.0 / curves.size)
          aligned = interpolate_curve(curve, target_length)
          aligned.each_with_index { |v, i| result[i] += v * w }
        end
        result
      end

      # Compute the views-weighted mean of relativeRetentionPerformance across multiple videos.
      # benchmarks: { vid_id => Array<Float> }  (per-video rel_performance arrays)
      # weights:    { vid_id => Integer }        (same keys as benchmarks)
      # Returns a Float (0.0..1.0) representing the weighted mean, or nil if no benchmark data.
      def views_weighted_benchmark(benchmarks, weights)
        non_empty = benchmarks.reject { |_, rp| rp.empty? }
        return nil if non_empty.empty?

        total_views = non_empty.keys.sum { |vid_id| weights[vid_id].to_i }.to_f

        non_empty.sum do |vid_id, rp_arr|
          mean_rp = rp_arr.sum / rp_arr.size.to_f
          w       = total_views > 0 ? weights[vid_id].to_f / total_views : (1.0 / non_empty.size)
          mean_rp * w
        end
      end

      # Thresholds for mapping relativeRetentionPerformance (0..1, ~0.5 = average) to a word.
      BENCHMARK_ABOVE_THRESHOLD = 0.55
      BENCHMARK_BELOW_THRESHOLD = 0.45

      # Map a relativeRetentionPerformance scalar to a benchmark word.
      # nil input → "typical" (no data = don't claim it's bad).
      def benchmark_word(rel_performance)
        return "typical" if rel_performance.nil?

        if rel_performance >= BENCHMARK_ABOVE_THRESHOLD
          "above average"
        elsif rel_performance <= BENCHMARK_BELOW_THRESHOLD
          "below average"
        else
          "typical"
        end
      end

      # Interpolate the retention series at ratio = total_pct / 100 to get the
      # audience watch ratio (%) at the avg-view-duration mark.
      # Uses linear interpolation identical to interpolate_curve.
      # Returns an Integer (whole %).
      def at_mark_pct(series, total_pct)
        return 0 if series.empty?

        ratio = (total_pct.to_f / 100.0).clamp(0.0, 1.0)
        n     = series.size
        return series.first.round if n <= 1

        src_f = ratio * (n - 1)
        lo    = src_f.floor
        hi    = [ src_f.ceil, n - 1 ].min
        frac  = src_f - lo
        (series[lo] * (1 - frac) + series[hi] * frac).round
      end

      # Linear interpolation to resize a curve to `target_length` points.
      def interpolate_curve(curve, target_length)
        return curve if curve.size == target_length
        return Array.new(target_length, curve.first.to_f) if curve.size <= 1

        target_length.times.map do |i|
          fraction = i.to_f / (target_length - 1)
          src_f    = fraction * (curve.size - 1)
          lo       = src_f.floor
          hi       = [ src_f.ceil, curve.size - 1 ].min
          frac     = src_f - lo
          curve[lo] * (1 - frac) + curve[hi] * frac
        end
      end

      # Normalize for DB storage (string keys, like Primitives.store).
      def normalize_data(data)
        case data
        when Array
          data.map { |row| row.is_a?(Hash) ? row.transform_keys(&:to_s) : row }
        when Hash
          data.transform_keys(&:to_s)
        else
          data
        end
      end

      def empty_result
        Result.new(series: [], total_pct: 0.0, rel_performance: nil)
      end
    end
  end
end
