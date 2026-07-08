# frozen_string_literal: true

module Pito
  module Mcp
    # Inline analytics compute for the read-only MCP surface. pito's analyze / glance
    # / channel-distribution verbs emit a PENDING marker that a background job fills
    # over the cable — but MCP is pull-only and never runs those jobs, so a raw
    # Router Result would hand the caller an unfilled scaffold. This module detects
    # each pending family and computes the numbers SYNCHRONOUSLY via the SAME
    # services the jobs use, replacing the pending event with a clean, EventText-
    # friendly payload (a heading + `metrics` / `bars` / a list).
    #
    # THREE families (the Finalizer completion gate is authoritative):
    #   * "analytics"            → glance / at-a-glance   → Pito::Analytics::Scalars
    #   * "analyze"              → analyze / breakdowns   → Pito::Analytics::AnalyzeMetricFill
    #   * "channel_distribution" → channels               → Game::ChannelDistribution
    #
    # READ-ONLY: the compute services read (and may warm Rails.cache — allowed); this
    # module itself never persists or enqueues. Pending detection digs the payload
    # directly (the builders' `pending?` predicates take a persisted Event; MCP holds
    # raw `{kind:, payload:}` hashes).
    module AnalyticsFill
      module_function

      # Map each event through its family filler; non-analytics events pass through.
      def call(events)
        Array(events).map { |event| fill(event) }
      end

      def fill(event)
        payload = indifferent(event_payload(event))
        return event unless payload.is_a?(Hash)

        return glance(event, payload[:analytics])              if pending?(payload[:analytics])
        return analyze(event, payload[:analyze])               if pending?(payload[:analyze])
        return distribution(event, payload[:channel_distribution]) if pending?(payload[:channel_distribution])

        event
      end

      # ── Family 1 — glance (Scalars) ────────────────────────────────────────────

      # Scalars metric keys in a readable order (a superset of the glance card's
      # curated five — an LLM benefits from the whole scalar picture).
      GLANCE_KEYS = %i[
        views watched_hours avg_view_duration avg_viewed_pct
        subs_gained subs_lost likes dislikes comments
      ].freeze

      def glance(event, marker)
        records = load_records(marker)
        return note(event, "Analytics unavailable — the entity is no longer present.") if records.empty?

        scope  = records.one? ? records.first : records
        result = Pito::Analytics::Scalars.for(scope: scope, period: marker[:period])
        return note(event, unavailable_note) if result == Pito::Analytics::Scalars::UNAVAILABLE

        replace(event, text: heading(records, marker[:period]), metrics: glance_metrics(result))
      end

      def glance_metrics(result)
        GLANCE_KEYS.each_with_object({}) do |key, out|
          cell = result.metrics[key]
          next if cell.nil?

          out[key.to_s.tr("_", " ")] = format_metric(key, cell[:current])
        end
      end

      def format_metric(key, value)
        return "—" if value.nil?

        case key
        when :avg_view_duration then format_duration(value)
        when :avg_viewed_pct    then "#{value}%"
        else                         value.to_s
        end
      end

      def format_duration(seconds)
        s = seconds.to_i
        format("%d:%02d", s / 60, s % 60)
      end

      # ── Family 2 — analyze / breakdowns (AnalyzeMetricFill) ────────────────────

      # The marker names the fan-out metric set for this role+level. Each metric is
      # computed by the same service the AnalyzeMetricJob uses; a "charts" slot
      # yields a scalar total (metrics line), a "bars" slot yields breakdown
      # percentages (bars → % lists). Heatmap/likes slots have no scalar → skipped.
      def analyze(event, marker)
        level      = marker[:level]
        entity_ids = Array(marker[:entity_ids]).compact
        period     = marker[:period]
        metrics    = {}
        bars       = {}

        Array(marker[:metric_keys]).map(&:to_sym).each do |metric|
          filled = Pito::Analytics::AnalyzeMetricFill.for(metric:, level:, entity_ids:, period:)
          raw    = filled&.raw
          next if raw.nil?

          case raw["slot"]
          when "charts"
            total = chart_total(raw["data"])
            metrics[metric.to_s.tr("_", " ")] = total unless total.nil?
          when "bars"
            bars[metric.to_s.tr("_", " ")] = Array(raw["data"])
          end
        end

        payload = { "text" => analyze_heading(marker) }
        payload["metrics"] = metrics if metrics.any?
        payload["bars"]    = bars    if bars.any?
        { kind: event_kind(event), payload: payload }
      end

      # A chart's scalar: the plain `total`, or a retention-style `total_pct`.
      def chart_total(data)
        return nil unless data.is_a?(Hash)
        return data["total"].to_s if data.key?("total")
        return "#{data['total_pct']}%" if data.key?("total_pct")

        nil
      end

      def analyze_heading(marker)
        title  = marker[:title].presence || "your channels"
        period = marker[:period].presence || "lifetime"
        "Analytics for #{title} (#{period}):"
      end

      # ── Family 3 — channel distribution (Game::ChannelDistribution) ────────────

      # Replicates ChannelDistributionFillJob#fill: the top-N covering channels
      # (Recommendations) blended by videos/views/watch-hours into a 0–100 share
      # each. Projected as a readable list rather than the two-column HTML card.
      def distribution(event, marker)
        game = ::Game.find_by(id: marker[:game_id])
        return note(event, "Channel distribution unavailable — the game is no longer present.") if game.nil?

        shares = compute_shares(game)
        return note(event, "No channels cover #{game.title} yet.") if shares.blank?

        note(event, distribution_text(game, shares))
      end

      def compute_shares(game)
        channels = Pito::Recommendations.channels_for(game, include_all: true)
                                        .first(Pito::Games::ChannelsComponent::TOP_N)
                                        .map(&:channel)
        return [] if channels.empty?

        channel_ids = channels.map(&:id)
        covering    = game.linked_videos.select { |v| channel_ids.include?(v.channel_id) }
        watch_hours = ::Game::ChannelWatchTime.hours_for(videos: covering)
        result      = ::Game::ChannelDistribution.call(game: game, channels: channels, watch_hours: watch_hours)
        result[:nodata] ? [] : result[:shares]
      end

      def distribution_text(game, shares)
        lines = shares.map do |s|
          "- #{entity_label(s.channel)}: #{s.share}% (#{s.raw[:videos]} vids, #{s.raw[:views]} views)"
        end
        "Channels covering #{game.title}:\n#{lines.join("\n")}"
      end

      # ── scope loading + labels ─────────────────────────────────────────────────

      SCOPE_CLASSES = { "Video" => "Video", "Game" => "Game", "Channel" => "Channel" }.freeze
      PLURALS       = { "Video" => "vids", "Game" => "games", "Channel" => "channels" }.freeze

      # marker → the loaded records (single scope_id OR a scope_ids set), preserving
      # the requested id order; [] when the type is unknown or nothing resolves.
      def load_records(marker)
        klass = scope_class(marker[:scope_type])
        return [] unless klass

        ids = Array(marker[:scope_ids].presence || marker[:scope_id]).compact
        return [] if ids.empty?

        by_id = klass.where(id: ids).index_by(&:id)
        ids.filter_map { |id| by_id[id.to_i] || by_id[id] }
      end

      def scope_class(type)
        name = SCOPE_CLASSES[type.to_s]
        name && Object.const_get(name)
      end

      def heading(records, period)
        label = records.one? ? entity_label(records.first) : "#{records.size} #{PLURALS.fetch(records.first.class.name, 'items')}"
        "Analytics for #{label} (#{period}):"
      end

      def entity_label(record)
        record.respond_to?(:at_handle) && record.at_handle.present? ? record.at_handle : record.try(:title).to_s
      end

      def unavailable_note
        "Analytics unavailable — no connected channel, or the YouTube Analytics API is unreachable."
      end

      # ── event rewriting ────────────────────────────────────────────────────────

      def replace(event, text:, metrics:)
        { kind: event_kind(event), payload: { "text" => text, "metrics" => metrics } }
      end

      def note(event, text)
        { kind: event_kind(event), payload: { "text" => text } }
      end

      # ── predicates / accessors ─────────────────────────────────────────────────

      def pending?(marker)
        marker.is_a?(Hash) && marker[:status].to_s == "pending"
      end

      def event_payload(event)
        return {} unless event.respond_to?(:[])

        event[:payload] || event["payload"] || {}
      end

      def event_kind(event)
        event[:kind] || event["kind"] || :system
      end

      def indifferent(obj)
        obj.is_a?(Hash) ? obj.with_indifferent_access : obj
      end
    end
  end
end
