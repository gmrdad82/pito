# frozen_string_literal: true

module Pito
  module Stream
    class EventRenderer
      # Maps event kinds to component classes.
      # Components that accept `payload:` go in COMPONENT_CLASSES.
      # Components that take keyword args get special treatment in #build_component.
      COMPONENT_CLASSES = {
        "echo"                => Pito::Event::EchoComponent,
        "assistant_text"      => Pito::Event::AssistantTextComponent,
        "error"               => Pito::Event::ErrorComponent,
        "confirmation_prompt" => Pito::Event::ConfirmationPromptComponent
      }.freeze

      PLAN1_COMPONENTS = %w[
        user_message
        thought
        tool_output
        status_footer
      ].to_set.freeze

      def self.render(event)
        component = component_for(event)
        ApplicationController.renderer.render(component, layout: false)
      end

      def self.component_for(event)
        build_component(event.kind, indifferent_payload(event))
      end

      # Build the correct component instance for a given kind and payload.
      def self.build_component(kind, payload)
        if (component_class = COMPONENT_CLASSES[kind])
          component_class.new(payload:)

        elsif kind == "user_message"
          # Visually identical to echo — orange bar + text
          Pito::Event::EchoComponent.new(payload:)

        else
          raise ArgumentError,
            "No component registered for event kind: #{kind.inspect}"
        end
      end

      def self.indifferent_payload(event)
        event.payload.is_a?(Hash) ? event.payload.with_indifferent_access : event.payload
      end
    end
  end
end
