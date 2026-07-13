# frozen_string_literal: true

module Pito
  module Event
    # Renders a confirmation / segment reply handle as `#handle` in plain
    # fg-default (owner round 5 — no shimmer, no muting, no chip).
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

      # The reply handle is DECORATIVE and NOT clickable. The click-to-prefill
      # affordance was removed; the shift+r keybinding (blue kbd shimmer)
      # remains the way to reply. The `data-pito-handle` hook is preserved for
      # the lasthashtag controller.
      def call
        token = "##{@handle}"
        tag.span(token,
                 class: Pito::Shimmer::HashtagTokenComponent.css_class(token),
                 data: { pito_handle: @handle })
      end
    end
  end
end
