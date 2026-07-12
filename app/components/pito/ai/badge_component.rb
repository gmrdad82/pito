# frozen_string_literal: true

module Pito
  module Ai
    # THE AI sparkle — the one centralized badge every AI marker renders:
    # the sidebar conversation rows (when a thread carries :ai messages) and
    # the ✨ model chip on AI answers. The Lucide sparkles glyph as a CSS
    # mask, sized to the 14px row (height can never disturb a row), its fill
    # shimmering in the AI accent-bar pair (purple base, pito-blue band) on
    # the GLOBAL shimmer angle/speed tokens. Pure chrome — hidden from the
    # accessibility tree.
    #
    # `ai:` gates rendering for callers answering "does this thing involve
    # AI?" per row (the sidebar precomputes it in one query; single-row
    # re-renders fall back to a per-row EXISTS). Always-AI chrome (the model
    # chip) omits it.
    #
    # Rendered via #call so no template newline sneaks a stray gap into the
    # monospace flex row (same reasoning as TimestampPrefixComponent).
    class BadgeComponent < ViewComponent::Base
      # @param ai [Boolean] render gate — false renders nothing
      def initialize(ai: true)
        @ai = ai
      end

      def render?
        @ai
      end

      def call
        tag.span(class: "pito-ai-badge", "aria-hidden": true)
      end
    end
  end
end
