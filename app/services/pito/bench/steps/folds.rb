# frozen_string_literal: true

module Pito
  module Bench
    module Steps
      # Warm-fold bench — times the analytics fold services over WARM
      # `analytics_primitives` rows only (the network guard turns any cold
      # fetch into an error, reported as "n/a (cold/error)"). This is the pure
      # compute the L0.5 per-metric cell cache will amortize.
      #
      # The scope is derived from the freshest warm `daily` row: its subject
      # (a video id, or a channel id for channel-level rows) becomes a
      # one-subject group, and its exact (start_date, end_date, token) becomes
      # a duck window — guaranteeing Primitives.fetch hits warm.
      module Folds
        # analytics_primitives report → Breakdown metric symbol.
        BREAKDOWN_REPORTS = {
          "country"           => :geography,
          "device"            => :devices,
          "subscribed_status" => :subscribed_status,
          "demographics"      => :gender
        }.freeze

        module_function

        def label = "folds"

        # @param ctx [Pito::Bench::Runner::Ctx]
        # @return [Hash] avg ms per fold service (or "n/a …" markers)
        def call(ctx)
          n   = [ ctx.iterations, 1 ].max
          row = warm_row("daily")
          return { "skipped" => "no warm daily primitive" } if row.nil?

          groups = groups_for(row)
          return { "skipped" => "no scope for warm subject #{row.video_youtube_id}" } if groups.nil?

          window  = duck_window(row)
          metrics = {
            "subject"              => row.video_youtube_id,
            "window"               => "#{row.start_date}..#{row.end_date}",
            "daily_series_avg_ms"  => fold_avg(n) { Pito::Analytics::DailySeries.for(groups:, window:) },
            "adaptive_avg_ms"      => fold_avg(n) { Pito::Analytics::AdaptiveSeries.for(groups:, window:) },
            "weekday_avg_ms"       => fold_avg(n) { Pito::Analytics::WeekdaySeries.for(groups:, window:) }
          }
          metrics.merge(breakdown_benches(n, groups)).merge(retention_bench(n, groups))
        end

        # ── benches ───────────────────────────────────────────────────────────

        def breakdown_benches(n, groups)
          BREAKDOWN_REPORTS.each_with_object({}) do |(report, metric), h|
            row = warm_row(report)
            next h["breakdown_#{metric}_avg_ms"] = "n/a (no warm row)" if row.nil?

            window = duck_window(row)
            h["breakdown_#{metric}_avg_ms"] = fold_avg(n) do
              Pito::Analytics::Breakdown.for(metric:, groups:, window:)
            end
          end
        end

        def retention_bench(n, groups)
          row = warm_row("retention")
          return { "retention_avg_ms" => "n/a (no warm row)" } if row.nil?

          window = duck_window(row)
          { "retention_avg_ms" => fold_avg(n) { Pito::Analytics::RetentionSeries.for(groups:, window:) } }
        end

        # Each fold gets its own rescue: a cold subject inside a fold raises the
        # network guard's BlockedError — reported, never fatal to the step.
        def fold_avg(n)
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          n.times { yield }
          (((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000) / n).round(3)
        rescue StandardError => e
          "n/a (#{e.class})"
        end

        # ── scope construction from a warm row ────────────────────────────────

        def warm_row(report)
          ::AnalyticsPrimitive.where(report:)
                              .where("expires_at IS NULL OR expires_at > ?", Time.current)
                              .order(fetched_at: :desc)
                              .first
        end

        # One-subject group so every fold stays inside warm rows: a channel-level
        # subject (`video_youtube_id` holds a channel id) → [channel, :channel];
        # a video subject → [its channel, [video id]].
        def groups_for(row)
          sid = row.video_youtube_id
          if (channel = ::Channel.find_by(youtube_channel_id: sid))
            [ [ channel, :channel ] ]
          elsif (video = ::Video.find_by(youtube_video_id: sid))
            video.channel ? [ [ video.channel, [ sid ] ] ] : nil
          end
        end

        # Duck window matching the row's exact range — same interface
        # Primitives.fetch needs (start_date / end_date / token / expires_at_for).
        def duck_window(row)
          Pito::Analytics::Window::PreviousRange.new(
            start_date: row.start_date, end_date: row.end_date, token: row.period_token
          )
        end
      end
    end
  end
end
