# frozen_string_literal: true

# Executes the domain handler for a follow-up reply.
#
# Called by ChatController#handle_follow_up after the Router has resolved a
# `#<handle> <rest>` input to a live (non-consumed) event.
#
# Parameters:
#   event_id  — ID of the source event carrying `reply_handle` + `reply_target`.
#   rest:     — the trailing string after `#<handle> ` (e.g. "preview tokyo-night").
#   turn_id:  — ID of the echo turn, required for :append mode handlers.
#               nil for :mutate mode (no turn was created).
#
# Result dispatch:
#
#   Mutation(kind:, payload:)
#     → event.update!(kind:, payload:) + broadcaster.replace_event(event)
#       No new events. No turn needed.
#
#   Append(events: [{kind:, payload:}, …])
#     → each event persisted as Event.create_with_position! under turn,
#       broadcast via broadcaster.broadcast_event.
#     → source event consumed: payload["reply_consumed"] = true +
#       broadcaster.replace_event(source).
#
#   Error(message_key:, message_args:)
#     → an :error event appended to turn (or a standalone turn when turn_id is nil).
#       Broadcasts via broadcaster.broadcast_event.
#
# Defensive: a missing handler or nil reply_target logs a warning and no-ops.
class FollowUpDispatchJob < ApplicationJob
  queue_as :default

  def perform(event_id, rest:, turn_id: nil)
    event        = Event.find(event_id)
    conversation = event.conversation
    broadcaster  = Pito::Stream::Broadcaster.new(conversation:)

    target       = event.payload["reply_target"].to_s
    handler_class = Pito::FollowUp::Registry.for(target)

    if handler_class.nil?
      Rails.logger.warn("[FollowUpDispatchJob] No handler registered for target #{target.inspect} (event #{event_id})")
      return
    end

    result = handler_class.new.call(event:, rest:, conversation:)

    case result
    when Pito::FollowUp::Result::Mutation
      event.update!(kind: result.kind.to_s, payload: result.payload)
      broadcaster.replace_event(event)
      # Turn-less flow — emit pito:done against the mutated event so the
      # post-command dots fade out (no Turn is created for :mutate replies).
      broadcaster.broadcast_done(dom_id: "event_#{event.id}")

    when Pito::FollowUp::Result::Append
      turn = Turn.find(turn_id)
      result.events.each do |e|
        new_event = Event.create_with_position!(
          conversation:,
          turn:,
          kind:    e[:kind],
          payload: e[:payload]
        )
        broadcaster.broadcast_event(new_event)
      end
      # Consume the source so its affordance is hidden + handle stays reserved.
      event.update!(payload: event.payload.merge("reply_consumed" => true))
      broadcaster.replace_event(event)
      broadcaster.complete_turn(turn:)

    when Pito::FollowUp::Result::Error
      error_payload = if result.message_key.to_s.start_with?("pito.")
        { message_key: result.message_key, message_args: result.message_args }
      else
        { text: result.message_key }
      end

      if turn_id
        turn = Turn.find(turn_id)
        err_event = Event.create_with_position!(
          conversation:, turn:, kind: :error, payload: error_payload
        )
        broadcaster.broadcast_event(err_event)
      else
        # mutate-mode error with no turn: create a minimal turn to hold the error.
        turn = conversation.turns.create!(
          position:   Turn.next_position_for(conversation),
          input_kind: :hashtag,
          input_text: "##{event.payload["reply_handle"]} #{rest}"
        )
        err_event = Event.create_with_position!(
          conversation:, turn:, kind: :error, payload: error_payload
        )
        broadcaster.broadcast_event(err_event)
      end
      broadcaster.complete_turn(turn:)
    end
  rescue StandardError => e
    Rails.logger.error("[FollowUpDispatchJob] Error processing event #{event_id}: #{e.class}: #{e.message}")
    raise
  end
end
