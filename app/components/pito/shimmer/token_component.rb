# frozen_string_literal: true

module Pito
  module Shimmer
    # Renders an identifier token — a channel @handle, the @all / period (28d)
    # scope chip, or a video/game #id — with the cyan→pito-blue shimmer
    # (.pito-token-shimmer) and a shared staggered offset (Pito::Shimmer.offset_class)
    # so adjacent tokens are out of phase (never synchronised).
    #
    # `extra_class` carries layout-only utilities (e.g. "tabular-nums",
    # "whitespace-nowrap") — the shimmer owns the colour via background-clip.
    #
    #   render(Pito::Shimmer::TokenComponent.new(text: channel.at_handle))
    #   render(Pito::Shimmer::TokenComponent.new(text: "##{video.id}", extra_class: "tabular-nums"))
    #
    # String-only call sites (kv-table cells, message builders that emit a class
    # string or an html fragment) use the class methods so they never re-derive
    # the offset math by hand:
    #   Pito::Shimmer::TokenComponent.css_class("##{id}", extra: "tabular-nums")
    #   Pito::Shimmer::TokenComponent.html(channel.at_handle)
    class TokenComponent < ViewComponent::Base
      SHIMMER_CLASS = "pito-token-shimmer"

      # Full class string for a shimmer span (colour + shared offset + extra).
      def self.css_class(text, extra: nil)
        [ SHIMMER_CLASS, Pito::Shimmer.offset_class(text), extra ].compact.join(" ")
      end

      # html-safe <span> for builders / cells that compose raw markup.
      def self.html(text, extra: nil)
        ActionController::Base.helpers.tag.span(text, class: css_class(text, extra: extra))
      end

      def initialize(text:, extra_class: nil)
        @text        = text.to_s
        @extra_class = extra_class
      end

      def call
        tag.span(@text, class: self.class.css_class(@text, extra: @extra_class))
      end
    end
  end
end
