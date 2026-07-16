# frozen_string_literal: true

module Pito
  # Stack — usage/resource tracking across the external API providers
  # (YouTube / IGDB) and the local Postgres store.
  #
  # Per-provider request counts come from the `api_requests` log (written by the
  # instrumentation shims at each client chokepoint); `Pito::Stack::Local`
  # reports Postgres size + record counts.
  #
  #   Pito::Stack.providers  # => { youtube: {...}, igdb: {...} }
  #   Pito::Stack.usage      # => providers + { local: {...} }
  module Stack
    module_function

    # Per-provider request usage (24h + current month).
    def providers
      {
        youtube: Youtube.to_h,
        igdb:    Igdb.to_h
      }
    end

    # Full snapshot: per-provider request usage + local Postgres footprint.
    def usage
      providers.merge(local: Local.to_h)
    end

    # Record one outbound API request. Called by the instrumentation shims at
    # each provider chokepoint. Never lets tracking break the API call.
    def track(provider, endpoint: nil, units: nil)
      ApiRequest.record!(provider: provider, endpoint: endpoint, units: units)
    rescue StandardError => e
      Rails.logger.warn("[Pito::Stack] failed to record api_request: #{e.class}: #{e.message}")
      nil
    end
  end
end
