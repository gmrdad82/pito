# frozen_string_literal: true

module Pito
  module Event
    # Renders a message body: an inline "HH:MM ·" timestamp prefix (or a filled
    # `data-pito-ts-slot` placeholder inside the body), the body span (optionally
    # revealed via the typewriter controller), and an always-visible `detail`
    # block. There is no collapse/expand — messages render in full.
    #
    # Params:
    #   body             — the primary text (String|nil)
    #   detail           — detail rows shown beneath, always visible (Array of String or
    #                      { key:, value:, key_class:, value_class: } hashes)
    #   html             — when true, `body` is pre-formatted HTML (no typewriter)
    #   typewriter       — true to emit typewriter targets (plain-text bodies only)
    #   owner_controller — when false and typewriter is true, emit the body target
    #                      attribute but NOT the data-controller; the caller's outer
    #                      div owns the typewriter controller.
    #   timestamp        — event timestamp for the inline "HH:MM ·" prefix
    class BodyComponent < ViewComponent::Base
      def initialize(body: nil, detail: [], html: false, typewriter: false,
                     owner_controller: true, timestamp: nil)
        @body             = body
        @html             = html == true || html == "true"
        @typewriter       = typewriter && !@html
        @owner_controller = owner_controller
        @detail           = detail
        @timestamp        = timestamp
      end

      attr_reader :body, :detail

      # Inline "HH:MM ·" prefix rendered before the body's first line. Renders
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

      def html?            = @html
      def typewriter?      = @typewriter
      def owns_controller? = @typewriter && @owner_controller
    end
  end
end
