# frozen_string_literal: true

require "digest/md5"

module Pito
  module Analytics
    # Aggregated scalar metrics for a scope (a Video, a Game's linked videos, or
    # a Channel) over a period window, with the prior comparable window so the
    # view layer can render trends.
    #
    #   result = Pito::Analytics::Scalars.for(scope: video, period: "28d")
    #   result.metrics[:views]   # => { current: 1234, previous: 1000 }
    #   result.comparable        # => true   (false for a lifetime window)
    #   result.label             # => "28d"
    #
    # Additive metrics (views, watch-minutes, subs gained/lost, likes, dislikes,
    # comments) are summed across the scope's channels; ratio metrics (avg view
    # duration, avg viewed %) are views-weighted. A game's linked videos can span
    # channels, and `scalars` is one-channel-per-call, so we group by channel and
    # fan out (the SyncVideosJob / AchievementsRefreshJob pattern).
    #
    # Returns :unavailable when the scope has no usable (connected, non-reauth)
    # channel, or the YouTube Analytics API errors.
    module Scalars
      DEFAULT_PERIOD = "28d"
      CACHE_TTL      = 1.hour
      UNAVAILABLE    = :unavailable

      # Output metric keys, in kv-table render order.
      KEYS = %i[
        views watched_hours avg_view_duration avg_viewed_pct
        subs_gained subs_lost likes dislikes comments
      ].freeze

      Result = Data.define(:metrics, :label, :comparable)

      module_function

      def for(scope:, period: nil)
        window = Pito::Analytics::Window.for(period.presence || DEFAULT_PERIOD, reference_date: Date.current)
        groups = channel_groups(scope)
        return UNAVAILABLE if groups.blank?

        payload = Pito::Analytics::Cache.fetch(signature(scope, window, groups), ttl: CACHE_TTL) do
          compute(groups, window)
        end
        build_result(payload, window)
      rescue StandardError => e
        Rails.logger.warn("[Analytics::Scalars] #{scope.class}##{scope.try(:id)}: #{e.class}: #{e.message}")
        UNAVAILABLE
      end

      # ── scope → [[channel, [youtube_video_id, …]], …] ─────────────────────────

      def channel_groups(scope)
        case scope
        when ::Video
          ch = scope.channel
          usable?(ch) ? [ [ ch, [ scope.youtube_video_id ] ] ] : []
        when ::Game
          scope.linked_videos.includes(:channel).group_by(&:channel).filter_map do |ch, vids|
            next unless usable?(ch)

            ids = vids.filter_map(&:youtube_video_id)
            next if ids.empty?

            [ ch, ids ]
          end
        when ::Channel
          usable?(scope) ? [ [ scope, [] ] ] : [] # [] videos → whole channel, no filter
        else
          []
        end
      end

      def usable?(channel)
        conn = channel&.youtube_connection
        conn.present? && !conn.needs_reauth
      end

      # ── aggregation ───────────────────────────────────────────────────────────

      def compute(groups, window)
        current  = aggregate(groups, window.start_date, window.end_date)
        previous = window.comparable? ? aggregate(groups, window.prev_start, window.prev_end) : nil

        metrics = KEYS.each_with_object({}) do |key, h|
          h[key.to_s] = { "current" => current[key], "previous" => previous && previous[key] }
        end
        { "metrics" => metrics }
      end

      def aggregate(groups, start_date, end_date)
        sums         = Hash.new(0)
        weighted_dur = 0.0
        weighted_pct = 0.0
        views_total  = 0

        groups.each do |channel, video_ids|
          row = ::Channel::Youtube::AnalyticsClient
            .new(channel.youtube_connection)
            .scalars(channel_id: channel.youtube_channel_id, start_date:, end_date:, videos: video_ids.presence)
          next if row.blank?

          v = row[:views].to_i
          views_total                      += v
          sums[:views]                     += v
          sums[:estimated_minutes_watched] += row[:estimated_minutes_watched].to_i
          sums[:subscribers_gained]        += row[:subscribers_gained].to_i
          sums[:subscribers_lost]          += row[:subscribers_lost].to_i
          sums[:likes]                     += row[:likes].to_i
          sums[:dislikes]                  += row[:dislikes].to_i
          sums[:comments]                  += row[:comments].to_i
          weighted_dur                     += row[:average_view_duration].to_f * v
          weighted_pct                     += row[:average_view_percentage].to_f * v
        end

        {
          views:             sums[:views],
          watched_hours:     (sums[:estimated_minutes_watched] / 60.0).round(1),
          avg_view_duration: views_total.positive? ? (weighted_dur / views_total).round : 0,
          avg_viewed_pct:    views_total.positive? ? (weighted_pct / views_total).round(1) : 0.0,
          subs_gained:       sums[:subscribers_gained],
          subs_lost:         sums[:subscribers_lost],
          likes:             sums[:likes],
          dislikes:          sums[:dislikes],
          comments:          sums[:comments]
        }
      end

      def build_result(payload, window)
        metrics = payload.fetch("metrics").each_with_object({}) do |(key, vals), h|
          h[key.to_sym] = { current: vals["current"], previous: vals["previous"] }
        end
        Result.new(metrics:, label: window.label, comparable: window.comparable?)
      end

      def signature(scope, window, groups)
        vid_ids = groups.flat_map { |_ch, ids| ids }.sort
        digest  = Digest::MD5.hexdigest(vid_ids.join(","))
        "scalars:#{scope.class.name}:#{scope.id}:#{window.token}:#{window.start_date}:#{window.end_date}:#{digest}"
      end
    end
  end
end
