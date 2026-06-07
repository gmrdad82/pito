# frozen_string_literal: true

module Pito
  module FollowUp
    # Value types returned by FollowUp::Handler#call.
    #
    # == Result::Mutation
    #
    # The handler wants to UPDATE the source event in place (no echo, no new turn).
    # FollowUpDispatchJob will call event.update!(kind:, payload:) then
    # broadcaster.replace_event(event).
    #
    #   Result::Mutation.new(kind: :theme_diff, payload: { … })
    #
    # == Result::Append
    #
    # The handler wants to APPEND one or more new events to the conversation.
    # FollowUpDispatchJob persists each `{kind:, payload:}` element as a new Event
    # in the given turn, broadcasts each one, then marks the SOURCE event consumed
    # (reply_consumed: true) and broadcasts a replace of the source.
    #
    #   Result::Append.new(events: [{ kind: :system, payload: { text: "Done." } }])
    #
    # == Result::Error
    #
    # The handler could not process the request.
    # FollowUpDispatchJob appends a kind: :error event with the error message.
    #
    #   Result::Error.new(message_key: "pito.follow_up.errors.unknown_action",
    #                     message_args: { action: "foo" })
    module Result
      Mutation = Data.define(:kind, :payload)
      Append   = Data.define(:events)
      Error    = Data.define(:message_key, :message_args)
    end
  end
end
