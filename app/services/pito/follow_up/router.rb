# frozen_string_literal: true

module Pito
  module FollowUp
    # Routes a `#<handle> <rest>` input to the matching non-consumed event
    # within the conversation that carries that handle in its `reply_handle`
    # payload field.
    #
    # Return shapes (Hash):
    #
    #   { status: :ok, event: Event, handle: String, rest: String }
    #     — input matched the pattern AND a live (non-consumed) event was found.
    #       `rest` is everything after `#<handle> ` (trimmed).
    #
    #   { status: :not_found, handle: String }
    #     — input matched the pattern but no live event carries that handle.
    #       This happens when the handle is unknown or the event was already
    #       consumed.  The controller falls through to the existing
    #       confirmation/hashtag branches unchanged.
    #
    #   { status: :not_a_follow_up }
    #     — input does not match `#<word>-<4digits> <something>` at all.
    #       The controller falls through immediately.
    #
    # Design notes:
    #   - Consumed events (reply_consumed = true) are NOT routable; the caller
    #     receives :not_found, not :ok.
    #   - The router does NOT know about specific handlers; it only finds the
    #     event.  The controller reads the target and asks the Registry for the mode.
    #   - Since P14, confirmation events are stamped with `reply_handle` and routed
    #     here like any other follow-up.  A re-reply to a consumed confirmation
    #     returns :not_found and falls through to hashtag routing (acceptable).
    class Router
      PATTERN = /\A#([a-z]+-\d{4})\s+(.+)\z/im

      def self.call(input:, conversation:)
        new(input, conversation).route
      end

      private_class_method :new

      def initialize(input, conversation)
        @input        = input.to_s.strip
        @conversation = conversation
      end

      def route
        m = @input.match(PATTERN)
        return { status: :not_a_follow_up } unless m

        handle = m[1].downcase
        rest   = m[2].strip

        event = find_live(handle)
        return { status: :not_found, handle: handle } if event.nil?

        { status: :ok, event: event, handle: handle, rest: rest }
      end

      private

      def find_live(handle)
        @conversation.events
          .where("payload->>'reply_handle' = ?", handle)
          .where("(payload->>'reply_consumed') IS NULL OR (payload->>'reply_consumed') = 'false'")
          .last
      end
    end
  end
end
