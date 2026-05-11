class SettingsController < ApplicationController
  OAUTH_KEYS = %w[youtube_client_id youtube_client_secret youtube_redirect_uri].freeze
  GENERAL_KEYS = %w[max_panes pane_title_length].freeze

  def index
    @settings = (OAUTH_KEYS + GENERAL_KEYS).index_with { |key| AppSetting.get(key) }
    @max_panes_default = ENV.fetch("MAX_PANES", 3).to_i
    @pane_title_length_default = ENV.fetch("PANE_TITLE_LENGTH", 14).to_i
    @theme = AppSetting.get("theme") || "auto"
    # 2026-05-11 — keyboard-navigation master toggle. Stored as a Boolean
    # column on the singleton AppSetting row (NOT NULL, default true).
    # When no row exists yet we fall back to true so the install starts
    # with the feature enabled, matching the column default. The view
    # renders a yes/no radio pair; the layout surfaces the setting to
    # Stimulus via `data-keyboard-navigation-enabled` on `<body>`.
    @keyboard_navigation_enabled = AppSetting.keyboard_navigation_enabled?
    @voyage_configured = AppSetting.voyage_configured?
    @voyage_indexing_project_notes = AppSetting.voyage_indexing_project_notes?
    # Phase 12 polish (2026-05-10) — the YouTube pane masks the client
    # secret the same way the Voyage.ai pane masks its API key. The view
    # never re-emits the stored value; it only reflects the configured
    # state via a placeholder. The underlying AppSetting `value` column
    # is encrypted at rest, so this is purely a "don't show secrets in
    # the form" measure.
    @youtube_client_secret_configured = AppSetting.get("youtube_client_secret").present?
    # Phase 3 — Step C: tokens pane shows a count + link to the dedicated page.
    @active_tokens_count = ApiToken.active.count
    # Phase 12 polish (2026-05-10) — combined OAuth/tokens pane renders
    # the active + revoked counts on the same compact-prose line.
    @revoked_tokens_count = ApiToken.revoked.count
    # Phase 12 — Step A: sessions pane (active session count for the user).
    @active_sessions_count = Current.user.present? ? Current.user.sessions.where(revoked_at: nil).count : 0
    # Phase 12 — Step B: oauth applications pane (registered app count).
    @oauth_applications_count = defined?(OauthApplication) ? OauthApplication.count : 0
    # Phase 9 — Google pane reflecting YoutubeConnection state.
    # 2026-05-10 polish — also expose the full set of connections
    # belonging to the current user plus an aggregated channels
    # summary (count + first-N titles) so the Settings index Google
    # card can show "N channels: A, B, C" across all connections.
    # `Channel.all` is install-wide because pito is single-install,
    # multi-user (ADR 0003) — there is no per-user channel scope.
    @youtube_connections = defined?(YoutubeConnection) && Current.user.present? ?
      YoutubeConnection.where(user_id: Current.user.id).order(last_authorized_at: :desc).to_a :
      []
    @youtube_connection = @youtube_connections.first

    @channels_count = defined?(Channel) ? Channel.count : 0
    # 2026-05-10 — Google card channel list.
    #
    # The view renders one label per row (no count prefix, no comma-
    # separation). Label resolution order per channel:
    #   1. `title` once populated by the sync job, else
    #   2. the UC-id portion of `channel_url` (always present —
    #      `channel_url` is required + format-validated).
    #
    # We pull the columns we need rather than full records so the helper
    # stays cheap on installs that grow past a handful of channels. The
    # ORDER pins titled rows first (so freshly synced names rise to the
    # top), then falls back to id for the un-titled tail. We cap at 5
    # to match the prior summary's first-N policy; the view appends an
    # "…and N more" hint when the install has additional channels.
    @channel_labels =
      if defined?(Channel)
        rows = Channel.order(Arel.sql("title IS NULL, title, id"))
                      .limit(5)
                      .pluck(:title, :channel_url)
        rows.filter_map do |title, url|
          label = title.to_s.strip
          next label if label.present?

          slug = url.to_s[%r{/channel/(UC[A-Za-z0-9_-]{22})}, 1]
          slug.presence
        end
      else
        []
      end
    begin
      @search_healthy = Search.engine.healthy?
      @search_stats = Search.engine.index_stats
    rescue StandardError
      @search_healthy = false
      @search_stats = {}
    end

    respond_to do |format|
      format.html
      format.json { render json: settings_json }
    end
  end

  # Phase B refinement (2026-05-04) — per-fieldset saves. Each fieldset on the
  # Settings page submits its own form with a hidden `section` field. The
  # action only touches the keys belonging to that section, leaving the others
  # untouched. Without `section` (legacy callers, e.g. tests written before
  # the refactor), we fall through to the original "update everything we
  # see" behavior — preserves backward compatibility.
  def update
    case params[:section]
    when "workspaces"
      update_general
    when "appearance"
      update_appearance
    when "youtube_oauth"
      update_oauth
    when "voyage"
      result = update_voyage
      if result.is_a?(String)
        redirect_to settings_path, alert: result
        return
      end
    else
      update_legacy
    end

    redirect_to settings_path, notice: "settings saved."
  end

  def update_theme
    theme = params[:theme]
    if %w[light dark auto].include?(theme)
      AppSetting.set("theme", theme)
      head :ok
    else
      head :unprocessable_content
    end
  end

  def reindex
    ReindexAllJob.perform_later
    redirect_to settings_path, notice: "reindex started."
  end

  private

  def update_general
    GENERAL_KEYS.each do |key|
      value = params.dig(:settings, key).presence
      AppSetting.set(key, value) if value
    end
  end

  # ui / ux section (still wired with `section=appearance` on the wire
  # for backward compatibility). Persists theme + keyboard_navigation_enabled
  # in one submit. The keyboard toggle is a yes/no string at the boundary
  # per the project's external-boolean rule; we convert to Boolean before
  # writing to the singleton AppSetting row. Other values are ignored —
  # the radio group can only ship "yes" or "no", but we stay defensive
  # against scripted callers.
  def update_appearance
    theme = params.dig(:settings, :theme)
    AppSetting.set("theme", theme) if %w[light dark auto].include?(theme)

    raw_kbd = params.dig(:settings, :keyboard_navigation_enabled).to_s
    if %w[yes no].include?(raw_kbd)
      AppSetting.set_keyboard_navigation_enabled(raw_kbd == "yes")
    end
  end

  def update_oauth
    OAUTH_KEYS.each do |key|
      value = params.dig(:settings, key).presence
      AppSetting.set(key, value) if value
    end
  end

  # Voyage fieldset — Phase B revamp (2026-05-04). Three optional inputs:
  #
  #   - `voyage_api_key` (text): when blank AND `clear_voyage_api_key` is not
  #     "yes", the existing key is left untouched (no clobber on empty
  #     submit). When non-blank, replaces the key.
  #   - `clear_voyage_api_key` ("yes" / anything else): explicit clear.
  #     Setting it "yes" forces voyage_api_key to nil. The model validation
  #     prevents this when `voyage_index_project_notes` is on.
  #   - `voyage_index_project_notes` ("yes" / "no"): per-target flag. Only
  #     "yes" / "no" are honored — other values leave the flag unchanged
  #     (matches the project's external-boolean rule).
  #
  # Returns the validation error string when the model rejects the update;
  # the caller surfaces it via flash[:alert]. Returns nil on success.
  def update_voyage
    if AppSetting.none?
      AppSetting.set("pane_title_length", ENV.fetch("PANE_TITLE_LENGTH", 14).to_s)
    end
    setting = AppSetting.first

    attrs = {}

    raw_clear = params.dig(:settings, :clear_voyage_api_key).to_s
    raw_key = params.dig(:settings, :voyage_api_key).to_s

    if raw_clear == "yes"
      attrs[:voyage_api_key] = nil
    elsif raw_key.strip.present?
      attrs[:voyage_api_key] = raw_key.strip
    end

    raw_flag = params.dig(:settings, :voyage_index_project_notes).to_s
    if %w[yes no].include?(raw_flag)
      attrs[:voyage_index_project_notes] = (raw_flag == "yes")
    end

    return if attrs.empty?

    setting.assign_attributes(attrs)
    if setting.save
      nil
    else
      setting.errors.full_messages.first || "Voyage settings invalid."
    end
  end

  # Legacy single-form behavior — preserved so callers without a section
  # parameter still work (existing MCP-style or scripted PATCH callers).
  def update_legacy
    update_oauth
    update_general
    update_appearance
  end

  # Public-safe subset of AppSetting values exposed to the JSON API. The
  # OAuth client secret and other credentials are intentionally excluded.
  # The pito CLI's `AppSettings` Rust struct binds to these three fields.
  def settings_json
    {
      max_panes: (AppSetting.get("max_panes") || @max_panes_default).to_i,
      pane_title_length: (AppSetting.get("pane_title_length") || @pane_title_length_default).to_i,
      theme: @theme
    }
  end
end
