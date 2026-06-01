# frozen_string_literal: true

class ChatController < ApplicationController
  allow_anonymous :create

  def create
    input = params[:input].to_s

    # T22 / Home-transition: blank input + no uuid → create conversation only.
    # Returns {uuid, signed_stream_name} so the JS can set up the cable before
    # posting the actual message.
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
      # Auth stays synchronous — it mints the session cookie, which can only be
      # set on the HTTP response (a background job can't set cookies).
      handle_authenticate(input, conversation)
      return respond_to_client(conversation)
    end

    # Every other command — authenticated or not — goes through the async
    # pipeline (T23): persist + broadcast the echo now, enqueue the job, 204.
    # Auth gating is applied inside the job via the `authenticated` flag, because
    # Current.session is request-scoped and unavailable in the worker.
    handle_async(input, conversation, authenticated: Current.session.present?)
    respond_to_client(conversation)
  end

  private

  # ── Async dispatch (P23) ────────────────────────────────────────────────────

  def handle_async(input, conversation, authenticated:)
    input_kind = input.start_with?("/") ? "slash" : "chat"

    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind:,
      input_text: input
    )

    # Persist echo first, then broadcast (T23.1 + T23.2 / T24.1 + T24.2 — the
    # echo Segment carries the exact submitted text).
    echo_event = conversation.events.create!(
      turn:,
      position: Event.next_position_for(conversation),
      kind:     "echo",
      payload:  { text: input }
    )
    Pito::Stream::Broadcaster.new(conversation:).broadcast_event(echo_event)

    # T23.3: read channel + period from params (defaults until TAB/Shift+TAB land).
    channel = params[:channel].presence || "@all"
    period  = params[:period].presence

    # T23.4: enqueue job — auth gating decided here, applied in the worker.
    ChatDispatchJob.perform_later(turn.id, channel:, period:, authenticated:)
  end

  # ── Conversation resolution ─────────────────────────────────────────────────

  def resolve_conversation
    if params[:uuid].present?
      Conversation.find_by!(uuid: params[:uuid])
    else
      Conversation.create!
    end
  end

  def respond_to_client(conversation)
    if params[:uuid].present?
      head :no_content                                           # T23.5
    elsif html_request?
      redirect_to conversation_path(uuid: conversation.uuid)
    else
      render json: { uuid: conversation.uuid }, status: :created
    end
  end

  def html_request?
    request.format.html? || request.headers["Accept"]&.include?("text/html")
  end

  # ── Authentication branch ───────────────────────────────────────────────────
  #
  # Stays synchronous — auth result must be visible before the next command.

  def authenticate_command?(input)
    input.strip.match?(%r{\A/authenticate(\s|\z)}i)
  end

  def handle_authenticate(input, conversation)
    masked = mask_secret(input)

    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: "slash",
      input_text: masked
    )

    broadcaster = Pito::Stream::Broadcaster.new(conversation:)
    broadcaster.emit(turn:, kind: "echo", payload: { text: masked })

    code   = input.strip.split(/\s+/, 2)[1].to_s
    result = Pito::Auth::ChatLogin.call(code:, request:)

    if result.authenticated?
      Current.session = result.session_data
      broadcaster.emit(
        turn:,
        kind:    "assistant_text",
        payload: { message_key: "pito.auth.authenticated", message_args: {} }
      )
    else
      broadcaster.emit(
        turn:,
        kind:    "error",
        payload: { message_key: auth_error_key(result.status), message_args: {} }
      )
    end
  end

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
end
