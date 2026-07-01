# IGDB API v4 HTTP client.
#
# Wraps every IGDB endpoint pito uses. POST per-endpoint with an
# Apicalypse string body. Two headers per request:
#   - `Client-ID: <twitch_client_id>`
#   - `Authorization: Bearer <twitch_token>`
#
# On a 401 the cached Twitch token is invalidated and the request
# retries ONCE with a fresh token. A second 401 surfaces as
# `Game::Igdb::Client::AuthError`. 429 raises `RateLimited` (Sidekiq
# retries the wrapping job with backoff). 4xx other than 401 raises
# `ValidationError`. 5xx raises `ServerError`.
#
# All requests pass through `Game::Igdb::RateLimiter#acquire` so the
# process-wide 4 req/s + 8 in-flight cap is enforced.
require "net/http"
require "json"

class Game
  module Igdb
    class Client
      # Error class hierarchy. Nested under `Game::Igdb::Client`
      # so callers can `rescue Game::Igdb::Client::RateLimited`.
      class Error < StandardError; end

      class RateLimited < Error
        attr_reader :retry_after

        def initialize(retry_after: 1, message: "IGDB rate limit hit")
          @retry_after = retry_after
          super(message)
        end
      end

      class ValidationError < Error; end
      class ServerError < Error; end
      class AuthError < Error; end
      class MissingCredentials < Error; end

      BASE_URL = "https://api.igdb.com/v4".freeze

      # Bounded HTTP timeouts so a hung IGDB endpoint cannot wedge a Sidekiq
      # worker indefinitely. Values match the webhook-style 5s open / 10s read / 5s write tuning.
      OPEN_TIMEOUT_SEC  = 5
      READ_TIMEOUT_SEC  = 10
      WRITE_TIMEOUT_SEC = 5

      # Steam = 1 per IGDB external-game enum docs
      # (https://api-docs.igdb.com). GOG (5) and Epic (26) were dropped;
      # the mapper no longer routes them onto local columns.
      EXTERNAL_GAME_CATEGORY_STEAM = 1

      # IGDB `Game.category` enum.
      # Values lifted from the IGDB v4 schema:
      #   0 main_game | 1 dlc_addon | 2 expansion | 3 bundle |
      #   4 standalone_expansion | 5 mod | 6 episode | 7 season |
      #   8 remake | 9 remaster | 10 expanded_game | 11 port |
      #   12 fork | 13 pack | 14 update.
      #
      # 2026-05-18 follow-up (per user direction) — the filter now
      # reads `game_type` instead of `category`. IGDB introduced
      # `game_type` as a successor to `category`; on the `search`
      # endpoint, `category` hydrates as null for nearly every row
      # (including bundles, DLC, packs, costumes — which is why the
      # previous 2-pass filter was forced to fall back to "keep nulls"
      # and bundles still leaked through). `game_type` is populated
      # reliably on the same search-endpoint payload, with the same
      # enum semantics — verified live for SF6 ids 191692 (main, 0),
      # 239146 (bundle, 3), 256097 (bundle, 3) and the full
      # search-endpoint result set. One pass against `game_type` now
      # drops every non-primary entry cleanly.
      #
      # The constants are kept (and renamed) for documentation /
      # future reuse. `DEFAULT_SEARCH_GAME_TYPES` is the single source
      # of truth for the "main entries only" subset.
      GAME_TYPE_MAIN_GAME      = 0
      GAME_TYPE_DLC_ADDON      = 1
      GAME_TYPE_EXPANSION      = 2
      GAME_TYPE_BUNDLE         = 3
      GAME_TYPE_REMAKE         = 8
      GAME_TYPE_REMASTER       = 9
      GAME_TYPE_EXPANDED_GAME  = 10
      GAME_TYPE_PORT           = 11
      GAME_TYPE_PACK           = 13
      # Main games, remakes/remasters, expanded games, AND combo bundles.
      # A remake (e.g. Demon's Souls 2020) is a distinct, importable title.
      # An expanded game (e.g. "Granblue Fantasy: Relink - Endless Ragnarok",
      # game_type 10) is a standalone title — the owner imports these separately.
      # Bundles (3) are admitted at the API layer so combo bundles survive
      # ("Super Mario 3D World + Bowser's Fury"); non-combo gt3 rows are
      # filtered in the post-step (see filter_search_hits).
      # DLC (1), packs (13), and ports (11) still drop at the API layer.
      #
      # IGB1 (2026-06-28): added GAME_TYPE_BUNDLE (3).
      DEFAULT_SEARCH_GAME_TYPES = [
        GAME_TYPE_MAIN_GAME, GAME_TYPE_BUNDLE, GAME_TYPE_REMAKE, GAME_TYPE_REMASTER, GAME_TYPE_EXPANDED_GAME
      ].freeze

      # Back-compat aliases for any callers / specs referencing the
      # old constant names. The values match the new `game_type` enum
      # (same semantics — IGDB documents `game_type` as the successor
      # to `category` with identical numeric assignments for the
      # values we care about).
      GAME_CATEGORY_MAIN     = GAME_TYPE_MAIN_GAME
      GAME_CATEGORY_REMAKE   = GAME_TYPE_REMAKE
      GAME_CATEGORY_REMASTER = GAME_TYPE_REMASTER
      GAME_CATEGORY_PORT     = GAME_TYPE_PORT
      DEFAULT_SEARCH_CATEGORIES = DEFAULT_SEARCH_GAME_TYPES

      GAME_FIELDS = %w[
        id name slug summary first_release_date
        rating rating_count aggregated_rating aggregated_rating_count
        total_rating total_rating_count
        cover.id cover.image_id
        genres.id genres.name genres.slug
        themes.id themes.name
        player_perspectives.id player_perspectives.name
        platforms.id platforms.name platforms.slug
        involved_companies.id
        involved_companies.developer
        involved_companies.publisher
        involved_companies.porting
        involved_companies.supporting
        involved_companies.company.id
        involved_companies.company.name
        involved_companies.company.slug
        alternative_names.id
        alternative_names.name
        release_dates.category release_dates.y release_dates.m release_dates.d release_dates.date
        release_dates.platform.id release_dates.platform.name
      ].freeze

      def initialize(token_cache: TokenCache.new, rate_limiter: RateLimiter.shared, http: Net::HTTP)
        @token_cache = token_cache
        @rate_limiter = rate_limiter
        @http = http
      end

      def search_games(query, limit: 10, include_editions: false)
        raise ArgumentError, "query must be a non-blank string" if query.to_s.strip.empty?
        raise ArgumentError, "limit must be a positive integer" unless limit.is_a?(Integer) && limit.positive?

        builder = Apicalypse.new
          .search(query)
          .fields("id", "name", "slug", "cover.image_id", "first_release_date", "game_type", "version_parent")
          .limit(limit)

        unless include_editions
          # 2026-05-18 — single-pass `game_type` filter. IGDB's search
          # endpoint hydrates `game_type` reliably for every row
          # (unlike `category`, which is null for almost every search
          # hit). `game_type = (0,8,9,10)` keeps main games + remakes +
          # remasters + expanded games (all distinct importable titles
          # the user may want); bundles (3), DLC (1), packs (13),
          # costumes / pack subtypes, ports (11), etc. drop out at the
          # API layer. No second pass needed.
          #
          # 2026-06-28 — added expanded_game (10): standalone titles
          # such as "Granblue Fantasy: Relink - Endless Ragnarok" carry
          # game_type 10 and are legitimate import targets. Packs (13)
          # are excluded. Bundles (3) pass the API filter so combo bundles
          # ("X + Y") survive; non-combo gt3 rows drop in filter_search_hits.
          #
          # Null-tolerant just in case IGDB ever ships a freshly
          # indexed row before `game_type` is populated.
          #
          # 2026-06-07 — also filter `version_parent = null`.
          # IGDB populates `version_parent` on "edition" entries
          # (e.g. "Red Dead Redemption 2: Special Edition") pointing to
          # the parent game id. Filtering it null excludes these edition
          # variants even when they are mis-tagged as game_type = 0.
          builder = builder
            .where("game_type = (#{DEFAULT_SEARCH_GAME_TYPES.join(",")}) | game_type = null")
            .where("version_parent = null")
        end

        hits = post("games", builder.to_s)
        return hits if include_editions || hits.empty?

        # 2026-05-19 — drop cover-less rows from omnisearch results. A
        # row without `cover.image_id` renders as a `[?]` placeholder in
        # the `[+]` add-from-IGDB modal and is almost always noise (IGDB
        # stubs, regional duplicates, draft entries). Filter at the
        # client boundary so every caller (GamesController#search,
        # Game::SearchService, Search::Everywhere) gets the same clean
        # payload. `include_editions: true` callers bypass this — same
        # discipline as `denoise_by_name`.
        filter_search_hits(hits, query)
      end

      def fetch_game(igdb_id)
        raise ArgumentError, "igdb_id must be a positive integer" unless valid_igdb_id?(igdb_id)

        body = Apicalypse.new
          .fields(*GAME_FIELDS)
          .where("id = #{igdb_id.to_i}")
          .limit(1)
          .to_s
        post("games", body)
      end

      def fetch_time_to_beat(igdb_id)
        raise ArgumentError, "igdb_id must be a positive integer" unless valid_igdb_id?(igdb_id)

        body = Apicalypse.new
          .fields("id", "game_id", "hastily", "normally", "completely")
          .where("game_id = #{igdb_id.to_i}")
          .limit(1)
          .to_s
        post("game_time_to_beats", body)
      end

      def fetch_external_games(igdb_id)
        raise ArgumentError, "igdb_id must be a positive integer" unless valid_igdb_id?(igdb_id)

        body = Apicalypse.new
          .fields("id", "category", "uid", "url", "game")
          .where("game = #{igdb_id.to_i}")
          .limit(50)
          .to_s
        post("external_games", body)
      end

      def fetch_genres(igdb_ids)
        ids = sanitize_id_list(igdb_ids)
        return [] if ids.empty?

        body = Apicalypse.new
          .fields("id", "name", "slug")
          .where("id = (#{ids.join(",")})")
          .limit(ids.size)
          .to_s
        post("genres", body)
      end

      def fetch_platforms(igdb_ids)
        ids = sanitize_id_list(igdb_ids)
        return [] if ids.empty?

        body = Apicalypse.new
          .fields("id", "name", "slug")
          .where("id = (#{ids.join(",")})")
          .limit(ids.size)
          .to_s
        post("platforms", body)
      end

      # Paginate the full `/platforms` endpoint for
      # `Platforms::SyncFromIgdb`. IGDB caps `limit` at 500 per request;
      # one full sync today is well under 250 rows so a single page is
      # the common case, but the loop is here so future expansion works.
      PLATFORMS_PAGE_SIZE = 500

      def list_all_platforms
        results = []
        offset = 0
        loop do
          body = Apicalypse.new
            .fields("id", "name", "slug")
            .limit(PLATFORMS_PAGE_SIZE)
            .offset(offset)
            .to_s
          page = post("platforms", body)
          break if page.blank?
          results.concat(page)
          break if page.size < PLATFORMS_PAGE_SIZE
          offset += PLATFORMS_PAGE_SIZE
        end
        results
      end

      def fetch_companies(igdb_ids)
        ids = sanitize_id_list(igdb_ids)
        return [] if ids.empty?

        body = Apicalypse.new
          .fields("id", "name", "slug")
          .where("id = (#{ids.join(",")})")
          .limit(ids.size)
          .to_s
        post("companies", body)
      end

      # The IGDB
      # game-listing endpoints (`fetch_games_for_franchise`,
      # `fetch_games_for_collection`, `fetch_games_for_genre`) powered the
      # `Bundle#seed_from_igdb` flow. The flow + the columns it depended
      # on were removed in the 2026-05-17 Bundle simplification; the
      # fetchers are gone with it.

      private

      # 2026-05-18 — secondary safety net on top of the IGDB `game_type`
      # filter. Drops any non-top-result row whose name starts with the
      # top result's name + ":". Catches edition / pack / DLC noise that
      # IGDB occasionally mis-tags as `game_type = 0` (or that slips
      # through with a null `game_type`).
      #
      # Example — search "street fighter 6":
      #   top hit:           "Street Fighter 6"
      #   drop:              "Street Fighter 6: Mad Gear Box"
      #   drop:              "Street Fighter 6: Year 2 Character Pass"
      #   keep:              "Street Fighter VI 12 Peoples"  (different prefix)
      #
      # Explicit edition searches (e.g. "street fighter 6: collector's
      # edition") naturally bypass this: the top hit IS the edition, so
      # the prefix doesn't match anything below it.
      # 2026-05-19 — drop rows lacking a cover image. IGDB occasionally
      # returns entries with no `cover` association (stubs, drafts) or
      # with a `cover` hash whose `image_id` is blank. Both render as
      # `[?]` placeholders in the omnisearch row and are filtered out
      # here before they reach any UI surface.
      def reject_coverless(rows)
        rows.reject { |row| row.dig("cover", "image_id").to_s.strip.empty? }
      end

      def denoise_by_name(rows)
        return rows if rows.size <= 1
        top = rows.first
        top_name = top["name"].to_s
        return rows if top_name.empty?
        prefix = "#{top_name}:"
        rows.reject { |row| !row.equal?(top) && row["name"].to_s.start_with?(prefix) }
      end

      # Edition / DLC / bundle name markers. IGDB's SEARCH endpoint does not
      # reliably hydrate `game_type` / `version_parent` for these rows, so the
      # API-side filter misses them — this is the name-level safety net.
      # Catches "Elden Ring: Collector's Edition", "… Deluxe Edition",
      # "… Premium Bundle", "… Season Pass", etc. Keeps the base game + distinct
      # titles ("Elden Ring", "Elden Ring Nightreign", "Elden Ring GB").
      EDITION_NOISE = /\b(edition|deluxe|premium|collector'?s|complete|definitive|goty|game of the year|season pass|bundle|pack|anniversary|upgrade)\b/i

      # IGB1 (2026-06-28): A "combo" bundle joins two distinct titles with a
      # space-plus-space separator, e.g. "Super Mario 3D World + Bowser's Fury"
      # or "Super Mario Galaxy + Super Mario Galaxy 2". Non-combo gt3 rows
      # (Deluxe/Collector editions mis-tagged as bundles, season passes, packs)
      # do not carry this pattern and are dropped by filter_search_hits.
      COMBO_NAME = / \+ /

      # Bundle-name ALLOWLIST (owner 2026-07-01): keep bundle (gt3) rows whose
      # name is a legit standalone release the owner wants — GOTY / Game of the
      # Year / Anniversary editions (e.g. "Rayman: 30th Anniversary Edition") —
      # in addition to combo bundles. Case-insensitive (goty/GOTY/GoTY, etc.).
      BUNDLE_KEEP_NAME = /\b(goty|game of the year|anniversary)\b/i

      # Drop edition/DLC/bundle rows by name. Skipped when the user's query
      # itself names an edition term (an explicit edition search should return
      # the editions). Called only for gt0/8/9/null rows by filter_search_hits.
      def reject_editions(rows, query)
        return rows if query.to_s.match?(EDITION_NOISE)
        rows.reject { |row| row["name"].to_s.match?(EDITION_NOISE) }
      end

      # IGB1 (2026-06-28) — unified per-row post-fetch filter.
      #
      # Rule 1: Drop cover-less rows for every game type.
      # Rule 2: game_type 10 (expanded_game) — always keep. These are
      #   standalone titles even when the name contains "Edition" or a colon
      #   prefix (e.g. "Kirby and the Forgotten Land: Nintendo Switch 2
      #   Edition + Star-Crossed World"). Name filters must not touch them.
      # Rule 3: game_type 3 (bundle) — keep combo bundles whose name contains
      #   " + " (e.g. "Super Mario 3D World + Bowser's Fury") OR bundles on the
      #   BUNDLE_KEEP_NAME allowlist (GOTY / Game of the Year / Anniversary
      #   editions the owner imports as standalone titles). Other non-combo gt3
      #   rows (Deluxe/Collector editions, packs, season passes) are dropped here
      #   regardless of EDITION_NOISE.
      # Rule 4: all other types (gt0/8/9/null) — apply the existing colon-
      #   prefix denoise + EDITION_NOISE name safety net (query bypass intact).
      #
      # Limit note: default limit is 10. Combo bundles from IGDB are typically
      # ranked high enough by relevance that they land within 10 results when
      # searched directly. Callers can raise the limit if needed.
      def filter_search_hits(hits, query)
        hits = reject_coverless(hits)
        return hits if hits.empty?

        top      = hits.first
        top_name = top["name"].to_s
        query_is_edition = query.to_s.match?(EDITION_NOISE)

        hits.select do |row|
          case row["game_type"]
          when GAME_TYPE_EXPANDED_GAME
            true
          when GAME_TYPE_BUNDLE
            name = row["name"].to_s
            name.match?(COMBO_NAME) || name.match?(BUNDLE_KEEP_NAME)
          else
            colon_noise   = !row.equal?(top) && !top_name.empty? && row["name"].to_s.start_with?("#{top_name}:")
            edition_noise = !query_is_edition && row["name"].to_s.match?(EDITION_NOISE)
            !colon_noise && !edition_noise
          end
        end
      end

      def valid_igdb_id?(value)
        value.is_a?(Integer) && value.positive?
      end

      def sanitize_id_list(ids)
        Array(ids).select { |x| valid_igdb_id?(x) }.map(&:to_i).uniq
      end

      def post(endpoint, body, retry_on_401: true)
        @rate_limiter.acquire do
          Pito::Stack.track("igdb", endpoint: endpoint)
          response = perform_request(endpoint, body)
          handle_response(response, endpoint, body, retry_on_401: retry_on_401)
        end
      end

      def perform_request(endpoint, body)
        uri = URI("#{BASE_URL}/#{endpoint}")
        creds = Igdb.credentials!
        headers = {
          "Client-ID"     => creds[:client_id],
          "Authorization" => "Bearer #{@token_cache.token}",
          "Content-Type"  => "text/plain",
          "Accept"        => "application/json"
        }
        # Explicit `Net::HTTP.start` block so we can set bounded open / read /
        # write timeouts. `Net::HTTP.post` defaults to 60s open + 60s read,
        # which is long enough to wedge a Sidekiq worker on a hung IGDB
        # endpoint.
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.open_timeout  = OPEN_TIMEOUT_SEC
          http.read_timeout  = READ_TIMEOUT_SEC
          http.write_timeout = WRITE_TIMEOUT_SEC
          request = Net::HTTP::Post.new(uri.request_uri, headers)
          request.body = body
          http.request(request)
        end
      end

      def handle_response(response, endpoint, body, retry_on_401:)
        code = response.code.to_i

        case code
        when 200
          parse_json(response.body)
        when 401
          if retry_on_401
            @token_cache.invalidate!
            retry_response = perform_request(endpoint, body)
            handle_response(retry_response, endpoint, body, retry_on_401: false)
          else
            raise AuthError, "IGDB returned 401 after token refresh"
          end
        when 404
          []
        when 429
          retry_after = (response["Retry-After"] || response["retry-after"]).to_i
          retry_after = 1 if retry_after.zero?
          raise RateLimited.new(retry_after: retry_after)
        when 400..499
          raise ValidationError, "IGDB returned #{code}: #{response.body}"
        when 500..599
          raise ServerError, "IGDB returned #{code}"
        else
          raise Error, "Unexpected IGDB response: #{code}"
        end
      end

      def parse_json(body)
        return [] if body.nil? || body.strip.empty?
        JSON.parse(body)
      rescue JSON::ParserError => e
        raise Error, "IGDB returned malformed JSON: #{e.message}"
      end
    end
  end
end
