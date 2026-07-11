# frozen_string_literal: true

module Pito
  module Segment
    class Component < ViewComponent::Base
      # @param accent [Symbol, nil] Accent color for the left bar:
      #   :orange, :red, :yellow, :purple. When nil, the bar is omitted.
      # @param background [String, nil] CSS background for the content wrapper
      #   (e.g. "var(--bg-surface)"). When nil, the content area is transparent.
      # @param msg_bg [String, nil] override for the exposed --pito-msg-bg custom
      #   property when the background itself isn't a paintable chip color
      #   (e.g. the :ai gradient surface still hands chips an opaque surface).
      #   Defaults to +background+.
      # @param content_class [String, nil] extra class(es) for the content
      #   wrapper — the seam for class-driven surfaces (the animated :ai
      #   gradient needs background-size + animation, which an inline
      #   `background:` shorthand would reset).
      def initialize(accent: nil, background: nil, id: nil, scrollback_message: false, msg_bg: nil, content_class: nil)
        @accent = accent
        @background = background
        @id = id
        @scrollback_message = scrollback_message
        @msg_bg = msg_bg || background
        @content_class = content_class
      end

      # The content wrapper's inline style — background (when given) plus the
      # --pito-msg-bg custom property chip descendants read. Nil when neither
      # applies, so the attribute is omitted entirely.
      def content_style
        parts = []
        parts << "background: #{@background};" if @background
        parts << "--pito-msg-bg: #{@msg_bg};" if @msg_bg
        parts.join(" ").presence
      end
    end
  end
end
