# frozen_string_literal: true

class ChatController < ApplicationController
  allow_anonymous :create

  def create
    input = params[:input].to_s
    return head :no_content if input.blank?

    conversation = current_conversation

    if input.start_with?("/")
      handle_slash(input, conversation)
    else
      handle_chat(input, conversation)
    end

    head :no_content
  end

  private

  # ── Slash branch (Plan 2) ──────────────────────────────────────────

  def handle_slash(input, conversation)
    turn = conversation.turns.create!(
      position: Turn.next_position_for(conversation),
      input_kind: "slash",
      input_text: input
    )

    broadcaster = Pito::Stream::Broadcaster.new(conversation:)
    broadcaster.emit(turn:, kind: "echo", payload: { text: input })

    result = Pito::Slash::Dispatcher.call(input:, conversation:)

    case result
    when Pito::Slash::Result::Ok
      result.events.each do |event_params|
        broadcaster.emit(turn:, kind: event_params[:kind], payload: event_params[:payload])
      end
    when Pito::Slash::Result::Error
      broadcaster.emit(
        turn:,
        kind: "error",
        payload: { message_key: result.message_key, message_args: result.message_args }
      )
    when Pito::Slash::Result::NeedsConfirmation
      broadcaster.emit(
        turn:,
        kind: "confirmation_prompt",
        payload: {
          prompt_key: result.prompt_key,
          prompt_args: result.prompt_args,
          command_text: result.command_text
        }
      )
    end
  end

  # ── Chat branch (Plan 3) ───────────────────────────────────────────

  def handle_chat(input, conversation)
    result = Pito::Chat::Dispatcher.call(input:, conversation:)

    case result
    when Pito::Chat::Result::Ok
      turn = current_or_new_turn(conversation:, input_text: input, input_kind: "chat")
      emit_chat_events(conversation, turn, input, result.events)
    when Pito::Chat::Result::Error
      turn = current_or_new_turn(conversation:, input_text: input, input_kind: "chat")
      error_event = { kind: "error", payload: { message_key: result.message_key, message_args: result.message_args } }
      emit_chat_events(conversation, turn, input, [ error_event ])
    when Pito::Chat::Result::Refine
      turn = current_or_new_turn(conversation:, input_text: input, input_kind: "chat", attach_to_existing: true)
      emit_chat_events(conversation, turn, input, result.events)
    end
  end

  # ── Shared helpers ─────────────────────────────────────────────────

  # Returns the Turn to attach events to.
  # When attach_to_existing is true, uses the most recent open Turn
  # (must exist — the chat parser already verified refinement eligibility).
  # Otherwise, creates a new Turn.
  def current_or_new_turn(conversation:, input_text:, input_kind:, attach_to_existing: false)
    if attach_to_existing
      Turn.last_for(conversation)
    else
      conversation.turns.create!(
        position: Turn.next_position_for(conversation),
        input_kind:,
        input_text:
      )
    end
  end

  def emit_chat_events(conversation, turn, input, events)
    broadcaster = Pito::Stream::Broadcaster.new(conversation:)
    broadcaster.emit(turn:, kind: "echo", payload: { text: input })
    events.each do |event_params|
      broadcaster.emit(turn:, kind: event_params[:kind], payload: event_params[:payload])
    end
  end
end
