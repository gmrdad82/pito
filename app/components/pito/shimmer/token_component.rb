# frozen_string_literal: true

module Pito
  module Shimmer
    # Renders an identifier token — a channel @handle, the @all / period (28d)
    # scope chip, or a video/game #id — with a shared staggered offset
    # (Pito::Shimmer.offset_class) so adjacent tokens are out of phase.
    # Owner round 5: clickable tokens shimmer bold fg-default + theme-purple
    # band; reference tokens are plain bold fg-default (no shimmer).
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
      # Convention: a token that prefills/submits on click SHIMMERS (action-shimmer,
      # the only clickable shimmer); a purely-identifying token is PLAIN (owner 17.4 —
      # @handle / #id / scope chips no longer shimmer). Raw-markup callers that merge
      # `prefill_data` themselves must pass `clickable: true` so the styling matches.
      # Semantic REFERENCES (the AI text blocks' [ref] tokens) are the exception:
      # they wear the bold fg-default reference styling (`shimmer: true` —
      # static since owner round 5; the class name is the stable hook).
      SHIMMER_CLASS   = "pito-reference-shimmer" # semantic [ref] tokens (AI text blocks)
      CLICKABLE_CLASS = "pito-action-shimmer"   # CLICKABLE (the only clickable shimmer)
      PLAIN_CLASS     = "pito-token"            # DECORATIVE identifiers — plain text + JS hook

      # Full class string for a token span.
      # CLICKABLE tokens shimmer (action-shimmer + a shared staggered offset so
      #   adjacent tokens never sync; `seed:` breaks synchrony when text repeats).
      # REFERENCE tokens (`shimmer: true` — AI [ref]) wear the cyan reference
      #   shimmer with the same shared offset stagger.
      # DECORATIVE tokens (@handle / #id / scope chips) are PLAIN (owner 17.4): no
      #   shimmer, no offset — just the `pito-token` hook class (the chat-form
      #   controller targets it to update a cycled value) plus any layout `extra`.
      def self.css_class(text, extra: nil, seed: nil, clickable: false, shimmer: false)
        if clickable
          [ CLICKABLE_CLASS, Pito::Shimmer.offset_class(text, seed: seed), extra ].compact.join(" ")
        elsif shimmer
          [ SHIMMER_CLASS, Pito::Shimmer.offset_class(text, seed: seed), extra ].compact.join(" ")
        else
          [ PLAIN_CLASS, extra ].compact.join(" ")
        end
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
