class SettingsController < ApplicationController
  # 2026-05-16 (sessions revamp v2). The Security pane now renders the
  # sessions table INLINE. Column sort is driven by `?sessions_sort=…`
  # + `?sessions_dir=…` on `/settings` itself (the standalone
  # `/settings/sessions` index is gone). The allowlist mirrors the
  # rendered column shape (`user_agent`, `last_activity`). The `ip`
  # value is rendered as an inline tooltip badge inside the
  # user-agent cell — it is not sortable, so it is not in the
  # allowlist. `active` / `remember` columns were dropped from the
  # table.
  SESSIONS_ALLOWED_SORTS = {
    "last_activity" => "last_activity_at",
    "user_agent"    => "user_agent"
  }.freeze
  SESSIONS_ALLOWED_DIRS = %w[asc desc].freeze
  SESSIONS_DEFAULT_SORT = "last_activity"
  SESSIONS_DEFAULT_DIR  = "desc"

  # Phase 29 (settings refactor) — `/settings` is a 3-row dashboard.
  # Phase 32 follow-up (2026-05-16) — Row 2 simplification.
  #
  # Row 1
  #   Left  : profile inline form (username + password).
  #   Right : bracketed links to security modals (2FA, sessions, blocks).
  # Row 2
  #   Left  : Discord webhook pane.
  #   Right : Slack webhook pane.
  # Row 3   : Stack pane (db / search / storage / notes) spanning both
  #           columns via `.pane--wide`.
  #
  # The dropped UI/UX, Workspace, and Voyage panes are gone — workspace
  # knobs (`max_panes`, `pane_title_length`, `timezone`) live in
  # `config/pito.yml` now (see `config/initializers/pito_config.rb`);
  # theme persistence moved to localStorage; keyboard navigation is
  # always-on.
  #
  # The OAuth-applications + tokens management UI is also gone — pito
  # is single-user, the operator manages those from the shell via
  # `bin/rails pito:oauth_apps:*` and `bin/rails pito:tokens:*`. The
  # Doorkeeper handshake endpoints (`/oauth/authorize`,
  # `/oauth/token`, `/oauth/revoke`, `/oauth/introspect`) stay live
  # for the Claude Desktop OAuth client.
  #
  # `update_theme` is gone too — the route is dropped from `routes.rb`.
  #
  # `update` is no longer a multi-section dispatcher; the only surviving
  # legacy caller (the JSON-PATCH path some scripted setups still target)
  # is treated as a no-op (redirect with notice) so we never 500. Real
  # writes flow through the focused per-resource controllers
  # (`Settings::UserController`, the webhook controllers, the
  # time-zone controller).

  def index
    # Profile pane.
    @user = Current.user

    # Security pane — counters surfaced inside the modal launchers.
    # Post-Phase-25 rollback: the auto-block list is gone, so the
    # blocks counter is dropped.
    @twofa_enabled = Current.user&.totp_enabled? || false
    @active_sessions_count = Current.user.present? ? Current.user.sessions.where(revoked_at: nil).count : 0

    # Inline sessions table — only active rows surface in the UI.
    # Revoked rows stay in the DB for audit (operator can list via
    # `bin/rails pito:sessions:list[all]`).
    @sessions_sort = sanitized_sessions_sort_key
    @sessions_dir  = sanitized_sessions_dir
    @sessions =
      if Current.user.present?
        Current.user.sessions.active_sessions.order(sessions_sort_clause)
      else
        Session.none
      end

    # Webhook panes.
    @slack_webhook = NotificationDeliveryChannel.find_record_for("slack")
    @discord_webhook = NotificationDeliveryChannel.find_record_for("discord")

    # Stack pane — same probe set the previous /settings exposed.
    begin
      @search_healthy = Search.engine.healthy?
      @search_stats = Search.engine.index_stats
    rescue StandardError
      @search_healthy = false
      @search_stats = {}
    end
    @postgres_status = postgres_status_for_settings_pane
    @redis_status = redis_status_for_settings_pane
    @search_per_index_stats = search_per_index_stats_for_settings_pane
    @storage_status = storage_status_for_settings_pane
    @notes_volume_status = notes_volume_status_for_settings_pane
    @postgres_table_breakdown = postgres_table_breakdown_for_settings_pane
    @sidekiq_breakdown = sidekiq_breakdown_for_settings_pane
    @assets_breakdown = assets_breakdown_for_settings_pane
    @notes_breakdown = notes_breakdown_for_settings_pane
    @voyage_configured = AppSetting.voyage_configured?

    respond_to do |format|
      format.html
      format.json { render json: settings_json }
    end
  end

  # Phase 29 (settings refactor) — legacy passthrough. The multi-section
  # dispatcher is gone (no more `update_general` / `update_appearance`
  # / `update_voyage`). Scripted PATCH callers still hitting `/settings`
  # get a clean redirect + notice — no 500s, no silent writes.
  def update
    redirect_to settings_path, notice: "settings saved."
  end

  # Phase 32 follow-up (2026-05-16) — three-layer reindex lock.
  # Layer 1 (DB flag) is enforced here BEFORE enqueueing. If the flag
  # is set the controller short-circuits with an alert; no second job
  # enqueues. Layer 2 (`sidekiq_options` in `ReindexAllJob`) is a no-op
  # belt-and-suspenders for the future-Sidekiq-Enterprise case. The
  # job's `ensure` block clears the flag (Layer 3 ties the UI to it).
  def reindex
    if AppSetting.reindex_running?
      redirect_to settings_path, alert: "reindex already in progress."
      return
    end

    AppSetting.start_reindex!
    ReindexAllJob.perform_later
    redirect_to settings_path, notice: "reindex started."
  end

  private

  def sanitized_sessions_sort_key
    SESSIONS_ALLOWED_SORTS.key?(params[:sessions_sort]) ? params[:sessions_sort] : SESSIONS_DEFAULT_SORT
  end

  def sanitized_sessions_dir
    requested = params[:sessions_dir]&.downcase
    SESSIONS_ALLOWED_DIRS.include?(requested) ? requested : SESSIONS_DEFAULT_DIR
  end

  # `column` is looked up from `SESSIONS_ALLOWED_SORTS` (frozen
  # allowlist) and `direction` is one of the two literal strings in
  # `SESSIONS_ALLOWED_DIRS` — no user input ever reaches the SQL
  # string. Secondary sort by `last_activity_at desc, created_at desc`
  # keeps rows with equal primary-key values stable.
  def sessions_sort_clause
    column = SESSIONS_ALLOWED_SORTS.fetch(@sessions_sort)
    direction = SESSIONS_ALLOWED_DIRS.include?(@sessions_dir) ? @sessions_dir : SESSIONS_DEFAULT_DIR
    [
      Arel.sql("#{column} #{direction}"),
      Arel.sql("last_activity_at desc nulls last"),
      Arel.sql("created_at desc")
    ]
  end

  # Public-safe subset surfaced to the JSON API. The pito CLI's
  # `AppSettings` Rust struct still binds to these three fields; the
  # Rust crate is paused so we keep the contract intact with the
  # config.x.pito values and a static `theme: "auto"` placeholder
  # (theme is browser-local now, no server-side preference exists).
  def settings_json
    {
      max_panes: Rails.application.config.x.pito.max_panes,
      pane_title_length: Rails.application.config.x.pito.pane_title_length,
      theme: "auto"
    }
  end

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

  # 2026-05-18 (DR) — only the `games` index surfaces on /settings now.
  # `notes` and `videos` are removed because those product surfaces have
  # not been revisited in the beta-3 sweep yet; surfacing their indexes
  # would imply they are first-class. The `games` index hosts both Game
  # and Bundle documents (planned DH consolidation), so the single row
  # reads as the "games (games + bundles)" section indicator.
  SEARCH_INDEX_DISPLAY_ALLOWLIST = %w[games].freeze

  def search_per_index_stats_for_settings_pane
    rows = []

    if Search.engine.respond_to?(:per_index_stats)
      stats = Search.engine.per_index_stats
      rows = stats.map do |index_name, payload|
        next if index_name.to_s.end_with?("_test")
        label = index_name.to_s.sub(/_(development|production)\z/, "")
        next unless SEARCH_INDEX_DISPLAY_ALLOWLIST.include?(label)
        {
          label: label,
          documents: payload[:documents] || payload["documents"] || 0,
          size_bytes: payload[:size_bytes] || payload["size_bytes"],
          missing: false
        }
      end.compact
    end

    # 2026-05-18 — backfill placeholder rows for any allowlisted index
    # the engine didn't return. Covers the "index not yet created" case
    # (no documents indexed → Meilisearch has no record of the index),
    # so the Stack pane still surfaces the `games` row instead of going
    # silent. `missing: true` lets the view render "not yet indexed"
    # cells in place of doc count + size.
    SEARCH_INDEX_DISPLAY_ALLOWLIST.each do |required|
      next if rows.any? { |row| row[:label] == required }
      rows << {
        label: required,
        documents: 0,
        size_bytes: nil,
        missing: true
      }
    end

    rows.sort_by { |row| -row[:documents].to_i }
  rescue StandardError
    SEARCH_INDEX_DISPLAY_ALLOWLIST.map do |required|
      { label: required, documents: 0, size_bytes: nil, missing: true }
    end
  end

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

  def redis_persistence_summary(info)
    aof_enabled = info["aof_enabled"].to_s == "1"
    return "aof" if aof_enabled
    rdb_changes = info["rdb_changes_since_last_save"]
    return "rdb" if rdb_changes
    nil
  end

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

  # 2026-05-18 (DR) — Postgres breakdown is trimmed to the single
  # surface that has been revisited in the beta-3 sweep: games (which
  # encompasses both `games` and `bundles` tables per the DH model
  # consolidation). Channels / videos / projects / notifications /
  # calendar_entries are dropped from the display until those product
  # areas land in beta-3 — keeping them would falsely advertise them as
  # first-class.
  #
  # The single row aggregates `Game.count + Bundle.count` (when present)
  # and sums `pg_total_relation_size` across both tables, so the figure
  # matches the user-facing notion of "the games section in Postgres".
  POSTGRES_GAMES_TABLES = %w[games bundles].freeze

  def postgres_table_breakdown_for_settings_pane
    stats = combined_games_postgres_stats
    [ { label: "games", count: stats[:count], size_bytes: stats[:size_bytes] } ]
  rescue StandardError
    []
  end

  def combined_games_postgres_stats
    conn = ActiveRecord::Base.connection
    total_count = 0
    total_size = 0
    any_count = false
    any_size = false

    POSTGRES_GAMES_TABLES.each do |table|
      next unless conn.table_exists?(table)

      stats = postgres_table_stats(table, table.classify)
      if stats[:count]
        total_count += stats[:count].to_i
        any_count = true
      end
      if stats[:size_bytes]
        total_size += stats[:size_bytes].to_i
        any_size = true
      end
    end

    {
      count: any_count ? total_count : nil,
      size_bytes: any_size ? total_size : nil
    }
  rescue StandardError
    { count: nil, size_bytes: nil }
  end

  def postgres_table_stats(table, class_name)
    Rails.cache.fetch([ "settings/pg-table-stats", "v2", table ], expires_in: 5.minutes) do
      compute_postgres_table_stats(table, class_name)
    end
  rescue StandardError
    compute_postgres_table_stats(table, class_name)
  end

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

  # 2026-05-18 (DR) — assets breakdown is trimmed to the single
  # surface revisited so far in the beta-3 sweep: cover arts (the
  # `composites` directory under `Pito::AssetsRoot`). Thumbnails,
  # banners, and the catch-all "other" bucket are dropped — the
  # underlying directories may still exist on disk, but the /settings
  # pane no longer advertises them as first-class until the matching
  # product surfaces (footage / channel banners / etc.) are revisited.
  ASSETS_CATEGORY_DIRECTORIES = {
    "cover arts" => "composites"
  }.freeze

  def assets_breakdown_for_settings_pane
    root = Pito::AssetsRoot.root
    return assets_breakdown_empty unless File.directory?(root)

    Rails.cache.fetch([ "settings/assets-breakdown", "v3", root.to_s ], expires_in: 5.minutes) do
      compute_assets_breakdown(root)
    end
  rescue StandardError
    assets_breakdown_empty
  end

  def compute_assets_breakdown(root)
    named = ASSETS_CATEGORY_DIRECTORIES.each_with_object({}) do |(label, _dir), acc|
      acc[label] = { label: label, file_count: 0, size_bytes: 0 }
    end

    ASSETS_CATEGORY_DIRECTORIES.each do |label, dir|
      child_path = File.join(root.to_s, dir)
      next unless File.directory?(child_path)

      stats = compute_directory_volume_stats(child_path)
      named[label][:file_count] += stats[:file_count].to_i
      named[label][:size_bytes] += stats[:size_bytes].to_i
    end

    named.values
  rescue StandardError
    assets_breakdown_empty
  end

  def assets_breakdown_empty
    ASSETS_CATEGORY_DIRECTORIES.keys.map do |label|
      { label: label, file_count: 0, size_bytes: 0 }
    end
  end

  NOTES_NAMESPACE_SOURCES = [
    {
      label: "project",
      counter: -> { Note.count },
      path:    -> { ENV["PITO_NOTES_PATH"].presence || Rails.root.join("tmp/pito-notes").to_s }
    }
  ].freeze

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
