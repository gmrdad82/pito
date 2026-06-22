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
      # `seed:` is forwarded to Pito::Shimmer.offset_class so that list-row
      # call sites can break synchrony when the same text repeats across rows.
      def self.css_class(text, extra: nil, seed: nil)
        [ SHIMMER_CLASS, Pito::Shimmer.offset_class(text, seed: seed), extra ].compact.join(" ")
      end

      # html-safe <span> for builders / cells that compose raw markup.
      def self.html(text, extra: nil, seed: nil)
        ActionController::Base.helpers.tag.span(text, class: css_class(text, extra: extra, seed: seed))
      end

      # `prefill:` (optional) turns the token into a click-to-type affordance:
      # clicking it prefills the chatbox with that string (no submit) via the
      # pito--chat-prefill controller. The shimmer styling is untouched.
      # `seed:` (optional) — forwarded to offset_class for list-row staggering.
      def initialize(text:, extra_class: nil, prefill: nil, seed: nil)
        @text        = text.to_s
        @extra_class = extra_class
        @prefill     = prefill.presence
        @seed        = seed
      end

      def call
        tag.span(@text, class: self.class.css_class(@text, extra: @extra_class, seed: @seed), **prefill_attrs)
      end

      private

      def prefill_attrs
        return {} unless @prefill

        {
          data: {
            controller: "pito--chat-prefill",
            action: "click->pito--chat-prefill#fill",
            "pito--chat-prefill-text-value": @prefill
          }
        }
      end
    end
  end
end
