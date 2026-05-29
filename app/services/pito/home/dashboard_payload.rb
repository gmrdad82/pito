module Pito
  module Home
    # Pito::Home::DashboardPayload
    #
    # Assembles the data payload for DashboardController#index.
    # Aggregates stack health + sessions + webhooks + voyage state into
    # a single value object the controller assigns to ivars in one call.
    #
    # ## Why this exists
    #
    # The Home dashboard pulls cross-domain data (sessions, webhooks,
    # postgres + meilisearch + voyage + assets stack stats). Rather than
    # bloating the controller with 24 helpers, all that orchestration
    # lives here.
    #
    # ## Usage
    #
    #   payload = Pito::Home::DashboardPayload.new(user: Current.user, params: params).call
    #   payload.each { |key, value| instance_variable_set("@#{key}", value) }
    #
    class DashboardPayload
      SESSIONS_ALLOWED_SORTS = {
        "device"        => "device",
        "browser"       => "browser",
        "ip"            => "ip",
        "last_activity" => "last_activity_at",
        "created"       => "created_at",
        "user_agent"    => "device" # legacy alias
      }.freeze
      SESSIONS_ALLOWED_DIRS  = %w[asc desc].freeze
      SESSIONS_DEFAULT_SORT  = "last_activity"
      SESSIONS_DEFAULT_DIR   = "desc"

      SEARCH_INDEX_DISPLAY_ALLOWLIST = %w[games].freeze

      # R1 (2026-05-25) — bundles row removed.
      POSTGRES_TABLE_ROWS = [
        { label: "games", table: "games", class_name: "Game" }
      ].freeze

      # R1 (2026-05-25) — composites/bundles dir removed.
      ASSETS_CATEGORY_DIRECTORIES = {
        "cover arts" => [ "covers", "games" ]
      }.freeze

      def initialize(user:, params: {})
        @user   = user
        @params = params
      end

      # Returns a Hash of ivars the controller assigns via instance_variable_set.
      def call
        sessions_sort = sanitized_sessions_sort_key
        sessions_dir  = sanitized_sessions_dir

        sessions =
          if @user.present?
            @user.sessions.active_sessions.order(
              sessions_sort_clause(sessions_sort, sessions_dir)
            )
          else
            Session.none
          end

        search_healthy, search_stats = resolve_search_health

        {
          user:                     @user,
          twofa_enabled:            @user&.totp_enabled? || false,
          active_sessions_count:    @user.present? ? @user.sessions.where(revoked_at: nil).count : 0,
          sessions_sort:            sessions_sort,
          sessions_dir:             sessions_dir,
          sessions:                 sessions,
          slack_webhook:            NotificationDeliveryChannel.find_record_for("slack"),
          discord_webhook:          NotificationDeliveryChannel.find_record_for("discord"),
          search_healthy:           search_healthy,
          search_stats:             search_stats,
          postgres_status:          postgres_status_for_settings_pane,
          search_per_index_stats:   search_per_index_stats_for_settings_pane,
          storage_status:           storage_status_for_settings_pane,
          postgres_table_breakdown: postgres_table_breakdown_for_settings_pane,
          assets_breakdown:         assets_breakdown_for_settings_pane,
          voyage_configured:        AppSetting.voyage_configured?
        }
      end

      private

      # ---------------------------------------------------------------------------
      # Sessions helpers
      # ---------------------------------------------------------------------------

      def sanitized_sessions_sort_key
        SESSIONS_ALLOWED_SORTS.key?(@params[:sessions_sort]) ? @params[:sessions_sort] : SESSIONS_DEFAULT_SORT
      end

      def sanitized_sessions_dir
        requested = @params[:sessions_dir]&.downcase
        SESSIONS_ALLOWED_DIRS.include?(requested) ? requested : SESSIONS_DEFAULT_DIR
      end

      def sessions_sort_clause(sort_key, dir)
        column    = SESSIONS_ALLOWED_SORTS.fetch(sort_key)
        direction = SESSIONS_ALLOWED_DIRS.include?(dir) ? dir : SESSIONS_DEFAULT_DIR
        [
          Arel.sql("#{column} #{direction}"),
          Arel.sql("last_activity_at desc nulls last"),
          Arel.sql("created_at desc")
        ]
      end

      # ---------------------------------------------------------------------------
      # Search helpers
      # ---------------------------------------------------------------------------

      def resolve_search_health
        healthy = Pito::Search.engine.healthy?
        stats   = Pito::Search.engine.index_stats
        [ healthy, stats ]
      rescue StandardError
        [ false, {} ]
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
              documents:      (payload[:documents] || payload["documents"] || 0).to_i,
              size_bytes:     payload[:size_bytes] || payload["size_bytes"],
              raw_index_name: index_name.to_s
            }
          end
        end

        rows = []
        games_payload = engine_rows["games"]
        if games_payload
          games_docs, bundles_docs = split_games_index_by_kind(
            games_payload[:raw_index_name], games_payload[:documents]
          )
          rows << { label: "games",   documents: games_docs.to_i,   size_bytes: games_payload[:size_bytes], missing: false }
          rows << { label: "bundles", documents: bundles_docs.to_i, size_bytes: nil, omit_size: true,       missing: false }
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

      # ---------------------------------------------------------------------------
      # Postgres helpers
      # ---------------------------------------------------------------------------

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

      # ---------------------------------------------------------------------------
      # Storage / assets helpers
      # ---------------------------------------------------------------------------

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
    end
  end
end
