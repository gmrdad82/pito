# frozen_string_literal: true

module Pito
  # Routes a `#word-digits confirm|cancel` input to the matching pending
  # confirmation event within the conversation.
  #
  # Returns a Hash:
  #   { event: Event, action: :confirm | :cancel }  — found + routed
  #   { error: :not_found, handle: String }          — no matching pending event
  #   { error: :invalid_format }                     — input doesn't match the pattern
  #
  # Design notes:
  #   - Generic: any handler that emits a `confirmation` event with a
  #     `confirmation_handle` in the payload is automatically routable.
  #   - The `command` field in the payload tells ConfirmationDispatchJob which
  #     executor to call; this router does not need to know about specific commands.
  #   - An event is "pending" when `resolved` is absent or false in its payload.
  class ConfirmationRouter
    PATTERN = /\A#([a-z]+-\d{4})\s+(confirm|cancel)\z/i
    def self.call(input:, conversation:)
      new(input, conversation).route
    end

    private_class_method :new

    def initialize(input, conversation)
      @input        = input.strip
      @conversation = conversation
    end

    def route
      m = @input.match(PATTERN)
      return { error: :invalid_format } unless m

      handle = m[1].downcase
      action = m[2].downcase.to_sym

      event = find_pending(handle)
      return { error: :not_found, handle: handle } if event.nil?

      { event: event, action: action }
    end

    private

    def find_pending(handle)
      @conversation.events
        .where(kind: "confirmation")
        .where("payload->>'confirmation_handle' = ?", handle)
        .where("(payload->>'resolved') IS NULL OR (payload->>'resolved') = 'false'")
        .first
    end
  end
end
