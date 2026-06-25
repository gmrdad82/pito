# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Analyze
      # Builds the two `analyze` messages (roles "system" + "enhanced") in pending
      # and ready states.
      #
      # INTERIM (FORK-A, owner-resolved): both roles render the SAME scalar kv-table
      # via Pito::Analytics::EnhancedComponent, differing only by their Pito::Copy
      # intro (`pito.copy.analyze.{system,enhanced}.intro`, 50 variants each). A
      # later ViewComponent session adds the per-role extra scalars
      # (system: devices/subscribed/geography; enhanced: heatmap/retention/
      # demographics) and extracts each kv cell into its own component.
      #
      # Uses a dedicated `"analyze"` marker (NOT the show-vid/game `"analytics"`
      # marker) so the two stacks stay isolated; AnalyzePrepareJob reads it to
      # rebuild the scope (level + entity_ids + period) and fill both messages.
      # Payload keys are strings so they round-trip through jsonb unchanged.
      module Message
        extend Pito::MessageBuilder::Helpers
        module_function

        INTRO_KEYS = {
          "system"   => "pito.copy.analyze.system.intro",
          "enhanced" => "pito.copy.analyze.enhanced.intro"
        }.freeze

        ROLES = INTRO_KEYS.keys.freeze

        # Canonical predicate: a persisted event carrying an analyze marker still
        # in its pending state. Shared by the Finalizer + AnalyzePrepareJob.
        def pending?(event)
          event.payload.is_a?(Hash) && event.payload.dig("analyze", "status") == "pending"
        end

        def role(event)
          event.payload.dig("analyze", "role")
        end

        # Instant pending state — intro only; the spinner stays up until the job
        # fills the data.
        #
        # @param role       [String] "system" | "enhanced"
        # @param title      [String] the scope's display title (shimmered subject)
        # @param level      [Symbol/String] :channel | :vid | :game
        # @param entity_ids [Array<Integer>] resolved entity ids at that level
        # @param period     [String] the shift+space window token
        def pending(role:, title:, level:, entity_ids:, period:)
          intro = intro_for(role, title)
          {
            "body"    => render_component(Pito::Analytics::EnhancedComponent.new(intro:, pending: true)),
            "html"    => true,
            "anchor"  => true,
            "analyze" => marker("pending", role:, title:, level:, entity_ids:, period:, intro:)
          }
        end

        # Ready state, written by AnalyzePrepareJob. Reuses the STORED intro so it
        # never changes under the user.
        #
        # @param event  [Event] the pending event being filled
        # @param result [Pito::Analytics::Scalars::Result, Symbol] the aggregated
        #   result, or Pito::Analytics::Scalars::UNAVAILABLE
        def ready_payload(event, result:)
          marker = event.payload.fetch("analyze")
          {
            "body"    => render_component(Pito::Analytics::EnhancedComponent.new(intro: marker["intro"], result:)),
            "html"    => true,
            "anchor"  => true,
            "analyze" => marker.merge("status" => "ready")
          }
        end

        def intro_for(role, title)
          Pito::Copy.render_html(INTRO_KEYS.fetch(role.to_s), { title: title }, shimmer: [ :title ])
        end

        def marker(status, role:, title:, level:, entity_ids:, period:, intro:)
          {
            "status"     => status,
            "role"       => role.to_s,
            "title"      => title,
            "level"      => level.to_s,
            "entity_ids" => Array(entity_ids),
            "period"     => period,
            "intro"      => intro
          }
        end
      end
    end
  end
end
