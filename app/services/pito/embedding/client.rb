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
# Chunk-and-pool: the llama.cpp physical batch caps at 512 tokens, so any
# single input over ~500 tokens 500s ("input is too large to process").
# To embed arbitrarily long inputs we split each one into context-sized
# chunks (#chunk_text), embed every chunk (HTTP-sub-batched at
# MAX_BATCH_SIZE), then mean-pool an input's chunk vectors back into ONE
# 768-dim vector (#pool). Short inputs are one chunk and pass through
# byte-identically to the pre-chunking behavior.
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

      # Upper bound on chunks sent per HTTP request. llama.cpp accepts
      # large batches but the sidecar is CPU-bound — one input may produce
      # more than this many chunks, so #embed / #embed_batch sub-batch the
      # flattened chunk list at this size (they never raise on chunk count).
      MAX_BATCH_SIZE = 128

      # embeddinggemma-300m output width; callers and migrations key off this.
      DIMENSIONS = 768

      # Per-chunk character budget (~300 English tokens). The embedder's
      # llama.cpp physical batch is 512 tokens; anything past ~500 tokens
      # returns HTTP 500 ("increase the physical batch size"). 1200 chars
      # stays safely under 512 even for token-dense text, so no single
      # chunk can trip the batch limit.
      MAX_CHARS_PER_CHUNK = 1200

      # EmbeddingGemma task prompt (3.0.1 full adoption). The model was
      # TRAINED with task-prefixed inputs; raw text is out-of-distribution.
      # This is the documented symmetric sentence-similarity prompt, applied
      # to EVERY input on the wire (per chunk, inside #perform_request) so
      # all PITO vectors live in ONE prompt space — which keeps cross-entity
      # comparisons (video↔game link suggestions) coherent. A measured A/B,
      # 2026-07-16, on the NL-router surface: auto-run hits 6/21→8/21, reject
      # ceiling .846→.806, no safety regressions. Callers never see the
      # prefix: they pass raw text and
      # digest raw text. CHANGING OR REMOVING THIS INVALIDATES EVERY STORED
      # VECTOR — it requires a coordinated FORCE re-embed of games, videos,
      # events, and nl_examples, plus threshold recalibration.
      PROMPT_PREFIX = "task: sentence similarity | query: "

      # Chunks are split to this budget so that chunk + PROMPT_PREFIX still
      # fits the MAX_CHARS_PER_CHUNK safety envelope after the wire-level
      # prefix is prepended.
      CHUNK_BUDGET = MAX_CHARS_PER_CHUNK - PROMPT_PREFIX.length

      # The single canonical seam identifying which VECTOR SPACE a stored
      # embedding lives in (3.0.1 correctness fix). Every `embedded_digest`
      # gate in the codebase (Game::EmbeddingIndexer, Video::EmbeddingIndexer,
      # Pito::Embedding::EventIndexer, Pito::Nl::Router's nl_examples corpus)
      # MUST hash `VECTOR_SPACE + text`, never bare text — digesting text
      # alone only detects a SOURCE TEXT change, but the stored vector also
      # depends on PROMPT_PREFIX baked into every wire request above. A text-
      # only digest left every 3.0.0 row's digest matching post-3.0.1 (text
      # unchanged) while its vector was still raw-space — a silent, permanent
      # mismatch against prefixed queries, with no error anywhere.
      #
      # CHANGING OR REMOVING THE WIRE-LEVEL PROMPT CHANGES THIS CONSTANT,
      # WHICH INVALIDATES EVERY STORED DIGEST AND TRIGGERS A CLEAN RE-EMBED
      # EVERYWHERE: every digest-gated row instantly looks "changed" to its
      # gate (old digest was salted with the old space), so the very next
      # plain reindex sweep — or simply the next nightly job — re-embeds
      # games, videos, conversation events, and the nl_examples corpus with
      # zero manual FORCE=1 steps. Any FUTURE prompt change self-heals the
      # same way, automatically, forever.
      VECTOR_SPACE = PROMPT_PREFIX

      # Forgiving contract. Returns an Array of embeddings, one per input,
      # in input order. A nil slot means that input could not be embedded.
      # Unconfigured URL or all-blank inputs → an array of nils without an
      # HTTP call. Long inputs are chunked; an input's surviving chunk
      # vectors are pooled — if some chunks fail the survivors still pool,
      # if all fail the slot is nil. Never raises.
      def embed(texts)
        list = Array(texts).map { |t| t.to_s.strip }
        return [] if list.empty?
        return Array.new(list.length) if base_url.blank?
        return Array.new(list.length) if list.all?(&:blank?)

        # Blank inputs get no chunks (nil slot); the rest split into
        # context-sized chunks, kept grouped per input.
        chunks_per_input = list.map { |text| text.blank? ? [] : chunk_text(text) }
        chunk_vectors = forgiving_chunk_vectors(chunks_per_input.flatten)

        cursor = 0
        chunks_per_input.map do |chunks|
          slice = chunk_vectors[cursor, chunks.length] || []
          cursor += chunks.length
          survivors = slice.compact
          survivors.empty? ? nil : pool(survivors)
        end
      end

      # Strict contract for bulk/reindex jobs and any caller that needs a
      # visible failure. Raises Error on: unconfigured URL, non-2xx, a
      # malformed response, or any missing embedding slot. Raises
      # ArgumentError above MAX_BATCH_SIZE INPUTS (long inputs are chunked
      # and sub-batched internally — the guard bounds inputs per call, not
      # chunks). Returns one pooled embedding per input in INPUT order.
      def embed_batch(inputs:)
        list = Array(inputs).map { |t| t.to_s.strip }
        return [] if list.empty?

        if list.size > MAX_BATCH_SIZE
          raise ArgumentError, "embed batch limit is #{MAX_BATCH_SIZE} inputs per request (got #{list.size}); chunk before calling."
        end
        raise Error, "embedder not configured (set PITO_EMBEDDER_URL — see docker-compose.yml `embedder`)" if base_url.blank?

        chunks_per_input = list.map { |text| chunk_text(text) }
        chunk_vectors = strict_chunk_vectors(chunks_per_input.flatten)

        cursor = 0
        chunks_per_input.each_with_index.map do |chunks, input_index|
          slice = chunk_vectors[cursor, chunks.length] || []
          cursor += chunks.length
          if slice.length != chunks.length || slice.any?(&:nil?)
            raise Error, "embedder response missing embeddings for input index #{input_index}"
          end
          pool(slice)
        end
      end

      # Cheap forgiving reachability probe for the settings surface (P8,
      # 3.0.1) — a plain GET of the sidecar's own `/health` endpoint (every
      # llama.cpp server build exposes one), NOT an embeddings call. Never
      # raises: an unconfigured URL, a non-2xx response, a timeout, or a
      # connection failure all collapse to `false`, mirroring the forgiving
      # contract `#embed` already uses elsewhere in this class. Short timeouts
      # on purpose — this runs synchronously while rendering `/config`, not on
      # a background job.
      def healthy?
        return false if base_url.blank?

        uri = URI.parse("#{base_url.chomp('/')}/health")
        response = Net::HTTP.start(uri.hostname, uri.port,
                                    use_ssl: uri.scheme == "https",
                                    open_timeout: 2, read_timeout: 2) do |http|
          http.request(Net::HTTP::Get.new(uri))
        end
        response.is_a?(Net::HTTPSuccess)
      rescue StandardError => e
        Rails.logger.warn("[Pito::Embedding::Client] health check failed: #{e.class}: #{e.message}")
        false
      end

      private

      # Split `text` into ordered pieces each at most CHUNK_BUDGET
      # characters (MAX_CHARS_PER_CHUNK minus the wire-level PROMPT_PREFIX,
      # so a prefixed chunk never exceeds the safety envelope). Short text
      # passes through as a single-element array (unchanged). Longer text
      # breaks on whitespace so words stay intact; a single word longer
      # than the budget is force-split by length as a last resort. The
      # splitting path never emits empty pieces.
      def chunk_text(text)
        return [ text ] if text.length <= CHUNK_BUDGET

        chunks = []
        current = +""

        text.scan(/\S+\s*/) do |token|
          # A lone token past the budget can't share a chunk — flush what
          # we have, then hard-split the token by length.
          if token.length > CHUNK_BUDGET
            unless current.empty?
              chunks << current
              current = +""
            end
            token.chars.each_slice(CHUNK_BUDGET) { |piece| chunks << piece.join }
            next
          end

          if current.length + token.length > CHUNK_BUDGET
            chunks << current unless current.empty?
            current = +""
          end
          current << token
        end

        chunks << current unless current.empty?
        chunks
      end

      # Mean-pool an input's chunk vectors into one DIMENSIONS-long vector.
      # `vectors` is a NON-EMPTY array of equal-length embedding arrays.
      # A single vector passes through UNCHANGED (no normalization) so
      # short inputs stay byte-identical to the pre-chunking behavior.
      # Two or more are averaged element-wise and L2-normalized (the raw
      # mean is returned if its norm is 0).
      def pool(vectors)
        return vectors.first if vectors.length == 1

        dims = vectors.first.length
        sums = Array.new(dims, 0.0)
        vectors.each do |vec|
          vec.each_with_index { |val, i| sums[i] += val }
        end
        mean = sums.map { |s| s / vectors.length }

        norm = Math.sqrt(mean.sum { |v| v * v })
        return mean if norm.zero?
        mean.map { |v| v / norm }
      end

      # Embed a flat chunk list via the FORGIVING transport, sub-batching
      # at MAX_BATCH_SIZE. Returns a vector array aligned to `chunks`, nil
      # where a chunk (or its whole sub-batch) failed to embed.
      def forgiving_chunk_vectors(chunks)
        vectors = Array.new(chunks.length)
        chunks.each_slice(MAX_BATCH_SIZE).with_index do |slice, batch_index|
          offset = batch_index * MAX_BATCH_SIZE
          data = post_embeddings(slice)
          next if data.nil?

          data.each do |row|
            idx = row["index"]
            next unless idx.is_a?(Integer) && idx.between?(0, slice.length - 1)
            vectors[offset + idx] = row["embedding"]
          end
        end
        vectors
      end

      # Embed a flat chunk list via the STRICT transport, sub-batching at
      # MAX_BATCH_SIZE. Returns a vector array aligned to `chunks`; raises
      # on a non-2xx / malformed response or a malformed row. A slot the
      # response simply omits stays nil for the caller to flag as missing.
      def strict_chunk_vectors(chunks)
        vectors = Array.new(chunks.length)
        chunks.each_slice(MAX_BATCH_SIZE).with_index do |slice, batch_index|
          offset = batch_index * MAX_BATCH_SIZE
          data = post_embeddings_strict(slice)

          data.each do |row|
            idx = row["index"]
            raise Error, "embedder response row missing 'index' field: #{row.inspect[0, 200]}" unless idx.is_a?(Integer) && idx.between?(0, slice.length - 1)
            vectors[offset + idx] = row["embedding"]
          end
        end
        vectors
      end

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
        # PROMPT_PREFIX rides in here — the ONE wire-level choke point (see
        # the constant's doc). Chunks were split to CHUNK_BUDGET, so the
        # prefixed strings stay inside the MAX_CHARS_PER_CHUNK envelope.
        request.body = JSON.generate(input: inputs.map { |t| PROMPT_PREFIX + t })

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
