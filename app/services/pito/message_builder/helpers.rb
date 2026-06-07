# frozen_string_literal: true

module Pito
  module MessageBuilder
    # Shared helpers for all Pito::MessageBuilder::* builders.
    #
    # Include or extend this module inside a builder to get access to:
    #   render_component(component)    — render a ViewComponent to an HTML string
    #   html_payload(body:, **extra)   — build the canonical { "body", "html" } hash
    module Helpers
      module_function

      # Render a ViewComponent instance to a raw HTML string (no layout).
      #
      # @param component [ViewComponent::Base] an instantiated component.
      # @return [String] HTML string.
      def render_component(component)
        ApplicationController.renderer.render(component, layout: false)
      end

      # Build a canonical HTML payload hash.
      #
      # @param body   [String] HTML body string.
      # @param extra  [Hash]   additional string or symbol-keyed entries to merge.
      # @return [Hash] string-keyed payload with at least "body" and "html" keys.
      def html_payload(body:, **extra)
        { "body" => body, "html" => true }.merge(extra.stringify_keys)
      end
    end
  end
end
