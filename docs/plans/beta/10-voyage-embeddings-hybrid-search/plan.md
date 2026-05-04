# Phase 10 — Voyage Embeddings + Hybrid Search

> **Goal:** Generate embeddings for all KB and YouTube content via Voyage AI.
> Store vectors in **both** Postgres (pgvector) for related-content SQL joins
> and Meilisearch for hybrid keyword+vector search via the existing search bar.
> One Voyage call per content change; dual-write to both stores; no redundant
> embedding work.

**Depends on:** Phase 2 (pgvector extension installed but unused), Phase 8 (real
channel/video data), Phase 9 (KB markdown structure populated).

**Unblocks:** Phase 11 (workflow features can use "find related videos / notes"
queries; Claude can suggest content directions based on semantic neighbors), and
the qualitative leap from "Pito stores my data" to "Pito helps me think about my
data."

---

## Why Phase 10 is now

Embeddings work best on real, settled content — not stub seeds. After Phase 9,
Pito has:

- Real channel metadata (titles, descriptions, branding)
- Real video metadata (titles, descriptions, captions if available)
- Real KB markdown (channel context, video notes, research files)

That's enough corpus to embed and search meaningfully. Doing it earlier would
burn Voyage credits on data destined to change.

The dual-write decision is the architecturally interesting one:

- **Postgres + pgvector** lets us join vectors with relational queries. "Show me
  videos similar to this one, filtered to my owned channels, published in the
  last 90 days, with at least 1000 views." That's a Postgres join. Meilisearch
  can't do it.
- **Meilisearch hybrid** powers the user-facing search bar that already exists.
  Adding vectors there gives "search 'video about react hooks'" behavior where
  exact keyword AND semantic match both contribute, ranked appropriately.
- **One Voyage call per change** means we don't pay twice. Compute the vector
  once on content change; write to both stores. Simple, cheap, correct.

This phase is also where embedding **cost discipline** gets established. Voyage
charges per token. The user's full library backfill is roughly $5 (depending on
corpus size); ongoing churn is pennies per day. The audit table from Phase 7's
pattern (`YoutubeApiCall`) gets a sibling (`VoyageApiCall`) so Phase 13's
observability has the data it needs.

---

## In scope

### Voyage AI integration

- Add a Voyage HTTP client (no maintained Ruby gem at the time of writing; a
  thin wrapper around `Net::HTTP` or `Faraday` is the right shape)
- Use the **`voyage-3`** model: 1024 dimensions, well-balanced quality/cost,
  multilingual
- Single-text and batch endpoints (Voyage supports up to 128 texts per batch;
  use it for backfill)
- API key stored in Rails credentials as `VOYAGE_API_KEY`
- Rate limit awareness: Voyage has per-minute request limits and per-month token
  quotas; the client respects 429 responses with exponential backoff

### Schema additions

- Migration: confirm `enable_extension :vector` from Phase 2 is active; add it
  again idempotently if not
- Migration: add `embedding vector(1024)`, `content_hash` (string),
  `embedded_at` (timestamp) to `channels` and `videos`
- Migration: create `kb_file_embeddings` table — `id`, `path` (unique within
  tenant), `tenant_id`, `embedding vector(1024)`, `content_hash`, `embedded_at`.
  Polymorphic-ish; references markdown content roots configured per environment.
  The original spec scoped this to `PITO_YT_KB_PATH`; the YouTube KB repo has
  been dropped, and channel/video notes will reuse the project-notes pattern
  from Phase 4 — Project Workspace.
- Migration: create `voyage_api_calls` audit table — `id`, `tenant_id`,
  `user_id` (nullable; system jobs may not have a user context), `endpoint`,
  `input_tokens`, `output_dimensions`, `outcome`, `error_message`, `created_at`
- Indexes:
  - **HNSW index** on each `embedding` column
    (`USING hnsw (embedding vector_cosine_ops)` with default parameters). HNSW
    preferred over IVFFlat for accuracy at Pito's corpus size.
  - Standard B-tree on `content_hash` for fast skip-on-no-change checks
  - Index on `kb_file_embeddings.path` for lookup

### Embeddings infrastructure

