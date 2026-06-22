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

  def perform(event_id, rest:, turn_id: nil, period: nil, viewport_width: nil, channel: nil)
    event        = Event.find(event_id)
    conversation = event.conversation
    broadcaster  = Pito::Stream::Broadcaster.new(conversation:)
    finalizer    = Pito::Dispatch::Finalizer.new(conversation:, broadcaster:)

    target       = event.payload["reply_target"].to_s
    handler_class = Pito::FollowUp::Registry.for(target)

    if handler_class.nil?
      Rails.logger.warn("[FollowUpDispatchJob] No handler registered for target #{target.inspect} (event #{event_id})")
      return
    end

    # period / viewport_width / channel are threaded through to the delegated
    # chat verb (analytics window / list column auto-fill / scope) so a reply
    # dispatches identically to the same verb typed in free chat.
    result = handler_class.new.call(event:, rest:, conversation:, period:, viewport_width:, channel:)

    case result
    when Pito::FollowUp::Result::Mutation
      event.update!(kind: result.kind.to_s, payload: result.payload)
      broadcaster.replace_event(event)
      # Turn-less flow — emit pito:done against the mutated event so the
      # post-command dots fade out (no Turn is created for :mutate replies).
      broadcaster.broadcast_done(dom_id: "event_#{event.id}")

    when Pito::FollowUp::Result::Append
      turn = Turn.find(turn_id)
      # Persist + broadcast (with canonical kinds — the D1 fix: reply-appended
      # events now get the same :system/:enhanced canonicalisation as chat).
      persisted = finalizer.persist(events: result.events, turn:)
      # Consume the source (hide its affordance + reserve the handle) only when
      # the result opts in (consume: true, which is the default).  Repeatable
      # verbs such as link/unlink set consume: false so the card stays reusable.
      if result.consume
        event.update!(payload: event.payload.merge("reply_consumed" => true))
        broadcaster.replace_event(event)
      end
      # Analytics-fill gate (shared with the typed path): defer to
      # AnalyticsFillJob when an appended event is a pending analytics marker,
      # else resolve the thinking indicator + complete the turn.
      finalizer.complete(turn:, events: persisted)

    when Pito::FollowUp::Result::Error
      error_payload = Pito::Dispatch::Finalizer.error_payload(
        message_key: result.message_key, message_args: result.message_args
      )
      turn = if turn_id
        Turn.find(turn_id)
      else
        # mutate-mode error with no turn: create a minimal turn to hold the error.
        conversation.turns.create!(
          position:   Turn.next_position_for(conversation),
          input_kind: :hashtag,
          input_text: "##{event.payload["reply_handle"]} #{rest}"
        )
      end
      finalizer.append_and_complete(events: [ { kind: :error, payload: error_payload } ], turn:)
    end
  rescue StandardError => e
    Rails.logger.error("[FollowUpDispatchJob] Error processing event #{event_id}: #{e.class}: #{e.message}")

    # Guard: if Event.find(event_id) itself raised (event/conversation missing),
    # we have no conversation to broadcast to — just re-raise as before.
    ev = Event.find_by(id: event_id)
    raise unless ev

    conv = ev.conversation

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

    # Shared error path: emit a visible :error event, resolve the spinner, then
    # complete the turn (mirrors the typed pipeline's rescue).
    Pito::Dispatch::Finalizer.new(conversation: conv).surface_error(turn: err_turn, detail: e.message) if err_turn

    raise
  end
end
