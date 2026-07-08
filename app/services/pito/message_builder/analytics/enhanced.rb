# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Analytics
      # Builds the analytics `:enhanced` message for show video / show game, in
      # two states:
      #
      #   .pending(scope, period:)  — emitted INSTANTLY: a 50-variant Pito::Copy
      #     intro (with the inline timestamp slot, like the detail cards) plus an
      #     `analytics` marker the AnalyticsFillJob reads. No data yet; the
      #     thinking spinner stays up.
      #
      #   .ready_payload(...)       — written by AnalyticsFillJob once the scalars
      #     are fetched: the same (stored) intro + the kv-table panel. On
      #     :unavailable it's intro + a brief note.
      #
      # Both states render via EnhancedComponent (html), whose intro carries the
      # `data-pito-ts-slot` so the timestamp lands inline (BodyComponent fills it)
      # rather than dropping to its own row. The intro chosen at pending time is
      # stored in the marker and reused on ready so it never changes under the
      # user. Payload keys are strings so they round-trip through jsonb unchanged.
      module Enhanced
        extend Pito::MessageBuilder::Helpers
        module_function

        # True when a persisted event carries an analytics marker still in its
        # pending state. Single canonical predicate shared by ChatDispatchJob,
        # AnalyticsFillJob, and FollowUpDispatchJob.
        def pending?(event)
          event.payload.is_a?(Hash) && event.payload.dig("analytics", "status") == "pending"
        end

        # `scope` is a single Video/Game/Channel OR an Array of same-level records
        # (multi-id `at-a-glance videos 2,3,4` → one combined glance over the set).
        def pending(scope, period: nil, conversation: nil)
          # The glance always shows lifetime data — force "lifetime" regardless of
          # the period arg (which may come from the user's `show` context).
          glance_period = "lifetime"
          token         = SecureRandom.hex(4)
          intro = Pito::Copy.render_html("pito.copy.analytics.intro", { title: scope_title(scope) }, shimmer: [ :title ])
          payload = {
            "body"      => render_component(Pito::Analytics::EnhancedComponent.new(intro: intro, pending: true, token: token)),
            "html"      => true,
            "anchor"    => true, # stable event_<id> DOM id for replace_event + the handle
            "analytics" => marker("pending", scope: scope, period: glance_period, intro: intro, token: token)
          }
          # Followupable: replying `with`/`without` to the glance spawns a NEW analyze
          # pair on this entity (handled by FollowUp::Handlers::AnalyticsGlance).
          return payload if conversation.nil?

          Pito::FollowUp.make_followupable!(payload, target: "analytics_glance", conversation:)
        end

        def ready_payload(scope:, period:, result:, intro:, series: {}, token: nil)
          {
            "body"      => render_component(Pito::Analytics::EnhancedComponent.new(intro: intro, result: result, nudge: nudge_for(scope), series: series, token: token)),
            "html"      => true,
            "anchor"    => true,
            "analytics" => marker("ready", scope: scope, period: period, intro: intro)
          }
        end

        # The witty "use `analyze` for more" nudge — vid / game / channel-specific.
        # nil for any other scope.
        def nudge_for(scope)
          case scope
          when ::Game    then Pito::Copy.render("pito.copy.analytics.suggest.game")
          when ::Video   then Pito::Copy.render("pito.copy.analytics.suggest.video")
          when ::Channel then Pito::Copy.render("pito.copy.analytics.suggest.channel")
          end
        end

        # Single scope → scope_id; a set → scope_ids (both derive scope_type from the
        # member class, so the fill job reconstructs the right entity/entities).
        def marker(status, scope:, period:, intro:, token: nil)
          multi = scope.is_a?(Array)
          {
            "status"      => status,
            "scope_type"  => (multi ? scope.first : scope)&.class&.name,
            "scope_id"    => multi ? nil : scope&.id,
            "scope_ids"   => multi ? scope.map(&:id) : nil,
            "period"      => period,
            "intro"       => intro,
            "token"       => token,
            "metric_keys" => token ? Pito::Analytics::ScalarsTableComponent::GLANCE_METRICS.map { |m| m[:key].to_s } : nil
          }.compact
        end

        # A single entity's own title, or "N vids/games/channels" for a set.
        MULTI_PLURALS = { "Video" => "vids", "Game" => "games", "Channel" => "channels" }.freeze

        def scope_title(scope)
          return scope.title unless scope.is_a?(Array)

          "#{scope.size} #{MULTI_PLURALS.fetch(scope.first&.class&.name, 'items')}"
        end
      end
    end
  end
end
