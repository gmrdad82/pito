# frozen_string_literal: true

module Pito
  module Event
    # Renders a message body: an inline "HH:MM " timestamp prefix (or a filled
    # `data-pito-ts-slot` placeholder inside the body), the body span, and an
    # always-visible `detail` block. Messages render in full, INSTANTLY (the
    # typewriter/text-reveal was removed).
    #
    # Params:
    #   body      — the primary text (String|nil)
    #   detail    — detail rows shown beneath, always visible (Array of String or
    #               { key:, value:, key_class:, value_class: } hashes)
    #   html      — when true, `body` is pre-formatted HTML
    #   timestamp — event timestamp for the inline "HH:MM " prefix
    class BodyComponent < ViewComponent::Base
      def initialize(body: nil, detail: [], html: false, timestamp: nil)
        @body      = body
        @html      = html == true || html == "true"
        @detail    = detail
        @timestamp = timestamp
      end

      attr_reader :body, :detail

      # Inline "HH:MM " prefix rendered before the body's first line. Renders
      # nothing when no timestamp was supplied.
      def timestamp_prefix
        @timestamp_prefix ||= render(Pito::Event::TimestampPrefixComponent.new(timestamp: @timestamp))
      end

      # Detail cards embed `<span data-pito-ts-slot></span>` inside their left
      # column so the timestamp lands THERE instead of leading the whole card.
      TS_SLOT = "<span data-pito-ts-slot></span>"

      def ts_slot?
        @body.to_s.include?("data-pito-ts-slot")
      end

      # The prefix shown BEFORE the body — empty when the body fills its own slot.
      def leading_prefix
        ts_slot? ? "".html_safe : timestamp_prefix
      end

      # The body with the timestamp slot filled (no-op when there is no slot).
      def filled_body
        return @body unless ts_slot?

        @body.to_s.sub(TS_SLOT, timestamp_prefix.to_s).html_safe
      end

      def html? = @html
    end
  end
end
