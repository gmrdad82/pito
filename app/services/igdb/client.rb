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

    # Steam = 1, GOG = 5, Epic Games Store = 26 per IGDB
    # external-game enum docs (https://api-docs.igdb.com).
    EXTERNAL_GAME_CATEGORY_STEAM = 1
    EXTERNAL_GAME_CATEGORY_GOG   = 5
    EXTERNAL_GAME_CATEGORY_EPIC  = 26

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

    def search_games(query, limit: 10)
      raise ArgumentError, "query must be a non-blank string" if query.to_s.strip.empty?
      raise ArgumentError, "limit must be a positive integer" unless limit.is_a?(Integer) && limit.positive?

      body = Apicalypse.new
        .search(query)
        .fields("id", "name", "slug", "cover.image_id", "first_release_date")
        .limit(limit)
        .to_s
      post("games", body)
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
      Net::HTTP.post(uri, body, headers)
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
