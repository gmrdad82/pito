# frozen_string_literal: true

# Model picker's list of available models for one AI provider.
#
# Live path: GET `{base_url}{models_endpoint}` (OpenAI list shape —
# `{"object": "list", "data": [{"id": "..."}, ...]}`), sending the
# provider's configured API key per its `auth` style when one is set
# (`AppSetting.get("#{provider}_api_key")`), or no auth header at all when
# it's blank (e.g. OpenCode Zen's models listing is unauthenticated).
#
# A successful, non-empty live fetch is cached for a day under
# `pito:ai:models:#{provider}`. Any HTTP/parse/network failure, or an
# empty list, falls back to the provider's `pinned_models`
# (config/pito/ai_providers.yml) UNCACHED — so the very next call
# retries live instead of getting stuck on a transient outage — logging
# one `Rails.logger.warn` for the failure.
#
# Provider wiring (base_url, auth, models_endpoint, pinned_models) comes
# from `Ai::ProviderRegistry.provider(name)`, which raises `KeyError` for
# an unknown provider — that propagates as-is, it's a caller bug.
module Ai
  class ModelCatalog
    CACHE_TTL    = 1.day
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15

    # @param provider [String, Symbol] provider key from ai_providers.yml.
    # @param live [Boolean] when false, skip the HTTP fetch entirely and serve
    #   the cached list or the pinned fallback — the multi-provider picker uses
    #   this for keyless providers so opening the dialog never stacks up nine
    #   doomed requests.
    # @return [Array<Hash>] `{ id:, pinned: }` rows, in source order.
    def self.models(provider:, live: true)
      new(provider: provider).models(live: live)
    end

    # Manual refresh — drops the cached live result so the next `models`
    # call re-fetches instead of serving a day-old list.
    def self.bust!(provider:)
      Rails.cache.delete(cache_key(provider))
    end

    def self.cache_key(provider)
      "pito:ai:models:#{provider}"
    end

    def initialize(provider:)
      @provider = provider
      @config = Ai::ProviderRegistry.provider(provider)
    end

    def models(live: true)
      cached =
        if live
          Rails.cache.fetch(self.class.cache_key(@provider), expires_in: CACHE_TTL, skip_nil: true) do
            fetch_live
          end
        else
          Rails.cache.read(self.class.cache_key(@provider))
        end

      return cached if cached.present?

      pinned_fallback
    end

    private

    def fetch_live
      uri = URI.parse("#{@config[:base_url]}#{@config[:models_endpoint]}")
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      apply_auth(request)

      response = Net::HTTP.start(uri.hostname, uri.port,
                                  use_ssl: uri.scheme == "https",
                                  open_timeout: OPEN_TIMEOUT,
                                  read_timeout: READ_TIMEOUT) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[Ai::ModelCatalog] provider=#{@provider} non-2xx response: #{response.code} #{response.message}")
        return nil
      end

      rows = parse_rows(response.body)
      if rows.empty?
        Rails.logger.warn("[Ai::ModelCatalog] provider=#{@provider} empty models list")
        return nil
      end

      rows
    rescue StandardError => e
      Rails.logger.warn("[Ai::ModelCatalog] provider=#{@provider} #{e.class}: #{e.message}")
      nil
    end

    def apply_auth(request)
      api_key = AppSetting.get("#{@provider}_api_key")
      return if api_key.blank?

      case @config[:auth].to_s
      when "bearer"
        request["Authorization"] = "Bearer #{api_key}"
      when "x_api_key"
        request["x-api-key"] = api_key
      end
    end

    def parse_rows(body)
      parsed = JSON.parse(body)
      Array(parsed["data"]).filter_map do |row|
        id = row["id"] if row.is_a?(Hash)
        { id: id, pinned: false } if id.present?
      end
    end

    def pinned_fallback
      Array(@config[:pinned_models]).map { |id| { id: id, pinned: true } }
    end
  end
end
