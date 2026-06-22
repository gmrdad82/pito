# frozen_string_literal: true

module Pito
  module Event
    # Renders the user's own message echoed back into the conversation stream.
    #
    # Payload keys:
    #   text:             [String]  — the raw input text to display (required)
    #   authenticated:    [Boolean] — whether the user was authenticated when the
    #                                 message was sent (defaults to true)
    #   triggers_logout:  [Boolean] — true when this echo is the final event
    #                                 before a logout choreography fires; the
    #                                 template wires the `pito--logout` controller
    #
    # Rendered inside a `Pito::Segment` with a purple accent bar and an
    # elevated background.  The meta line shows the formatted timestamp.
    #
    # The echoed text types in character-by-character via the `pito--typewriter`
    # controller (body target), honouring all of the typewriter's skip guards
    # (initial server render, prefers-reduced-motion, `/config fx` off → instant).
    # The mount sets `doneEvent: "pito:echo-typed"` so the comet (pito--dots)
    # clears the moment the echo lands — including on the instant/skip path.
    class EchoComponent < ViewComponent::Base
      # @param payload [Hash] event payload with `{ text: }`.
      # @param event [Event, nil] the persisted event — used for timestamp.
      def initialize(payload: {}, event: nil)
        @text             = payload[:text].to_s
        @timestamp        = event&.created_at
        @authenticated    = payload.fetch(:authenticated, true)
        @triggers_logout  = payload[:triggers_logout] == true || payload[:triggers_logout] == "true"
      end

      def triggers_logout? = @triggers_logout
    end
  end
end
