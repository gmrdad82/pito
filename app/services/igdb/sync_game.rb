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
# `attrs` hash. Local-only columns (`platform_owned_id`, `played_at`,
# `notes`, `hours_of_footage_manual`) are NEVER written here.
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
