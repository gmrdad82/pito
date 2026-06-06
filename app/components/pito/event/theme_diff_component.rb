# frozen_string_literal: true

module Pito
  module Event
    # Renders a theme-diff event: the result of a #preview or #apply hashtag
    # transforming the most-recent theme-list message in place.
    #
    # This component renders the FINAL state (reload-correct, works without JS)
    # and emits `pito--diff-reveal` wiring for the animation engine (P12b).
    # Until the controller is registered the wiring is inert.
    #
    # Payload contract
    # ----------------
    # Common keys:
    #   phase       [String]  "preview" or "apply"
    #   granularity [String]  "char" or "line"  (dark → char, light → line)
    #   from_text   [String]  plain-text snapshot of the PREVIOUS content
    #                         (used as data-from on the outermost diff cell or
    #                          on the per-row marker cell for preview phase)
    #
    # Preview phase keys (theme_list: true is also retained so re-finds work):
    #   previewed_slug [String]   slug of the theme being previewed
    #   sections       [Array]    Dark/Light section arrays from the list payload
    #                             Each section: { title:, rows: [{key:, value:}] }
    #   theme_list     [Boolean]  retained so subsequent #preview/#apply re-finds
    #                             the same event
    #
    # Apply phase keys:
    #   body           [String]   the witty confirmation quip (final text)
    #   (theme_list is dropped for apply — the list is consumed)
    #
    # Rendering structure (both phases share the same root Segment wiring):
    #   - Root Segment id: "event_<event.id>" (stable DOM anchor)
    #   - Content wrapper: data-controller="pito--diff-reveal"
    #                      data-pito--diff-reveal-granularity-value="<granularity>"
    #                      data-pito--diff-reveal-phase-value="<phase>"
    #   - Each animatable text node:
    #       <span data-pito--diff-reveal-target="cell" data-from="<old>">NEW</span>
    #     textContent = final state (correct on reload / no-JS)
    #     data-from   = pre-transform text (for animation in P12b)
    class ThemeDiffComponent < ViewComponent::Base
      # @param payload [Hash]
      # @param event   [Event, nil]
      def initialize(payload: {}, event: nil)
        payload    = payload.with_indifferent_access if payload.respond_to?(:with_indifferent_access)
        @payload   = payload
        @event     = event
        @phase       = payload[:phase].to_s
        @granularity = payload[:granularity].to_s
        @from_text   = payload[:from_text].to_s

        # Preview-specific fields
        @previewed_slug = payload[:previewed_slug].to_s
        @sections = Array(payload[:sections]).map do |s|
          s.respond_to?(:with_indifferent_access) ? s.with_indifferent_access : s
        end

        # Apply-specific fields
        @body = payload[:body].to_s
      end

      def accent     = :surface
      def background = nil

      private

      def segment_id
        @event ? "event_#{@event.id}" : nil
      end

      def preview? = @phase == "preview"
      def apply?   = @phase == "apply"
    end
  end
end
