# frozen_string_literal: true

class ChatController < ApplicationController
  include YoutubeConnectionOauthRedirect

  allow_anonymous :create

  def create
    input = params[:input].to_s

    # Home-transition: blank input + no uuid → create conversation only.
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

    # --help / -h is a universal flag. Intercept it before any fast-path
    # handler so that e.g. `/connect --help` never starts OAuth.
    unless help_flag?(input)
      if Pito::InputMasking.login_command?(input)
        # Auth stays synchronous — it mints the session cookie, which can only be
        # set on the HTTP response (a background job can't set cookies).
        was_authenticated = Current.session.present?
        handle_login(input, conversation)

        # On a conversation page, a successful login flips the visitor from
        # unauthenticated to authenticated. The scrollback was withheld while
        # unauthenticated and a live broadcast can't backfill the existing
        # history — so reload the conversation to render it now.
        if params[:uuid].present? && !was_authenticated && Current.session.present?
          return render_turbo_navigate(conversation_path(uuid: conversation.uuid))
        end

        return respond_to_client(conversation)
      end

      if logout_command?(input)
        # Logout stays synchronous — it clears the session cookie, which can only
        # be done on the HTTP response.
        handle_logout(input, conversation)
        return respond_to_client(conversation)
      end

      if Pito::InputMasking.config_credential_command?(input)
        # /config google|voyage|igdb|webhook carries secrets → handle
        # SYNCHRONOUSLY so the raw value is applied in-request and NEVER persisted:
        # the turn stores the masked form while the dispatcher receives the raw
        # input from memory. EVERY OTHER /config form (fx, motion, me, sound,
        # timezone, bare, --help) stays on the async pipeline below, exactly as
        # today. (--help is excluded by the help_flag? guard above regardless.)
        handle_config(input, conversation, authenticated: Current.session.present?)
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
        # Bare /resume populates the #pito-sidebar with a conversation list; a
        # `/resume <name>` opens that conversation, or — if none — broadcasts a
        # repliable "create it?" message with similar-name suggestions.
        return handle_resume(input, conversation)
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

      if bare_video_picker_command?(input)
        # `show vid` / `show video` / `show vids` / `show videos` with no title/id
        # → open the videos picker sidebar (Turbo Stream update).
        # Auth gating: requires an active session. No echo, no Turn, no async job.
        return handle_video_picker_sidebar(conversation)
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

    # Follow-up engine — handles `#<handle> <rest>` replies for any
    # event stamped with `reply_handle` + `reply_target` (including confirmations).
    # Only fires when a live (non-consumed) event carries the handle.
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

    # Non-credential /config (fx, motion, me, sound, timezone, bare, --help) still
    # flows async — mask any credential kwargs in the echo just as before (covers
    # the odd `/config google client_id=… --help` form that the help guard sends
    # here). Credential /config is handled synchronously above.
    echo_input = Pito::InputMasking.config_command?(input) ? Pito::InputMasking.mask_config_credentials(input) : input

    # Every other command — authenticated or not — goes through the async
    # pipeline: persist + broadcast the echo now, enqueue the job, 204. Auth
    # gating is applied inside the job via the `authenticated` flag, because
    # Current.session is request-scoped and unavailable in the worker.
    handle_async(input, conversation, authenticated: Current.session.present?, echo_text: echo_input)
    respond_to_client(conversation)
  end

  private

  # ── Async dispatch ──────────────────────────────────────────────────────────

  def handle_async(input, conversation, authenticated:, echo_text: input)
    input_kind = input.start_with?("/") ? :slash : :chat
    channel = input_kind == :chat ? (params[:channel].presence || "@all") : nil
    period  = input_kind == :chat ? params[:period].presence : nil
    # Scrollback width at send time, so `list` can auto-fill columns to fit.
    viewport_width = input_kind == :chat ? params[:viewport_width].presence : nil
    # Clear any persisted draft when a real message is sent.
    conversation.update_column(:draft, nil) if conversation.draft.present?
    # Prior #hashtag affordances are retired by the Finalizer when this command's
    # :system/:confirmation result renders (covers typed verbs AND replies-that-append
    # uniformly) — no send-time consume needed here.
    enqueue_turn(input, conversation, input_kind:, authenticated:, echo_text:, channel:, period:, viewport_width:)
  end

  def handle_hashtag(input, conversation)
    enqueue_turn(input, conversation, input_kind: :hashtag, authenticated: Current.session.present?, echo_text: input, channel: nil, period: nil, viewport_width: nil)
  end

  def enqueue_turn(input, conversation, input_kind:, authenticated:, echo_text:, channel:, period:, viewport_width: nil)
    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind:,
      input_text: input
    )

    broadcaster = Pito::Stream::Broadcaster.new(conversation:)

    # Persist echo first, then broadcast.
    # echo_text may differ from input when sensitive kwargs are masked.
    # Slash / hashtag command echoes never show the channel filter in the meta line.
    echo_event   = Event.create_with_position!(
      conversation:, turn:, kind: :echo,
      payload: { text: echo_text, authenticated: input_kind == :chat ? authenticated : false }
    )
    broadcaster.broadcast_event(echo_event)

    # Thinking indicator — one per turn, resolved by the backend when the
    # job completes. The word_index is frozen at creation (survives refresh).
    broadcaster.emit_thinking(turn:, dictionary: input_kind == :hashtag ? "chat" : input_kind.to_s)

    # Enqueue job — auth gating decided here, applied in the worker.
    ChatDispatchJob.perform_later(turn.id, channel:, period:, authenticated:, viewport_width:)
  end

  # /config is the only credential-bearing command, so it runs SYNCHRONOUSLY: the
  # turn stores the MASKED form (raw credentials never persist in the conversation),
  # while the dispatcher receives the RAW input from memory to apply the real
  # values. UX is identical to the async path — echo → thinking → result via the
  # broadcaster — and the dispatch runs inline (no ChatDispatchJob, no retry).
  def handle_config(input, conversation, authenticated:)
    masked = Pito::InputMasking.mask_config_credentials(input)

    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :slash,
      input_text: masked
    )

    broadcaster = Pito::Stream::Broadcaster.new(conversation:)
    echo_event  = Event.create_with_position!(
      conversation:, turn:, kind: :echo, payload: { text: masked, authenticated: false }
    )
    broadcaster.broadcast_event(echo_event)
    broadcaster.emit_thinking(turn:, dictionary: "slash")

    # Auth gating mirrors ChatDispatchJob: an unauthenticated session may only
    # /login — /config requires a session.
    result = if authenticated
      Pito::Slash::Dispatcher.call(input:, conversation:, authenticated:)
    else
      Pito::Chat::Result::Error.new(
        message_key: Pito::Copy.render("pito.copy.auth.mandatories"), message_args: {}
      )
    end

    Pito::Dispatch::Finalizer.new(conversation:).append_and_complete(
      events: Pito::Dispatch::Finalizer.result_events(result), turn:
    )
  rescue StandardError => e
    Pito::Dispatch::Finalizer.new(conversation:).surface_error(turn:, detail: e.message) if turn
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
      head :no_content
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

  def handle_login(input, conversation)
    masked = Pito::InputMasking.mask_secret(input)

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
        kind:    :error,
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
    input.strip.match?(%r{\A/(?:logout|exit|quit)(\s|\z)}i)
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
        kind:    :error,
        payload: { text: Pito::Copy.render("pito.copy.auth.mandatories") }
      )
      return nil
    end

    unless Pito::Credentials.google_oauth_configured?
      broadcaster.emit(
        turn:,
        kind:    :error,
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

  # Detects `show vid(s)?` / `show video(s)?` with NO trailing title or ID —
  # i.e. the user wants the videos picker, not a lookup.
  # Returns true when the input is bare "show + video noun(s)", nil otherwise.
  VIDEO_NOUN_PATTERN = /\A(?:vid|vids|video|videos)\z/i.freeze

  def bare_video_picker_command?(input)
    words = input.to_s.strip.downcase.split
    return nil if words.empty?

    return nil unless words.first == "show"

    rest_words = words.drop(1)
    rest_words.present? && rest_words.all? { |w| VIDEO_NOUN_PATTERN.match?(w) }
  end

  # Renders a Turbo Stream that populates #pito-sidebar with the videos picker.
  # Auth gating: unauthenticated → mandatory-auth error event broadcast + 204.
  # No echo, no Turn, no async job.
  def handle_video_picker_sidebar(conversation)
    unless Current.session.present?
      broadcaster = Pito::Stream::Broadcaster.new(conversation:)
      broadcaster.emit(
        turn:    conversation.turns.create!(
          position:   Turn.next_position_for(conversation),
          input_kind: :chat,
          input_text: "show vid"
        ),
        kind:    :error,
        payload: { text: Pito::Copy.render("pito.copy.auth.mandatories") }
      )
      return respond_to_client(conversation)
    end

    render partial: "chat/video_picker_sidebar",
           formats: [ :turbo_stream ],
           locals:  {
             videos: Video.includes(:channel).order(:title).limit(50)
           }
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
        kind:    :error,
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
  def handle_resume(input, conversation)
    unless Current.session.present?
      broadcaster = Pito::Stream::Broadcaster.new(conversation:)
      broadcaster.emit(
        turn:    conversation.turns.create!(
          position:   Turn.next_position_for(conversation),
          input_kind: :slash,
          input_text: input
        ),
        kind:    :error,
        payload: { text: Pito::Copy.render("pito.copy.auth.mandatories") }
      )
      return respond_to_client(conversation)
    end

    # `/resume <name>`: exact (case-insensitive) title match → open it; no match →
    # broadcast a repliable "create it?" message + up to-5 similarly-named convos.
    name = slash_arg(input, "resume")
    if name.present?
      target = ::Conversation.find_by_title_ci(name)
      return render_turbo_navigate(conversation_path(target)) if target

      broadcaster = Pito::Stream::Broadcaster.new(conversation:)
      broadcaster.emit(
        turn:    conversation.turns.create!(
          position:   Turn.next_position_for(conversation),
          input_kind: :slash,
          input_text: input
        ),
        kind:    :system,
        payload: Pito::MessageBuilder::Conversation::ResumeMissing.call(
          name:         name,
          similar:      ::Conversation.similar_titles(name),
          conversation: conversation
        )
      )
      return respond_to_client(conversation)
    end

    # Bare `/resume` → the resume sidebar (unchanged).
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
        kind:    :error,
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
        kind:    :error,
        payload: { text: Pito::Copy.render("pito.copy.auth.mandatories") }
      )
      return respond_to_client(conversation)
    end

    render partial: "chat/game_picker_sidebar",
           formats: [ :turbo_stream ],
           locals:  {
             games: Game.order(:title).limit(50),
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
        kind:    :error,
        payload: { text: Pito::Copy.render("pito.copy.auth.mandatories") }
      )
      return nil
    end

    new_conversation = Conversation.create!
    # `/new <name>` → title the fresh conversation (broadcasts the name + global
    # sidebar row via Conversation::Rename). Bare `/new` keeps the default title.
    name = slash_arg(input, "new")
    Conversation::Rename.call(conversation: new_conversation, title: name) if name.present?
    conversation_path(new_conversation)
  end

  # The free-text argument after a `/<verb>` slash command (e.g. the name for
  # `/new <name>` / `/resume <name>`), or "" when bare.
  def slash_arg(input, verb)
    input.to_s.strip.sub(%r{\A/#{verb}\b\s*}i, "").strip
  end

  # ── Follow-up engine dispatch ────────────────────────────────────────────────

  # Dispatch a matched follow-up reply to the appropriate path by mode.
  #
  # :mutate — no echo, no turn.  Requires an active session; silently falls
  #           through if unauthenticated.  Enqueues FollowUpDispatchJob without a turn_id.
  # :append — echo + turn + thinking indicator (mirrors enqueue_turn).
  #           Requires an active session; silently falls through if unauthenticated.
  def handle_follow_up(input, conversation, ff)
    event  = ff[:event]
    target = event.payload["reply_target"].to_s

    # --help intercept: `#<handle> --help` → target page;
    # `#<handle> <action> --help` → action page.
    # Renders synchronously (like login/logout) and returns early.
    help_payload = follow_up_help_payload(target, ff[:rest], event:)
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
    # Universal verbs (share / revoke / unshare) work on any reply_handle event
    # regardless of its reply_target. Force :append mode so a turn + echo are
    # created before FollowUpDispatchJob runs its universal short-circuit.
    mode =
      if Pito::Share::UniversalActions::VERBS.include?(action)
        :append
      else
        Pito::FollowUp::Registry.mode_for(target, action:)
      end

    # Thread the same dispatch context the typed pipeline carries (mirrors
    # handle_async): channel scope, analytics period, and scrollback width — so
    # the delegated chat verb runs identically to the same verb typed in chat.
    # Missing any one of these silently drops it, so they travel in lockstep
    # across every hop down to Chat::Dispatcher.
    channel        = params[:channel].presence || "@all"
    period         = params[:period].presence
    viewport_width = params[:viewport_width].presence
    # Request origin (scheme + host + port, e.g. "https://dev.pitomd.com") so the
    # async `share` verb mints a /share URL on the host the owner is actually using
    # — NOT the static PublicHosts.app_base (localhost in a tunnelled dev setup).
    origin         = request.base_url

    case mode
    when :mutate
      return unless Current.session.present?

      FollowUpDispatchJob.perform_later(event.id, rest: ff[:rest], period:, viewport_width:, channel:, origin:)

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
      broadcaster.emit_thinking(turn:, dictionary: "chat")

      FollowUpDispatchJob.perform_later(event.id, rest: ff[:rest], turn_id: turn.id, period:, viewport_width:, channel:, origin:)

    else
      # Unknown mode (handler not registered, or handler has no mode).
      # Silently return — fall-through to next branches already prevented by
      # the caller's `return respond_to_client`.
      Rails.logger.warn("[FollowUp] Unknown mode #{mode.inspect} for target #{target.inspect}")
    end
  end

  # Returns a HashtagHelp payload Hash (or nil) for the --help flag in a follow-up rest string.
  # `rest` is everything after `#<handle> `.
  #   "--help"              → target-level page (universal share rows gated by event's Share)
  #   "<action> --help"     → action-level page
  #   anything else         → nil (fall through to normal dispatch)
  def follow_up_help_payload(target, rest, event: nil)
    stripped = rest.to_s.strip
    if stripped == "--help"
      Pito::MessageBuilder::HashtagHelp.call(target:, event:)
    elsif (m = stripped.match(/\A(\S+)(?:\s+by)?\s+--help\z/i))
      Pito::MessageBuilder::HashtagHelp.call(target:, action: m[1], event:)
    end
  end

  def hashtag_message?(input)
    input.start_with?("#")
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
