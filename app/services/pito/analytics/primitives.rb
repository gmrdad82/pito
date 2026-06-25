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

      # @param groups [Array<[Channel, Array<String>]>] (channel, youtube_video_ids)
      # @param window [Pito::Analytics::Window]
      # @param report [String]
      # @param now    [Time] treated as "now" for TTL computation
      # @return [Hash{String => Hash/Array}] youtube_video_id → raw metrics
      def fetch(groups:, window:, report: "scalars", now: Time.current)
        report = report.to_s
        method = REPORT_METHODS.fetch(report) do
          raise ArgumentError, "unsupported primitives report: #{report.inspect}"
        end

        groups.each_with_object({}) do |(channel, subjects), acc|
          next if channel.nil?

          if subjects == :channel
            sid = channel.youtube_channel_id
            acc[sid] = primitive_for(channel:, subject_id: sid, videos: nil, report:, method:, window:, now:)
          else
            Array(subjects).each do |vid|
              acc[vid] = primitive_for(channel:, subject_id: vid, videos: [ vid ], report:, method:, window:, now:)
            end
          end
        end
      end

      def primitive_for(channel:, subject_id:, videos:, report:, method:, window:, now:)
        warm = AnalyticsPrimitive.find_by(
          video_youtube_id: subject_id, report:, start_date: window.start_date, end_date: window.end_date
        )
        return warm.metrics if warm&.live?

        metrics = client(channel).public_send(
          method,
          channel_id: channel.youtube_channel_id,
          start_date: window.start_date,
          end_date:   window.end_date,
          videos:     videos
        )
        store(subject_id:, report:, window:, metrics:, now:).metrics
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
