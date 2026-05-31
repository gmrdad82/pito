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
# API key resolution: `ENV["PITO_VOYAGE_API_KEY"]`. Blank key
# returns nil from `#embed` (no HTTP call, no raise) so callers can
# no-op cleanly when the key is not configured.
#
# Error contract: any non-2xx response, JSON parse failure, or
# network error returns nil (the per-input slot in the batch is nil).
# Caller decides what nil means — `Notes::EmbedJob` writes nothing,
# `Game::VoyageIndexer` skips the pgvector write. Errors are logged
# via `Rails.logger.warn` with the exception class + message for
# operator visibility.
#
# Test behaviour: in `Rails.env.test?` WebMock blocks all non-
# localhost HTTP. Specs that exercise the Voyage code path stub the
# endpoint explicitly (see `spec/support/voyage.rb`).
module Voyage
  class Client
    # 2026-05-18 follow-up — strict batch path used by `BulkVoyageIndexJob`
    # raises `Voyage::Client::Error` on non-2xx / network failure rather
    # than swallowing to nil like `#embed`. The bulk reindex caller wants
    # visible failures + Sidekiq retries; the single-record path keeps
    # the forgiving contract so per-row sync hooks don't crash on
    # transient Voyage hiccups.
    class Error < StandardError; end

    # Voyage's `/v1/embeddings` accepts up to 128 input strings per
    # request. Callers (BulkVoyageIndexJob) chunk above that.
    MAX_BATCH_SIZE = 128

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

    # Strict batch variant for `BulkVoyageIndexJob` and any caller that
    # needs guaranteed-ordered embeddings or a visible failure on a
    # non-2xx Voyage response. Differs from `#embed` in three ways:
    #
    #   1. Raises `Voyage::Client::Error` on non-2xx / network failure
    #      / JSON parse failure rather than silently returning nil
    #      slots. The bulk reindex caller wants Sidekiq to record a
    #      visible failure (and retry) when the Voyage call breaks.
    #   2. Raises `ArgumentError` when `inputs.size > MAX_BATCH_SIZE`
    #      (128). Chunking is the caller's responsibility — the bulk
    #      job slices in groups of 128.
    #   3. Raises `Voyage::Client::Error` when the API key is missing
    #      or blank, rather than no-op'ing. The bulk reindex requires
    #      Voyage to be configured; a silent skip would leave the
    #      `/settings` Voyage stats row stuck at zero with no signal.
    #
    # Returns an Array of embeddings in INPUT order. Voyage's response
    # carries an `index` field per row that maps the embedding back to
    # its input slot; we sort by that field so a reordered response
    # still produces correctly-aligned output.
    def embed_batch(inputs:, model: DEFAULT_MODEL)
      list = Array(inputs).map { |t| t.to_s }
      return [] if list.empty?

      if list.size > MAX_BATCH_SIZE
        raise ArgumentError, "Voyage embed batch limit is #{MAX_BATCH_SIZE} inputs per request (got #{list.size}); chunk before calling."
      end

      api_key = resolve_api_key
      raise Error, "Voyage API key not configured (ENV[\"PITO_VOYAGE_API_KEY\"])" if api_key.blank?

      response_data = post_embeddings_strict(list, model: model, api_key: api_key)

      ordered = Array.new(list.length)
      response_data.each do |row|
        idx = row["index"]
        raise Error, "Voyage response row missing 'index' field: #{row.inspect}" unless idx.is_a?(Integer) && idx.between?(0, list.length - 1)
        ordered[idx] = row["embedding"]
      end

      missing = ordered.each_with_index.select { |v, _| v.nil? }.map(&:last)
      raise Error, "Voyage response missing embeddings for input indices #{missing.inspect}" if missing.any?

      ordered
    end

    private

    # Strict variant — raises on any failure rather than rescuing to
    # nil. Returns the parsed `data` array on success.
    def post_embeddings_strict(inputs, model:, api_key:)
      uri = URI.parse(VOYAGE_URL)
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"]  = "application/json"
      request.body = JSON.generate(input: inputs, model: model)

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Voyage non-2xx response: #{response.code} #{response.message} — body: #{response.body.to_s[0, 500]}"
      end

      parsed = JSON.parse(response.body)
      data = parsed["data"]
      raise Error, "Voyage response missing 'data' array: #{parsed.inspect[0, 500]}" unless data.is_a?(Array)
      data
    rescue Error
      raise
    rescue StandardError => e
      raise Error, "Voyage embed_batch failed: #{e.class}: #{e.message}"
    end

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
      ENV["PITO_VOYAGE_API_KEY"].presence
    end
  end
end
