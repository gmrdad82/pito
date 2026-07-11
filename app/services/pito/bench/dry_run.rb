# frozen_string_literal: true

module Pito
  module Bench
    # Dry-run interception for the cold-path counter step: runs the REAL
    # glance/analyze fill code while counting — instead of firing — YouTube
    # Analytics requests.
    #
    # Three surgical prepends, inert unless `active?` (same pattern as
    # NetworkGuard):
    #
    #   * `Channel::Youtube::AnalyticsClient#query` — the single funnel every
    #     report method (scalars/daily/by_*/demographics/retention) goes
    #     through. Counts the call and returns one FAKE_ROW so the calling
    #     fold keeps walking its full request plan (an empty response would
    #     short-circuit e.g. MetricFill before its series request).
    #   * `Pito::Analytics::Primitives.store` — returns an UNSAVED
    #     AnalyticsPrimitive (`.metrics` intact) so cold fetch paths complete
    #     without writing (the runner's read-only session would refuse).
    #   * `Pito::Analytics::RetentionSeries.store_primitive` — same, no-op.
    #
    # Usage:
    #   counts = Pito::Bench::DryRun.capture { …run fills… }
    #   counts # => { "requests" => 12, "by_report" => { "views…" => 2, … } }
    module DryRun
      # Symbol-keyed like real query rows; every metric the folds read, one
      # plausible value each, so sums/weights stay finite. `day: nil` rows are
      # skipped by daily folds without aborting the plan walk.
      FAKE_ROW = {
        day: nil, views: 1, estimated_minutes_watched: 60, average_view_duration: 60.0,
        average_view_percentage: 40.0, subscribers_gained: 1, subscribers_lost: 0,
        likes: 1, dislikes: 0, comments: 0
      }.freeze

      module ClientCounter
        def query(**kwargs)
          return super unless Pito::Bench::DryRun.active?

          Pito::Bench::DryRun.record!(kwargs)
          Pito::Bench::DryRun.fake_rows(kwargs)
        end
      end

      # Store → VIRTUAL warm row (per capture), so within one counted command
      # the second metric folds warm exactly as it would in production (where
      # the first metric's fetch persists). Without this, every metric re-counts
      # the same subjects cold and the totals overstate reality.
      module PrimitivesStoreStub
        def store(subject_id:, report:, window:, metrics:, now:)
          return super unless Pito::Bench::DryRun.active?

          normalized = Pito::Analytics::Primitives.normalize(metrics)
          Pito::Bench::DryRun.put_virtual(subject_id:, report:, window:, metrics: normalized)
          ::AnalyticsPrimitive.new(metrics: normalized)
        end
      end

      # Warm lookup honors the capture's virtual rows before the real table —
      # intercepts the ONE lookup helper both the single and batched paths use.
      module PrimitivesVirtualWarm
        def warm_metrics_for(subject_id:, report:, window:, require_keys: [])
          if Pito::Bench::DryRun.active?
            virtual = Pito::Bench::DryRun.virtual(subject_id:, report:, window:)
            return virtual unless virtual.nil?
          end
          super
        end
      end

      # Retention keeps its own store/lookup pair (single-video reports) — mirror
      # the virtual-warm treatment so a repeat analyze counts 0 for retention,
      # exactly as the persisted row would behave in production.
      module RetentionStoreStub
        def store_primitive(video_id:, lifetime_window:, data:, now:)
          return super unless Pito::Bench::DryRun.active?

          Pito::Bench::DryRun.put_virtual(
            subject_id: video_id, report: "retention", window: lifetime_window, metrics: data
          )
          nil
        end
      end

      module RetentionFetchStub
        def fetch_and_store(channel:, video_id:, lifetime_window:, now:)
          if Pito::Bench::DryRun.active?
            virtual = Pito::Bench::DryRun.virtual(subject_id: video_id, report: "retention", window: lifetime_window)
            return virtual unless virtual.nil?
          end
          super
        end
      end

      @active    = false
      @installed = false
      @counts    = nil
      MUTEX      = Mutex.new

      module_function

      def active?
        @active
      end

      # Runs the block with counting interception; returns the counts Hash.
      def capture
        install!
        @counts  = { "requests" => 0, "by_report" => Hash.new(0) }
        @virtual = {}
        @active  = true
        yield
        @counts
      ensure
        @active = false
      end

      # Counter/virtual-store access is mutex-guarded: cold fetches fan out
      # over Primitives' bounded thread pool.
      def record!(kwargs)
        MUTEX.synchronize do
          @counts["requests"] += 1
          key = [ kwargs[:metrics], kwargs[:dimensions] ].compact.join("/")
          @counts["by_report"][key] += 1
        end
      end

      # Running total inside an open capture — lets a scenario split its count
      # into first-run vs repeat-run segments (the warm-reuse assertion).
      def current_total
        MUTEX.synchronize { @counts ? @counts["requests"] : 0 }
      end

      # Video-DIMENSIONED queries (the batched scalars path) must return one
      # row per filtered video WITH its `:video` key — otherwise the batch
      # stores empty rows and downstream folds short-circuit, hiding the very
      # requests the counter exists to count (e.g. the glance's daily fetches).
      def fake_rows(kwargs)
        ids = kwargs[:filters].to_s[/video==([^;]+)/, 1]&.split(",")
        if kwargs[:dimensions].to_s.include?("video") && ids
          ids.map { |id| FAKE_ROW.merge(video: id) }
        else
          [ FAKE_ROW.dup ]
        end
      end

      def put_virtual(subject_id:, report:, window:, metrics:)
        MUTEX.synchronize do
          @virtual[[ subject_id, report.to_s, window.start_date, window.end_date ]] = metrics
        end
      end

      def virtual(subject_id:, report:, window:)
        MUTEX.synchronize do
          @virtual[[ subject_id, report.to_s, window.start_date, window.end_date ]]
        end
      end

      def install!
        return if @installed

        ::Channel::Youtube::AnalyticsClient.prepend(ClientCounter)
        Pito::Analytics::Primitives.singleton_class.prepend(PrimitivesStoreStub)
        Pito::Analytics::Primitives.singleton_class.prepend(PrimitivesVirtualWarm)
        Pito::Analytics::RetentionSeries.singleton_class.prepend(RetentionStoreStub)
        Pito::Analytics::RetentionSeries.singleton_class.prepend(RetentionFetchStub)
        @installed = true
      end
    end
  end
end
