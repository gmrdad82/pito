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
      new_events = result.events.map do |e|
        new_event = Event.create_with_position!(
          conversation:,
          turn:,
          kind:    e[:kind],
          payload: e[:payload]
        )
        broadcaster.broadcast_event(new_event)
        new_event
      end
      # Consume the source (hide its affordance + reserve the handle) only when
      # the result opts in (consume: true, which is the default).  Repeatable
      # verbs such as link/unlink set consume: false so the card stays reusable.
      if result.consume
        event.update!(payload: event.payload.merge("reply_consumed" => true))
        broadcaster.replace_event(event)
      end
      # If any appended event carries a pending analytics marker, defer
      # resolve_thinking + complete_turn to AnalyticsFillJob — it fills the
      # data then resolves, mirroring the typed (ChatDispatchJob) path.
      if new_events.any? { |e| Pito::MessageBuilder::Analytics::Enhanced.pending?(e) }
        AnalyticsFillJob.perform_later(turn.id)
      else
        broadcaster.resolve_thinking(turn:)
        broadcaster.complete_turn(turn:)
      end

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
      broadcaster.resolve_thinking(turn:)
      broadcaster.complete_turn(turn:)
    end
  rescue StandardError => e
    Rails.logger.error("[FollowUpDispatchJob] Error processing event #{event_id}: #{e.class}: #{e.message}")

    # Guard: if Event.find(event_id) itself raised (event/conversation missing),
    # we have no conversation to broadcast to — just re-raise as before.
    ev = Event.find_by(id: event_id)
    raise unless ev

    conv       = ev.conversation
    bcaster    = Pito::Stream::Broadcaster.new(conversation: conv)
    error_text = Pito::Copy.render("pito.copy.errors.dispatch_failed")

    err_turn = if turn_id
      Turn.find_by(id: turn_id)
    else
      # Mutate path: no turn was created — make a minimal one to hold the error,
      # mirroring the Result::Error mutate branch.
      conv.turns.create!(
        position:   Turn.next_position_for(conv),
        input_kind: :hashtag,
        input_text: "##{ev.payload["reply_handle"]} #{rest}"
      )
    end

    if err_turn
      err_event = Event.create_with_position!(
        conversation: conv, turn: err_turn, kind: :error,
        payload: { text: error_text, detail: e.message }
      )
      bcaster.broadcast_event(err_event)
      bcaster.resolve_thinking(turn: err_turn)
      bcaster.complete_turn(turn: err_turn)
    end

    raise
  end
end
