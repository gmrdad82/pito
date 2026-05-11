# Phase 14 §1 — IGDB API v4 HTTP client.
#
# Wraps every IGDB endpoint pito uses. POST per-endpoint with an
# Apicalypse string body. Two headers per request:
#   - `Client-ID: <twitch_client_id>`
#   - `Authorization: Bearer <twitch_token>`
#
# On a 401 the cached Twitch token is invalidated and the request
# retries ONCE with a fresh token. A second 401 surfaces as
# `Igdb::Client::AuthError`. 429 raises `RateLimited` (Sidekiq
# retries the wrapping job with backoff). 4xx other than 401 raises
# `ValidationError`. 5xx raises `ServerError`.
#
# All requests pass through `Igdb::RateLimiter#acquire` so the
# process-wide 4 req/s + 8 in-flight cap is enforced.
require "net/http"
require "json"

module Igdb
  class Client
    # Phase 14 §1 — error class hierarchy. Nested under `Igdb::Client`
    # so callers can `rescue Igdb::Client::RateLimited`.
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

    # Phase 14 audit F1 — bounded HTTP timeouts so a hung IGDB endpoint
    # cannot wedge a Sidekiq worker indefinitely. Mirrors the pattern in
    # `Youtube::ServiceFactory` (open/read/send) and
    # `NotificationDeliveryChannel#configure_http` (open/read/write/ssl).
    # Values match the webhook-style 5s open / 10s read / 5s write tuning
    # the audit landed elsewhere.
    OPEN_TIMEOUT_SEC  = 5
    READ_TIMEOUT_SEC  = 10
    WRITE_TIMEOUT_SEC = 5

    # Steam = 1, GOG = 5, Epic Games Store = 26 per IGDB
    # external-game enum docs (https://api-docs.igdb.com).
    EXTERNAL_GAME_CATEGORY_STEAM = 1
    EXTERNAL_GAME_CATEGORY_GOG   = 5
    EXTERNAL_GAME_CATEGORY_EPIC  = 26

    # Phase 14 §1 polish (2026-05-10) — IGDB `Game.category` enum.
    # Values lifted from the IGDB v4 schema:
    #   0 main_game | 1 dlc_addon | 2 expansion | 3 bundle |
    #   4 standalone_expansion | 5 mod | 6 episode | 7 season |
    #   8 remake | 9 remaster | 10 expanded_game | 11 port |
    #   12 fork | 13 pack | 14 update.
    # `search_games` filters by the "main entries" subset by default
    # so duplicates like "Pragmata Deluxe Edition" or
    # "Red Dead Redemption II Ultimate Edition" don't clutter
    # results. Callers can pass `include_editions: true` to disable
    # the filter and receive every IGDB hit.
    GAME_CATEGORY_MAIN     = 0
    GAME_CATEGORY_REMAKE   = 8
    GAME_CATEGORY_REMASTER = 9
    GAME_CATEGORY_PORT     = 11
    DEFAULT_SEARCH_CATEGORIES = [
      GAME_CATEGORY_MAIN,
      GAME_CATEGORY_REMAKE,
      GAME_CATEGORY_REMASTER,
      GAME_CATEGORY_PORT
    ].freeze

    GAME_FIELDS = %w[
      id name slug summary checksum first_release_date
      rating rating_count aggregated_rating aggregated_rating_count
      total_rating total_rating_count
      cover.id cover.image_id
      genres.id genres.name genres.slug
      platforms.id platforms.name platforms.abbreviation platforms.slug
      involved_companies.id
      involved_companies.developer
      involved_companies.publisher
      involved_companies.porting
      involved_companies.supporting
      involved_companies.company.id
      involved_companies.company.name
      involved_companies.company.slug
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
        .fields("id", "name", "slug", "cover.image_id", "first_release_date", "category")
        .limit(limit)

      unless include_editions
        # Restrict to main entries + remakes / remasters / ports so
        # "Deluxe Edition" / "Ultimate Edition" / "Definitive Edition"
        # bundles, expansions, packs, etc. drop out of the result set.
        builder = builder.where("category = (#{DEFAULT_SEARCH_CATEGORIES.join(",")})")
      end

      post("games", builder.to_s)
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
        .fields("id", "name", "abbreviation", "slug")
        .where("id = (#{ids.join(",")})")
        .limit(ids.size)
        .to_s
      post("platforms", body)
    end

    # Phase 27 §1a — paginate the full `/platforms` endpoint for
    # `Platforms::SyncFromIgdb`. IGDB caps `limit` at 500 per request;
    # one full sync today is well under 250 rows so a single page is
    # the common case, but the loop is here so future expansion works.
    PLATFORMS_PAGE_SIZE = 500

    def list_all_platforms
      results = []
      offset = 0
      loop do
        body = Apicalypse.new
          .fields("id", "name", "abbreviation", "slug")
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

    # Phase 14 §2 — IGDB game-listing endpoints used by
    # `Bundle#seed_from_igdb`. Each method takes the IGDB resource id
    # and returns an array of `{ "id" => …, "name" => … }` hashes for
    # every Game IGDB associates with that resource. The caller is
    # responsible for adding any missing rows to the local Game
    # library (typically via `GameIgdbSync` per id).
    def fetch_games_for_franchise(franchise_id, limit: 500)
      raise ArgumentError, "franchise_id must be a positive integer" unless valid_igdb_id?(franchise_id)

      body = Apicalypse.new
        .fields("id", "name", "slug")
        .where("franchises = (#{franchise_id.to_i}) | franchise = #{franchise_id.to_i}")
        .limit(limit)
        .to_s
      post("games", body)
    end

    def fetch_games_for_collection(collection_id, limit: 500)
      raise ArgumentError, "collection_id must be a positive integer" unless valid_igdb_id?(collection_id)

      body = Apicalypse.new
        .fields("id", "name", "slug")
        .where("collection = #{collection_id.to_i}")
        .limit(limit)
        .to_s
      post("games", body)
    end

    def fetch_games_for_genre(genre_id, limit: 500)
      raise ArgumentError, "genre_id must be a positive integer" unless valid_igdb_id?(genre_id)

      body = Apicalypse.new
        .fields("id", "name", "slug")
        .where("genres = (#{genre_id.to_i})")
        .limit(limit)
        .to_s
      post("games", body)
    end

    private

    def valid_igdb_id?(value)
      value.is_a?(Integer) && value.positive?
    end

    def sanitize_id_list(ids)
      Array(ids).select { |x| valid_igdb_id?(x) }.map(&:to_i).uniq
    end

    def post(endpoint, body, retry_on_401: true)
      @rate_limiter.acquire do
        response = perform_request(endpoint, body)
        handle_response(response, endpoint, body, retry_on_401: retry_on_401)
      end
    end

    def perform_request(endpoint, body)
      uri = URI("#{BASE_URL}/#{endpoint}")
      creds = Igdb.credentials!
      headers = {
        "Client-ID"     => creds.client_id,
        "Authorization" => "Bearer #{@token_cache.token}",
        "Content-Type"  => "text/plain",
        "Accept"        => "application/json"
      }
      # Phase 14 audit F1 — explicit `Net::HTTP.start` block so we can
      # set bounded open / read / write timeouts. `Net::HTTP.post`
      # defaults to 60s open + 60s read, which is long enough to wedge
      # a Sidekiq worker on a hung IGDB endpoint.
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
