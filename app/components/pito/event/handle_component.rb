# frozen_string_literal: true

module Pito
  module Event
    # Renders a confirmation / segment reply handle as `#handle` with the
    # blue→purple hashtag shimmer (distinct from the cyan @handle / #id shimmer).
    # Used inside MetaLineComponent and anywhere a reply handle appears inline.
    # The class comes from Pito::Shimmer::HashtagTokenComponent.css_class so the
    # `data-pito-handle` hook (used by the lasthashtag controller) is preserved.
    class HandleComponent < ViewComponent::Base
      def initialize(handle)
        @handle = handle.to_s.presence
      end

      def render?
        @handle.present?
      end

      # The reply handle is DECORATIVE (purple hashtag shimmer) and NOT clickable
      # (owner 2026-06-29: purple shimmer must never be clickable — only the yellow
      # shimmer is). The click-to-prefill affordance was removed; the shift+r
      # keybinding (yellow kbd) remains the way to reply. The `data-pito-handle`
      # hook is preserved for the lasthashtag controller.
      def call
        token = "##{@handle}"
        tag.span(token,
                 class: Pito::Shimmer::HashtagTokenComponent.css_class(token),
                 data: { pito_handle: @handle })
      end
    end
  end
end
