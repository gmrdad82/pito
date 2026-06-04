# frozen_string_literal: true

class ChatController < ApplicationController
  include YoutubeConnectionOauthRedirect

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

    if login_command?(input)
      # Auth stays synchronous — it mints the session cookie, which can only be
      # set on the HTTP response (a background job can't set cookies).
      handle_login(input, conversation)
      return respond_to_client(conversation)
    end

    if logout_command?(input)
      # Logout stays synchronous — it clears the session cookie, which can only
      # be done on the HTTP response.
      handle_logout(input, conversation)
      return respond_to_client(conversation)
    end

    if connect_command?(input)
      # /connect initiates Google OAuth. Returns the OAuth URL on success, or nil
      # when credentials are missing (error Event is broadcast + normal 204 sent).
      # We respond with a Turbo Stream `navigate` action rather than redirect_to,
      # because Turbo submits forms via fetch — fetch follows the redirect chain
      # internally and can't trigger a real browser navigation to accounts.google.com.
      oauth_url = handle_connect(input, conversation)
      return oauth_url ? render_turbo_navigate(oauth_url) : respond_to_client(conversation)
    end

    if new_command?(input)
      # /new creates a fresh Conversation and navigates the browser to it.
      # Auth gating: mirrors /connect — requires an active session; returns a
      # mandatory-auth error event (broadcast to the current conversation) if not.
      # Uses render_turbo_navigate so Turbo's fetch-based form submission triggers
      # a real browser navigation rather than an in-fetch redirect.
      result = handle_new(input, conversation)
      return result ? render_turbo_navigate(result) : respond_to_client(conversation)
    end

    if resume_command?(input)
      # /resume populates the #pito-sidebar with a conversation list (Turbo Stream
      # update). Auth gating: requires an active session. No echo, no job dispatch.
      return handle_resume(conversation)
    end

    if confirmation_response?(input)
      # #handle confirm|cancel — no echo; updates the existing confirmation
      # segment to processing state, then enqueues ConfirmationDispatchJob.
      handle_confirmation(input, conversation)
      return respond_to_client(conversation)
    end

    if hashtag_message?(input)
      handle_hashtag(input, conversation)
      return respond_to_client(conversation)
    end

    # Mask sensitive kwargs before persisting the echo (T27.0.d).
    # The raw input is dispatched to the job; only the echo text is masked.
    echo_input = config_command?(input) ? mask_config_credentials(input) : input

    # Every other command — authenticated or not — goes through the async
    # pipeline (T23): persist + broadcast the echo now, enqueue the job, 204.
    # Auth gating is applied inside the job via the `authenticated` flag, because
    # Current.session is request-scoped and unavailable in the worker.
    handle_async(input, conversation, authenticated: Current.session.present?, echo_text: echo_input)
    respond_to_client(conversation)
  end

  private

  # ── Async dispatch (P23) ────────────────────────────────────────────────────

  def handle_async(input, conversation, authenticated:, echo_text: input)
    input_kind = input.start_with?("/") ? :slash : :chat
    channel = input_kind == :chat ? (params[:channel].presence || "@all") : nil
    period  = input_kind == :chat ? params[:period].presence : nil
    enqueue_turn(input, conversation, input_kind:, authenticated:, echo_text:, channel:, period:)
  end

  def handle_hashtag(input, conversation)
    enqueue_turn(input, conversation, input_kind: :hashtag, authenticated: Current.session.present?, echo_text: input, channel: nil, period: nil)
  end

  def enqueue_turn(input, conversation, input_kind:, authenticated:, echo_text:, channel:, period:)
    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind:,
      input_text: input
    )

    # Persist echo first, then broadcast (T23.1 + T23.2 / T24.1 + T24.2).
    # echo_text may differ from input when sensitive kwargs are masked (T27.0.d).
    # Slash / hashtag command echoes never show the channel filter in the meta line.
    broadcaster  = Pito::Stream::Broadcaster.new(conversation:)
    echo_event   = Event.create_with_position!(
      conversation:, turn:, kind: :echo,
      payload: { text: echo_text, authenticated: input_kind == :chat ? authenticated : false }
    )
    broadcaster.broadcast_event(echo_event)

    # T25: thinking indicator — one per turn, resolved by the backend when the
    # job completes. The word_index is frozen at creation (survives refresh).
    broadcaster.emit_thinking(turn:, dictionary: input_kind.to_s)

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

  def render_turbo_navigate(url)
    render(
      body: %(<turbo-stream action="navigate" target="#{CGI.escapeHTML(url)}"></turbo-stream>),
      content_type: "text/vnd.turbo-stream.html"
    )
  end

  # ── Authentication branch ───────────────────────────────────────────────────
  #
  # Stays synchronous — auth result must be visible before the next command.

  def login_command?(input)
    input.strip.match?(%r{\A/login(\s|\z)}i)
  end

  def handle_login(input, conversation)
    masked = mask_secret(input)

    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :slash,
      input_text: masked
    )

    broadcaster = Pito::Stream::Broadcaster.new(conversation:)
    broadcaster.emit(turn:, kind: :echo, payload: { text: masked, authenticated: false })

    broadcaster.emit_thinking(turn:, dictionary: "slash")

    code   = input.strip.split(/\s+/, 2)[1].to_s
    result = Pito::Auth::ChatLogin.call(code:, request:)

    broadcaster.resolve_thinking(turn:)

    if result.authenticated?
      Current.session = result.session_data
      greeting = I18n.t("pito.auth.greetings").sample
      broadcaster.emit(
        turn:,
        kind:    :system,
        payload: { text: greeting }
      )
      broadcaster.broadcast_auth_update(authenticated: true)
    else
      broadcaster.emit(
        turn:,
        kind:    "error",
        payload: { text: auth_error_key(result.status) }
      )
    end
  end

  # ── Logout branch ────────────────────────────────────────────────────────────
  #
  # Stays synchronous — must clear the session cookie on the HTTP response.

  def logout_command?(input)
    input.strip.match?(%r{\A/logout(\s|\z)}i)
  end

  def handle_logout(input, conversation)
    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :slash,
      input_text: input
    )

    broadcaster = Pito::Stream::Broadcaster.new(conversation:)
    broadcaster.emit(turn:, kind: :echo, payload: { text: input, authenticated: false, triggers_logout: true })
    broadcaster.emit(
      turn:,
      kind:    :system,
      payload: { text: I18n.t("pito.auth.logouts").sample }
    )

    Pito::Auth::SessionCookie.new(request).clear!
    Current.session = nil
  end

  def connect_command?(input)
    input.strip.match?(%r{\A/connect(\s|\z)}i)
  end

  # Returns the OAuth URL string to redirect to, or nil on any error
  # (an error Event is broadcast and the caller responds 204).
  def handle_connect(input, conversation)
    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :slash,
      input_text: input
    )
    broadcaster = Pito::Stream::Broadcaster.new(conversation:)

    # Auth gating: /connect requires an active session. Check before
    # touching Pito::Credentials (which hits Rails.cache / SolidCache).
    authenticated = Current.session.present?

    # Echo always comes first so the turn container exists in the DOM before
    # any subsequent event tries to append into it via Turbo Stream.
    broadcaster.emit(turn:, kind: :echo, payload: { text: input, authenticated: false })

    unless authenticated
      broadcaster.emit(
        turn:,
        kind:    "error",
        payload: { text: I18n.t("pito.auth.mandatories").sample }
      )
      return nil
    end

    unless Pito::Credentials.google_oauth_configured?
      broadcaster.emit(
        turn:,
        kind:    "error",
        payload: {
          text:        I18n.t("pito.slash.connect.errors.not_configured"),
          credentials: {
            client_id:     Pito::Credentials.google_oauth_client_id.present?,
            client_secret: Pito::Credentials.google_oauth_client_secret.present?,
            redirect_uri:  Pito::Credentials.google_oauth_redirect_uri,
            api_key:       Pito::Credentials.google_api_key.present?
          }
        }
      )
      return nil
    end
    stash_youtube_connect_intent
    stash_connect_conversation_uuid(conversation.uuid)

    "/auth/google_oauth2"
  end

  def new_command?(input)
    input.strip.match?(%r{\A/new(\s|\z)}i)
  end

  def resume_command?(input)
    input.strip.match?(%r{\A/resume(\s|\z)}i)
  end

  # Renders a Turbo Stream that populates #pito-sidebar with the conversation list.
  # Auth gating: unauthenticated → mandatory-auth error event broadcast + 204.
  # No echo, no Turn, no async job.
  def handle_resume(conversation)
    unless Current.session.present?
      broadcaster = Pito::Stream::Broadcaster.new(conversation:)
      broadcaster.emit(
        turn:    conversation.turns.create!(
          position:   Turn.next_position_for(conversation),
          input_kind: :slash,
          input_text: "/resume"
        ),
        kind:    "error",
        payload: { text: I18n.t("pito.auth.mandatories").sample }
      )
      return respond_to_client(conversation)
    end

    current_uuid = params[:uuid].presence
    render turbo_stream: turbo_stream.update(
      "pito-sidebar",
      Pito::Sidebar::Conversations::Component.new(
        groups:       Conversation.recency_groups,
        current_uuid: current_uuid
      )
    )
  end

  # Creates a fresh Conversation and returns its path for a Turbo Stream navigate,
  # or nil when the user is unauthenticated (auth error is broadcast; caller sends 204).
  def handle_new(input, conversation)
    broadcaster = Pito::Stream::Broadcaster.new(conversation:)

    unless Current.session.present?
      broadcaster.emit(
        turn:    conversation.turns.create!(
          position:   Turn.next_position_for(conversation),
          input_kind: :slash,
          input_text: input
        ),
        kind:    "error",
        payload: { text: I18n.t("pito.auth.mandatories").sample }
      )
      return nil
    end

    new_conversation = Conversation.create!
    conversation_path(new_conversation)
  end

  def confirmation_response?(input)
    input.strip.match?(Pito::ConfirmationRouter::PATTERN)
  end

  # T28.5a-b: No echo. Flip the confirmation segment to processing immediately,
  # then enqueue the job. Auth required — silently 204 if unauthenticated.
  def handle_confirmation(input, conversation)
    return unless Current.session.present?

    routing = Pito::ConfirmationRouter.call(input:, conversation:)
    return if routing[:error]

    event  = routing[:event]
    action = routing[:action]

    event.update!(payload: event.payload.merge("processing" => true))
    broadcaster = Pito::Stream::Broadcaster.new(conversation:)
    broadcaster.replace_event(event)

    ConfirmationDispatchJob.perform_later(event.id, action: action.to_s)
  end

  def hashtag_message?(input)
    input.start_with?("#") && !input.strip.match?(Pito::ConfirmationRouter::PATTERN)
  end

  def config_command?(input)
    input.strip.match?(%r{\A/config(\s|\z)}i)
  end

  # Mask client_id and client_secret kwarg values; redirect_uri is shown as-is.
  # Example: /config google client_id=abc client_secret=xyz redirect_uri=http://...
  #       →  /config google client_id=*** client_secret=*** redirect_uri=http://...
  MASKED_CONFIG_KEYS = %w[client_id client_secret api_key].freeze

  def mask_config_credentials(input)
    MASKED_CONFIG_KEYS.reduce(input) do |text, key|
      text.gsub(/(?<=\b#{key}=)\S+/, "***")
    end
  end

  def mask_secret(input)
    verb, rest = input.strip.split(/\s+/, 2)
    return input if rest.blank?

    "#{verb} #{'*' * rest.length}"
  end

  # Returns the already-resolved error text (not an i18n key).
  # Callers must store it under payload[:text], not payload[:message_key].
  def auth_error_key(status)
    case status
    when :throttled    then I18n.t("pito.auth.throttles").sample
    when :not_enrolled then I18n.t("pito.auth.not_enrolled")
    else                    I18n.t("pito.auth.failures").sample
    end
  end
end
