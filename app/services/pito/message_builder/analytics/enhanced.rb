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

        def pending(scope, period: nil)
          intro = Pito::Copy.render("pito.copy.analytics.intro", { title: scope.title })
          {
            "body"      => render_component(Pito::Analytics::EnhancedComponent.new(intro: intro, pending: true)),
            "html"      => true,
            # `anchor` gives the segment a stable `event_<id>` DOM id so the fill
            # job's replace_event can swap it in place (it isn't follow-up-able,
            # which is the other way an event earns an id).
            "anchor"    => true,
            "analytics" => marker("pending", scope: scope, period: period, intro: intro)
          }
        end

        def ready_payload(scope:, period:, result:, intro:)
          {
            "body"      => render_component(Pito::Analytics::EnhancedComponent.new(intro: intro, result: result)),
            "html"      => true,
            "anchor"    => true,
            "analytics" => marker("ready", scope: scope, period: period, intro: intro)
          }
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
