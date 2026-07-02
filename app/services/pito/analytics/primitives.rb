# frozen_string_literal: true

module Pito
  module Analytics
    # Per-video primitive fetch + cache. Resolves a set of (channel, video) pairs
    # for ONE report over ONE window into raw-count metrics: reads warm rows from
    # `analytics_primitives`, and fetches ONLY the cold ones from YouTube (one
    # atomic request per cold video), storing each with a Window-derived TTL
    # (finalized periods → frozen forever; live windows → 1h).
    #
    #   Primitives.fetch(groups: [[channel, %w[ytid1 ytid2]]], report: "scalars", window:)
    #   # => { "ytid1" => { "views" => 12, … }, "ytid2" => { … } }
    #
    # A group's second element is either an Array of youtube_video_ids (per-video
    # primitives — vid/game scope) OR the symbol `:channel` (channel-level scope:
    # one channel-wide primitive, client call with no video filter, keyed by the
    # channel's youtube_channel_id). Channel-level is NOT the sum of a channel's
    # vids — subs aren't all video-attributable and channel-wide covers unsynced/
    # deleted videos — so it's fetched directly (FORK-B / B1). The
    # `video_youtube_id` column therefore holds a "subject id" (a video id, or a
    # channel id for channel-level rows).
    #
    # Metrics are returned with STRING keys (matching the jsonb round-trip) so warm
    # and cold reads are interchangeable. Per-subject YouTube errors propagate to the
    # caller — the fan-out job (Phase 3) owns retry / failure surfacing.
    module Primitives
      # report → AnalyticsClient method (videos:-filtered, per single video).
      # NOTE: `retention` is single-video via `video:` (not `videos:`) and is
      # handled by a dedicated path in Phase 3 — not listed here.
      REPORT_METHODS = {
        "scalars"           => :scalars,
        "daily"             => :daily,
        "country"           => :by_country,
        "device"            => :by_device,
        "subscribed_status" => :by_subscribed_status,
        "demographics"      => :demographics
      }.freeze

      module_function

      # @param groups       [Array<[Channel, Array<String>]>] (channel, youtube_video_ids)
      # @param window       [Pito::Analytics::Window]
      # @param report       [String]
      # @param now          [Time] treated as "now" for TTL computation
      # @param require_keys [Array<String>] metric keys a warm row must carry to
      #   count as warm — rows stored before a report gained a metric (e.g. the
      #   daily report's `likes`, 0.9.0) lack the key and refetch ONCE, after
      #   which the row carries the full current metric set.
      # @return [Hash{String => Hash/Array}] youtube_video_id → raw metrics
      def fetch(groups:, window:, report: "scalars", now: Time.current, require_keys: [])
        report = report.to_s
        method = REPORT_METHODS.fetch(report) do
          raise ArgumentError, "unsupported primitives report: #{report.inspect}"
        end

        groups.each_with_object({}) do |(channel, subjects), acc|
          next if channel.nil?

          if subjects == :channel
            sid = channel.youtube_channel_id
            acc[sid] = primitive_for(channel:, subject_id: sid, videos: nil, report:, method:, window:, now:, require_keys:)
          elsif report == "scalars" && Array(subjects).many?
            # Batched cold path (0.9.0 Phase 3): all of a group's cold videos in
            # one dimensions=video request per ≤200-slice instead of one request
            # each. Only `scalars` batches — the API has no video-dimensioned
            # daily/breakdown reports (see 0.9.0.md T3.1 findings).
            acc.merge!(batched_scalars(channel:, ids: Array(subjects), window:, now:, require_keys:))
          else
            # Un-batchable reports (daily/breakdowns — per-video by API design):
            # cold subjects fetch CONCURRENTLY under a bounded pool instead of
            # serially (0.9.0 Phase 3). Warm subjects never spawn a thread.
            acc.merge!(parallel_primitives(channel:, ids: Array(subjects), report:, method:, window:, now:, require_keys:))
          end
        end
      end

      # Max ids per batched scalars request — the Top-videos report row cap.
      SCALARS_BATCH_SIZE = 200

      def batched_scalars(channel:, ids:, window:, now:, require_keys:)
        result = {}
        cold   = ids.reject do |vid|
          warm = warm_metrics_for(subject_id: vid, report: "scalars", window:, require_keys:)
          result[vid] = warm unless warm.nil?
          !warm.nil?
        end

        cold.each_slice(SCALARS_BATCH_SIZE) do |slice|
          rows = client(channel).scalars_by_video(
            channel_id: channel.youtube_channel_id,
            start_date: window.start_date,
            end_date:   window.end_date,
            videos:     slice
          )
          by_vid = rows.group_by { |r| r[:video].to_s }
          slice.each do |vid|
            # No row = no activity in range — store {} so the emptiness is warm
            # too (matching the aggregate #scalars "rows.first || {}" shape).
            metrics = (by_vid[vid.to_s]&.first || {}).except(:video)
            result[vid] = store(subject_id: vid, report: "scalars", window:, metrics:, now:).metrics
          end
        end
        result
      end

      # Bounded concurrency for cold per-video fetches. Specs run sequential
      # (see spec/support/analytics_primitives.rb) — threaded writes would
      # escape the per-example transaction.
      MAX_FETCH_CONCURRENCY = 4

      def max_concurrency
        @max_concurrency || MAX_FETCH_CONCURRENCY
      end

      def max_concurrency=(value)
        @max_concurrency = value
      end

      # Warm subjects answer inline; cold ones fan out over a bounded thread
      # pool (one client instance per fetch — never shared). The FIRST error
      # aborts the remaining queue and re-raises after join, preserving the
      # sequential path's propagate-to-caller semantics.
      def parallel_primitives(channel:, ids:, report:, method:, window:, now:, require_keys:)
        result = {}
        cold   = ids.reject do |vid|
          warm = warm_metrics_for(subject_id: vid, report:, window:, require_keys:)
          result[vid] = warm unless warm.nil?
          !warm.nil?
        end
        return result if cold.empty?

        workers = [ max_concurrency, cold.size ].min
        if workers <= 1
          cold.each { |vid| result[vid] = fetch_and_store_one(channel:, subject_id: vid, videos: [ vid ], report:, method:, window:, now:) }
          return result
        end

        queue = Queue.new
        cold.each { |vid| queue << vid }
        mutex = Mutex.new
        error = nil

        threads = Array.new(workers) do
          Thread.new do
            Rails.application.executor.wrap do
              while (vid = pop_nonblock(queue))
                begin
                  metrics = fetch_and_store_one(channel:, subject_id: vid, videos: [ vid ], report:, method:, window:, now:)
                  mutex.synchronize { result[vid] = metrics }
                rescue StandardError => e
                  mutex.synchronize { error ||= e }
                  break
                end
              end
            end
          end
        end
        threads.each(&:join)
        raise error if error

        result
      end

      def pop_nonblock(queue)
        queue.pop(true)
      rescue ThreadError
        nil
      end

      def primitive_for(channel:, subject_id:, videos:, report:, method:, window:, now:, require_keys: [])
        warm = warm_metrics_for(subject_id:, report:, window:, require_keys:)
        return warm unless warm.nil?

        fetch_and_store_one(channel:, subject_id:, videos:, report:, method:, window:, now:)
      end

      def fetch_and_store_one(channel:, subject_id:, videos:, report:, method:, window:, now:)
        metrics = client(channel).public_send(
          method,
          channel_id: channel.youtube_channel_id,
          start_date: window.start_date,
          end_date:   window.end_date,
          videos:     videos
        )
        store(subject_id:, report:, window:, metrics:, now:).metrics
      end

      # The ONE warm lookup both the single and batched paths use (and the
      # bench dry-run intercepts for its virtual store).
      def warm_metrics_for(subject_id:, report:, window:, require_keys: [])
        warm = AnalyticsPrimitive.find_by(
          video_youtube_id: subject_id, report:, start_date: window.start_date, end_date: window.end_date
        )
        return warm.metrics if warm&.live? && keys_satisfied?(warm.metrics, require_keys)

        nil
      end

      def store(subject_id:, report:, window:, metrics:, now:)
        row = AnalyticsPrimitive.find_or_initialize_by(
          video_youtube_id: subject_id, report:, start_date: window.start_date, end_date: window.end_date
        )
        row.assign_attributes(
          period_token: window.token,
          metrics:      normalize(metrics),
          fetched_at:   now,
          expires_at:   window.expires_at_for(now:)
        )
        row.save!
        row
      rescue ActiveRecord::RecordNotUnique
        # A concurrent fan-out won the unique index; reuse its row.
        AnalyticsPrimitive.find_by!(
          video_youtube_id: subject_id, report:, start_date: window.start_date, end_date: window.end_date
        )
      end

      # True when the stored metrics carry every required key. An EMPTY array
      # (a window with genuinely no data rows) can't be inspected — treat it as
      # satisfied; refetching would return the same emptiness.
      def keys_satisfied?(metrics, require_keys)
        return true if require_keys.empty?

        case metrics
        when Hash  then require_keys.all? { |k| metrics.key?(k) }
        when Array then metrics.empty? || metrics.any? { |row| row.is_a?(Hash) && require_keys.all? { |k| row.key?(k) } }
        else true
        end
      end

      def client(channel)
        ::Channel::Youtube::AnalyticsClient.new(channel.youtube_connection)
      end

      # jsonb stores string keys; normalize so warm + cold reads are identical.
      def normalize(metrics)
        case metrics
        when Hash  then metrics.deep_stringify_keys
        when Array then metrics.map { |row| row.respond_to?(:deep_stringify_keys) ? row.deep_stringify_keys : row }
        else metrics
        end
      end
    end
  end
end
