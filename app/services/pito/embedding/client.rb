# frozen_string_literal: true

# Local embeddings client (3.0.0) — replaces Voyage AI.
#
# Single-purpose HTTP wrapper around the llama.cpp embedder sidecar's
# OpenAI-compatible `/v1/embeddings` endpoint (see the `embedder` service
# in docker-compose.yml / docker-compose.dev.yml). The sidecar serves
# embeddinggemma-300m; no API key, no auth — it is a private
# compose-network / localhost service, never the public internet.
#
# Model + dimensions are LOCKED at embeddinggemma-300m (768-dim) to match
# the pgvector columns. Changing the model requires a coordinated
# re-embed + column migration; do not change it in passing.
#
# Configuration: `ENV["PITO_EMBEDDER_URL"]` (http://embedder:8081 in the
# production stack, http://127.0.0.1:8091 for host-Puma dev). A blank or
# absent URL means "not configured" and mirrors the old keyless-Voyage
# behavior exactly (K2 data honesty): the forgiving path no-ops to nils
# with no HTTP call, the strict path raises — features degrade, nothing
# crashes, nothing bad persists.
#
# Two contracts, mirroring the Voyage client the callers grew up on:
#   * `#embed`       — forgiving; nil slots on any failure, never raises.
#   * `#embed_batch` — strict; raises Error naming the real cause so jobs
#                      record a visible failure (and retry) instead of a
#                      silent zero.
#
# Test behaviour: WebMock blocks non-localhost HTTP in test; specs stub
# the endpoint explicitly.
module Pito
  module Embedding
    class Client
      class Error < StandardError; end

      # llama.cpp accepts large batches, but callers already chunk at the
      # Voyage-era size and the sidecar is CPU-bound — keep the contract.
      MAX_BATCH_SIZE = 128

      # embeddinggemma-300m output width; callers and migrations key off this.
      DIMENSIONS = 768

      # Forgiving contract. Returns an Array of embeddings, one per input,
      # preserving input order via the response `index` field. A nil slot
      # means that input could not be embedded. Unconfigured URL or
      # all-blank inputs → an array of nils without an HTTP call.
      def embed(texts)
        list = Array(texts).map { |t| t.to_s.strip }
        return [] if list.empty?
        return Array.new(list.length) if base_url.blank?
        return Array.new(list.length) if list.all?(&:blank?)

        response_data = post_embeddings(list)
        return Array.new(list.length) if response_data.nil?

        ordered = Array.new(list.length)
        response_data.each do |row|
          idx = row["index"]
          next unless idx.is_a?(Integer) && idx.between?(0, list.length - 1)
          ordered[idx] = row["embedding"]
        end
        ordered
      end

      # Strict contract for bulk/reindex jobs and any caller that needs a
      # visible failure. Raises Error on: unconfigured URL, non-2xx, a
      # malformed response, or any missing embedding slot. Raises
      # ArgumentError above MAX_BATCH_SIZE (chunking is the caller's job).
      # Returns embeddings in INPUT order.
      def embed_batch(inputs:)
        list = Array(inputs).map(&:to_s)
        return [] if list.empty?

        if list.size > MAX_BATCH_SIZE
          raise ArgumentError, "embed batch limit is #{MAX_BATCH_SIZE} inputs per request (got #{list.size}); chunk before calling."
        end
        raise Error, "embedder not configured (set PITO_EMBEDDER_URL — see docker-compose.yml `embedder`)" if base_url.blank?

        response_data = post_embeddings_strict(list)

        ordered = Array.new(list.length)
        response_data.each do |row|
          idx = row["index"]
          raise Error, "embedder response row missing 'index' field: #{row.inspect[0, 200]}" unless idx.is_a?(Integer) && idx.between?(0, list.length - 1)
          ordered[idx] = row["embedding"]
        end

        missing = ordered.each_with_index.select { |v, _| v.nil? }.map(&:last)
        raise Error, "embedder response missing embeddings for input indices #{missing.inspect}" if missing.any?

        ordered
      end

      private

      # Strict transport — raises on any failure rather than rescuing to
      # nil. Returns the parsed `data` array on success.
      def post_embeddings_strict(inputs)
        response = perform_request(inputs)

        unless response.is_a?(Net::HTTPSuccess)
          raise Error, "embedder non-2xx response: #{response.code} #{response.message} — body: #{response.body.to_s[0, 500]}"
        end

        parsed = JSON.parse(response.body)
        data = parsed["data"]
        raise Error, "embedder response missing 'data' array: #{parsed.inspect[0, 500]}" unless data.is_a?(Array)
        data
      rescue Error
        raise
      rescue StandardError => e
        # Strict path (K2 distinction — see #post_embeddings for the
        # forgiving counterpart): a bulk/reindex caller wants a visible,
        # retryable failure, so this incident IS worth an AppSignal report.
        # Report the ORIGINAL exception `e` (not the `Error` wrapper below)
        # so the incident carries the real cause — class + backtrace —
        # exactly like AchievementsRefreshJob forwards a rescued exception
        # before continuing. `Appsignal.report_error` is a no-op when
        # AppSignal is inactive (no push key / non-production).
        Appsignal.report_error(e)
        raise Error, "embedder request failed: #{e.class}: #{e.message}"
      end

      # Forgiving transport — any failure logs a warn (operator visibility
      # in docker logs) and returns nil; the caller's nil-slot semantics
      # take over. Never raises (K2: a sidecar hiccup degrades features,
      # never breaks the caller).
      #
      # K2 distinction from #post_embeddings_strict: a nil here is DESIGNED
      # degradation (chat search/link-suggestion features quietly do
      # without a vector), not an incident — so this path deliberately does
      # NOT call Appsignal.report_error. Reporting every cold-path miss
      # would page/alert on expected behavior and spam AppSignal; the warn
      # log is the right amount of visibility for a forgiving path.
      def post_embeddings(inputs)
        response = perform_request(inputs)

        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.warn("[Pito::Embedding::Client] non-2xx response: #{response.code} #{response.message}")
          return nil
        end

        JSON.parse(response.body)["data"]
      rescue StandardError => e
        Rails.logger.warn("[Pito::Embedding::Client] embed failed: #{e.class}: #{e.message}")
        nil
      end

      def perform_request(inputs)
        uri = URI.parse("#{base_url.chomp('/')}/v1/embeddings")
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(input: inputs)

        Pito::Stack.track("embedding", endpoint: "embeddings", units: Array(inputs).size)
        Net::HTTP.start(uri.hostname, uri.port,
                        use_ssl: uri.scheme == "https",
                        open_timeout: 5, read_timeout: 60) do |http|
          http.request(request)
        end
      end

      def base_url
        ENV["PITO_EMBEDDER_URL"]
      end
    end
  end
end