`Embeddings::VoyageClient` — single-text and batch endpoints. Records every call
to `voyage_api_calls` with input token count and outcome. Handles 429 with
exponential backoff (1s / 2s / 4s, max 3 retries). Treats network errors as
retryable; treats 4xx (except 429) as terminal.

`Embeddings::Indexer` — orchestration:

- Accepts a record (`Channel`, `Video`, or a KB file path)
- Composes the embedding source text (the canonical "what to embed"
  representation — see below)
- Computes a SHA-256 hash of the source text
- If `content_hash` matches what's already stored, returns early (no Voyage
  call, no DB write)
- Otherwise calls Voyage, gets the vector
- **Dual-writes** the vector: updates the pgvector column on the record /
  `kb_file_embeddings` row, and pushes to Meilisearch's user-supplied embedder
  field for the same document

`Embeddings::SourceComposer` — single source of truth for "what does an X embed
look like":

- **Channel:** `[name, description, summarized channel context]` concatenation,
  capped at ~4000 tokens
  - Channel context summary = concatenation of the 5 KB context files
    (voice/audience/skills/strategy/progress) if they exist
- **Video:** `[title, description, KB plan/notes/retro if they exist]`
  concatenation, capped at ~4000 tokens
- **KB file:** body text with front-matter stripped

The composition strategy is documented in `pito/docs/embeddings.md` so future
tweaks are visible and reversible.

### Backfill jobs (Sidekiq)

- `Embeddings::BackfillChannelsJob` — embeds all channels in the tenant in
  batches of 10
- `Embeddings::BackfillVideosJob` — embeds all videos in batches of 50 (or
  whatever Voyage's batch limit is)
- `Embeddings::BackfillKbJob` — walks the configured KB roots (the YouTube KB
  repo has been dropped; channel/video notes reuse the Phase 4 — Project
  Workspace project-notes pattern), embeds each `.md` file, batches
- CLI: `bin/rails embeddings:backfill_all` — runs all three sequentially
- CLI: `bin/rails embeddings:status` — shows counts of embedded vs not embedded
  per type
- All jobs idempotent: re-running skips already-current records based on content
  hash
- Run on a single-threaded Sidekiq queue to respect Voyage rate limits (one
  queue dedicated to embeddings)

### Reactive embedding (incremental updates)

- `after_commit` hook on `Channel` and `Video`: enqueue
  `Embeddings::ReindexRecordJob(record)` if any embedded field changed (title,
  description, etc.)
- `Mcp::Tools::Yt::WriteKbFile` (Phase 9) calls
  `Embeddings::ReindexKbFileJob(path)` after success
- `Mcp::Tools::Yt::DeleteKbFile` removes the corresponding `kb_file_embeddings`
  row and Meilisearch document
- All reactive jobs check content hash first; no-op if unchanged. So a channel
  re-sync that updates `last_synced_at` but not title/description doesn't
  trigger a Voyage call.

### Meilisearch hybrid setup

- Update Meilisearch index settings to declare an embedder using user-provided
  vectors (Meilisearch supports user-supplied embeddings — verify version
  supports it; upgrade Meilisearch image if needed)
- Indexing path: when a record is reindexed in pgvector, also push its vector
  into Meilisearch's embedder field for the same document
- Search controller updates: use Meilisearch's hybrid mode for queries ≥ 3
  characters; pure keyword for shorter queries (typo prefix matching)
- Display match annotation in results UI: small bracketed `[match: keyword]` or
  `[match: similar meaning]` per result so the user knows what the relevance
  signal is

### Related-content endpoint and UI

- `GET /api/related?type=video&id=...&limit=5` — returns top-K nearest neighbors
  by cosine similarity
  - Supports `type=video`, `type=channel`, `type=kb_file`
  - Tenant-scoped via `Current.tenant`
  - Uses pgvector's `<=>` operator (cosine distance) — fast with HNSW index
- Video show page: "Related" panel showing top-5 similar videos plus top-3
  similar KB notes
- Channel show page: "Related channels" panel (top-5 similar channels, including
  external)
- KB file editor (from Phase 9): "Related notes" sidebar showing top-5 similar
  markdown files
- All related panels respect `yt:read` scope when accessed via API; web UI
  honors implicit user session

### Search bar enhancements

- Existing search bar UI unchanged externally
- Backend swaps to Meilisearch hybrid query for queries ≥ 3 chars
- Results display match-type annotation
- For very short queries (1-2 chars), keep keyword-only behavior (typo prefix is
  more useful at that length than semantic)

### Cost monitoring

- Settings → Stats (Phase 13 will mature this) gets an early "Embeddings cost"
  widget — total Voyage tokens used today, this month, dollar estimate from a
  config constant
- Phase 13's full observability page reads from `voyage_api_calls`; this phase
  establishes the data

### Out of scope

- Re-ranking with Voyage's rerank model (would improve relevance but doubles
  cost; defer to Theta)
