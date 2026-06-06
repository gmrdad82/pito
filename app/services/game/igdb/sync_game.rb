# Phase 14 §1 — IGDB sync orchestrator.
#
# Single public method `call(game)`:
#   1. Fetch the IGDB game row + time-to-beat row + external-games rows.
#   2. Map the JSON into IGDB-sourced attributes (no local-only columns).
#   3. Upsert reference rows (Genre, Company) by `igdb_id`.
#   4. Replace join rows (game_genres / game_developers / game_publishers)
#      — delete-and-create semantics.
#   5. Stamp `igdb_synced_at`, clear `last_sync_error`.
#
# Last-write-wins per spec Q5: every IGDB-sourced column is in the
# `attrs` hash. Local-only columns (`played_at`, `notes`,
# `hours_of_footage_manual`) are NEVER written here.
#
# The whole flow runs in a single transaction so a partial failure
# rolls back the IGDB-sourced overwrite.
class Game
  module Igdb
    class SyncGame
      def initialize(client: Game::Igdb::Client.new)
        @client = client
      end

      def call(game)
        raise ArgumentError, "Game has no igdb_id" if game.igdb_id.blank?

        game_json = @client.fetch_game(game.igdb_id).first
        raise Game::Igdb::Client::ValidationError, "IGDB has no game with id=#{game.igdb_id}" if game_json.nil?

        ttb_json = @client.fetch_time_to_beat(game.igdb_id)

        attrs = Game::Igdb::GameMapper.map_game(game_json, ttb_json)

        Game.transaction do
          assign_with_slug_collision_guard(game, attrs)
          sync_genres(game, game_json["genres"])
          # Phase 27 v2 spec 01 — re-evaluate the canonical primary genre
          # on EVERY sync. `update_column` writes the FK without callbacks.
          re_assign_primary_genre(game)
          sync_developers(game, game_json["involved_companies"])
          sync_publishers(game, game_json["involved_companies"])
          game.update!(igdb_synced_at: Time.current, last_sync_error: nil)
        end

        # Phase 27 follow-up (2026-05-17) — generate the normalized
        # cover master after every IGDB sync. Idempotent — the
        # Normalizer short-circuits when the master file's mtime is
        # newer than `igdb_synced_at` (which we just bumped, so this
        # run always re-normalizes).
        #
        # Rescued + logged because IGDB CDN can 404 / network can blip;
        # a cover-art hiccup must not fail the sync (the IGDB-sourced
        # row is already committed at this point).
        begin
          Game::CoverArt::Normalizer.new(game: game).call
        rescue StandardError => e
          Rails.logger.warn "[Game::Igdb::SyncGame] cover normalization failed for game id=#{game.id}: #{e.class}: #{e.message}"
        end

        # Phase 34 (2026-05-18) — enqueue Voyage embedding for the
        # freshly synced row. Async so the user-facing sync POST
        # doesn't block on Voyage HTTP. The job is idempotent
        # (re-embeds + re-writes) so a duplicate enqueue from any
        # other path (rake backfill, manual console call) is safe.
        GameVoyageIndexJob.perform_later(game.id)

        game
      rescue Game::Igdb::Client::ValidationError => e
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

      # IGDB returns `genres` in canonical primacy order (first = primary).
      # `game_genres.position` captures the 0-based IGDB array index so
      # later ordering can prefer the IGDB-first genre. Re-syncs overwrite
      # the position for rows that survive the delete-and-create boundary.
      def sync_genres(game, genres_json)
        list = Array(genres_json).select { |row| row.is_a?(Hash) }
        genre_records = list.map { |row| upsert_genre(row) }
        game.game_genres.where.not(genre_id: genre_records.map(&:id)).destroy_all
        genre_records.each_with_index do |g, index|
          join = GameGenre.where(game_id: game.id, genre_id: g.id).first_or_create!
          join.update_column(:position, index) unless join.position == index
        end
      end

      # Phase 27 v2 spec 01 — explicit re-pick on every sync. The
      # `Game::PrimaryGenrePicker` rule 1 honors an existing
      # `primary_genre_id` pin (so user-set pins survive). IGDB sync
      # deliberately bypasses that pin honor: a re-sync is the canonical
      # moment to re-derive from IGDB's current metadata, so we clear
      # the pointer in memory FIRST, then run the picker so its rule 2
      # (alphabetical) drives the choice. Reloads first so
      # `game.genres` reflects the post-`sync_genres` set rather than a
      # cached pre-sync snapshot. Writes via `update_column` to skip
      # the `before_save` hook so the caller's `game.update!
      # (igdb_synced_at: ...)` still detects the `igdb_synced_at`
      # change cleanly without a double-write loop. Writes `nil` when
      # the post-sync set is empty (IGDB dropped every previously-
      # linked genre) so the pointer never stays stale.
      def re_assign_primary_genre(game)
        game.reload
        # In-memory clear so the picker's rule-1 pin guard short-circuits
        # to the alphabetical pick. The actual DB write that follows
        # carries the freshly-derived id (or nil).
        game.primary_genre_id = nil
        pick = Game::PrimaryGenrePicker.new.pick(game)
        game.update_column(:primary_genre_id, pick&.id)
      end

      def sync_developers(game, involved_companies)
        records = Game::Igdb::GameMapper.developers(involved_companies).map { |attrs| upsert_company(attrs) }
        game.game_developers.where.not(company_id: records.map(&:id)).destroy_all
        records.each do |c|
          GameDeveloper.where(game_id: game.id, company_id: c.id).first_or_create!
        end
      end

      def sync_publishers(game, involved_companies)
        records = Game::Igdb::GameMapper.publishers(involved_companies).map { |attrs| upsert_company(attrs) }
        game.game_publishers.where.not(company_id: records.map(&:id)).destroy_all
        records.each do |c|
          GamePublisher.where(game_id: game.id, company_id: c.id).first_or_create!
        end
      end

      def upsert_genre(row)
        attrs = Game::Igdb::GameMapper.map_genre(row)
        genre = Genre.find_or_initialize_by(igdb_id: attrs[:igdb_id])
        genre.assign_attributes(attrs)
        genre.save!
        genre
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
end
