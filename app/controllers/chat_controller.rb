# frozen_string_literal: true

class ChatController < ApplicationController
  allow_anonymous :create

  def create
    input = params[:input].to_s

    # Home→chat transition (T22): blank input + no uuid → create conversation only.
    # JS calls this first to get the UUID and signed stream name for cable setup,
    # then calls again with uuid + actual input to process the message.
    if input.blank? && params[:uuid].blank?
      conversation = Conversation.create!
      return render json: {
        uuid: conversation.uuid,
        signed_stream_name: Turbo::StreamsChannel.signed_stream_name(
          "pito:conversation:#{conversation.uuid}"
        )
      }, status: :created
    end

    return head :no_content if input.blank?

    conversation = resolve_conversation

    if authenticate_command?(input)
      handle_authenticate(input, conversation)
    elsif Current.session.present?
      if input.start_with?("/")
        handle_slash(input, conversation)
      else
        handle_chat(input, conversation)
      end
    else
      handle_unauthenticated(input, conversation)
    end

    if params[:uuid].present?
      head :no_content
    elsif html_request?
      redirect_to conversation_path(uuid: conversation.uuid)
    else
      render json: { uuid: conversation.uuid }, status: :created
    end
  end

  private

  # ── Conversation resolution ─────────────────────────────────────────

  def html_request?
    request.format.html? || request.headers["Accept"]&.include?("text/html")
  end

  def resolve_conversation
    if params[:uuid].present?
      Conversation.find_by!(uuid: params[:uuid])
    else
      Conversation.create!
    end
  end

  # ── Authentication branch ──────────────────────────────────────────
  #
  # `/authenticate <code>` is the single login entry point (no /login
  # route). The 6-digit code is masked before it is echoed or persisted
  # so the real code never touches the DB or the scrollback.

  def authenticate_command?(input)
    input.strip.match?(%r{\A/authenticate(\s|\z)}i)
  end

  def handle_authenticate(input, conversation)
    masked = mask_secret(input)

    turn = conversation.turns.create!(
      position: Turn.next_position_for(conversation),
      input_kind: "slash",
      input_text: masked
    )

    broadcaster = Pito::Stream::Broadcaster.new(conversation:)
    broadcaster.emit(turn:, kind: "echo", payload: { text: masked })

    code = input.strip.split(/\s+/, 2)[1].to_s
    result = Pito::Auth::ChatLogin.call(code:, request:)

    if result.authenticated?
      Current.session = result.session_data
      broadcaster.emit(
        turn:,
        kind: "assistant_text",
        payload: { message_key: "pito.auth.authenticated", message_args: {} }
      )
    else
      broadcaster.emit(
        turn:,
        kind: "error",
        payload: { message_key: auth_error_key(result.status), message_args: {} }
      )
    end
  end

  # Masks everything after the verb: `/authenticate 123456` → `/authenticate ******`.
  def mask_secret(input)
    verb, rest = input.strip.split(/\s+/, 2)
    return input if rest.blank?

    "#{verb} #{'*' * rest.length}"
  end

  def auth_error_key(status)
    case status
    when :throttled    then "pito.auth.throttled"
    when :not_enrolled then "pito.auth.not_enrolled"
    else                    "pito.auth.failed"
    end
  end

  # Any non-`/authenticate` command issued without a session is refused.
  def handle_unauthenticated(input, conversation)
    turn = conversation.turns.create!(
      position: Turn.next_position_for(conversation),
      input_kind: input.start_with?("/") ? "slash" : "chat",
      input_text: input
    )

    broadcaster = Pito::Stream::Broadcaster.new(conversation:)
    broadcaster.emit(turn:, kind: "echo", payload: { text: input })
    broadcaster.emit(
      turn:,
      kind: "error",
      payload: { message_key: "pito.auth.required", message_args: {} }
    )
  end

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