- Cross-encoder rerank as a Phase 11 enhancement (capture in `additions.md` if
  requested mid-phase)
- Multi-language embedding strategies beyond `voyage-3`'s built-in multilingual
  support
- User-customizable similarity weights or hybrid alpha (use Meilisearch
  defaults; expose later if needed)
- Per-user embedding partitions (single-user, single-tenant; tenant scoping is
  sufficient)
- Real-time vector indexing of search queries themselves (Meilisearch handles
  this internally for hybrid)

---

## Plan checklist

### Voyage client

- [ ] Add `VOYAGE_API_KEY` to Rails credentials (development + test)
- [ ] Implement `Embeddings::VoyageClient` — single-text and batch endpoints;
      `voyage-3` model hardcoded but configurable via constant
- [ ] Specs with VCR for happy path, batch, 429 with backoff, terminal errors,
      network failure handling
- [ ] Cost tracking: every call writes a `VoyageApiCall` row with input token
      count from Voyage's response

### Schema

- [ ] Migration: verify `vector` extension active (idempotent enable)
- [ ] Migration: add `embedding`, `content_hash`, `embedded_at` to `channels`
      and `videos`
- [ ] Migration: create `kb_file_embeddings` table
- [ ] Migration: create `voyage_api_calls` audit table (mirrors
      `youtube_api_calls` shape)
- [ ] Migration: HNSW indexes on each `embedding` column with default parameters
- [ ] Spec: query plan for `nearest_neighbors` uses the HNSW index (use
      `EXPLAIN`)

### Indexer

- [ ] `Embeddings::SourceComposer` — methods for `for_channel`, `for_video`,
      `for_kb_file`. Token-cap respected. Document the strategy in
      `pito/docs/embeddings.md`.
- [ ] `Embeddings::Indexer.index(record)` — composes source, hashes, no-ops on
      unchanged, calls Voyage, dual-writes
- [ ] `Embeddings::Indexer.index_kb_file(path)` — same shape for KB files
- [ ] `Embeddings::Indexer.delete_kb_file(path)` — removes pgvector row +
      Meilisearch document
- [ ] Specs: composition correctness, hash skip, dual-write success, partial
      failure (Voyage success but Meilisearch failure → log and retry without
      re-embedding via the existing hash)

### Backfill

- [ ] `Embeddings::BackfillChannelsJob` — batches of 10, uses Voyage batch
      endpoint
- [ ] `Embeddings::BackfillVideosJob` — batches of 50 (or batch limit)
- [ ] `Embeddings::BackfillKbJob` — walks the KB filesystem, batches
- [ ] CLI: `bin/rails embeddings:backfill_all`
- [ ] CLI: `bin/rails embeddings:status`
- [ ] Sidekiq queue dedicated to embeddings, single-threaded to respect Voyage
      rate limits
- [ ] Specs: idempotency, batching, rate-limit-aware backoff

### Reactive embedding

- [ ] `after_commit` hook on `Channel` model: enqueue reindex job when
      title/description/relevant fields change
- [ ] `after_commit` hook on `Video` model: same
- [ ] `Mcp::Tools::Yt::WriteKbFile` triggers
      `Embeddings::ReindexKbFileJob(path)` after success
- [ ] `Mcp::Tools::Yt::DeleteKbFile` triggers
      `Embeddings::DeleteKbEmbeddingJob(path)` after success
- [ ] Reactive jobs hash-check first; skip if unchanged
- [ ] Specs: reactive trigger fires correctly, hash skip works on no-op edits

### Meilisearch hybrid

