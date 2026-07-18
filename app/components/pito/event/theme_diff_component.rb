# frozen_string_literal: true

module Pito
  module Event
    # Renders a theme-diff event: the result of a #preview or #apply hashtag
    # transforming the most-recent theme-list message in place.
    #
    # This component renders the FINAL state instantly (the diff-reveal morph
    # animation was removed). Reload-correct, no JS needed.
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
    # Preview phase keys (reply_handle/reply_target retained so re-finds work via the follow-up engine):
    #   previewed_slug [String]   slug of the theme being previewed
    #   sections       [Array]    Dark/Light section arrays from the list payload
    #                             Each section: { title:, rows: [{key:, value:}] }
    #   reply_handle   [String]   RETAINED — kept for display purposes only (no longer routable)
    #   reply_target   [String]   retained in stored events for historical data
    #
    # Apply phase keys:
    #   body           [String]   the witty confirmation quip (final text)
    #   reply_consumed [Boolean]  true — handle reserved but event no longer routable
    #
    # Rendering structure (both phases share the same root Segment wiring):
    #   - Root Segment id: "event_<event.id>" (stable DOM anchor)
    #   - Text nodes render their FINAL state directly — the diff-reveal morph
    #     was removed, so no reveal controller or data-* attrs remain.
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

        # Follow-up affordance fields (reply_handle / reply_consumed).
        @reply_handle   = payload[:reply_handle].to_s.presence
        @reply_consumed = Pito::FollowUp.consumed?(payload)
      end

      def accent     = :surface
      def background = nil

      private

      def segment_id
        @event ? "event_#{@event.id}" : nil
      end

      def preview? = @phase == "preview"
      def apply?   = @phase == "apply"

      # True when the message has a live follow-up handle (preview phase only;
      # apply is consumed) AND — when a persisted event backs this render —
      # currently has at least one available reply action (the owner's "no
      # actions → no handle, no chip" rule; see
      # SystemComponent#followupable? for the full rationale, identical
      # here). Payload-only renders with no @event (component-level specs)
      # skip that extra check.
      #
      # In practice this component only ever re-renders OLD persisted rows —
      # the theme picker moved fully client-side and no current code path
      # mints a theme_diff event — so this predicate is what correctly
      # retires their long-stale, already-unroutable handle on next render.
      def followupable?
        return false unless @reply_handle.present? && !@reply_consumed

        @event.nil? || Pito::FollowUp.renderable_actions?(@event)
      end
    end
  end
end
