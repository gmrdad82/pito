# frozen_string_literal: true

module Pito
  module Stream
    # EventRenderer — factory that maps an Event to its ViewComponent and renders it.
    #
    # COMPONENT_CLASSES is a frozen Hash<String, Class> mapping each event `kind`
    # string to its ViewComponent class:
    #
    #   "echo"                   → Pito::Event::EchoComponent
    #   "thinking"               → Pito::Event::ThinkingComponent
    #   "system"                 → Pito::Event::SystemComponent
    #   "enhanced"               → Pito::Event::EnhancedComponent
    #   "system_follow_up"       → Pito::Event::SystemFollowUpComponent
    #   "enhanced_follow_up"     → Pito::Event::EnhancedFollowUpComponent
    #   "confirmation"           → Pito::Event::ConfirmationComponent
    #   "confirmation_follow_up" → Pito::Event::ConfirmationFollowUpComponent
    #   "error"                  → Pito::Event::ErrorComponent
    #
    # Public API (all class methods)
    # ────────────────────────────────
    # render(event)                           — renders the event to an HTML string.
    # component_for(event)                    — instantiate the component without rendering.
    # build_component(kind, payload, event:)  — lower-level; caller supplies kind + payload.
    #
    # Payload coercion
    # ─────────────────
    # `indifferent_payload` converts `event.payload` to a
    # HashWithIndifferentAccess so components can access keys by either
    # String or Symbol.  Non-Hash payloads are passed through unchanged.
    #
    # Unknown kind
    # ─────────────
    # `build_component` calls `Hash#fetch` with a block that raises
    # `ArgumentError` ("No component registered for event kind: <kind>").
    # Callers that need a safe path should rescue ArgumentError.
    class EventRenderer
      COMPONENT_CLASSES = {
        "echo"                    => Pito::Event::EchoComponent,
        "thinking"                => Pito::Event::ThinkingComponent,
        "system"                  => Pito::Event::SystemComponent,
        "enhanced"                => Pito::Event::EnhancedComponent,
        "system_follow_up"        => Pito::Event::SystemFollowUpComponent,
        "enhanced_follow_up"      => Pito::Event::EnhancedFollowUpComponent,
        "confirmation"            => Pito::Event::ConfirmationComponent,
        "confirmation_follow_up"  => Pito::Event::ConfirmationFollowUpComponent,
        "error"                   => Pito::Event::ErrorComponent,
        "theme_diff"              => Pito::Event::ThemeDiffComponent
      }.freeze

      def self.render(event)
        component = component_for(event)
        ApplicationController.renderer.render(component, layout: false)
      end

      def self.component_for(event)
        build_component(event.kind, indifferent_payload(event), event:)
      end

      def self.build_component(kind, payload, event: nil)
        component_class = COMPONENT_CLASSES.fetch(kind.to_s) do
          raise ArgumentError, "No component registered for event kind: #{kind.inspect}"
        end
        component_class.new(payload:, event:)
      end

      def self.indifferent_payload(event)
        event.payload.is_a?(Hash) ? event.payload.with_indifferent_access : event.payload
      end
    end
  end
end