- [ ] Verify Meilisearch version supports user-supplied embedders; upgrade
      Docker image if needed (capture in migration steps)
- [ ] Update Meilisearch index settings to register the user-supplied embedder
- [ ] Update indexing path: every reindex pushes the vector into Meilisearch
      alongside pgvector
- [ ] Update search controller: hybrid mode for queries ≥ 3 chars; keyword-only
      for shorter
- [ ] Display match annotation per result
- [ ] Specs: keyword-dominant query, vector-dominant query (semantic match
      without keyword), mixed query

### Related content

- [ ] `GET /api/related` endpoint with `type` and `id` parameters
- [ ] `Channel`, `Video`, `KbFileEmbedding` models expose `nearest_neighbors`
      scope using pgvector
- [ ] Tenant scoping enforced
- [ ] Web UI: "Related" panels on video show, channel show, KB file editor
- [ ] Specs: top-K accuracy with fixture vectors, tenant scoping, type filtering

### Cost monitoring placeholder

- [ ] Settings → Stats: simple widget showing today's Voyage tokens, this
      month's tokens, dollar estimate
- [ ] Pricing constant in a config file (Voyage's `voyage-3` price per million
      tokens)
- [ ] Phase 13 will mature this; Phase 10 establishes the data

### Documentation

- [ ] Update `pito/docs/architecture.md`: embeddings architecture, dual-write
      rationale, hybrid search
- [ ] `pito/docs/embeddings.md` (new): model choice, dimensions, source
      composition strategy, hash strategy, expected costs, troubleshooting
- [ ] Update `pito/docs/mcp.md`: note that `yt:write_kb_file` and
      `yt:delete_kb_file` trigger reindex
- [ ] Update `pito/docs/setup.md`: `VOYAGE_API_KEY` credential setup,
      Meilisearch version requirement

### Validation

- [ ] Run `bin/rails embeddings:backfill_all` against the full real dataset
      (Phase 8 data + Phase 9 KB content)
- [ ] Voyage dashboard cost ≈ matches `VoyageApiCall.sum(:input_tokens)` ×
      pricing constant
- [ ] pgvector queries work:
      `Channel.nearest_neighbors(:embedding, query_vec, distance: "cosine").limit(5)`
- [ ] Meilisearch hybrid: search "videos about [some semantic concept not in
      titles]" returns relevant results
- [ ] Video show page: "Related" panel populated with sensible matches
- [ ] Edit a KB file via in-app editor → reindex job fires → `embedded_at`
      updated within ~30 seconds
- [ ] All RSpec specs pass
- [ ] Brakeman, bundler-audit, Dependabot — clean

---

## Specs requirements

- `Embeddings::VoyageClient`: happy path, batch, 429 with backoff, terminal 4xx
  errors, network failure.
- `Embeddings::SourceComposer`: each record type produces correct source string
  with token cap respected.
- `Embeddings::Indexer`: hash skip on unchanged, dual-write success, partial
  failure (Voyage OK / Meilisearch fails) handled correctly with retry
  semantics.
- Backfill job specs: idempotency, batching, rate-limit awareness.
- Reactive job specs: triggered on relevant field changes, no-op on unchanged
  content.
- Hybrid search specs: keyword-dominant, vector-dominant, mixed queries; match
  annotation correct.
- Related endpoint specs: top-K accuracy with fixture vectors, tenant scoping,
  type filtering.
- Cross-tenant scoping: `KbFileEmbedding` and embedded records all scoped to
  `Current.tenant`; second-tenant-leak spec asserts isolation.

## Security requirements

- `VOYAGE_API_KEY` in Rails credentials, never in repo or `.env`.
- Voyage API calls include only the content being embedded (titles,
  descriptions, KB body). Nothing about user identity, no tokens, no PII beyond
  what's already in the content.
- Embedding content not logged at INFO level (avoid full-text in logs);
  aggregate metrics only.
- `VoyageApiCall` audit table records aggregates (token counts, outcomes), not
  full content.
- Meilisearch index continues to scope by tenant.
- VCR cassettes for Voyage testing scrub the API key.
- Brakeman: no new warnings.
- bundler-audit: clean.
- Dependabot: review.
- `pito/docs/design.md`: Related panel and search match annotation patterns
  documented.

