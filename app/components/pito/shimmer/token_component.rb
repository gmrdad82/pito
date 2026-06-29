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
      # Convention (owner 2026-06-29): YELLOW shimmer = clickable; everything else is
      # decorative. A token that prefills/submits on click renders yellow
      # (pito-kbd-shimmer, the shared clickable-shimmer); a purely-identifying token
      # stays the cyan decorative shimmer. Raw-markup callers that merge
      # `prefill_data` themselves must pass `clickable: true` so the colour matches.
      SHIMMER_CLASS   = "pito-token-shimmer" # cyan — DECORATIVE (not clickable)
      CLICKABLE_CLASS = "pito-kbd-shimmer"   # yellow — CLICKABLE (the only clickable shimmer)

      # Full class string for a shimmer span (colour + shared offset + extra).
      # `seed:` is forwarded to Pito::Shimmer.offset_class so that list-row
      # call sites can break synchrony when the same text repeats across rows.
      # `clickable:` picks the yellow clickable shimmer over the cyan decorative one.
      def self.css_class(text, extra: nil, seed: nil, clickable: false)
        base = clickable ? CLICKABLE_CLASS : SHIMMER_CLASS
        [ base, Pito::Shimmer.offset_class(text, seed: seed), extra ].compact.join(" ")
      end

      # html-safe <span> for builders / cells that compose raw markup.
      def self.html(text, extra: nil, seed: nil, clickable: false)
        ActionController::Base.helpers.tag.span(text, class: css_class(text, extra: extra, seed: seed, clickable: clickable))
      end

      # The pito--chat-prefill data hash for a click-to-type token. STRING call
      # sites (list-cell `#id`s built via css_class) merge this into the cell's
      # `data:` so SystemComponent renders the same controller/action/value
      # attributes the component would. `submit: true` adds the submit-value so
      # the click auto-submits (an `#id` that OPENS the entity); the reply
      # #hashtag prefill omits it (prefill-only).
      def self.prefill_data(text, submit: false)
        data = {
          controller: "pito--chat-prefill",
          action: "click->pito--chat-prefill#fill",
          "pito--chat-prefill-text-value": text
        }
        data[:"pito--chat-prefill-submit-value"] = "true" if submit
        data
      end

      # `prefill:` (optional) turns the token into a click-to-type affordance:
      # clicking it prefills the chatbox with that string via the
      # pito--chat-prefill controller. `submit:` (optional) makes the click
      # auto-submit the command (Enter) instead of only prefilling. The shimmer
      # styling is untouched.
      # `seed:` (optional) — forwarded to offset_class for list-row staggering.
      def initialize(text:, extra_class: nil, prefill: nil, submit: false, seed: nil)
        @text        = text.to_s
        @extra_class = extra_class
        @prefill     = prefill.presence
        @submit      = submit
        @seed        = seed
      end

      def call
        # Clickable (prefill present) ⇒ yellow shimmer; decorative ⇒ cyan.
        tag.span(@text, class: self.class.css_class(@text, extra: @extra_class, seed: @seed, clickable: @prefill.present?), **prefill_attrs)
      end

      private

      def prefill_attrs
        return {} unless @prefill

        { data: self.class.prefill_data(@prefill, submit: @submit) }
      end
    end
  end
end
