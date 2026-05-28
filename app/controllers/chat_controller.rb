# frozen_string_literal: true

class ChatController < ApplicationController
  allow_anonymous :create

  def create
    input = params[:input].to_s
    return head :no_content if input.blank?

    conversation = current_conversation
    input_kind = input.start_with?("/") ? "slash" : "chat"

    turn = conversation.turns.create!(
      position: Turn.next_position_for(conversation),
      input_kind:,
      input_text: input
    )

    broadcaster = Pito::Stream::Broadcaster.new(conversation:)

    # Always echo the user input
    broadcaster.emit(turn:, kind: "echo", payload: { text: input })

    if input.start_with?("/")
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

    head :no_content
  end
end
