class SettingsController < ApplicationController
  # 2026-05-16 (sessions revamp v2). The Security pane now renders the
  # sessions table INLINE. Column sort is driven by `?sessions_sort=…`
  # + `?sessions_dir=…` on `/settings` itself (the standalone
  # `/settings/sessions` index is gone).
  #
  # FB-132 (2026-05-21). Allowlist expanded to all five data columns
  # (`device`, `browser`, `ip`, `last_activity`, `created`) after
  # migration `20260521002333_add_device_and_browser_to_sessions`
  # promoted `device` + `browser` to real indexable columns. The legacy
  # `user_agent` alias stays for backward compat (the prior
  # `sessions_sort=user_agent` query string still resolves) but the
  # canonical key is `device` going forward.
  SESSIONS_ALLOWED_SORTS = {
    "device"        => "device",
    "browser"       => "browser",
    "ip"            => "ip",
    "last_activity" => "last_activity_at",
    "created"       => "created_at",
    "user_agent"    => "device" # legacy alias — pre-FB-132 query strings
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
  # the theme system was removed entirely (2026-05-19); keyboard
  # navigation is always-on.
  #
  # The OAuth-applications + tokens management UI is also gone — pito
  # is single-user, the operator manages those from the shell via
  # `bin/rails pito:oauth_apps:*` and `bin/rails pito:tokens:*`. The
  # Doorkeeper handshake endpoints (`/oauth/authorize`,
  # `/oauth/token`, `/oauth/revoke`, `/oauth/introspect`) stay live
  # for the Claude Desktop OAuth client.
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
    redirect_to settings_path, notice: t("settings.flash.saved")
  end

  # 2026-05-18 (DR follow-up) — KEPT as a fallback / diagnostics
  # endpoint after the live `/settings` pane moved from HTTP polling to
  # ActionCable push (see `StackStatsChannel` + `StackStats::Broadcaster`).
  # The Stimulus controller no longer hits this URL on a timer, but
  # leaving the route + action live is cheap and useful for one-shot
  # `curl /settings/stack_stats` debugging and any future automation
  # that wants a synchronous snapshot.
  #
  # Both this action and the cable broadcaster call the same shared
  # builder (`StackStats::Payload`) so the wire shape is identical
  # regardless of transport.
  def stack_stats
    render json: StackStats::Payload.call
  rescue StandardError => e
    Rails.logger.warn("[settings#stack_stats] #{e.class}: #{e.message}")
    render json: { redis: {}, voyage: {}, postgres: {}, meilisearch: {}, assets: {} }, status: :ok
  end

  # FB-63 (2026-05-20) — split reindex actions. The combined
  # `[reindex]` action that triggered both Meilisearch + Voyage in one
  # job is gone; each subsystem tile in the Stack pane now owns its
  # own `[reindex]` link.
  #
  # Three-layer reindex lock contract is unchanged from the prior
  # combined action — both halves share the same
  # `AppSetting.reindex_running?` flag, so kicking one while the
  # other is in flight is rejected with the same alert. Layer 1 (DB
  # flag) is enforced here BEFORE enqueueing. Layer 2
  # (`sidekiq_options lock: :until_executed`) lives on each job.
  # Layer 3 (UI gate) is the Voyage section + tile-level link
  # rendering — see `_voyage_section.html.erb` + `_stack_pane.html.erb`.
  # FB-138 (2026-05-21). The reindex actions are submitted from the
  # `Tui::ConfirmationDialogComponent` form which IS Turbo-driven
  # (Rails 8 `form_with` default). Returning `head :no_content`
  # (HTTP 204) tells Turbo to do nothing — no navigation, no body
  # render — and the controller's `turbo:submit-end` listener closes
  # the dialog. The cable broadcast
  # (`StackStats::Broadcaster.broadcast!` from the job + the
  # brand-tagged `reindex_started` event) drives the in-place UI swap.
  #
  # FB-149 (2026-05-21). Conflicts (a second click while the shared
  # lock is held) ALSO return 204 — Turbo's 409 handling renders the
  # empty response body and could trigger a navigation to the action
  # URL. The cable already surfaces the running state visually, so
  # the dialog closes silently on the no-op path. The double click
  # is harmless: `start_reindex!` is gated by `reindex_running?`
  # below so we never enqueue twice.
  def meilisearch_reindex
    unless AppSetting.reindex_running?
      AppSetting.start_reindex!
      MeilisearchReindexJob.perform_later
    end
    head :no_content
  end

  def voyage_reindex
    unless AppSetting.reindex_running?
      AppSetting.start_reindex!
      VoyageReindexJob.perform_later
    end
    head :no_content
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

  # Public-safe subset surfaced to the JSON API. Sourced from
  # `config.x.pito`. The pito CLI's `AppSettings` Rust struct binds to
  # these fields; the Rust crate is paused and will be rebuilt against
  # this shape when CLI parity work resumes.
  def settings_json
    {
      max_panes: Rails.application.config.x.pito.max_panes,
      pane_title_length: Rails.application.config.x.pito.pane_title_length
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

  # 2026-05-18 — the unified `games_<env>` Meilisearch index holds both
  # Game and Bundle documents (distinguished by the `kind` field — see
  # `Meilisearch::BundleIndexer`). We surface them as TWO rows in the
  # Stack pane so the operator can see games-vs-bundles indexed counts
  # at a glance.
  #
  # Size-by-kind: Meilisearch reports total index size only; splitting it
  # cleanly is impossible. The simplest, most-honest rendering is to put
  # the total index size on the `games` row and `—` on the `bundles` row.
  # The bundles row carries `size_bytes: nil` + `omit_size: true` so the
  # view renders a single dash in that column. (The alternative —
  # apportioning by doc ratio — risks misleading the operator into
  # thinking the engine actually reports per-kind storage.)
  SEARCH_INDEX_DISPLAY_ALLOWLIST = %w[games].freeze

  def search_per_index_stats_for_settings_pane
    engine_rows = {}

    if Search.engine.respond_to?(:per_index_stats)
      stats = Search.engine.per_index_stats
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
      rows << {
        label: "games",
        documents: games_docs.to_i,
        size_bytes: games_payload[:size_bytes],
        missing: false
      }
      rows << {
        label: "bundles",
        documents: bundles_docs.to_i,
        size_bytes: nil,
        omit_size: true,
        missing: false
      }
    else
      # Index not yet created. Render both rows as not-yet-indexed so
      # the Stack pane still surfaces the section instead of going silent.
      rows << { label: "games", documents: 0, size_bytes: nil, missing: true }
      rows << { label: "bundles", documents: 0, size_bytes: nil, missing: true, omit_size: true }
    end

    rows
  rescue StandardError
    [
      { label: "games", documents: 0, size_bytes: nil, missing: true },
      { label: "bundles", documents: 0, size_bytes: nil, missing: true, omit_size: true }
    ]
  end

  # Query Meilisearch for `kind = "game"` and `kind = "bundle"` counts
  # inside the unified index. Falls back to "all games, zero bundles"
  # when the engine doesn't support filtered counts (or the call fails)
  # so the row totals still reconcile with the total reported by
  # `per_index_stats`.
  def split_games_index_by_kind(raw_index_name, total_documents)
    return [ total_documents, 0 ] unless Search.engine.respond_to?(:documents_count_for)

    games_count = Search.engine.documents_count_for(raw_index_name, field: "kind", value: "game")
    bundles_count = Search.engine.documents_count_for(raw_index_name, field: "kind", value: "bundle")

    if games_count.nil? && bundles_count.nil?
      [ total_documents, 0 ]
    else
      [ games_count.to_i, bundles_count.to_i ]
    end
  rescue StandardError
    [ total_documents, 0 ]
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

  # 2026-05-20 — Notes volume status now reads the SAME path the
  # `notes` namespace breakdown table reads (see
  # `NOTES_NAMESPACE_SOURCES` below). The previous implementation
  # checked `Rails.root.join("docs/notes")` — an UNRELATED design-doc
  # directory that has no relationship to the notes data root used by
  # `NotesFilesystem.root` / `NOTES_NAMESPACE_SOURCES`. The result was
  # a logically contradictory display: the chip rendered `[not
  # present]` (because `docs/notes/` is absent / removed) while the
  # breakdown table below it reported a 39 KB volume sourced from
  # `tmp/pito-notes`. Aligning both surfaces to the same path resolver
  # keeps the chip and the table answering the same question.
  def notes_volume_status_for_settings_pane
    path = notes_volume_path_for_settings_pane
    present = path.present? && File.directory?(path)
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

  # Resolves the same notes-data root that the breakdown table renders
  # against. Mirrors the `path:` lambda inside `NOTES_NAMESPACE_SOURCES`
  # so the two surfaces never drift. `PITO_NOTES_PATH` wins when set;
  # otherwise the dev fallback (`tmp/pito-notes`) is used.
  def notes_volume_path_for_settings_pane
    ENV["PITO_NOTES_PATH"].presence || Rails.root.join("tmp/pito-notes").to_s
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

  # 2026-05-18 (DR) — Postgres breakdown surfaces the two beta-3-revisited
  # surfaces as separate rows: `games` and `bundles`. Channels / videos /
  # projects / notifications / calendar_entries stay dropped from the
  # display until those product areas land in beta-3 — keeping them would
  # falsely advertise them as first-class.
  #
  # Each row reads `pg_total_relation_size` for its own table and uses the
  # corresponding model's `.count` (via `safe_constantize`). Missing tables
  # render with nil → "—" in the view.
  POSTGRES_TABLE_ROWS = [
    { label: "games", table: "games", class_name: "Game" },
    { label: "bundles", table: "bundles", class_name: "Bundle" }
  ].freeze

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

  # 2026-05-18 — live-stats shapers for the per-row Postgres / Meilisearch /
  # assets cells. Each returns a flat hash the `stack-stats-live` Stimulus
  # controller can read directly. Errors swallow to `{}` so a transient
  # blip never blanks the page; the next 3-second poll retries.
  def stack_stats_postgres
    rows = postgres_table_breakdown_for_settings_pane
    flat = {}
    rows.each do |row|
      key = row[:label].to_s
      flat["#{key}_rows".to_sym] = row[:count]
      flat["#{key}_size_bytes".to_sym] = row[:size_bytes]
    end
    flat
  rescue StandardError
    {}
  end

  def stack_stats_meilisearch
    rows = search_per_index_stats_for_settings_pane
    flat = {}
    rows.each do |row|
      key = row[:label].to_s
      flat["#{key}_docs".to_sym] = row[:documents]
      flat["#{key}_size_bytes".to_sym] = row[:size_bytes]
      flat["#{key}_missing".to_sym] = row[:missing] ? true : false
      flat["#{key}_omit_size".to_sym] = row[:omit_size] ? true : false
    end
    flat
  rescue StandardError
    {}
  end

  def stack_stats_assets
    rows = assets_breakdown_for_settings_pane
    flat = {}
    rows.each do |row|
      key = row[:label].to_s.tr(" ", "_")
      flat["#{key}_files".to_sym] = row[:file_count]
      flat["#{key}_size_bytes".to_sym] = row[:size_bytes]
    end
    flat
  rescue StandardError
    {}
  end

  # 2026-05-18 (DR) — Redis / Sidekiq counters for the live
  # `/settings/stack_stats` JSON endpoint. Mirrors
  # `sidekiq_breakdown_for_settings_pane` shape but flat-keyed so the
  # JS controller can read each value with a single property access.
  # Errors swallow to `{}` so a transient Redis blip never blanks the
  # page; the next poll retries.
  def stack_stats_redis
    stats = Sidekiq::Stats.new
    busy =
      begin
        Sidekiq::Workers.new.size
      rescue StandardError
        0
      end
    {
      busy: busy,
      scheduled: stats.scheduled_size,
      enqueued: stats.enqueued,
      retry: stats.retry_size,
      dead: stats.dead_size,
      processed: stats.processed,
      failed: stats.failed
    }
  rescue StandardError
    {}
  end

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

  # 2026-05-18 — assets breakdown surfaces the two beta-3 cover-art
  # categories as separate rows:
  #
  #   * cover arts — game master images normalized by
  #     `Games::CoverArt::Normalizer` to `<root>/covers/games/<id>/master.jpg`
  #   * composites — bundle composites assembled by `Composite::Builder`
  #     to `<root>/covers/bundles/<id>/composite.jpg`
  #
  # Both rows always render — even when the directories are empty or
  # missing — so the operator sees the category list at a glance.
  # Thumbnails, banners, and the catch-all "other" bucket stay dropped
  # until those product surfaces (footage / channel banners / etc.) are
  # revisited in the beta-3 sweep.
  ASSETS_CATEGORY_DIRECTORIES = {
    "cover arts" => [ "covers", "games" ],
    "composites" => [ "covers", "bundles" ]
  }.freeze

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
