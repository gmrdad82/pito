# Phase 14 §1 — IGDB Twitch OAuth token cache.
#
# Acquires the client-credentials token from
#   POST https://id.twitch.tv/oauth2/token
# and caches it in `Rails.cache` under `igdb:twitch_token`. TTL is
# `expires_in - 60s` so the cached token never serves a request that
# would 401 mid-flight.
#
# `#token` is the public read; `#invalidate!` clears the cache entry
# (called by `Igdb::Client` on a 401, which retries the request once).
require "net/http"
require "json"

module Igdb
  class TokenCache
    TWITCH_TOKEN_URL = "https://id.twitch.tv/oauth2/token".freeze
    CACHE_KEY        = "igdb:twitch_token".freeze
    TTL_SAFETY_MARGIN_SECONDS = 60

    def initialize(cache: Rails.cache)
      @cache = cache
    end

    def token
      cached = @cache.read(CACHE_KEY)
      return cached if cached.present?

      fetch_and_cache!
    end

    def invalidate!
      @cache.delete(CACHE_KEY)
    end

    private

    def fetch_and_cache!
      creds = Igdb.credentials!
      uri = URI(TWITCH_TOKEN_URL)
      uri.query = URI.encode_www_form(
        client_id: creds.client_id,
        client_secret: creds.client_secret,
        grant_type: "client_credentials"
      )

      response = Net::HTTP.post(uri, "")
      handle(response)
    end

    def handle(response)
      code = response.code.to_i
      raise Igdb::Client::AuthError, "Twitch token endpoint returned #{code}: #{response.body}" unless code == 200

      payload = parse_json(response.body)
      access_token = payload["access_token"]
      expires_in   = payload["expires_in"].to_i

      raise Igdb::Client::AuthError, "Twitch returned no access_token" if access_token.blank?

      ttl = [ expires_in - TTL_SAFETY_MARGIN_SECONDS, 60 ].max
      @cache.write(CACHE_KEY, access_token, expires_in: ttl)
      access_token
    end

    def parse_json(body)
      JSON.parse(body)
    rescue JSON::ParserError => e
      raise Igdb::Client::AuthError, "Twitch returned malformed JSON: #{e.message}"
    end
  end
end
