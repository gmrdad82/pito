class DashboardController < ApplicationController
  # Chart-sweep dispatch (2026-05-07). The dashboard charts (daily views,
  # views by channel, daily engagement) have been retired as a coordinated
  # cross-stack reset. The JSON branch collapses to summary counts only —
  # the count shape mirrors the MCP `get_dashboard` tool exactly so the
  # pito CLI's `DashboardData` struct deserializes cleanly.
  #
  # D18 (2026-05-21) — Projects dropped; project_count removed from
  # the JSON envelope.
  #
  # C18 (2026-05-21) — /settings consolidated into /. The ex-settings
  # panels (security, notifications, stack, time_zone) now render from
  # this action. Ivar setup mirrors SettingsController#index (Approach A
  # per the consolidation spec — both controllers stay alive until C19e
  # cleans up SettingsController). The same private helpers are forwarded
  # to a shared concern; for now they are duplicated here verbatim to
  # keep the dispatch small.

  # Allowlist + defaults for the inline sessions sort — mirrors
  # SettingsController::SESSIONS_ALLOWED_SORTS and friends so the
  # _security_pane partial can read the same ivars unchanged.
  SESSIONS_ALLOWED_SORTS = {
    "device"        => "device",
    "browser"       => "browser",
    "ip"            => "ip",
    "last_activity" => "last_activity_at",
    "created"       => "created_at",
    "user_agent"    => "device" # legacy alias
  }.freeze
  SESSIONS_ALLOWED_DIRS = %w[asc desc].freeze
  SESSIONS_DEFAULT_SORT = "last_activity"
  SESSIONS_DEFAULT_DIR  = "desc"

  SEARCH_INDEX_DISPLAY_ALLOWLIST = %w[games].freeze

  POSTGRES_TABLE_ROWS = [
    { label: "games", table: "games", class_name: "Game" },
    { label: "bundles", table: "bundles", class_name: "Bundle" }
  ].freeze

  SIDEKIQ_BREAKDOWN_STATES = %w[
    processed failed busy scheduled enqueued retry dead
  ].freeze

  ASSETS_CATEGORY_DIRECTORIES = {
    "cover arts" => [ "covers", "games" ],
    "composites" => [ "covers", "bundles" ]
  }.freeze

  def index
    @video_count = Video.count
    @channel_count = Channel.count

    # Ex-settings ivars — needed by the partials rendered in index.html.erb.
    load_settings_ivars

    respond_to do |format|
      format.html
      format.json do
        @footage_count = Footage.count
        render json: dashboard_json
      end
    end
  end

  private

  def dashboard_json
    {
      video_count: @video_count,
      channel_count: @channel_count,
      footage_count: @footage_count
    }
  end

  # ---------------------------------------------------------------------------
  # Ex-settings ivar setup (C18 consolidation). Mirrors
  # SettingsController#index exactly. Kept private so the public surface
  # stays minimal. C19e will extract these into a shared concern or delete
  # SettingsController entirely.
  # ---------------------------------------------------------------------------

  def load_settings_ivars
    # Profile / security pane.
    @user = Current.user
    @twofa_enabled = Current.user&.totp_enabled? || false
    @active_sessions_count = Current.user.present? ? Current.user.sessions.where(revoked_at: nil).count : 0

    # Inline sessions table.
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

    # Stack pane — Meilisearch / Search health.
    begin
      @search_healthy = Pito::Search.engine.healthy?
      @search_stats = Pito::Search.engine.index_stats
    rescue StandardError
      @search_healthy = false
      @search_stats = {}
    end

    @postgres_status             = postgres_status_for_settings_pane
    @redis_status                = redis_status_for_settings_pane
    @search_per_index_stats      = search_per_index_stats_for_settings_pane
    @storage_status              = storage_status_for_settings_pane
    @postgres_table_breakdown    = postgres_table_breakdown_for_settings_pane
    @sidekiq_breakdown           = sidekiq_breakdown_for_settings_pane
    @assets_breakdown            = assets_breakdown_for_settings_pane
    @voyage_configured           = AppSetting.voyage_configured?
  end

  def sanitized_sessions_sort_key
    SESSIONS_ALLOWED_SORTS.key?(params[:sessions_sort]) ? params[:sessions_sort] : SESSIONS_DEFAULT_SORT
  end

  def sanitized_sessions_dir
    requested = params[:sessions_dir]&.downcase
    SESSIONS_ALLOWED_DIRS.include?(requested) ? requested : SESSIONS_DEFAULT_DIR
  end

  def sessions_sort_clause
    column    = SESSIONS_ALLOWED_SORTS.fetch(@sessions_sort)
    direction = SESSIONS_ALLOWED_DIRS.include?(@sessions_dir) ? @sessions_dir : SESSIONS_DEFAULT_DIR
    [
      Arel.sql("#{column} #{direction}"),
      Arel.sql("last_activity_at desc nulls last"),
      Arel.sql("created_at desc")
    ]
  end

  def postgres_status_for_settings_pane
    conn      = ActiveRecord::Base.connection
    db_config = ActiveRecord::Base.connection_db_config.configuration_hash
    version   = conn.select_value("SHOW server_version_num").to_s
    major     = version.to_i / 10_000
    {
      connected: conn.active?,
      adapter:   db_config[:adapter] || "postgresql",
      database:  db_config[:database].to_s,
      version:   major.positive? ? major.to_s : nil
    }
  rescue StandardError
    { connected: false, adapter: "postgresql", database: nil, version: nil }
  end

  def storage_status_for_settings_pane
    root    = Pito::AssetsRoot.root
    present = File.directory?(root)
    stats   = present ? directory_volume_stats(root) : { size_bytes: 0, file_count: 0 }
    {
      path:       root.to_s,
      present:    present,
      writable:   present && File.writable?(root),
      size_bytes: stats[:size_bytes],
      file_count: stats[:file_count]
    }
  rescue StandardError
    { path: nil, present: false, writable: false, size_bytes: 0, file_count: 0 }
  end

  def search_per_index_stats_for_settings_pane
    engine_rows = {}

    if Pito::Search.engine.respond_to?(:per_index_stats)
      stats = Pito::Search.engine.per_index_stats
      stats.each do |index_name, payload|
        next if index_name.to_s.end_with?("_test")
        label = index_name.to_s.sub(/_(development|production)\z/, "")
        next unless SEARCH_INDEX_DISPLAY_ALLOWLIST.include?(label)
        engine_rows[label] = {
          documents: (payload[:documents] || payload["documents"] || 0).to_i,
          size_bytes: payload[:size_bytes] || payload["size_bytes"],
          raw_index_name: index_name.to_s
        }
      end
    end

    rows = []
    games_payload = engine_rows["games"]
    if games_payload
      games_docs, bundles_docs = split_games_index_by_kind(games_payload[:raw_index_name], games_payload[:documents])
      rows << { label: "games",   documents: games_docs.to_i,   size_bytes: games_payload[:size_bytes], missing: false }
      rows << { label: "bundles", documents: bundles_docs.to_i, size_bytes: nil, omit_size: true,        missing: false }
    else
      rows << { label: "games",   documents: 0, size_bytes: nil, missing: true }
      rows << { label: "bundles", documents: 0, size_bytes: nil, missing: true, omit_size: true }
    end

    rows
  rescue StandardError
    [
      { label: "games",   documents: 0, size_bytes: nil, missing: true },
      { label: "bundles", documents: 0, size_bytes: nil, missing: true, omit_size: true }
    ]
  end

  def split_games_index_by_kind(raw_index_name, total_documents)
    return [ total_documents, 0 ] unless Pito::Search.engine.respond_to?(:documents_count_for)

    games_count   = Pito::Search.engine.documents_count_for(raw_index_name, field: "kind", value: "game")
    bundles_count = Pito::Search.engine.documents_count_for(raw_index_name, field: "kind", value: "bundle")

    if games_count.nil? && bundles_count.nil?
      [ total_documents, 0 ]
    else
      [ games_count.to_i, bundles_count.to_i ]
    end
  rescue StandardError
    [ total_documents, 0 ]
  end

  def redis_status_for_settings_pane
    url    = ENV.fetch("REDIS_URL", "redis://127.0.0.1:64527/0")
    client = Redis.new(url: url, timeout: 0.5, reconnect_attempts: 0)
    info   = client.info
    db_size = client.dbsize
    client.close
    {
      connected:        true,
      version:          info["redis_version"],
      used_memory_human: info["used_memory_human"],
      db_size:          db_size,
      persistence:      redis_persistence_summary(info)
    }
  rescue StandardError
    { connected: false, version: nil, used_memory_human: nil, db_size: nil, persistence: nil }
  end

  def redis_persistence_summary(info)
    aof_enabled  = info["aof_enabled"].to_s == "1"
    return "aof" if aof_enabled
    rdb_changes  = info["rdb_changes_since_last_save"]
    return "rdb" if rdb_changes
    nil
  end

  def directory_volume_stats(path)
    Rails.cache.fetch([ "settings/volume-stats", path.to_s ], expires_in: 5.minutes) do
      compute_directory_volume_stats(path)
    end
  rescue StandardError
    compute_directory_volume_stats(path)
  end

  def compute_directory_volume_stats(path)
    size  = 0
    count = 0
    Dir.glob(File.join(path.to_s, "**", "*"), File::FNM_DOTMATCH).each do |entry|
      next if File.basename(entry) == "." || File.basename(entry) == ".."
      next unless File.file?(entry)
      begin
        size  += File.size(entry)
        count += 1
      rescue StandardError
        next
      end
    end
    { size_bytes: size, file_count: count }
  rescue StandardError
    { size_bytes: 0, file_count: 0 }
  end

  def postgres_table_breakdown_for_settings_pane
    conn = ActiveRecord::Base.connection
    POSTGRES_TABLE_ROWS.map do |row|
      if conn.table_exists?(row[:table])
        stats = postgres_table_stats(row[:table], row[:class_name])
        { label: row[:label], count: stats[:count], size_bytes: stats[:size_bytes] }
      else
        { label: row[:label], count: nil, size_bytes: nil }
      end
    end
  rescue StandardError
    []
  end

  def postgres_table_stats(table, class_name)
    Rails.cache.fetch([ "settings/pg-table-stats", "v2", table ], expires_in: 5.minutes) do
      compute_postgres_table_stats(table, class_name)
    end
  rescue StandardError
    compute_postgres_table_stats(table, class_name)
  end

  def compute_postgres_table_stats(table, class_name)
    conn   = ActiveRecord::Base.connection
    quoted = conn.quote_table_name(table)
    size   = conn.select_value("SELECT pg_total_relation_size('#{quoted}')")&.to_i
    count  = class_name.safe_constantize&.count
    { count: count, size_bytes: size }
  rescue StandardError
    { count: nil, size_bytes: nil }
  end

  def sidekiq_breakdown_for_settings_pane
    require "sidekiq/api"
    stats = Sidekiq::Stats.new
    busy  = begin
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

  def assets_breakdown_for_settings_pane
    root = Pito::AssetsRoot.root
    return assets_breakdown_empty unless File.directory?(root)

    Rails.cache.fetch([ "settings/assets-breakdown", "v4", root.to_s ], expires_in: 5.minutes) do
      compute_assets_breakdown(root)
    end
  rescue StandardError
    assets_breakdown_empty
  end

  def compute_assets_breakdown(root)
    named = ASSETS_CATEGORY_DIRECTORIES.each_with_object({}) do |(label, _segments), acc|
      acc[label] = { label: label, file_count: 0, size_bytes: 0 }
    end

    ASSETS_CATEGORY_DIRECTORIES.each do |label, segments|
      child_path = File.join(root.to_s, *segments)
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
end
