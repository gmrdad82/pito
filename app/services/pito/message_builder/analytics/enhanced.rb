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

        def pending(scope, period: nil, conversation: nil)
          intro = Pito::Copy.render_html("pito.copy.analytics.intro", { title: scope.title }, shimmer: [ :title ])
          payload = {
            "body"      => render_component(Pito::Analytics::EnhancedComponent.new(intro: intro, pending: true)),
            "html"      => true,
            "anchor"    => true, # stable event_<id> DOM id for replace_event + the handle
            "analytics" => marker("pending", scope: scope, period: period, intro: intro)
          }
          # Followupable: replying `with`/`without` to the glance spawns a NEW analyze
          # pair on this entity (handled by FollowUp::Handlers::AnalyticsGlance).
          return payload if conversation.nil?

          Pito::FollowUp.make_followupable!(payload, target: "analytics_glance", conversation:)
        end

        def ready_payload(scope:, period:, result:, intro:, series: {})
          {
            "body"      => render_component(Pito::Analytics::EnhancedComponent.new(intro: intro, result: result, nudge: nudge_for(scope), series: series)),
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

        def marker(status, scope:, period:, intro:)
          {
            "status"     => status,
            "scope_type" => scope&.class&.name,
            "scope_id"   => scope&.id,
            "period"     => period,
            "intro"      => intro
          }
        end
      end
    end
  end
end
