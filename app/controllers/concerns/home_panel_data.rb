# Concerns::HomePanelData
#
# Controller concern feeding ivars for the three rescued ex-settings
# panels mounted on Home (/): Security, Notifications, Stack. Each
# panel's ViewComponent constructor demands a specific kwarg set; this
# concern centralizes the data fetches so DashboardController stays thin.
#
# C19f follow-up (2026-05-23). Previously the fetch logic lived in
# `SettingsController#index` (deleted as part of C19e); a temporary
# `set_panel_stub_ivars` in DashboardController fed `false`/`nil`/`[]`
# to the panels so the render was green but every panel rendered empty.
# This concern restores the real probes verbatim from the pre-C19e
# SettingsController body — same allowlists, same rescue boundaries,
# same Rails.cache keys — and exposes three `set_*_panel_data` methods
# that the controller calls in a before_action.
#
# This is a transitional home. Each panel will eventually own its own
# data source via a panel-scoped controller action + cable broadcast
# (per the canonical cable grammar `pito:home:<panel>`); when that
# lands, the matching method here goes away. Until then, the concern
# keeps DashboardController readable.
#
# The Stack panel's status chips read from `Pito::Stack::HealthState`;
# the probe logic itself (Postgres / Meilisearch / Voyage / assets)
# lives here because no canonical service has claimed it yet. The Redis
# + Sidekiq probes were dropped 2026-05-23 along with the Redis
# sub-panel.
module HomePanelData
  extend ActiveSupport::Concern

  # Session-table column sort allowlist. Mirrors the pre-C19e contract
  # so `?sessions_sort=…&sessions_dir=…` query strings stay supported.
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

  # Meilisearch sub-panel sort — columns: index (label), docs, size.
  MEILISEARCH_ALLOWED_SORTS = %w[index docs size].freeze
  MEILISEARCH_DEFAULT_SORT  = "docs"
  MEILISEARCH_DEFAULT_DIR   = "desc"

  # Voyage sub-panel sort — columns: collection (label), embedded.
  VOYAGE_ALLOWED_SORTS = %w[collection embedded].freeze
  VOYAGE_DEFAULT_SORT  = "embedded"
  VOYAGE_DEFAULT_DIR   = "desc"

  # Postgres sub-panel sort — columns: model (label), rows, size.
  POSTGRES_ALLOWED_SORTS = %w[model rows size].freeze
  POSTGRES_DEFAULT_SORT  = "rows"
  POSTGRES_DEFAULT_DIR   = "desc"

  # Assets sub-panel sort — columns: category (label), files, size.
  ASSETS_ALLOWED_SORTS = %w[category files size].freeze
  ASSETS_DEFAULT_SORT  = "files"
  ASSETS_DEFAULT_DIR   = "desc"

  STACK_ALLOWED_DIRS = %w[asc desc].freeze

  # Meilisearch unified `games_*` index displays games. Only the unified
  # index is surfaced; per-env suffixes are stripped.
  # R1 (2026-05-25) — bundles row removed.
  SEARCH_INDEX_DISPLAY_ALLOWLIST = %w[games].freeze

  # Postgres rows displayed in the Stack panel breakdown. Other tables
  # (channels / videos / notifications) stay hidden until those product
  # surfaces re-enter scope.
  # R1 (2026-05-25) — bundles row removed.
  POSTGRES_TABLE_ROWS = [
    { label: "games", table: "games", class_name: "Game" }
  ].freeze

  # Assets root sub-directory map. Each row appears in the assets
  # breakdown regardless of whether the directory has any files yet.
  # R1 (2026-05-25) — composites/bundles dir removed.
  ASSETS_CATEGORY_DIRECTORIES = {
    "cover arts" => [ "covers", "games" ]
  }.freeze

  # -----------------------------------------------------------------
  # Entry points
  # -----------------------------------------------------------------

  # Assembles `@home_panel_data` — a single Hash mapping every panel key
  # to the kwargs Hash its ViewComponent initializer expects. Called after
  # all individual `set_*_panel_data` methods have run so every ivar is
  # already populated.
  #
  # The dashboard view (`dashboard/index.html.erb`) loops over
  # `AppSetting.home_rows_config` and renders each row via
  # `Pito::HomeRowComponent`, forwarding this hash as `panel_data:`.
  # The HomeRowComponent splats the matching sub-hash into each panel's
  # initializer via `kwargs_for(key)`.
  def assemble_home_panel_data
    @home_panel_data = {
      "games_releasing"    => {},
      "notifications_feed" => {},
      "calendar"           => {
        entries:    @calendar_entries,
        buckets:    @calendar_buckets,
        grid:       @calendar_grid,
        today:      @calendar_today,
        year:       @calendar_year,
        month:      @calendar_month,
        raw_filter: @calendar_raw_filter,
        category:   @calendar_category
      },
      "stack"              => {
        postgres_status:          @postgres_status,
        postgres_table_breakdown: @postgres_table_breakdown,
        search_healthy:           @search_healthy,
        search_stats:             @search_stats,
        search_per_index_stats:   @search_per_index_stats,
        voyage_configured:        @voyage_configured,
        storage_status:           @storage_status,
        assets_breakdown:         @assets_breakdown,
        meilisearch_sort:         @meilisearch_sort,
        meilisearch_dir:          @meilisearch_dir,
        voyage_sort:              @voyage_sort,
        voyage_dir:               @voyage_dir,
        postgres_sort:            @postgres_sort,
        postgres_dir:             @postgres_dir,
        assets_sort:              @assets_sort,
        assets_dir:               @assets_dir
      },
      "notifications"      => {
        discord_webhook: @discord_webhook,
        slack_webhook:   @slack_webhook
      },
      "security"           => {
        sessions:      @sessions,
        sessions_sort: @sessions_sort,
        sessions_dir:  @sessions_dir
      }
    }
  end

  # Sets `@sessions`, `@sessions_sort`, `@sessions_dir` for the
  # Security panel. Active (non-revoked) rows only; revoked rows stay
  # in the DB for audit. Falls back to `Session.none` when the request
  # has no authenticated user.
  def set_security_panel_data
    @sessions_sort = sanitized_sessions_sort_key
    @sessions_dir  = sanitized_sessions_dir
    @sessions =
      if Current.user.present?
        Current.user.sessions.active_sessions.order(sessions_sort_clause)
      else
        Session.none
      end
  end

  # Sets `@discord_webhook`, `@slack_webhook` for the Notifications
  # panel. Records are `NotificationDeliveryChannel` rows keyed on
  # `kind`. May be nil when a brand has never been configured.
  def set_notifications_panel_data
    @discord_webhook = NotificationDeliveryChannel.find_record_for("discord")
    @slack_webhook   = NotificationDeliveryChannel.find_record_for("slack")
  end

  # Fetches the current-month CalendarEntry buckets for the home Calendar
  # panel. Applies the 4-category `?calendar_filter[*]=on` server filter.
  # Also resolves the `?calendar_category=<cat>` single-category URL filter.
  # Calendar is month-only; schedule mode has been dropped.
  # Groups results by Date, ordered by created_at ASC within each day.
  def set_calendar_panel_data
    install_tz = Rails.application.config.x.pito.timezone
    tz = ActiveSupport::TimeZone[install_tz] || ActiveSupport::TimeZone["UTC"]
    today = Time.current.in_time_zone(tz).to_date
    @calendar_year   = today.year
    @calendar_month  = today.month
    @calendar_raw_filter = params[:calendar_filter]

    # Resolve single-category filter from URL query param.
    raw_cat = params[:calendar_category].to_s
    @calendar_category = %w[channel game system manual].include?(raw_cat) ? raw_cat.to_sym : nil

    grid      = home_calendar_month_grid(@calendar_year, @calendar_month)
    first_day = grid.first
    last_day  = grid.last + 1.day

    range_start = tz.local(first_day.year, first_day.month, first_day.day)
    range_end   = tz.local(last_day.year,  last_day.month,  last_day.day)

    scope = CalendarEntry.in_range(range_start, range_end).visible.order(:created_at)
    scope = home_calendar_filter_scope(scope, @calendar_raw_filter)

    entries = scope.to_a
    @calendar_entries = entries
    @calendar_buckets = entries.group_by { |e| e.starts_at.in_time_zone(install_tz).to_date }
    @calendar_grid    = grid
    @calendar_today   = today
  end

  # Sets the 8 ivars the Stack panel demands plus the 8 sort ivars
  # (one sort key + direction per sub-panel). Each probe is rescued
  # so a transient subsystem failure (Meilisearch unreachable, etc.)
  # renders the panel in its "disconnected" state instead of 500ing the
  # whole home page. Redis + Sidekiq probes were removed 2026-05-23 when
  # the Redis sub-panel was dropped from the Stack panel.
  #
  # Server-side sort (2026-05-25) — each sub-panel's data array is sorted
  # here before being passed to the ViewComponent so the V4 underline
  # (`<a class="sort-asc">` / `<a class="sort-desc">`) is present on
  # first paint without any client-side JS.
  def set_stack_panel_data
    # Resolve sort params for all 4 sub-panels up front.
    @meilisearch_sort = sanitized_stack_sort(:meilisearch_sort, MEILISEARCH_ALLOWED_SORTS, MEILISEARCH_DEFAULT_SORT)
    @meilisearch_dir  = sanitized_stack_dir(:meilisearch_dir, MEILISEARCH_DEFAULT_DIR)
    @voyage_sort      = sanitized_stack_sort(:voyage_sort, VOYAGE_ALLOWED_SORTS, VOYAGE_DEFAULT_SORT)
    @voyage_dir       = sanitized_stack_dir(:voyage_dir, VOYAGE_DEFAULT_DIR)
    @postgres_sort    = sanitized_stack_sort(:postgres_sort, POSTGRES_ALLOWED_SORTS, POSTGRES_DEFAULT_SORT)
    @postgres_dir     = sanitized_stack_dir(:postgres_dir, POSTGRES_DEFAULT_DIR)
    @assets_sort      = sanitized_stack_sort(:assets_sort, ASSETS_ALLOWED_SORTS, ASSETS_DEFAULT_SORT)
    @assets_dir       = sanitized_stack_dir(:assets_dir, ASSETS_DEFAULT_DIR)

    begin
      engine          = Pito::Search.engine
      @search_healthy = engine.healthy?
      @search_stats   = engine.index_stats.merge(
        version: engine.respond_to?(:version) ? engine.version : nil
      )
    rescue StandardError
      @search_healthy = false
      @search_stats   = { version: nil }
    end

    @postgres_status          = probe_postgres_status
    @search_per_index_stats   = sort_meilisearch_rows(probe_search_per_index_stats)
    @storage_status           = probe_storage_status
    @postgres_table_breakdown = sort_postgres_rows(probe_postgres_table_breakdown)
    @assets_breakdown         = sort_assets_rows(probe_assets_breakdown)
    @voyage_configured        = AppSetting.voyage_configured?
  end

  private

  # -----------------------------------------------------------------
  # Home calendar helpers
  # -----------------------------------------------------------------

  # Build Monday-first 6-week-max grid of Date objects for a given year/month.
  def home_calendar_month_grid(year, month)
    first      = Date.new(year, month, 1)
    last       = Date.new(year, month, -1)
    leading    = first.cwday - 1 # cwday: 1=Mon … 7=Sun
    grid_start = first - leading.days
    total_days = (last - grid_start).to_i + 1
    rows       = (total_days / 7.0).ceil
    Array.new(rows * 7) { |i| grid_start + i.days }
  end

  # Apply the 4-category `?calendar_filter[*]=on` filter to a scope.
  # nil   = param absent → all on (default state, no WHERE clause).
  # {}    = param present but empty → all off → scope.none.
  # Hash  = explicit subset of categories that are "on".
  def home_calendar_filter_scope(scope, raw_filter)
    return scope if raw_filter.nil?
    active = CalendarHelper::PANEL_CALENDAR_CATEGORIES.keys.select { |k| raw_filter[k].to_s == "on" }
    return scope.none if active.empty?
    types = active.flat_map { |cat| CalendarHelper::PANEL_CALENDAR_CATEGORIES[cat] }.compact
    scope.where(entry_type: types)
  end

  # -----------------------------------------------------------------
  # Session sort helpers
  # -----------------------------------------------------------------

  def sanitized_sessions_sort_key
    SESSIONS_ALLOWED_SORTS.key?(params[:sessions_sort]) ? params[:sessions_sort] : SESSIONS_DEFAULT_SORT
  end

  def sanitized_sessions_dir
    requested = params[:sessions_dir]&.downcase
    SESSIONS_ALLOWED_DIRS.include?(requested) ? requested : SESSIONS_DEFAULT_DIR
  end

  # `column` is looked up from a frozen allowlist; `direction` is one
  # of two literals — no user input ever reaches the SQL string.
  # Secondary sort by `last_activity_at desc, created_at desc` keeps
  # rows stable when the primary key has duplicates.
  def sessions_sort_clause
    column = SESSIONS_ALLOWED_SORTS.fetch(@sessions_sort)
    direction = SESSIONS_ALLOWED_DIRS.include?(@sessions_dir) ? @sessions_dir : SESSIONS_DEFAULT_DIR
    [
      Arel.sql("#{column} #{direction}"),
      Arel.sql("last_activity_at desc nulls last"),
      Arel.sql("created_at desc")
    ]
  end

  # -----------------------------------------------------------------
  # Stack probes
  # -----------------------------------------------------------------

  def probe_postgres_status
    conn = ActiveRecord::Base.connection
    db_config = ActiveRecord::Base.connection_db_config.configuration_hash
    version = conn.select_value("SHOW server_version_num").to_s
    major = version.to_i / 10_000
    {
      connected: conn.active?,
      adapter:   db_config[:adapter] || "postgresql",
      database:  db_config[:database].to_s,
      version:   major.positive? ? major.to_s : nil
    }
  rescue StandardError
    { connected: false, adapter: "postgresql", database: nil, version: nil }
  end

  def probe_storage_status
    root = Pito::AssetsRoot.root
    present = File.directory?(root)
    stats = present ? directory_volume_stats(root) : { size_bytes: 0, file_count: 0 }
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

  # Meilisearch unified `games_*` index, split into 2 rows (games +
  # bundles) by the `kind` field. The total index size lands on the
  # `games` row; the `bundles` row carries `omit_size: true` so the
  # view renders a single dash in the size column.
  def probe_search_per_index_stats
    engine_rows = {}

    if Pito::Search.engine.respond_to?(:per_index_stats)
      stats = Pito::Search.engine.per_index_stats
      stats.each do |index_name, payload|
        next if index_name.to_s.end_with?("_test")
        label = index_name.to_s.sub(/_(development|production)\z/, "")
        next unless SEARCH_INDEX_DISPLAY_ALLOWLIST.include?(label)
        engine_rows[label] = {
          documents:      (payload[:documents] || payload["documents"] || 0).to_i,
          size_bytes:     payload[:size_bytes] || payload["size_bytes"],
          raw_index_name: index_name.to_s
        }
      end
    end

    rows = []
    games_payload = engine_rows["games"]
    if games_payload
      games_docs, bundles_docs = split_games_index_by_kind(games_payload[:raw_index_name], games_payload[:documents])
      rows << { label: "games",   documents: games_docs.to_i,   size_bytes: games_payload[:size_bytes], missing: false }
      rows << { label: "bundles", documents: bundles_docs.to_i, size_bytes: nil, omit_size: true, missing: false }
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

  def probe_postgres_table_breakdown
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
    conn = ActiveRecord::Base.connection
    quoted = conn.quote_table_name(table)
    size = conn.select_value("SELECT pg_total_relation_size('#{quoted}')")&.to_i
    count = class_name.safe_constantize&.count
    { count: count, size_bytes: size }
  rescue StandardError
    { count: nil, size_bytes: nil }
  end

  def probe_assets_breakdown
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

  # -----------------------------------------------------------------
  # Stack sub-panel sort helpers
  # -----------------------------------------------------------------

  def sanitized_stack_sort(param, allowed, default)
    v = params[param].to_s
    allowed.include?(v) ? v : default
  end

  def sanitized_stack_dir(param, default)
    v = params[param].to_s.downcase
    STACK_ALLOWED_DIRS.include?(v) ? v : default
  end

  # Sort Meilisearch per_index_stats rows by the current column + direction.
  # Columns: index (label string), docs (integer), size (size_bytes integer).
  def sort_meilisearch_rows(rows)
    key, dir = @meilisearch_sort, @meilisearch_dir
    sorted = case key
    when "index" then rows.sort_by { |r| r[:label].to_s.downcase }
    when "docs"  then rows.sort_by { |r| [ r[:missing] ? 1 : 0, r[:documents].to_i ] }
    when "size"  then rows.sort_by { |r| [ r[:omit_size] ? 1 : 0, r[:size_bytes].to_i ] }
    else rows
    end
    dir == "asc" ? sorted : sorted.reverse
  end

  # Sort Postgres table_breakdown rows by the current column + direction.
  # Columns: model (label string), rows (count integer), size (size_bytes integer).
  def sort_postgres_rows(rows)
    key, dir = @postgres_sort, @postgres_dir
    sorted = case key
    when "model" then rows.sort_by { |r| r[:label].to_s.downcase }
    when "rows"  then rows.sort_by { |r| r[:count].to_i }
    when "size"  then rows.sort_by { |r| r[:size_bytes].to_i }
    else rows
    end
    dir == "asc" ? sorted : sorted.reverse
  end

  # Sort assets breakdown rows by the current column + direction.
  # Columns: category (label string), files (file_count integer), size (size_bytes integer).
  def sort_assets_rows(rows)
    key, dir = @assets_sort, @assets_dir
    sorted = case key
    when "category" then rows.sort_by { |r| r[:label].to_s.downcase }
    when "files"    then rows.sort_by { |r| r[:file_count].to_i }
    when "size"     then rows.sort_by { |r| r[:size_bytes].to_i }
    else rows
    end
    dir == "asc" ? sorted : sorted.reverse
  end
end
