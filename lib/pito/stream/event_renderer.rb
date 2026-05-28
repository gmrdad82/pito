# frozen_string_literal: true

module Pito
  module Stream
    class EventRenderer
      KIND_COMPONENT_MAP = {
        "echo"               => Pito::Event::EchoComponent,
        "assistant_text"     => Pito::Event::AssistantTextComponent,
        "error"              => Pito::Event::ErrorComponent,
        "confirmation_prompt" => Pito::Event::ConfirmationPromptComponent
      }.freeze

      def self.render(event)
        component_class = KIND_COMPONENT_MAP[event.kind] or
          raise ArgumentError, "No component registered for event kind: #{event.kind.inspect}"

        component = component_class.new(payload: event.payload)
        ApplicationController.renderer.render(component, layout: false)
      end

      def self.component_for(event)
        component_class = KIND_COMPONENT_MAP[event.kind] or
          raise ArgumentError, "No component registered for event kind: #{event.kind.inspect}"

        component_class.new(payload: event.payload)
      end
    end
  end
end