## Manual testing checklist

The user runs through this before commit:

1. Set `VOYAGE_API_KEY` in development credentials
2. Confirm Meilisearch version supports user-supplied embedders; upgrade if
   needed
3. `bin/rails embeddings:backfill_all` — wait for completion (a few minutes for
   typical corpus)
4. `bin/rails embeddings:status` — confirm 100% coverage across channels,
   videos, KB files
5. Open a video show page → see "Related" panel with 5 sensible video matches
   plus 3 KB note matches
6. Search bar: query "videos about [a concept not literally in titles, e.g.,
   'speedrunning techniques' if no video has that exact phrase]" → results
   include semantically-related videos with `[match: similar meaning]`
   annotation
7. Edit a KB file via in-app editor (Phase 9) → check Sidekiq for reindex job →
   verify `embedded_at` updates within ~30s
8. Cost check: Voyage dashboard total roughly matches
   `VoyageApiCall.sum(:input_tokens)` × pricing constant
9. From Claude (mobile or desktop), prompt: "find videos in my library similar
   to [a specific video]" → MCP tool returns related videos using the
   embedding-backed query
10. Cross-tenant leak test (manual): create a second tenant via console, embed a
    record there, verify the first tenant's `nearest_neighbors` queries do not
    return the second tenant's record
11. `bundle exec rspec` — green

---

## Challenges to anticipate

- **Source composition tradeoffs.** Including too much context dilutes
  embeddings; too little misses signal. Recommended starting point: title +
  description + first ~1500 chars of associated KB content. Iterate based on
  related-results quality.
- **Hash sensitivity.** If hashing includes timestamps or generated content, the
  cache busts on every reindex even when nothing meaningful changed. Hash only
  the semantic source material (the SourceComposer output), nothing else.
- **Voyage rate limits.** Check current per-minute and per-month limits; design
  the single-threaded Sidekiq queue around them. Backfill of a large corpus may
  take hours; that's fine.
- **Meilisearch embedder feature compatibility.** User-supplied embedders is a
  relatively new Meilisearch feature; verify the running version supports it. If
  older, upgrade the Docker image as a sub-task of this phase.
- **pgvector index choice.** HNSW is the recommendation for accuracy at Pito's
  corpus size. Default parameters (`m=16`, `ef_construction=64`) are fine.
  IVFFlat is faster to build but lower recall — not worth it here.
- **KB file deletion sync.** When a KB file is deleted (`yt:delete_kb_file` from
  Phase 9), the corresponding embedding row and Meilisearch document must also
  be removed. Tied to the tool callback.
- **Backfill cost surprise.** ~$5 for the user's full library is a rough
  estimate. Confirm before kicking off backfill so the user isn't surprised.
  Capture actual cost post-backfill in `log.md` for future reference.
- **Both Pumas observe reactive triggers, not just one.** The `after_commit`
  hooks fire wherever the record is saved — Web Puma controllers, MCP Puma tool
  calls, Sidekiq jobs (sync workers). All paths must end up enqueueing the
  reindex job correctly.
- **Reindex job failures aren't catastrophic but shouldn't be silent.** If
  Voyage is down, reindex jobs retry via Sidekiq and end up in the retry queue.
  Phase 13's observability surfaces this; Phase 10 just needs to not silently
  swallow.

---

## Confirmation gates for Claude Code

Before executing, confirm with the user:

1. The user has a Voyage account; API key is obtained; cost expectations are
   clear (~$5 backfill, pennies/day ongoing).
2. `voyage-3` is the right model. Alternatives: `voyage-3-large` (better
   quality, more expensive — overkill for Pito's use), `voyage-code-3`
   (irrelevant). Stick with `voyage-3`.
3. Meilisearch version supports user-supplied embedders. If not, upgrade the
   Docker image as part of this phase.
4. The user is OK with embedding source content being sent to Voyage's API.
   Voyage's data retention policy applies; user reviews.
5. Source composition strategy (title + description + first ~1500 chars of
   associated KB) is acceptable. Tune later if related-results aren't useful.
6. Backfill timing: start in a session where the user can monitor for the first
   ~10 minutes to catch any unexpected cost or failure.
