# Phase 14 §1 — IGDB sync orchestrator.
#
# Single public method `call(game)`:
#   1. Fetch the IGDB game row + time-to-beat row + external-games rows.
#   2. Map the JSON into IGDB-sourced attributes (no local-only columns).
#   3. Upsert reference rows (Genre, Platform, Company) by `igdb_id`.
#   4. Replace join rows (game_genres / game_platforms / game_developers
#      / game_publishers) — delete-and-create semantics.
#   5. Stamp `igdb_synced_at`, clear `last_sync_error`.
#
# Last-write-wins per spec Q5: every IGDB-sourced column is in the
# `attrs` hash. Local-only columns (`played_at`, `notes`,
# `hours_of_footage_manual`) are NEVER written here. Per-platform
# ownership (Phase 27 §1a) lives in `game_platform_ownerships` — the
# join survives sync untouched.
#
# The whole flow runs in a single transaction so a partial failure
# rolls back the IGDB-sourced overwrite.
module Igdb
  class SyncGame
    def initialize(client: Igdb::Client.new)
      @client = client
    end

    def call(game)
      raise ArgumentError, "Game has no igdb_id" if game.igdb_id.blank?

      game_json = @client.fetch_game(game.igdb_id).first
      raise Igdb::Client::ValidationError, "IGDB has no game with id=#{game.igdb_id}" if game_json.nil?

      ttb_json    = @client.fetch_time_to_beat(game.igdb_id)
      extern_json = @client.fetch_external_games(game.igdb_id)

      attrs = Igdb::GameMapper.map_game(game_json, ttb_json, extern_json)

      Game.transaction do
        # Phase 28 §01a — resolve `version_parent_id` BEFORE the main
        # `assign_attributes` so the local FK is set in the same save.
        # Returns nil when the payload has no `version_parent` field
        # OR the field is blank (a primary). Idempotent: re-imports of
        # a row whose parent is already known reuse the existing local
        # row rather than create a sibling.
        parent_id = resolve_version_parent_id(game_json["version_parent"])
        attrs[:version_parent_id] = parent_id unless parent_id.nil?

        assign_with_slug_collision_guard(game, attrs)
        sync_genres(game, game_json["genres"])
        sync_platforms(game, game_json["platforms"])
        sync_developers(game, game_json["involved_companies"])
        sync_publishers(game, game_json["involved_companies"])
        game.update!(igdb_synced_at: Time.current, last_sync_error: nil)
      end

      game
    rescue Igdb::Client::ValidationError => e
      stamp_error(game, e.message)
      raise
    end

    private

    # Phase 28 §01a — resolve the IGDB `version_parent` payload field
    # to a local `games.id`. Behaviour:
    #
    #   - nil / blank payload     → nil (the row is a primary).
    #   - existing local row      → reuse its id.
    #   - not yet imported        → fetch from IGDB, recursively sync
    #                                the parent (which lands as a
    #                                primary — IGDB's `version_parent`
    #                                is one level deep by convention),
    #                                then return the new row's id.
    #   - IGDB returns a chain    → log a warning and walk to the first
    #                                primary the chain points at. v1
    #                                stops there; deeper chains are out
    #                                of scope.
    #
    # Idempotent: re-running the importer with the same payload does
    # not create a second parent row (the local lookup by `igdb_id`
    # is the de-dupe boundary).
    def resolve_version_parent_id(version_parent_igdb_id, depth: 0)
      return nil if version_parent_igdb_id.blank?
      return nil unless version_parent_igdb_id.is_a?(Integer) || version_parent_igdb_id.to_s.match?(/\A\d+\z/)

      parent_igdb_id = version_parent_igdb_id.to_i
      return nil unless parent_igdb_id.positive?

      existing = Game.find_by(igdb_id: parent_igdb_id)
      return existing.id if existing && existing.version_parent_id.nil?
      return existing.version_parent_id if existing && existing.version_parent_id.present? && depth.zero?

      # Cap recursion depth so a bad IGDB payload cannot loop forever.
      if depth >= 3
        Rails.logger.warn("[Igdb::SyncGame] version_parent recursion depth exceeded (#{parent_igdb_id})")
        return existing&.id
      end

      parent_json = @client.fetch_game(parent_igdb_id).first
      if parent_json.nil?
        Rails.logger.warn("[Igdb::SyncGame] version_parent id=#{parent_igdb_id} not found on IGDB")
        return existing&.id
      end

      # IGDB convention: a `version_parent` is one level deep. If we
      # encounter a chain, walk it and stop at the first primary so the
      # local DB does not mirror the chain.
      if parent_json["version_parent"].present? && parent_json["version_parent"].to_i != parent_igdb_id
        Rails.logger.warn("[Igdb::SyncGame] IGDB returned a chain at #{parent_igdb_id} → #{parent_json['version_parent']}; walking up")
        return resolve_version_parent_id(parent_json["version_parent"], depth: depth + 1)
      end

      # Create-or-find the local row by IGDB id, then sync the parent
      # so its IGDB-sourced columns are populated. `find_or_create_by!`
      # collapses the concurrent-sibling-import race (two editions of
      # the same not-yet-imported parent).
      parent_row = Game.find_or_create_by!(igdb_id: parent_igdb_id)
      if parent_row.igdb_synced_at.nil? || parent_row.title.to_s == "Untitled game"
        # Recurse via a fresh instance so the calling frame's local
        # state stays intact. `call` runs in its own transaction; we
        # are already inside the caller's transaction so the parent
        # save participates in the same outer transaction (Postgres
        # savepoints handle the nesting).
        self.class.new(client: @client).call(parent_row)
      end
      parent_row.id
    end

    def assign_with_slug_collision_guard(game, attrs)
      game.assign_attributes(attrs)
      game.save!
    rescue ActiveRecord::RecordNotUnique => e
      raise unless e.message.to_s.include?("igdb_slug")
      # Spec Open Question #7: slug collision. Fall back to NULL slug,
      # stamp last_sync_error, let the user resolve manually.
      game.assign_attributes(attrs.merge(igdb_slug: nil))
      game.last_sync_error = "igdb error: slug collision (#{attrs[:igdb_slug]})"
      game.save!
    end

    def sync_genres(game, genres_json)
      list = Array(genres_json).select { |row| row.is_a?(Hash) }
      genre_records = list.map { |row| upsert_genre(row) }
      game.game_genres.where.not(genre_id: genre_records.map(&:id)).destroy_all
      genre_records.each do |g|
        GameGenre.where(game_id: game.id, genre_id: g.id).first_or_create!
      end
    end

    def sync_platforms(game, platforms_json)
      list = Array(platforms_json).select { |row| row.is_a?(Hash) }
      platform_records = list.map { |row| upsert_platform(row) }
      game.game_platforms.where.not(platform_id: platform_records.map(&:id)).destroy_all
      platform_records.each do |p|
        GamePlatform.where(game_id: game.id, platform_id: p.id).first_or_create!
      end
    end

    def sync_developers(game, involved_companies)
      records = Igdb::GameMapper.developers(involved_companies).map { |attrs| upsert_company(attrs) }
      game.game_developers.where.not(company_id: records.map(&:id)).destroy_all
      records.each do |c|
        GameDeveloper.where(game_id: game.id, company_id: c.id).first_or_create!
      end
    end

    def sync_publishers(game, involved_companies)
      records = Igdb::GameMapper.publishers(involved_companies).map { |attrs| upsert_company(attrs) }
      game.game_publishers.where.not(company_id: records.map(&:id)).destroy_all
      records.each do |c|
        GamePublisher.where(game_id: game.id, company_id: c.id).first_or_create!
      end
    end

    def upsert_genre(row)
      attrs = Igdb::GameMapper.map_genre(row)
      genre = Genre.find_or_initialize_by(igdb_id: attrs[:igdb_id])
      genre.assign_attributes(attrs)
      genre.save!
      genre
    end

    def upsert_platform(row)
      attrs = Igdb::GameMapper.map_platform(row)
      platform = Platform.find_or_initialize_by(igdb_id: attrs[:igdb_id])
      platform.assign_attributes(attrs)
      platform.save!
      platform
    end

    def upsert_company(attrs)
      company = Company.find_or_initialize_by(igdb_id: attrs[:igdb_id])
      company.assign_attributes(attrs)
      company.save!
      company
    end

    def stamp_error(game, message)
      return if game.destroyed?
      Game.where(id: game.id).update_all(last_sync_error: "igdb error: #{message}")
      game.reload if game.persisted?
    rescue ActiveRecord::RecordNotFound
      # Game was deleted between fetch and stamp — nothing to do.
    end
  end
end
