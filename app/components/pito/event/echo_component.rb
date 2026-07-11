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
    # The echoed text renders instantly (the typewriter was removed). The
    # post-command comet (pito--dots) clears on `pito:result-appended` /
    # `pito:comet-clear` instead.
    class EchoComponent < ViewComponent::Base
      # @param payload [Hash] event payload with `{ text: }`.
      # @param event [Event, nil] the persisted event — used for timestamp.
      def initialize(payload: {}, event: nil)
        @text             = payload[:text].to_s
        @timestamp        = event&.created_at
        @authenticated    = payload.fetch(:authenticated, true)
        @triggers_logout  = payload[:triggers_logout] == true || payload[:triggers_logout] == "true"
        @ai               = payload[:ai] == true || payload[:ai] == "true"
      end

      def triggers_logout? = @triggers_logout

      # An `ai …` turn's echo joins the AI visual thread (gradient accent).
      def accent
        @ai ? :ai : :purple
      end
    end
  end
end
