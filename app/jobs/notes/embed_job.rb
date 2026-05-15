# Phase 4 §3.5 — single-API-call dual-write embedding job.
#
# Phase B revamp (2026-05-04): Voyage gating reads two signals — the
# per-target `voyage_indexing_project_notes?` flag (a non-secret column
# on AppSetting) AND the `voyage_configured?` (key present?) check. BOTH
# must be true for the job to call Voyage. The dual check is intentional
# belt-and-suspenders:
#
#   - The flag toggle and the key are independent surfaces, but...
#   - ...this job is the LAST line of defense before money is spent on
#     embedding tokens. If the flag is on but no key is configured, this
#     guard still short-circuits cleanly.
#
# When either guard is false: the note record stays unchanged; Meilisearch
# indexes the text body BM25-only (no embedding payload); `notes.embedding`
# stays NULL; NO HTTP call to Voyage.
#
# When both guards are true: call Voyage AI's embeddings API once (model
# `voyage-3`, returns a 1024-dim vector). Write the vector to BOTH:
#   - Meilisearch (hybrid index — embedding payload alongside indexed text)
#   - notes.embedding pgvector column
#
# Phase 29 — Unit A1. The Voyage API key lives exclusively in
# `Rails.application.credentials.voyage.api_key` again (the project's
# configuration strategy — secrets in credentials only). The AppSetting
# `voyage_api_key` column is dropped; `voyage_configured?` now checks
# the credentials presence. `resolve_api_key` reads credentials directly.
#
# Voyage credentials use a flat block (`voyage: { api_key }`) shared
# across environments — the same key applies to dev / test / production.
# In `Rails.env.test?`, WebMock blocks all non-localhost HTTP, so the
# real Voyage endpoint is never reached even when a key is present;
# specs that exercise the Voyage branch stub the endpoint explicitly
# (see `spec/support/voyage.rb`).
#
# Idempotent on retry: re-running re-embeds and re-writes; vector inserts
# replace the prior value.
module Notes
  class EmbedJob
    include Sidekiq::Job
    sidekiq_options queue: "search", retry: 3

    VOYAGE_URL = "https://api.voyageai.com/v1/embeddings".freeze
    VOYAGE_MODEL = "voyage-3".freeze

    def perform(note_id)
      # Phase 8 — tenant drop. The previous `Note.unscoped` workaround
      # bypassed `BelongsToTenant`'s default scope; with the tenant
      # model gone a plain `find_by` is fine.
      note = Note.find_by(id: note_id)
      return unless note

      body = NotesFilesystem.read(note)

      if AppSetting.voyage_indexing_project_notes? && AppSetting.voyage_configured?
        embedding = call_voyage(body)
        return if embedding.nil?

        note.update_columns(embedding: embedding)
        upsert_search(note, body, embedding: embedding)
      else
        # BM25 / text-only branch — no Voyage call, no vector write.
        upsert_search(note, body, embedding: nil)
      end
    end

    private

    def call_voyage(body)
      api_key = resolve_api_key
      return nil if api_key.blank?

      uri = URI.parse(VOYAGE_URL)
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(input: [ body.to_s ], model: VOYAGE_MODEL)

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
      return nil unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      data.dig("data", 0, "embedding")
    rescue StandardError => e
      Rails.logger.warn("Voyage embed failed: #{e.class}: #{e.message}")
      nil
    end

    # Phase 29 — Unit A1. The Voyage API key lives exclusively in the
    # flat `Rails.application.credentials.voyage` block (`api_key`,
    # shared across environments). The job no-ops cleanly when the key
    # is blank (the `call_voyage` caller guards on `api_key.blank?`).
    def resolve_api_key
      Rails.application.credentials.dig(:voyage, :api_key)
    end

    # Indexes the note's body in Meilisearch. When `embedding` is non-nil we
    # attach it as a payload field so the hybrid index can score by vector
    # similarity. When nil, the document still indexes text for BM25 search.
    #
    # The note model isn't `searchable` (Searchable concern is channels/videos
    # only for now), so we bypass the engine adapter and talk to Meilisearch
    # directly. The notes index ships when Phase 9 wires the search surface;
    # for now this writes if the host is reachable and silently swallows the
    # error otherwise (WebMock-friendly under specs).
    def upsert_search(note, body, embedding:)
      url = ENV.fetch("MEILISEARCH_URL", "http://127.0.0.1:7727")
      uri = URI.parse("#{url}/indexes/notes_#{Rails.env}/documents")

      doc = {
        id: note.id,
        title: note.title,
        body: body.to_s,
        project_id: note.project_id
      }
      doc[:_vectors] = { default: embedding } if embedding

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate([ doc ])
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(request) }
    rescue StandardError => e
      Rails.logger.warn("Meilisearch upsert failed for note #{note.id}: #{e.class}: #{e.message}")
    end
  end
end
