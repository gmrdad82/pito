# frozen_string_literal: true

module Pito
  module Bench
    module Steps
      # Inventory — no timing, just the data-volume facts the caching phases
      # act on: conversation/event distribution, payload weight, primitive-row
      # temperature (warm / expired / frozen), accumulated-cache states, and
      # the REAL external-request volume from the api_requests audit table
      # (last 7 days, per provider).
      module Inventory
        module_function

        def label = "inventory"

        # @param _ctx [Pito::Bench::Runner::Ctx]
        # @return [Hash]
        def call(_ctx)
          conversations.merge(payloads, primitives, cache_rows, api_volume)
        end

        def conversations
          per_conv = ::Event.group(:conversation_id).count.values
          {
            "conversations"   => ::Conversation.count,
            "events"          => ::Event.count,
            "events_max/conv" => per_conv.max || 0,
            "events_avg/conv" => per_conv.empty? ? 0 : (per_conv.sum.to_f / per_conv.size).round(1)
          }
        end

        def payloads
          row = ::Event.pick(Arel.sql("AVG(octet_length(payload::text)), MAX(octet_length(payload::text))"))
          { "payload_avg_b" => row&.first.to_f.round, "payload_max_b" => row&.last.to_i }
        end

        def primitives
          scope = ::AnalyticsPrimitive
          {
            "primitives"         => scope.count,
            "primitives_frozen"  => scope.where(expires_at: nil).count,
            "primitives_warm"    => scope.where("expires_at > ?", Time.current).count,
            "primitives_expired" => scope.where("expires_at <= ?", Time.current).count
          }
        end

        def cache_rows
          {
            "analytics_cache"        => ::AnalyticsCache.count,
            "analytics_cache_ready"  => ::AnalyticsCache.where(status: "ready").count,
            "analytics_cache_failed" => ::AnalyticsCache.where(status: "failed").count
          }
        end

        # Real request volume, last 7 days, flattened per provider.
        def api_volume
          ::ApiRequest.where(created_at: 7.days.ago..)
                      .group(:provider)
                      .count
                      .transform_keys { |provider| "api_#{provider}_7d" }
        end
      end
    end
  end
end
