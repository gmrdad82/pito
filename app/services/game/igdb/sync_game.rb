# IGDB sync orchestrator.
#
# Single public method `call(game)`:
#   1. Fetch the IGDB game row + time-to-beat row + external-games rows.
#   2. Map the JSON into IGDB-sourced attributes (no local-only columns).
#   3. Upsert reference rows (Genre, Company) by `igdb_id`.
#   4. Replace join rows (game_genres / game_developers / game_publishers)
#      — delete-and-create semantics.
#   5. Stamp `igdb_synced_at`, clear `last_sync_error`.
#
# Last-write-wins: every IGDB-sourced column is in the `attrs` hash.
# Local-only columns are NEVER written here.
#
# The whole flow runs in a single transaction so a partial failure
# rolls back the IGDB-sourced overwrite.
class Game
  module Igdb
    class SyncGame
      def initialize(client: Game::Igdb::Client.new)
        @client = client
      end

      # `prefetched:` — bulk callers (GameIgdbNightlyRefresh)
      # pass `{ game_json:, ttb_json: }` fetched via the ⌈N/500⌉ bulk queries;
      # the two per-game requests are then skipped. When prefetched is given
      # but carries no game_json, the game is MISSING on IGDB — same
      # ValidationError as an empty individual fetch (no silent refetch).
      def call(game, prefetched: nil)
        raise ArgumentError, "Game has no igdb_id" if game.igdb_id.blank?

        game_json = prefetched ? prefetched[:game_json] : @client.fetch_game(game.igdb_id).first
        raise Game::Igdb::Client::ValidationError, "IGDB has no game with id=#{game.igdb_id}" if game_json.nil?

        ttb_json = prefetched ? prefetched[:ttb_json] : @client.fetch_time_to_beat(game.igdb_id)

        attrs = Game::Igdb::GameMapper.map_game(game_json, ttb_json)

        Game.transaction do
          assign_with_slug_collision_guard(game, attrs)
          sync_genres(game, game_json["genres"])
          sync_developers(game, game_json["involved_companies"])
          sync_publishers(game, game_json["involved_companies"])
          # BOOKKEEPING stamp, not a data change — update_columns skips the
          # updated_at touch. The nightly refresh detects "this game changed"
          # by comparing updated_at before/after the sync: stamping
          # through update! marked every synced game as updated every night
          # ("checked 60, updated 60" with nothing actually changed).
          game.assign_attributes(igdb_synced_at: Time.current, last_sync_error: nil)
          game.save!(touch: false)
          sync_platform_releases(game, game_json)
        end

        # Generate the normalized cover master after every IGDB sync. Idempotent — the
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

        # Enqueue Voyage embedding for the freshly synced row. Async so the
        # user-facing sync POST doesn't block on Voyage HTTP. The job is
        # idempotent (re-embeds + re-writes) so a duplicate enqueue from any
        # other path (rake backfill, manual console call) is safe.
        GameVoyageIndexJob.perform_later(game.id)

        game
      rescue Game::Igdb::Client::ValidationError => e
        stamp_error(game, e.message)
        raise
      end

      private

      def assign_with_slug_collision_guard(game, attrs)
        # Platforms are OWNER-editable — the `platform` command appends to / overrides
        # them. Once a game has any platforms, an IGDB re-sync must NOT clobber the
        # owner's list (that would silently drop manual additions/overrides — owner
        # data loss). IGDB still SEEDS platforms on the INITIAL import, when the game
        # has none yet.
        attrs = attrs.except(:platforms) if game.platforms.present?

        game.assign_attributes(attrs)
        game.save!
      rescue ActiveRecord::RecordNotUnique => e
        raise unless e.message.to_s.include?("igdb_slug")
        # Slug collision. Fall back to NULL slug,
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

      # Per-platform release dates. Upsert one GamePlatformRelease per
      # recognised platform token, drop tokens no longer present, and re-derive
      # games.release_* as the EARLIEST across platforms (a lower-bound for
      # scopes/sorting; the countdown reads the per-platform rows directly).
      # Runs after game.update! so the game is persisted (association needs an id).
      def sync_platform_releases(game, game_json)
        by_token = Game::Igdb::PlatformReleaseMapper.call(game_json)

        by_token.each do |token, components|
          rel = game.platform_releases.find_or_initialize_by(platform_token: token)
          rel.assign_attributes(
            release_year:    components[:year],
            release_quarter: components[:quarter],
            release_month:   components[:month],
            release_day:     components[:day]
          )
          rel.save!
        end

        game.platform_releases.where.not(platform_token: by_token.keys).destroy_all

        earliest = game.platform_releases.reload.min_by { |r| r.release_date || Date.new(9999, 12, 31) }
        return if earliest.nil?

        # assign + save! writes (and touches updated_at) ONLY when a component
        # actually changed — an unconditional update! here re-stamped every game
        # every night even when IGDB returned identical dates (root cause:
        # introduced with the per-platform releases in 5a9a9642).
        game.assign_attributes(
          release_year:    earliest.release_year,
          release_quarter: earliest.release_quarter,
          release_month:   earliest.release_month,
          release_day:     earliest.release_day
        )
        game.save! if game.changed?
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
