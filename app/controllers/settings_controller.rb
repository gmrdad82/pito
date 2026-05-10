class SettingsController < ApplicationController
  OAUTH_KEYS = %w[youtube_client_id youtube_client_secret youtube_redirect_uri].freeze
  GENERAL_KEYS = %w[max_panes pane_title_length].freeze

  def index
    @settings = (OAUTH_KEYS + GENERAL_KEYS).index_with { |key| AppSetting.get(key) }
    @max_panes_default = ENV.fetch("MAX_PANES", 3).to_i
    @pane_title_length_default = ENV.fetch("PANE_TITLE_LENGTH", 14).to_i
    @theme = AppSetting.get("theme") || "auto"
    @voyage_configured = AppSetting.voyage_configured?
    @voyage_indexing_project_notes = AppSetting.voyage_indexing_project_notes?
    # Phase 3 — Step C: tokens pane shows a count + link to the dedicated page.
    @active_tokens_count = ApiToken.active.count
    # Phase 12 — Step A: sessions pane (active session count for the user).
    @active_sessions_count = Current.user.present? ? Current.user.sessions.where(revoked_at: nil).count : 0
    # Phase 12 — Step B: oauth applications pane (registered app count).
    @oauth_applications_count = defined?(OauthApplication) ? OauthApplication.count : 0
    # Phase 7 — Step C: Google pane reflecting connection state.
    @google_identity = defined?(GoogleIdentity) && Current.user.present? ?
      GoogleIdentity.where(user_id: Current.user.id).order(last_authorized_at: :desc).first :
      nil
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

  def update_appearance
    theme = params.dig(:settings, :theme)
    AppSetting.set("theme", theme) if %w[light dark auto].include?(theme)
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
