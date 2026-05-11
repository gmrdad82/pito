class SettingsController < ApplicationController
  GENERAL_KEYS = %w[max_panes pane_title_length].freeze

  def index
    @settings = GENERAL_KEYS.index_with { |key| AppSetting.get(key) }
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
    # Phase 3 — Step C: tokens pane shows a count + link to the dedicated page.
    @active_tokens_count = ApiToken.active.count
    # Phase 12 polish (2026-05-10) — combined OAuth/tokens pane renders
    # the active + revoked counts on the same compact-prose line.
    @revoked_tokens_count = ApiToken.revoked.count
    # Phase 12 — Step A: sessions pane (active session count for the user).
    @active_sessions_count = Current.user.present? ? Current.user.sessions.where(revoked_at: nil).count : 0
    # Phase 12 — Step B: oauth applications pane (registered app count).
    @oauth_applications_count = defined?(OauthApplication) ? OauthApplication.count : 0
    # Phase 24 — Google connection ivars (`@youtube_connections`,
    # `@youtube_connection`, `@channel_labels`, `@channels_count`) are
    # gone. The Google card moved to the new /channels banner — settings
    # goes back to its lane (app-wide preferences only).
    #
    # 2026-05-11 — YouTube credentials migrated out of
    # `Rails.application.credentials.google_oauth` into the AppSetting
    # singleton with Active Record Encryption on the sensitive fields
    # (api_key + client_secret). The pane is now an EDIT form
    # mirroring Voyage's input-with-placeholder UX:
    #   * sensitive fields show `•••••••` placeholder when configured,
    #     never echoing the stored value.
    #   * non-sensitive fields show the actual stored value as the
    #     input placeholder so the operator can verify them.
    #   * a clear checkbox renders next to each configured field for
    #     explicit wipes (form-level, no JS confirm).
    # The credentials block stays on-disk as a manual revert path; see
    # AppSetting header comment + `pito:backfill_youtube_credentials`.
    @youtube_credentials = youtube_credentials_status
    # Phase 26 — 01b/01c. Slack + Discord panes each read the
    # install-level `notification_delivery_channels` row (nil when no
    # row exists yet — pane renders with empty URL + unchecked boxes).
    # 2026-05-10 follow-up — Slack + Discord panes are no longer on
    # the /settings index page (user-locked customize / integrations
    # / stack restructure dropped them); the ivars remain populated
    # so the partials can still be rendered by other surfaces and
    # the view specs for the partials keep working in isolation.
    @slack_webhook = NotificationDeliveryChannel.find_record_for("slack")
    @discord_webhook = NotificationDeliveryChannel.find_record_for("discord")
    begin
      @search_healthy = Search.engine.healthy?
      @search_stats = Search.engine.index_stats
    rescue StandardError
      @search_healthy = false
      @search_stats = {}
    end
    # 2026-05-10 follow-up — `stack` section ivars.
    # `sql` pane reads Postgres connectivity + a few server-level
    # facts (version, database name) so the operator sees at a glance
    # whether the app is talking to the cluster it expects. `storage`
    # pane reads the `pito-assets` volume (resolved via
    # `Pito::AssetsRoot.root`). Both panes follow the same defensive
    # rescue pattern as the search pane: any failure flips the status
    # to "disconnected" / "unavailable" without exploding the request.
    #
    # 2026-05-11 follow-up — stack expansion. Adds:
    #   * `@postgres_size_stats` — total user-table row count +
    #     on-disk database size (bytes) for the `sql` pane.
    #   * `@search_index_size_bytes` — aggregated Meilisearch
    #     on-disk index size for the `search` pane.
    #   * `@redis_status` — Redis connectivity + version + memory
    #     + key count for the new `redis` pane (paired with
    #     `storage` in row 2 of the stack section).
    #   * `@storage_status` retained for `pito-assets`, and the
    #     storage pane additionally surfaces the on-disk `docs/notes/`
    #     directory via `@notes_volume_status`.
    @postgres_status = postgres_status_for_settings_pane
    # 2026-05-11 (later 2) — per user direction: drop the
    # version / database name / total rows / total size on disk
    # surface from the `db` pane (Postgres half). The per-model
    # breakdown table below remains the only Postgres surface.
    # The matching ivars (`@postgres_size_stats`) and helpers
    # (`postgres_size_stats_for_settings_pane`) are gone.
    #
    # Same direction drops the Redis version / memory / keys /
    # persistence lines and the Meilisearch total-index-size row.
    # The view now surfaces:
    #   * Postgres: status badge + per-model breakdown table.
    #   * Redis: status badge + Sidekiq breakdown table (grouped
    #     header: successful + failed totals, then 5 live state
    #     columns).
    #   * Meilisearch: status badge + per-index table (index |
    #     documents | size). The total-index-size summary line is
    #     dropped; `@search_per_index_stats` replaces
    #     `@search_index_size_bytes`.
    @redis_status = redis_status_for_settings_pane
    @search_per_index_stats = search_per_index_stats_for_settings_pane
    @storage_status = storage_status_for_settings_pane
    @notes_volume_status = notes_volume_status_for_settings_pane
    # 2026-05-11 (later) — per-user direction on /settings:
    #   * `sql` pane renamed to `db` (heading only — the on-disk
    #     `sql` identifier stays nowhere on the wire, we never had
    #     one).
    #   * `db` pane now fences Postgres + Redis with a hairline,
    #     mirroring the Meilisearch + Voyage embeddings pattern in
    #     the `search` pane.
    #   * `db` pane gains a per-model row + size breakdown table.
    #   * `db` pane's Redis section gains a Sidekiq job-state
    #     breakdown table.
    #   * `storage` pane goes 2-column: `assets` (renamed from
    #     `pito-assets`) on the left + `notes` on the right, with a
    #     per-subcategory breakdown table in each column.
    @postgres_table_breakdown = postgres_table_breakdown_for_settings_pane
    @sidekiq_breakdown = sidekiq_breakdown_for_settings_pane
    @assets_breakdown = assets_breakdown_for_settings_pane
    @notes_breakdown = notes_breakdown_for_settings_pane

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
  #
  # Phase 24 — `youtube_oauth` section is dropped along with the rest of
  # the Google card. Submitting `section=youtube_oauth` falls through to
  # `update_legacy`, which silently no-ops on the dropped keys.
  def update
    case params[:section]
    when "workspaces"
      update_general
    when "appearance"
      update_appearance
    when "voyage"
      result = update_voyage
      if result.is_a?(String)
        redirect_to settings_path, alert: result
        return
      end
    when "youtube"
      # 2026-05-11 — YouTube credentials moved out of
      # `Rails.application.credentials.google_oauth` into the
      # AppSetting singleton. Mirror `update_voyage`: blank input
      # keeps the current stored value, explicit clear via
      # `clear_youtube_<field>: "yes"` form params wipes a field.
      result = update_youtube
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

  # YouTube fieldset — 2026-05-11. Four optional inputs, all
  # following Voyage's "blank input keeps the current value" pattern:
  #
  #   - `youtube_api_key` (text, encrypted): public/server API key.
  #   - `youtube_client_id` (text, plaintext): OAuth client ID.
  #   - `youtube_client_secret` (text, encrypted): OAuth client secret.
  #   - `youtube_redirect_uri` (text, plaintext): OAuth callback URL.
  #
  # Each field accepts an explicit clear via
  # `clear_youtube_<field>: "yes"` form params (mirrors
  # `clear_voyage_api_key`). Blank input WITHOUT the clear flag is
  # a no-op for that field (so the operator can submit one field at
  # a time without nuking the others).
  YOUTUBE_FIELDS = %w[
    youtube_api_key
    youtube_client_id
    youtube_client_secret
    youtube_redirect_uri
  ].freeze

  def update_youtube
    if AppSetting.none?
      AppSetting.set("pane_title_length", ENV.fetch("PANE_TITLE_LENGTH", 14).to_s)
    end
    setting = AppSetting.first

    attrs = {}

    YOUTUBE_FIELDS.each do |field|
      raw_clear = params.dig(:settings, "clear_#{field}").to_s
      raw_value = params.dig(:settings, field).to_s

      if raw_clear == "yes"
        attrs[field.to_sym] = nil
      elsif raw_value.strip.present?
        attrs[field.to_sym] = raw_value.strip
      end
    end

    return if attrs.empty?

    setting.assign_attributes(attrs)
    if setting.save
      nil
    else
      setting.errors.full_messages.first || "YouTube settings invalid."
    end
  end

  # Legacy single-form behavior — preserved so callers without a section
  # parameter still work (existing MCP-style or scripted PATCH callers).
  # Phase 24 — the `update_oauth` branch is gone with the Google card;
  # the legacy path now only routes general + appearance keys.
  def update_legacy
    update_general
    update_appearance
  end

  # Public-safe subset of AppSetting values exposed to the JSON API. The
  # pito CLI's `AppSettings` Rust struct binds to these three fields.
  def settings_json
    {
      max_panes: (AppSetting.get("max_panes") || @max_panes_default).to_i,
      pane_title_length: (AppSetting.get("pane_title_length") || @pane_title_length_default).to_i,
      theme: @theme
    }
  end

  # 2026-05-11 — YouTube credentials moved from
  # `Rails.application.credentials.google_oauth` into the AppSetting
  # singleton so the operator can rotate them from the Settings UI
  # without a deploy. The pane is now an EDIT form (Voyage-style),
  # not a read-only status card.
  #
  # Returns a hash describing per-field state for the view to render
  # input placeholders + clear-checkboxes:
  #
  #   :fields — per-field metadata. Each entry carries:
  #     :configured — Boolean (is the column set on the singleton?)
  #     :sensitive  — Boolean (true for api_key / client_secret —
  #                   the view renders `•••••••` placeholder when
  #                   configured and NEVER echoes the value)
  #     :value      — the actual stored value for NON-sensitive
  #                   fields (client_id, redirect_uri) so the view
  #                   can show it as the placeholder text. Always
  #                   nil for sensitive fields.
  #     :effective_redirect_uri / :redirect_uri_default — only on
  #                   the redirect_uri entry. The effective URI
  #                   includes the production fallback when blank;
  #                   `:redirect_uri_default` flags the fallback
  #                   so the view can render a "(default)" suffix.
  #   :all_required_configured — Boolean.
  #
  # The credential values for sensitive fields NEVER leave this
  # method as plaintext — only the Boolean `configured` reaches the
  # view. The omniauth initializer's hard-coded default lives here
  # too so the view can render it as a placeholder hint.
  YOUTUBE_OAUTH_DEFAULT_REDIRECT_URI = "https://app.pitomd.com/auth/google/callback".freeze

  def youtube_credentials_status
    setting = AppSetting.first

    api_key       = setting&.youtube_api_key
    client_id     = setting&.youtube_client_id
    client_secret = setting&.youtube_client_secret
    redirect_uri  = setting&.youtube_redirect_uri

    redirect_value = redirect_uri.to_s.strip

    required_configured =
      api_key.to_s.strip.present? &&
      client_id.to_s.strip.present? &&
      client_secret.to_s.strip.present?

    {
      fields: {
        "youtube_api_key" => {
          label:      "public API key",
          configured: api_key.to_s.strip.present?,
          sensitive:  true,
          value:      nil
        },
        "youtube_client_id" => {
          label:      "OAuth client ID",
          configured: client_id.to_s.strip.present?,
          sensitive:  false,
          value:      client_id.to_s.strip.presence
        },
        "youtube_client_secret" => {
          label:      "OAuth client secret",
          configured: client_secret.to_s.strip.present?,
          sensitive:  true,
          value:      nil
        },
        "youtube_redirect_uri" => {
          label:      "OAuth redirect URI",
          configured: redirect_value.present?,
          sensitive:  false,
          value:      redirect_value.presence,
          effective_redirect_uri: redirect_value.presence ||
                                  YOUTUBE_OAUTH_DEFAULT_REDIRECT_URI,
          redirect_uri_default: redirect_value.empty?
        }
      },
      all_required_configured: required_configured
    }
  end

  # 2026-05-10 — `sql` pane on the Settings index. Reads connectivity
  # plus a couple of server-level facts (Postgres major version, the
  # database name) so the operator confirms at a glance which cluster
  # the app is talking to. `connected: false` flips the view into the
  # red "disconnected" state without exposing connection details.
  def postgres_status_for_settings_pane
    conn = ActiveRecord::Base.connection
    db_config = ActiveRecord::Base.connection_db_config.configuration_hash
    version = conn.select_value("SHOW server_version_num").to_s
    major = version.to_i / 10_000
    {
      connected: conn.active?,
      adapter: db_config[:adapter] || "postgresql",
      database: db_config[:database].to_s,
      version: major.positive? ? major.to_s : nil
    }
  rescue StandardError
    { connected: false, adapter: "postgresql", database: nil, version: nil }
  end

  # 2026-05-10 — `storage` pane on the Settings index. Reads the
  # resolved `pito-assets` volume root from `Pito::AssetsRoot.root`
  # and reports whether it exists + is writable. Surfaces the absolute
  # path so the operator sees exactly which mount point the app is
  # using. The volume may not exist yet on a greenfield install
  # (Active Storage will lazily create the
  # `<root>/active_storage/...` tree on first write) — that's the
  # "present: no" state, not an error.
  def storage_status_for_settings_pane
    root = Pito::AssetsRoot.root
    present = File.directory?(root)
    stats = present ? directory_volume_stats(root) : { size_bytes: 0, file_count: 0 }
    {
      path: root.to_s,
      present: present,
      writable: present && File.writable?(root),
      size_bytes: stats[:size_bytes],
      file_count: stats[:file_count]
    }
  rescue StandardError
    { path: nil, present: false, writable: false, size_bytes: 0, file_count: 0 }
  end

  # 2026-05-11 (later 2) — `search` pane per-index breakdown.
  # Returns a list of rows shaped `{ label:, documents:, size_bytes: }`,
  # one per non-test index. The display label drops the trailing
  # `_development` / `_production` suffix so the pane reads as a
  # logical index name (`channels`, `videos`, …) rather than the
  # raw on-disk name. Sorted by documents DESC so the heavy hitters
  # lead.
  def search_per_index_stats_for_settings_pane
    return [] unless Search.engine.respond_to?(:per_index_stats)

    stats = Search.engine.per_index_stats
    rows = stats.map do |index_name, payload|
      next if index_name.to_s.end_with?("_test")
      label = index_name.to_s.sub(/_(development|production)\z/, "")
      {
        label: label,
        documents: payload[:documents] || payload["documents"] || 0,
        size_bytes: payload[:size_bytes] || payload["size_bytes"]
      }
    end.compact
    rows.sort_by { |row| -row[:documents].to_i }
  rescue StandardError
    []
  end

  # 2026-05-11 — `redis` pane. Connects via `REDIS_URL` (the same
  # value Sidekiq / cache_store use) and pulls a small set of stats
  # out of `INFO`. The full INFO payload is hundreds of lines; we
  # only need a handful. Defensive rescue so a paused / unreachable
  # Redis flips the pane to `disconnected` without breaking the
  # request.
  def redis_status_for_settings_pane
    url = ENV.fetch("REDIS_URL", "redis://127.0.0.1:64527/0")
    client = Redis.new(url: url, timeout: 0.5, reconnect_attempts: 0)
    info = client.info
    db_size = client.dbsize
    client.close
    {
      connected: true,
      version: info["redis_version"],
      used_memory_human: info["used_memory_human"],
      db_size: db_size,
      persistence: redis_persistence_summary(info)
    }
  rescue StandardError
    { connected: false, version: nil, used_memory_human: nil, db_size: nil, persistence: nil }
  end

  # Compact persistence summary for the `redis` pane. Prefers AOF
  # when enabled, otherwise reports RDB. Returns nil when neither is
  # active (Redis with `save ""` and AOF off).
  def redis_persistence_summary(info)
    aof_enabled = info["aof_enabled"].to_s == "1"
    return "aof" if aof_enabled
    rdb_changes = info["rdb_changes_since_last_save"]
    return "rdb" if rdb_changes
    nil
  end

  # 2026-05-11 — `storage` pane on-disk stats for the notes volume.
  # The notes volume is the in-repo `docs/notes/` directory (per
  # CLAUDE.md the MCP `save_note` tool drops markdown there). The
  # pane surfaces availability + size + file count; the operator
  # doesn't need the path, hence no `path:` key on this hash.
  def notes_volume_status_for_settings_pane
    path = Rails.root.join("docs/notes")
    present = File.directory?(path)
    stats = present ? directory_volume_stats(path) : { size_bytes: 0, file_count: 0 }
    {
      present: present,
      writable: present && File.writable?(path),
      size_bytes: stats[:size_bytes],
      file_count: stats[:file_count]
    }
  rescue StandardError
    { present: false, writable: false, size_bytes: 0, file_count: 0 }
  end

  # Cached recursive size + file count for a directory. The result
  # is cached for 5 minutes so a large `pito-assets` tree (footage
  # thumbnails etc.) doesn't slow down every settings render. Cache
  # key is the absolute path string so multiple volumes share the
  # cache cleanly.
  def directory_volume_stats(path)
    Rails.cache.fetch([ "settings/volume-stats", path.to_s ], expires_in: 5.minutes) do
      compute_directory_volume_stats(path)
    end
  rescue StandardError
    compute_directory_volume_stats(path)
  end

  def compute_directory_volume_stats(path)
    size = 0
    count = 0
    Dir.glob(File.join(path.to_s, "**", "*"), File::FNM_DOTMATCH).each do |entry|
      next if File.basename(entry) == "." || File.basename(entry) == ".."
      next unless File.file?(entry)
      begin
        size += File.size(entry)
        count += 1
      rescue StandardError
        next
      end
    end
    { size_bytes: size, file_count: count }
  rescue StandardError
    { size_bytes: 0, file_count: 0 }
  end

  # 2026-05-11 — `db` pane per-model breakdown. The user direction
  # asked for "how many channels, videos, projects, games,
  # notifications, calendar namespaces with number of records and
  # size". Six rows surface the domain tables that matter at a
  # glance; the rest of the schema (analytics partitions, change
  # logs, daily-summary rollups) stays out of this pane so it
  # reads as the operator's mental model of the product, not a
  # raw schema dump.
  #
  # Sort: by size_bytes DESC. On-disk size is the more useful
  # signal here — a million-row stat table eclipses a few thousand
  # channels in storage cost. Row count is a secondary tiebreaker.
  # Cached for 5 minutes per table so the table-scan is cheap to
  # repeat across requests.
  POSTGRES_BREAKDOWN_MODELS = [
    [ "channels", "Channel" ],
    [ "videos", "Video" ],
    [ "projects", "Project" ],
    [ "games", "Game" ],
    [ "notifications", "Notification" ],
    [ "calendar_entries", "CalendarEntry" ]
  ].freeze

  def postgres_table_breakdown_for_settings_pane
    rows = POSTGRES_BREAKDOWN_MODELS.map do |table, class_name|
      stats = postgres_table_stats(table, class_name)
      { label: table, count: stats[:count], size_bytes: stats[:size_bytes] }
    end
    rows.sort_by { |row| -(row[:size_bytes] || 0) }
  rescue StandardError
    []
  end

  def postgres_table_stats(table, class_name)
    # Cache key bumped to v2 with the 2026-05-11 (later 2) stack
    # refactor — the view now right-aligns the count + size columns
    # via `class="num"`, so any cached payload from the prior shape
    # still matches the {count:, size_bytes:} contract; the bump
    # just shields against future tweaks to the helper output.
    Rails.cache.fetch([ "settings/pg-table-stats", "v2", table ], expires_in: 5.minutes) do
      compute_postgres_table_stats(table, class_name)
    end
  rescue StandardError
    compute_postgres_table_stats(table, class_name)
  end

  # Compute per-table count + on-disk size. The table name comes
  # from the hard-coded POSTGRES_BREAKDOWN_MODELS list — never
  # user input — so direct interpolation is safe; defensive
  # `quote_table_name` adds the belt-and-suspenders identifier
  # quoting that `pg_total_relation_size` expects.
  def compute_postgres_table_stats(table, class_name)
    conn = ActiveRecord::Base.connection
    quoted = conn.quote_table_name(table)
    size = conn.select_value(
      "SELECT pg_total_relation_size('#{quoted}')"
    )&.to_i
    count = class_name.safe_constantize&.count
    { count: count, size_bytes: size }
  rescue StandardError
    { count: nil, size_bytes: nil }
  end

  # 2026-05-11 — `db` pane Sidekiq breakdown. Surfaces queue + set
  # sizes across the seven lifecycle states the user asked for.
  # `busy` reads the live `ProcessSet#size * size` count — number
  # of workers across processes that are mid-job (i.e. the
  # `Sidekiq::Workers.new.size` total, not the process count).
  #
  # Sort: lifecycle order (processed → failed → busy → scheduled
  # → enqueued → retry → dead). Lifecycle order tells a clearer
  # story than count-descending for this surface: "we've done X,
  # Y failed, Z are running right now, ..." reads top-to-bottom.
  SIDEKIQ_BREAKDOWN_STATES = %w[
    processed failed busy scheduled enqueued retry dead
  ].freeze

  def sidekiq_breakdown_for_settings_pane
    require "sidekiq/api"
    stats = Sidekiq::Stats.new
    busy = begin
      Sidekiq::Workers.new.size
    rescue StandardError
      0
    end
    counts = {
      "processed" => stats.processed,
      "failed"    => stats.failed,
      "busy"      => busy,
      "scheduled" => stats.scheduled_size,
      "enqueued"  => stats.enqueued,
      "retry"     => stats.retry_size,
      "dead"      => stats.dead_size
    }
    SIDEKIQ_BREAKDOWN_STATES.map { |state| { label: state, count: counts[state] } }
  rescue StandardError
    []
  end

  # 2026-05-11 — `storage` / `assets` pane breakdown. Walks the
  # top-level subdirectories of the assets root and reports
  # per-category file count + size using a fixed allowlist:
  #
  #   * `cover arts` — `composites/` (collection cover composites)
  #   * `thumbnails` — `footage_thumbs/` (extracted footage frames)
  #   * `banners`    — `banners/` (channel banners, reserved)
  #   * `other`      — aggregate of everything else under the
  #                    assets root (Active Storage's 2-char shard
  #                    directories, future unknown trees, etc.)
  #
  # User direction (2026-05-11 follow-up): "no need for split.
  # Just major assets type: cover arts, thumbnails, banners..."
  # The prior pass leaked Active Storage's 2-char-prefix shard
  # directories (`iz`, `m4`, `7a`, ...) as separate rows because
  # the unknown-top-level fallback surfaced raw names. The
  # allowlist closes that hole: the four rows are deterministic,
  # empty categories still render so the operator sees the
  # structure, and `other` preserves the total without polluting
  # the table.
  ASSETS_CATEGORY_DIRECTORIES = {
    "cover arts" => "composites",
    "thumbnails" => "footage_thumbs",
    "banners"    => "banners"
  }.freeze
  ASSETS_OTHER_LABEL = "other".freeze

  def assets_breakdown_for_settings_pane
    root = Pito::AssetsRoot.root
    return assets_breakdown_empty unless File.directory?(root)

    Rails.cache.fetch([ "settings/assets-breakdown", "v2", root.to_s ], expires_in: 5.minutes) do
      compute_assets_breakdown(root)
    end
  rescue StandardError
    assets_breakdown_empty
  end

  # Allowlist-driven aggregation. The three named categories always
  # surface (even at 0 files / 0 bytes) so the operator sees the
  # full asset taxonomy. Every other top-level entry under the
  # assets root collapses into a single `other` row so Active
  # Storage's shard directories don't pollute the table.
  def compute_assets_breakdown(root)
    named = ASSETS_CATEGORY_DIRECTORIES.each_with_object({}) do |(label, _dir), acc|
      acc[label] = { label: label, file_count: 0, size_bytes: 0 }
    end
    other = { label: ASSETS_OTHER_LABEL, file_count: 0, size_bytes: 0 }

    Dir.children(root.to_s).each do |child|
      child_path = File.join(root.to_s, child)
      next unless File.directory?(child_path)
      stats = compute_directory_volume_stats(child_path)
      label = ASSETS_CATEGORY_DIRECTORIES.invert[child]
      target = label ? named[label] : other
      target[:file_count] += stats[:file_count].to_i
      target[:size_bytes] += stats[:size_bytes].to_i
    end

    named.values + [ other ]
  rescue StandardError
    assets_breakdown_empty
  end

  # Deterministic 4-row breakdown when the assets root is absent
  # or the walk fails. Keeps the table structure visible to the
  # operator even on a greenfield install.
  def assets_breakdown_empty
    rows = ASSETS_CATEGORY_DIRECTORIES.keys.map do |label|
      { label: label, file_count: 0, size_bytes: 0 }
    end
    rows << { label: ASSETS_OTHER_LABEL, file_count: 0, size_bytes: 0 }
    rows
  end

  # 2026-05-11 — `notes` pane breakdown. The notes volume today
  # holds two distinct populations:
  #
  #   * `project notes`  — `Note` rows attached to a Project. The
  #                        markdown lives under `<PITO_NOTES_PATH>/projects/`;
  #                        the row count comes from `Note.count`.
  #   * `mobile notes`   — Mobile drop-zone via MCP `save_note`,
  #                        in-repo `docs/notes/`. No DB rows;
  #                        we report file count + size of the
  #                        directory.
  #
  # User direction asks us to "have in mind we'll have notes in
  # other places too like videos. So the same count and size." —
  # the extension hook is `NOTES_NAMESPACE_SOURCES`: add a new
  # entry when video notes / channel notes / etc. ship and they
  # slot into the same table without view changes.
  def notes_breakdown_for_settings_pane
    rows = NOTES_NAMESPACE_SOURCES.map do |source|
      stats = notes_namespace_stats(source)
      {
        label: source[:label],
        count: stats[:count],
        size_bytes: stats[:size_bytes]
      }
    end
    rows.sort_by { |row| -(row[:size_bytes] || 0) }
  rescue StandardError
    []
  end

  # Each entry describes one notes namespace. `:counter` returns
  # the row count (or nil to omit a count column for that
  # namespace); `:path` returns the on-disk directory to walk for
  # size + file count, or nil to skip the filesystem walk.
  NOTES_NAMESPACE_SOURCES = [
    {
      label: "project notes",
      counter: -> { Note.count },
      path:    -> { ENV["PITO_NOTES_PATH"].presence || Rails.root.join("tmp/pito-notes").to_s }
    },
    {
      label: "mobile notes",
      counter: -> { nil },
      path:    -> { Rails.root.join("docs/notes").to_s }
    }
  ].freeze

  def notes_namespace_stats(source)
    count =
      begin
        source[:counter].call
      rescue StandardError
        nil
      end
    path = source[:path].call
    stats =
      if path && File.directory?(path)
        directory_volume_stats(path)
      else
        { size_bytes: 0, file_count: 0 }
      end
    { count: count, size_bytes: stats[:size_bytes], file_count: stats[:file_count] }
  rescue StandardError
    { count: nil, size_bytes: 0, file_count: 0 }
  end
end
