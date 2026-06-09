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

    # P56: --help / -h is a universal flag. Intercept it before any fast-path
    # handler so that e.g. `/connect --help` never starts OAuth.
    unless help_flag?(input)
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

      if bare_themes_command?(input)
        # Bare /themes (no args) opens the theme picker sidebar (Turbo Stream update).
        # Auth gating: requires an active session. No echo, no Turn, no async job.
        return handle_theme_sidebar(conversation)
      end

      if (picker_mode = bare_game_picker_command?(input))
        # `show game` / `rm game` / `delete game` with no title/id → open the
        # games picker sidebar (Turbo Stream update).
        # Auth gating: requires an active session.  No echo, no Turn, no async job.
        return handle_game_picker_sidebar(conversation, mode: picker_mode)
      end

      if (import_title = games_import_command?(input))
        # `/games import [title]` — opens the IGDB import sidebar (Turbo Stream update).
        # Auth gating: requires an active session. No echo, no Turn, no async job.
        return handle_games_import_sidebar(conversation, prefill: import_title)
      end

      if (import_title = import_game_command?(input))
        # Free-chat `import game[s] [title]` — same IGDB import sidebar as above.
        # Auth gating: identical to the /games import path (session required).
        # No echo, no Turn, no async job.
        return handle_games_import_sidebar(conversation, prefill: import_title)
      end
    end

    # Follow-up engine (P13/P14) — handles `#<handle> <rest>` replies for any
    # event stamped with `reply_handle` + `reply_target` (including confirmations
    # since P14).  Only fires when a live (non-consumed) event carries the handle.
    # :not_found / :not_a_follow_up fall through to the hashtag path below.
    ff = Pito::FollowUp::Router.call(input:, conversation:)
    if ff[:status] == :ok
      handle_follow_up(input, conversation, ff)
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
    # T47.3: clear any persisted draft when a real message is sent.
    conversation.update_column(:draft, nil) if conversation.draft.present?
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

  # True when the input carries a --help or -h flag anywhere after the verb.
  # Used to bypass fast-path handlers (login/logout/connect/new/resume) so
  # that --help never triggers side effects.
  def help_flag?(input)
    input.match?(/\s--help\b|\s-h\b/)
  end

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
      greeting = Pito::Copy.render("pito.copy.auth.greetings")
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

    # Synchronous flow — emit the done signal ourselves so the dots fade out
    # (no ChatDispatchJob runs to call complete_turn for login).
    broadcaster.complete_turn(turn:)
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
      payload: { text: Pito::Copy.render("pito.copy.auth.logouts") }
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
    # The /connect input is consumed into the turn echo here. Clear any
    # persisted draft (mirrors handle_async) so the chatbox doesn't rehydrate
    # "/connect" when the OAuth round-trip reloads the conversation page.
    conversation.update_column(:draft, nil) if conversation.draft.present?
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
        payload: { text: Pito::Copy.render("pito.copy.auth.mandatories") }
      )
      return nil
    end

    unless Pito::Credentials.google_oauth_configured?
      broadcaster.emit(
        turn:,
        kind:    "error",
        payload: {
          text:        Pito::Copy.render("pito.copy.connect.not_configured"),
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

  # True for `/themes`, `/themes list`, and `/themes ls` — all open the sidebar.
  # `/themes apply <name>`, `/themes preview <name>`, and other subcommands go
  # through the async pipeline.
  def bare_themes_command?(input)
    input.strip.match?(%r{\A/themes(?:\s+(?:list|ls))?\z}i)
  end

  # Detects `show game(s)?` / `delete game(s)?` / `rm game(s)?` with NO
  # trailing title or ID — i.e. the user wants the picker, not a lookup.
  # Returns the picker mode Symbol (:show or :delete) or nil.
  # The noun words `game`/`games` are optional (user may type just `show`).
  GAME_NOUN_PATTERN = /\A(?:game|games)\z/i.freeze

  def bare_game_picker_command?(input)
    words = input.to_s.strip.downcase.split
    return nil if words.empty?

    verb = words.first
    # After the verb, any remaining words must be only noun tokens.
    rest_words = words.drop(1)
    rest_only_nouns = rest_words.all? { |w| GAME_NOUN_PATTERN.match?(w) }
    return nil unless rest_only_nouns

    case verb
    when "show"  then :show
    when "delete" then :delete
    when "rm"    then :delete
    end
  end

  # Detects `/games import [title]` and returns the title string (may be "").
  # Returns nil if the input doesn't match.
  # The fast-path covers all `/games import` variants (with or without a title).
  # Other `/games` subcommands / unknown args go through the async pipeline so
  # the handler can return the witty usage hint.
  def games_import_command?(input)
    m = input.to_s.strip.match(%r{\A/games\s+import(?:\s+(.*))?\z}i)
    return nil unless m
    m[1].to_s.strip
  end

  # Detects free-chat `import game[s] [title]` and returns the title string
  # (may be ""). Returns nil if the input doesn't match.
  # Case-insensitive; captures everything after "game"/"games" as the prefill.
  # Slash commands (`/import …`) never match — they start with `/`.
  def import_game_command?(input)
    m = input.to_s.strip.match(/\Aimport\s+games?(?:\s+(.*))?\z/i)
    return nil unless m
    m[1].to_s.strip
  end

  # Renders a Turbo Stream that populates #pito-sidebar with the IGDB import sidebar.
  # prefill: optional title string to pre-fill the search box with.
  # Auth gating: unauthenticated → mandatory-auth error event broadcast + 204.
  # No echo, no Turn, no async job.
  def handle_games_import_sidebar(conversation, prefill:)
    unless Current.session.present?
      broadcaster = Pito::Stream::Broadcaster.new(conversation:)
      broadcaster.emit(
        turn:    conversation.turns.create!(
          position:   Turn.next_position_for(conversation),
          input_kind: :slash,
          input_text: "/games import"
        ),
        kind:    "error",
        payload: { text: Pito::Copy.render("pito.copy.auth.mandatories") }
      )
      return respond_to_client(conversation)
    end

    render partial: "chat/games_import_sidebar",
           formats: [ :turbo_stream ],
           locals:  {
             prefill:          prefill.to_s,
             conversation_uuid: conversation.uuid
           }
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
        payload: { text: Pito::Copy.render("pito.copy.auth.mandatories") }
      )
      return respond_to_client(conversation)
    end

    current_uuid = params[:uuid].presence
    render partial: "chat/resume_sidebar",
           formats: [ :turbo_stream ],
           locals:  {
             groups:       Conversation.recency_groups,
             current_uuid: current_uuid
           }
  end

  # Renders a Turbo Stream that populates #pito-sidebar with the theme picker.
  # Auth gating: unauthenticated → mandatory-auth error event broadcast + 204.
  # No echo, no Turn, no async job.
  def handle_theme_sidebar(conversation)
    unless Current.session.present?
      broadcaster = Pito::Stream::Broadcaster.new(conversation:)
      broadcaster.emit(
        turn:    conversation.turns.create!(
          position:   Turn.next_position_for(conversation),
          input_kind: :slash,
          input_text: "/themes"
        ),
        kind:    "error",
        payload: { text: Pito::Copy.render("pito.copy.auth.mandatories") }
      )
      return respond_to_client(conversation)
    end

    render partial: "chat/theme_sidebar",
           formats: [ :turbo_stream ],
           locals:  {
             groups:        Pito::Themes::Registry.grouped,
             current_theme: AppSetting.theme
           }
  end

  # Renders a Turbo Stream that populates #pito-sidebar with the games picker.
  # mode: :show or :delete — controls the command built on selection.
  # Auth gating: unauthenticated → mandatory-auth error event broadcast + 204.
  # No echo, no Turn, no async job.
  def handle_game_picker_sidebar(conversation, mode:)
    unless Current.session.present?
      broadcaster = Pito::Stream::Broadcaster.new(conversation:)
      broadcaster.emit(
        turn:    conversation.turns.create!(
          position:   Turn.next_position_for(conversation),
          input_kind: :chat,
          input_text: mode == :delete ? "delete game" : "show game"
        ),
        kind:    "error",
        payload: { text: Pito::Copy.render("pito.copy.auth.mandatories") }
      )
      return respond_to_client(conversation)
    end

    render partial: "chat/game_picker_sidebar",
           formats: [ :turbo_stream ],
           locals:  {
             games: Game.order(:title).all,
             mode:  mode
           }
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
        payload: { text: Pito::Copy.render("pito.copy.auth.mandatories") }
      )
      return nil
    end

    new_conversation = Conversation.create!
    conversation_path(new_conversation)
  end

  # ── Follow-up engine dispatch (P13) ──────────────────────────────────────────

  # Dispatch a matched follow-up reply to the appropriate path by mode.
  #
  # :mutate — no echo, no turn.  Enqueue FollowUpDispatchJob without a turn_id.
  # :append — echo + turn (like confirmations).  Requires an active session;
  #           silently falls through if unauthenticated.
  #           NOTE: no thinking indicator is emitted in the append path for now.
  def handle_follow_up(input, conversation, ff)
    event  = ff[:event]
    target = event.payload["reply_target"].to_s

    # --help intercept: `#<handle> --help` → target page;
    # `#<handle> <action> --help` → action page.
    # Renders synchronously (like login/logout) and returns early.
    help_payload = follow_up_help_payload(target, ff[:rest])
    if help_payload
      return unless Current.session.present?

      turn = conversation.turns.create!(
        position:   Turn.next_position_for(conversation),
        input_kind: :hashtag,
        input_text: input
      )
      broadcaster = Pito::Stream::Broadcaster.new(conversation:)
      broadcaster.emit(turn:, kind: :echo,   payload: { text: input, authenticated: false })
      broadcaster.emit(turn:, kind: :system, payload: help_payload)
      broadcaster.complete_turn(turn:)
      return
    end

    # Extract the first word of rest as the action name for per-action mode lookup.
    # This allows handlers to declare different modes per action (e.g. add: :mutate,
    # show: :append) while sharing a single handler class.
    action = ff[:rest].to_s.split(/\s+/).first&.downcase
    mode = Pito::FollowUp::Registry.mode_for(target, action:)

    case mode
    when :mutate
      FollowUpDispatchJob.perform_later(event.id, rest: ff[:rest])

    when :append
      return unless Current.session.present?

      turn = conversation.turns.create!(
        position:   Turn.next_position_for(conversation),
        input_kind: :hashtag,
        input_text: input
      )

      broadcaster = Pito::Stream::Broadcaster.new(conversation:)
      echo_event  = Event.create_with_position!(
        conversation:, turn:, kind: :echo,
        payload: { text: input, authenticated: false }
      )
      broadcaster.broadcast_event(echo_event)

      # No thinking indicator for append follow-ups (to be added if needed).
      FollowUpDispatchJob.perform_later(event.id, rest: ff[:rest], turn_id: turn.id)

    else
      # Unknown mode (handler not registered, or handler has no mode).
      # Silently return — fall-through to next branches already prevented by
      # the caller's `return respond_to_client`.
      Rails.logger.warn("[FollowUp] Unknown mode #{mode.inspect} for target #{target.inspect}")
    end
  end

  # Returns a HashtagHelp payload Hash (or nil) for the --help flag in a follow-up rest string.
  # `rest` is everything after `#<handle> `.
  #   "--help"              → target-level page
  #   "<action> --help"     → action-level page
  #   anything else         → nil (fall through to normal dispatch)
  def follow_up_help_payload(target, rest)
    stripped = rest.to_s.strip
    if stripped == "--help"
      Pito::MessageBuilder::HashtagHelp.call(target:)
    elsif (m = stripped.match(/\A(\S+)\s+--help\z/i))
      Pito::MessageBuilder::HashtagHelp.call(target:, action: m[1])
    end
  end

  def hashtag_message?(input)
    input.start_with?("#")
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
    when :throttled    then Pito::Copy.render("pito.copy.auth.throttles")
    when :not_enrolled then Pito::Copy.render("pito.copy.auth.not_enrolled")
    else                    Pito::Copy.render("pito.copy.auth.failures")
    end
  end
end
