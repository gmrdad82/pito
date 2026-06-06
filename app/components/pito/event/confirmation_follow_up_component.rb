# frozen_string_literal: true

module Pito
  module Event
    # ConfirmationFollowUp — the outcome message appended by the follow-up engine
    # after the user replies `#<handle> confirm|cancel`.
    #
    # This is a NEW, standalone event (not a mutated version of the original
    # confirmation).  It carries only the outcome fields:
    #   outcome:      "confirm" | "cancel"
    #   outcome_text: Human-readable result string.
    #   resolved:     true
    #
    # Appearance: orange border (same as the original confirmation) with a
    # surface background (`--bg-surface`, lighter than `--bg-elevated`).
    # Reload-safe: the outcome_text comes directly from the payload.
    class ConfirmationFollowUpComponent < ViewComponent::Base
      def initialize(payload: {}, event: nil)
        payload        = payload.with_indifferent_access
        @outcome_text  = payload[:outcome_text].to_s.presence
        @outcome       = payload[:outcome].to_s.presence
        @event         = event
      end

      def background = "var(--bg-surface)"

      def dom_id
        @event ? "event_#{@event.id}" : nil
      end

      attr_reader :outcome_text, :outcome
    end
  end
end
