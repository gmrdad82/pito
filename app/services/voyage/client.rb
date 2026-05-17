# Phase 34 (2026-05-18) — Voyage AI embeddings client.
#
# Single-purpose HTTP wrapper around Voyage AI's `/v1/embeddings`
# endpoint. Extracted from the inline implementation in
# `Notes::EmbedJob` so the games indexer (and any future consumer) can
# reuse one code path with a single error contract.
#
# Model + dimensions are LOCKED at `voyage-3` (1024-dim) to match the
# pgvector columns on `notes.embedding` and `games.summary_embedding`.
# Changing the model requires a migration to widen / narrow the
# columns; do that as a coordinated change, not in passing.
#
# API key resolution: `Rails.application.credentials.dig(:voyage,
# :api_key)`. The flat `voyage:` block is shared across environments
# (per `CLAUDE.md` Configuration strategy). Blank key returns nil
# from `#embed` (no HTTP call, no raise) so callers can no-op
# cleanly when credentials are not configured.
#
# Error contract: any non-2xx response, JSON parse failure, or
# network error returns nil (the per-input slot in the batch is nil).
# Caller decides what nil means — `Notes::EmbedJob` writes nothing,
# `Games::VoyageIndexer` skips the pgvector write. Errors are logged
# via `Rails.logger.warn` with the exception class + message for
# operator visibility.
#
# Test behaviour: in `Rails.env.test?` WebMock blocks all non-
# localhost HTTP. Specs that exercise the Voyage code path stub the
# endpoint explicitly (see `spec/support/voyage.rb`).
module Voyage
  class Client
    VOYAGE_URL = "https://api.voyageai.com/v1/embeddings".freeze
    DEFAULT_MODEL = "voyage-3".freeze
    EMBEDDING_DIMENSIONS = 1024

    # Returns an Array of embeddings, one per input string, preserving
    # input order. A nil slot means that input could not be embedded
    # (typically because the whole API call failed). When the API key
    # is blank or every input is blank, returns an array of nils
    # matching the input length without making an HTTP call.
    def embed(texts, model: DEFAULT_MODEL)
      list = Array(texts).map { |t| t.to_s.strip }
      return [] if list.empty?

      api_key = resolve_api_key
      return Array.new(list.length) if api_key.blank?
      return Array.new(list.length) if list.all?(&:blank?)

      response_data = post_embeddings(list, model: model, api_key: api_key)
      return Array.new(list.length) if response_data.nil?

      # Voyage returns `data: [{ embedding, index }, ...]` — preserve
      # input order by sorting on the `index` field rather than
      # relying on response order.
      ordered = Array.new(list.length)
      response_data.each do |row|
        idx = row["index"]
        next unless idx.is_a?(Integer) && idx.between?(0, list.length - 1)
        ordered[idx] = row["embedding"]
      end
      ordered
    end

    private

    def post_embeddings(inputs, model:, api_key:)
      uri = URI.parse(VOYAGE_URL)
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"]  = "application/json"
      request.body = JSON.generate(input: inputs, model: model)

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[Voyage::Client] non-2xx response: #{response.code} #{response.message}")
        return nil
      end

      JSON.parse(response.body)["data"]
    rescue StandardError => e
      Rails.logger.warn("[Voyage::Client] embed failed: #{e.class}: #{e.message}")
      nil
    end

    def resolve_api_key
      Rails.application.credentials.dig(:voyage, :api_key)
    end
  end
end
