# 01 — /games/:id "Recommended channels" section (v1, Voyage-driven)

> Phase 38 spec. Adds a new RIGHT-pane section to `/games/:id` titled
> `recommended channels` that ranks the locally-indexed `Channel` rows
> by semantic similarity to the game and surfaces the top hits with a
> 0-100 score. Section sits IMMEDIATELY BEFORE the existing bundles
> section.
>
> The recommendation backbone is **Voyage AI embeddings + pgvector
> HNSW cosine similarity**, mirroring the proven `Bundles::SuggestedFor`
> pattern (`app/services/bundles/suggested_for.rb` +
> `app/services/bundles/voyage_indexer.rb`). User-locked decision on
> 2026-05-19: channel recommendations adopt the same Voyage-first
> backbone the bundle "fits this game" surface uses.
>
> The channel Meilisearch index built earlier in this phase (Phase 37
> Wave A1, `Meilisearch::ChannelIndexer`) is NOT removed by this spec
> — it continues to back the Omnisearch "everywhere" modal. The two
> pipelines coexist for different use cases (see §"Meilisearch
> coexistence" below).

---

## Goal

Tell the user, at a glance, which of the channels the install owns
read as a semantic fit for the game they are looking at —
independently scored 0-100 (a percentage match), not a zero-sum
ranking against a fixed pool. The same channel can score 90+ for many
different games; the same game can light up many channels. Useful for
picking which of the user's tracked channels to look at when starting
a new game, and later (post-/videos) for routing footage / recordings
to the channel whose audience is the best match.

The capability matters for Phase 38 because:

- It seeds the data shape (game-embedding → channel-score tuples) the
  view contract depends on. Future iterations (per-video signal
  blending, see §"Future extensibility") swap the embedding
  composition INSIDE the indexer without changing the view or the
  service entry point.
- It validates that the bundle-tested Voyage + pgvector + HNSW stack
  generalises cleanly to a second cross-domain recommendation surface
  (game → channels, mirroring game → bundles).
- It gives the channel Voyage embedding column its first consumer,
  paving the way for additional semantic surfaces on channels later
  (channel → similar channels, channel → recommended games, etc.).

Audience: the install's authenticated users browsing `/games/:id`.

---

## Scope in

- New RIGHT-pane section on `/games/:id`, rendered BETWEEN the time-to-
  beat block (existing) and the bundles section (existing
  `Games::BundlesSectionComponent`).
- New `summary_embedding` column on `channels` (1024-dim pgvector) +
  HNSW cosine-ops index, mirroring `bundles.summary_embedding`.
- New `Channels::VoyageIndexer` service that mirrors
  `Bundles::VoyageIndexer`: build composite text from
  `title + handle + description + keywords`, embed via Voyage, upsert.
- New `ChannelVoyageIndexJob` Sidekiq job that wraps the indexer.
- Channel model wiring: `has_neighbors :summary_embedding`,
  `after_save_commit` hook enqueuing the index job.
- New rake task `pito:voyage:reindex_channels` for bulk reindex.
- New service `Games::ChannelRecommendation` (single `.call(game,
  limit:)` entry point, returns Array of Hashes — see §"Service
  contract").
- New `Games::RecommendedChannelsSectionComponent` ViewComponent.
- New `Games::ChannelRecommendationRowComponent` ViewComponent for the
  per-row render (avatar + display name + handle + score badge).
- Controller integration in `GamesController#show` (single line — call
  the service, assign to an ivar, view component reads it).
- View edit in `app/views/games/show.html.erb` (single render line +
  hairline above, between the existing TTB section and the existing
  bundles section).
- I18n keys for the section heading, the empty-state copy, and the
  badge `aria-label`.
- RSpec coverage (migration / model / indexer / job / service /
  component / view / request).

## Scope out (explicit non-goals)

- Per-video signal blending into the channel embedding —
  DEFERRED. Documented in §"Future extensibility" so the v1 indexer
  signature does not block v2 composition growth. v2 lands when
  `/videos` returns and per-video Voyage embeddings exist.
- Removing / replacing the Meilisearch channel index — OUT OF SCOPE.
  The Meilisearch index continues to serve Omnisearch. See
  §"Meilisearch coexistence".
- Precomputation cache table (`game_channel_scores`) — DEFERRED. v1
  computes the cosine query live on every `/games/:id` show; pgvector
  HNSW is fast enough that no caching layer is needed for v1.
- The reverse surface ("recommended games" on `/channels/:id`) —
  separate spec, separate phase.
- Click-through wiring to a dedicated `/channels/:id?game=<slug>` view
  with prefiltered videos — Phase 37 is still resolving the channel
  show page; this surface stays a plain `channel_path(channel)` link.
- Bulk / picker affordances (selecting a channel as the "owning"
  channel for a game) — out of scope until per-game footage routing
  lands.

---

## Surface-boundary note

`/games/:id` is the locked beta-3 milestone surface. This spec is an
ADD (one new section appended to the RIGHT pane between two existing
sections), not a refactor of any existing surface. The user
explicitly authorized this addition on 2026-05-19 in chat. No existing
section is altered, no existing component is touched.

The dispatch prompt for the implementation agent MUST include:

> /games is a locked beta-3 milestone surface. This dispatch is an
> additive new section ONLY. DO NOT modify:
> - `Games::BundlesSectionComponent` or its template
> - `Games::SimilarGames` service or its rendering block
> - `Games::TimeToBeatComponent` or its template
> - `Games::RatingHeatBarComponent`
> - `Games::OwnershipMatrixComponent`
> - `Games::DetailCoverComponent`, `Games::MetaTableComponent`,
>   `Games::GenresLineComponent`
> - The breadcrumb action strip
> - The two existing ConfirmModalComponent renders at the bottom of
>   `show.html.erb`
>
> Only insertions are: ONE `<hr class="hairline">` + ONE
> `<%= render Games::RecommendedChannelsSectionComponent.new(...) %>`
> immediately above the existing
> `<hr class="hairline"><%= render Games::BundlesSectionComponent.new(game: @game) %>`
> block.

---

## Meilisearch coexistence

Two independent channel pipelines run in parallel after this spec
ships. They DO NOT replace each other:

| Pipeline | Backbone | Consumer | Index payload |
| --- | --- | --- | --- |
| Channel Meilisearch index (`channels_<env>`) | BM25 + token tolerance | Omnisearch "everywhere" modal (text query → channel hits) | Title + handle + description + keywords (text) |
| Channel pgvector embedding (`channels.summary_embedding`) | Voyage 1024-dim + HNSW cosine | `Games::ChannelRecommendation` (game embedding → ranked channel hits) | 1024-dim vector embedded from the same composite text |

Both pipelines read from the SAME source columns on `Channel`. The
Voyage indexer composites the text, embeds it, and writes the vector;
the Meilisearch indexer composites the text and ships it as a
document. The user-facing surfaces (text-query autocomplete vs.
semantic "fits this game") justify keeping both alive.

The implementation MUST NOT remove, modify, or refactor
`Meilisearch::ChannelIndexer` or the `channels_<env>` index. The two
pipelines are siblings, not predecessors.

---

## Files to change

### New files

- `db/migrate/<ts>_add_summary_embedding_to_channels.rb` — adds the
  `vector(1024)` column and HNSW cosine-ops index. See §"Migration".
- `app/services/channels/voyage_indexer.rb` — mirror of
  `Bundles::VoyageIndexer`. See §"Indexer contract".
- `app/jobs/channel_voyage_index_job.rb` — mirror of
  `BundleVoyageIndexJob`. See §"Sidekiq job".
- `lib/tasks/pito_voyage.rake` (create or extend) — adds
  `pito:voyage:reindex_channels` task. See §"Reindex rake task".
- `app/services/games/channel_recommendation.rb` — single-purpose
  service. `Games::ChannelRecommendation.call(game, limit: 8) →
  Array<Hash>`. See §"Service contract".
- `app/components/games/recommended_channels_section_component.rb` +
  `.html.erb`. Renders the section heading, the optional show-more
  affordance, and iterates the rows.
- `app/components/games/channel_recommendation_row_component.rb` +
  `.html.erb`. Renders one row: avatar + display name + handle +
  score badge.
- `spec/services/channels/voyage_indexer_spec.rb`.
- `spec/jobs/channel_voyage_index_job_spec.rb`.
- `spec/services/games/channel_recommendation_spec.rb`.
- `spec/components/games/recommended_channels_section_component_spec.rb`.
- `spec/components/games/channel_recommendation_row_component_spec.rb`.

### Modified files

- `app/models/channel.rb` — add `has_neighbors :summary_embedding`,
  add `after_save_commit { ChannelVoyageIndexJob.perform_later(id) }`
  guarded so it only fires when one of the embedded columns
  (`title`, `handle`, `description`, `keywords`) actually changed.
  Mirror the guard pattern `Bundle` uses for its
  `after_commit :enqueue_voyage_index`.
- `app/controllers/games_controller.rb` — `#show` action. ONE new
  line: `@recommended_channels =
  Games::ChannelRecommendation.call(@game, limit: 8)`. No other
  controller change. No new strong params, no new filters.
- `app/views/games/show.html.erb` — TWO new lines (one `<hr>` + one
  `render`). See §"View placement" below.
- `config/locales/en.yml` (or the namespaced
  `config/locales/games/en.yml` if the project splits domain
  files — implementation agent picks per the existing pattern).
  New keys under `games.show.recommended_channels.*`. See
  §"I18n keys" below.
- `spec/models/channel_spec.rb` — extend with assertions for
  `has_neighbors :summary_embedding` and the `after_save_commit`
  enqueue guard.
- `spec/views/games/show.html.erb_spec.rb` — extend with assertions
  that the new section is present, ordered between TTB and bundles,
  and renders rows when the service returns hits; empty-state path
  asserted separately.
- `spec/requests/games_spec.rb` — extend `GET /games/:id` happy-path
  example with an assertion that `@recommended_channels` is assigned
  AND the section heading is present in the response body.

---

## Migration

`db/migrate/<ts>_add_summary_embedding_to_channels.rb`:

- Add `summary_embedding :vector, limit: 1024` to `channels`.
- Add HNSW index `index_channels_on_summary_embedding_hnsw` using
  `vector_cosine_ops`, with the same `m` / `ef_construction` knobs
  the bundles index uses (implementation agent looks up the exact
  values from `db/schema.rb`'s
  `index_bundles_on_summary_embedding_hnsw` line — DO NOT pick new
  values; mirror the canonical bundle index settings).
- The migration is reversible (the down direction drops the index
  then the column).

No data backfill in the migration itself — the rake task
(`pito:voyage:reindex_channels`) is the canonical backfill path so
the migration stays fast and idempotent.

---

## Channel model

Additions to `app/models/channel.rb` (no other line changes):

```ruby
has_neighbors :summary_embedding

after_save_commit :enqueue_voyage_index, if: :voyage_text_changed?

private

def voyage_text_changed?
  saved_change_to_title? ||
    saved_change_to_handle? ||
    saved_change_to_description? ||
    saved_change_to_keywords?
end

def enqueue_voyage_index
  ChannelVoyageIndexJob.perform_later(id)
end
```

The guard prevents the indexer from re-firing on `last_synced_at`
bumps, `star` toggles, and other non-embedding column writes.

---

## Indexer contract — `Channels::VoyageIndexer`

`app/services/channels/voyage_indexer.rb`. Mirror the shape of
`Bundles::VoyageIndexer` line-for-line; the only deltas are the input
record type and the composite-text composition.

### Public API

```ruby
# Embed a single channel and persist the 1024-dim vector to
# `channels.summary_embedding`. Idempotent — re-running on an
# unchanged channel produces the same vector.
#
# @param channel [Channel]
# @return [void]
Channels::VoyageIndexer.call(channel)
```

### Algorithm (v1)

1. Build composite text:
   - `[channel.title, channel.handle, channel.description,
     channel.keywords].compact.reject(&:blank?).join("\n")`.
   - When the result is blank → return immediately (no embedding,
     no DB write).
   - When `description` AND `keywords` are BOTH blank → return
     immediately. A channel with only a title + handle is too
     degenerate to embed meaningfully; the indexer skips it
     silently. (Implementation note: this is stricter than the
     bundle indexer because bundles always have at least a name
     plus member summaries; channels can come back from the
     YouTube API with no description text on day one.)
2. Gate on `AppSetting.voyage_configured?`. If the Voyage API key
   is blank, return without making the API call (no embedding, no
   write, no error — same silent skip the bundle indexer uses).
3. Call `Voyage::Client.new.embed([combined_text]).first`. If the
   client returns `nil`, return without writing.
4. Persist via `channel.update_column(:summary_embedding, vector)`
   — `update_column` skips validations + callbacks so this write
   does NOT re-trigger `after_save_commit :enqueue_voyage_index`.
5. Idempotent: calling the indexer twice with the same channel text
   produces the same vector (Voyage's embed model is deterministic
   per input).

### Future expansion point

The indexer's composite-text method is the seam for v2. Add a
comment at the top of the private composition method:

```ruby
# Future: when /videos returns, incorporate per-video signals into
# the composite text or compute a centroid over channel-text +
# top-N video embeddings (mirroring the way Bundles::VoyageIndexer
# composites bundle name + member-game summaries). See spec
# §"Future extensibility". Callers
# (`Games::ChannelRecommendation`) do NOT need to change; only the
# composition method grows.
```

---

## Sidekiq job — `ChannelVoyageIndexJob`

`app/jobs/channel_voyage_index_job.rb`. Standalone job, mirrors
`BundleVoyageIndexJob`:

```ruby
class ChannelVoyageIndexJob < ApplicationJob
  queue_as :default

  def perform(channel_id)
    channel = Channel.find_by(id: channel_id)
    return if channel.nil?

    Channels::VoyageIndexer.call(channel)
  end
end
```

Queue name + retry behavior + `find_by` (not `find!`) defense all
match the bundle job. The implementation agent mirrors whatever the
bundle job does; do not invent a new pattern.

---

## Reindex rake task

`lib/tasks/pito_voyage.rake` — add a `pito:voyage:reindex_channels`
task. If the file does not yet exist, create it and namespace under
`pito:voyage:`. Mirror the structure of `pito:voyage:reindex_games`
(or `reindex_bundles` if that exists — implementation agent mirrors
whichever is canonical).

```ruby
namespace :pito do
  namespace :voyage do
    desc "Reindex all channels via Channels::VoyageIndexer"
    task reindex_channels: :environment do
      Channel.find_each do |channel|
        ChannelVoyageIndexJob.perform_later(channel.id)
      end
    end
  end
end
```

Enqueues via the job rather than calling the indexer inline — keeps
the rake task fast (returns once enqueue is done) and the actual
embedding work happens on Sidekiq workers.

---

## Service contract — `Games::ChannelRecommendation`

### Public API

```ruby
# Returns an ordered Array of recommendation Hashes, descending by
# score. Empty Array on any failure path (game has no embedding,
# no channels indexed, all results below threshold).
#
# @param game [Game] — the game to recommend channels for.
# @param limit [Integer] — hard cap on returned rows. Default 8.
# @return [Array<Hash>] — each Hash has keys:
#   - :channel   — Channel ActiveRecord row
#   - :score     — Integer 0..100 (descending across the Array)
#   - :distance  — Float — raw cosine distance in [0, 2] (kept for
#                  debugging + future A/B logging)
Games::ChannelRecommendation.call(game, limit: 8)
```

The Array is ALREADY filtered by the threshold rule below (see
§"Threshold + filtering") and ALREADY sorted descending by `:score`.
Callers do not re-filter or re-sort.

### Algorithm (v1)

1. **Defensive guards.** Return `[]` immediately when ANY of:
   - `game.nil?`
   - `game.summary_embedding.blank?` (game has not been Voyage-indexed
     yet)
   - The result of step 2 raises (rescue + log WARN, return `[]`).

2. **Run the cosine nearest-neighbor query.** Mirror the
   `Bundles::SuggestedFor` shape:

   ```ruby
   Channel
     .where.not(summary_embedding: nil)
     .nearest_neighbors(:summary_embedding, game.summary_embedding,
                       distance: "cosine")
     .limit(limit * 2)
   ```

   The `* 2` headroom absorbs the post-fetch threshold filter so we
   don't underfill the page when several hits sit just below the
   floor. The `where.not(summary_embedding: nil)` guard keeps
   un-embedded channels (e.g., newly created or Voyage-key
   un-configured at insert time) out of the result.

3. **Read the cosine distance per row.** Each Channel returned by
   `nearest_neighbors` exposes `#neighbor_distance` (provided by the
   `neighbor` gem) returning the raw cosine distance in `[0, 2]`.

4. **Map cosine distance to a 0-100 score.**
   - `score = ((1 - distance) * 100).round.clamp(0, 100)`
   - Cosine distance `0` → score `100` (perfectly aligned vectors).
   - Cosine distance `1` → score `0` (orthogonal vectors; no
     semantic relationship).
   - Cosine distance `2` → score `-100` BEFORE clamp → clamped to
     `0`. The clamp guards against numerical edge cases; in practice
     Voyage embeddings rarely produce negative cosine similarity.
   - This is the **chosen normalization (locked)**: a linear map of
     `1 - cosine_distance` to `[0, 100]`. Independent across
     channels — a perfect semantic match always scores 100
     regardless of how many other channels also match.

5. **Threshold + filtering.** Drop any hit whose `score < 25`. Cap
   the resulting Array at `limit` entries. The 25 threshold is the
   v1 locked floor; the implementation agent does NOT pick a
   different threshold without spec amendment. Define it as a
   private constant `MIN_SCORE = 25` so a follow-up can tune it via
   spec amendment without code archaeology.

6. **Return** the Array of `{ channel:, score:, distance: }` Hashes,
   descending by `:score`. Ties broken by ascending `Channel#id`
   for determinism.

### Caching

- v1 does NOT cache. pgvector HNSW queries are sub-millisecond at
  realistic install scale; no caching layer is needed.
- If a future scale tier surfaces a measurable cost, the cache key
  would be `"games/channel_rec/#{game.id}/v1/#{limit}"`. Out of
  scope for v1.

### Error handling

- Game has no `summary_embedding` → return `[]`.
- No indexed channels (`where.not(summary_embedding: nil)` is empty)
  → returns `[]` naturally.
- Unexpected exception (DB error, gem bug) → rescue `StandardError`,
  log at WARN level with the game id, return `[]`. NEVER raise into
  the show action.

---

## View placement

In `app/views/games/show.html.erb`, the current RIGHT-pane order
inside `<div class="pane pane--game-detail">` is:

1. `last_sync_error` red line (conditional)
2. Summary section (or syncing-state)
3. Time-to-beat section
4. **(INSERT HERE)** — `<hr class="hairline">` +
   `<%= render Games::RecommendedChannelsSectionComponent.new(...) %>`
5. `<hr class="hairline">` + bundles section
6. `<hr class="hairline">` + similar shelf
7. `<hr class="hairline">` + videos heading + `[TBD]` badge

The new block sits IMMEDIATELY ABOVE the existing line
`<%= render Games::BundlesSectionComponent.new(game: @game) %>` and
its preceding `<hr class="hairline">`. No other line in
`show.html.erb` is altered.

The component is instantiated with the controller-assigned ivar:

```erb
<hr class="hairline">
<%= render Games::RecommendedChannelsSectionComponent.new(
      game: @game,
      recommendations: @recommended_channels) %>
```

The `recommendations` arg is the Array returned by
`Games::ChannelRecommendation.call`. Passing it in (rather than the
component calling the service itself) keeps the controller as the
single composition point and lets the view spec inject fixtures.

---

## Component contracts

### `Games::RecommendedChannelsSectionComponent`

**Constructor:**

```ruby
def initialize(game:, recommendations:)
  @game = game
  @recommendations = recommendations.to_a
end
```

**Template structure (`recommended_channels_section_component.html.erb`):**

- Outer `<section class="game-recommended-channels"
  aria-label="<%= t('games.show.recommended_channels.aria') %>">`.
- `<h2><%= t("games.show.recommended_channels.heading") %></h2>`
  — copy: `recommended channels` (lowercase, matches existing
  section heading style; see `summary_heading`, `videos_heading`,
  `similar_heading`).
- When `@recommendations.empty?`:
  - Render `<p class="text-muted"
    style="margin: 0;"><%= t("games.show.recommended_channels.empty") %></p>`.
  - Empty copy: `no good fits yet — sync your channels first.`
    (lowercase, ends with period, matches the project's flash
    copy style).
- When `@recommendations.any?`:
  - `<ul class="recommended-channels-list">` containing one
    `<li>` per recommendation, rendered via
    `Games::ChannelRecommendationRowComponent.new(
      channel: rec[:channel], score: rec[:score])`.
  - No show-more toggle in v1. The service-side `limit: 8` cap is
    the hard cap. (Show-more is an open question deliberately
    deferred — see §"Open questions".)

**Public methods:**

- `#empty? → Boolean` — true when `@recommendations.empty?`.
- `#recommendations → Array` — pass-through reader for tests.

### `Games::ChannelRecommendationRowComponent`

**Constructor:**

```ruby
def initialize(channel:, score:)
  @channel = channel
  @score   = score
end
```

**Template structure
(`channel_recommendation_row_component.html.erb`):**

Renders a single `<li>` row with FLEX layout:

- Left cluster: avatar tile + display name + handle, all inside
  `<a href="<%= channel_path(@channel) %>"
  class="recommended-channel-link">`.
- Right cluster: score badge.

Avatar tile rendering rules (LOCKED — copy from
`Channels::AvatarChipComponent` template, not re-invented):

- Square dimensions equal to **1.4em + 4px** (matches the canonical
  channel-avatar tile sizing per design.md §"Channel avatars" and
  `app/components/channels/avatar_chip_component.rb` L72-L79).
- Circular: `border-radius: 50%` (locked 2026-05-19, design.md
  §"Channel avatars" — DO NOT use 2px radius for channel
  avatars).
- 1px border `var(--color-border)`.
- `object-fit: cover`.
- When `@channel.avatar_url.blank?` → render the bordered empty
  circle placeholder (no initials, no glyph, per design.md). Same
  `<span>` shape `Channels::AvatarChipComponent` uses for its
  no-avatar branch.

Display name rendering:

- `<span class="recommended-channel-name"><%= @channel.title.presence
  || @channel.handle.presence || em_dash %></span>`. The em-dash
  fallback is the project's `—` convention.

Handle rendering:

- `<span class="text-muted recommended-channel-handle"><%=
  @channel.handle %></span>` ONLY when `@channel.handle.present?`.
  Otherwise omit the span entirely.

Score badge rendering (v1 — locked):

- A bracketed muted-styled number on the right, mirroring the
  bracketed-link convention but **non-interactive** (it's a label,
  not a link). Markup:
  `<span class="recommended-channel-score" aria-label="<%=
  t('games.show.recommended_channels.score_aria', score: @score)
  %>">[<%= @score %>]</span>`.
- Locked styling (architect choice — confirms over open question
  #1):
  - Plain bracketed number, no color grading in v1 (lets v1 ship
    fast without a new color token; color grading is a v1.1
    follow-up if the user wants more visual signal).
  - Right-aligned in the row via flex.
  - Bold via the project's `.bracketed` family OR plain weight —
    implementation agent inherits whichever the project's bracketed-
    label primitive supplies. Reuse, don't fork.

**Public methods:**

- `#score → Integer`
- `#channel → Channel`
- `#avatar_url → String | nil`
- `#display_name → String`
- `#handle → String | nil`

---

## I18n keys

Add under `games.show.recommended_channels.*`:

| Key | Value |
| --- | --- |
| `games.show.recommended_channels.heading` | `recommended channels` |
| `games.show.recommended_channels.aria` | `recommended channels` |
| `games.show.recommended_channels.empty` | `no good fits yet — sync your channels first.` |
| `games.show.recommended_channels.score_aria` | `match score %{score} out of 100` |

Lowercase except where the project's brand-capitalization rule
applies (none here). Period on the empty-state copy follows the
project flash-copy convention.

---

## CSS

Add minimal styling to `app/assets/tailwind/application.css` (NOT a
new stylesheet). All values reuse existing tokens.

```css
.game-recommended-channels h2 {
  margin-top: 0;
}

.recommended-channels-list {
  list-style: none;
  margin: 0;
  padding: 0;
}

.recommended-channels-list > li {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 4px 0;
}

.recommended-channel-link {
  display: flex;
  align-items: center;
  gap: 8px;
  flex: 1 1 auto;
  min-width: 0; /* allow the name to ellipsize inside flex */
}

.recommended-channel-name {
  font-weight: 700;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.recommended-channel-handle {
  white-space: nowrap;
}

.recommended-channel-score {
  flex: 0 0 auto;
  font-variant-numeric: tabular-nums;
  font-weight: 700;
}
```

No new color tokens. No new font sizes. The 4px vertical row padding
matches the project's compact-list rhythm; the implementation agent
may swap to a project-canonical class if one exists.

---

## Future extensibility (post-/videos)

User locked on 2026-05-19: future iterations will incorporate
per-video signals into channel embeddings. Design the embedding
pipeline so this growth happens INSIDE the indexer; no caller
(`Games::ChannelRecommendation`, the controller, the view) needs to
change.

### Today (v1) — channel-text-only embedding

`channel.summary_embedding` is the Voyage embedding of
`[title, handle, description, keywords].compact.join("\n")`.

### Future (v2) — channel-text + per-video centroid

When `/videos` returns and per-video Voyage embeddings exist on the
`videos` table, the channel embedding becomes a centroid of:

- The channel-level text vector (today's v1 embedding).
- Per-video vectors for the top N videos (by view-count) on the
  channel, each embedded from `video.title + tags + description`.

Aggregation candidates (decision deferred until v2 design):

- **Equal blend** — `final = 0.5 * channel_text_vector + 0.5 *
  mean(video_vectors)`.
- **View-count-weighted blend** — `final = 0.5 * channel_text_vector
  + 0.5 * sum(view_count_i * video_vector_i) / sum(view_count_i)`.
- **Pure centroid** — `final = mean([channel_text_vector,
  video_vector_1, ..., video_vector_N])`.

This mirrors the way `Bundles::VoyageIndexer` already composites a
bundle name + up to 5 member-game summaries before embedding. The
composition lives entirely inside the indexer; the database column
type (1024-dim vector), the HNSW index, the service contract, and
the view all stay identical.

### Service contract stability across v1 → v2

- `Games::ChannelRecommendation.call(game, limit:)` signature: same.
- Hash keys: same (`:channel`, `:score`, `:distance`).
- View component constructor args: same.
- `Channels::VoyageIndexer.call(channel)` signature: same.
- Only the indexer's private composite-text / composite-vector
  method grows.

### Field carry-over

The `:distance` Hash key is retained across versions to support A/B
comparison logging during the v1 → v2 migration. The view never
renders `:distance`; it exists for service-side introspection only.

---

## Behavior contracts

- The service is pure: same input game embedding + same channel
  embedding set → same Array. No randomization, no time-of-day
  jitter.
- The component is pure given its constructor args. It does not
  query the database, the embedding columns, or the cache. All
  data flows in via `recommendations:`.
- The view template inserts ONE `<hr class="hairline">` and ONE
  `<%= render %>` call. No other line of `show.html.erb` is
  changed.
- The recommended-channel row's anchor target is
  `channel_path(channel)`. Friendly URL resolution rides on the
  existing `Channel#to_param` override (see
  `app/models/channel.rb` L23-L25).
- When the same game is rendered repeatedly (page refresh) the
  recommendations Array MUST be deterministic given a stable
  embedding set — the tie-break rule (`:score` desc → `Channel#id`
  asc) enforces this. The view spec asserts row order.
- The Voyage indexer is idempotent. Calling
  `Channels::VoyageIndexer.call(channel)` twice with no intervening
  text change writes the same 1024-dim vector both times.
- The model's `after_save_commit` guard only enqueues the job when
  one of the four embedded columns (`title`, `handle`,
  `description`, `keywords`) actually changed. The spec asserts
  this guard.

---

## Empty / edge state matrix

| State | Service returns | View renders |
| --- | --- | --- |
| Game has no `summary_embedding` | `[]` | Empty-state copy |
| No channels with a `summary_embedding` | `[]` | Empty-state copy |
| Voyage API key un-configured (indexer skipped silently for all channels) | `[]` (no channels carry a vector) | Empty-state copy |
| Hits exist but all below threshold 25 | `[]` | Empty-state copy |
| 1+ hits at or above threshold 25 | Up-to-`limit` Array | Row list |
| Mid-flight resync (`game.resyncing?` true) | Service still runs against the current persisted embedding | Section renders (the v1 surface does not show a "syncing" state — out of scope) |
| Channel row deleted between query and render | Rare race — `nearest_neighbors` materializes rows before return so this is essentially impossible; if it happens the row falls out of the result naturally | N/A |
| Unexpected exception during the cosine query | Rescued, logged WARN, returns `[]` | Empty-state copy |

---

## Spec coverage (mandatory pyramid sweep)

### Migration spec

Not a separate file — the column + index are exercised by the model
spec and indexer spec. The migration runs as part of
`bin/rails db:test:prepare`; CI catches any schema regression.

### Indexer spec
`spec/services/channels/voyage_indexer_spec.rb`

- Channel with `description` blank AND `keywords` blank → returns
  without making a Voyage API call (WebMock asserts NO call) and
  without writing `summary_embedding`.
- Channel with all four embedded columns blank → no API call, no
  write.
- `AppSetting.voyage_configured?` false → no API call, no write.
- Happy path: title + description + keywords present → builds
  composite text, calls Voyage, writes the returned 1024-dim
  vector via `update_column` (assert callbacks did NOT re-fire).
- Voyage client returns `nil` → indexer does not write.
- Idempotence: stub Voyage to return the same vector twice; first
  call writes, second call writes the same vector (no exception).

### Job spec
`spec/jobs/channel_voyage_index_job_spec.rb`

- `perform(channel_id)` calls `Channels::VoyageIndexer.call` with
  the loaded channel.
- `perform` with a non-existent channel id → returns silently, no
  indexer call, no exception.

### Channel model spec
Extend `spec/models/channel_spec.rb`:

- `has_neighbors :summary_embedding` is declared (assert via
  `Channel.reflect_on_association`-style check or by calling
  `Channel.new.respond_to?(:nearest_neighbors)`).
- `after_save_commit` enqueues `ChannelVoyageIndexJob` when
  `title`, `handle`, `description`, or `keywords` changes (one
  assertion per column).
- `after_save_commit` does NOT enqueue when `star`,
  `last_synced_at`, or other non-embedding columns change.

### Service spec
`spec/services/games/channel_recommendation_spec.rb`

- Game with `nil` `summary_embedding` → returns `[]` without
  querying the channels table.
- Game with embedding but no channels indexed
  (`where.not(summary_embedding: nil)` empty) → returns `[]`.
- 3 channels indexed with cosine distances 0.05 / 0.50 / 0.85 →
  scores 95 / 50 / 15 → returns 2 entries (the 15 drops below
  threshold 25). Order descending.
- Limit honored: 12 channels indexed close to the game's vector,
  `limit: 5` → returns 5.
- Tie-break: two channels with identical distance → returned in
  ascending-id order.
- Unexpected exception inside the nearest-neighbor query → rescued,
  returns `[]`, logs at WARN.
- `:distance` key present in each Hash for debugging carry-over.

### Component specs

`spec/components/games/recommended_channels_section_component_spec.rb`:

- Renders the heading.
- Empty input → renders the empty copy, does NOT render the `<ul>`.
- Non-empty input → renders one `<li>` per recommendation, in input
  order.
- Aria-label on the outer `<section>` matches the i18n key.

`spec/components/games/channel_recommendation_row_component_spec.rb`:

- Renders avatar `<img>` with `border-radius: 50%` style fragment
  when `channel.avatar_url.present?`.
- Renders bordered empty `<span>` when `channel.avatar_url.blank?`.
- Renders display name with `font-weight: 700` (or the project's
  bold class).
- Renders handle when present; omits the handle span when blank.
- Renders `[score]` with the `recommended-channel-score` class.
- Outer link points at `channel_path(channel)`.
- Score aria-label uses the i18n key with the score interpolated.

### View spec
Extend `spec/views/games/show.html.erb_spec.rb`:

- Section heading `recommended channels` is present in the rendered
  HTML.
- The new section appears BEFORE the bundles section in the DOM
  (assert via index of substring or Nokogiri sibling ordering).
- The new section appears AFTER the time-to-beat block.
- When `@recommended_channels` is empty → empty-state copy
  rendered.
- When `@recommended_channels` is non-empty → row list rendered.

### Request spec
Extend `spec/requests/games_spec.rb`:

- `GET /games/:id` happy-path: assigns `@recommended_channels` (or
  the equivalent ivar — match the controller's chosen name);
  response body contains the section heading copy.

### No new system spec
The section is read-only HTML rendered server-side. The existing
`spec/system/games_show_revamp_spec.rb` is NOT extended in v1
(system specs stay thin; per `docs/agents/architect.md` rule D.10).

---

## Cross-stack scope

- **Rails web** — IN SCOPE. The complete surface of this spec.
- **MCP** — OUT OF SCOPE in v1. No new MCP tool. (A future
  `recommended_channels_for_game` tool is a reasonable follow-up
  once the v1 surface stabilizes; flagged as a follow-up only,
  not a scope item.)
- **`pito` CLI / TUI** — OUT OF SCOPE (project-wide web-polish
  focus per the current memory note; CLI / MCP are paused).
- **Astro website** — N/A.

---

## Manual test recipe

1. Start the stack: `bin/dev`. Confirm the Voyage API key is
   configured (`bin/rails console` →
   `AppSetting.voyage_configured?` returns `true`).
2. Run the migration: `bin/rails db:migrate`. Confirm
   `db/schema.rb` now lists `summary_embedding` on `channels` plus
   `index_channels_on_summary_embedding_hnsw`.
3. Ensure at least 2-3 channels exist locally with `title`,
   `description`, and `keywords` populated. From `bin/rails
   console`:
   `Channel.first.update(title: "Test Channel", description:
   "Souls-like deep-dive lore", keywords: "souls action rpg")` for
   2-3 rows. The `after_save_commit` hook fires
   `ChannelVoyageIndexJob`.
4. Watch Sidekiq (the `bin/dev` log) — the indexer should complete
   within a second per channel. Confirm
   `Channel.first.reload.summary_embedding.size == 1024` in console.
5. Bulk-reindex backstop:
   `bin/rails pito:voyage:reindex_channels`. Confirm every channel
   ends with a populated vector.
6. Open `/games/<slug>` for a game whose summary intersects the
   channel descriptions ("Elden Ring", "Dark Souls III", etc.
   against a "souls" keyword channel).
7. Confirm the `recommended channels` heading appears in the RIGHT
   pane, BETWEEN the time-to-beat block and the bundles section.
8. Confirm each row shows:
   - A circular avatar tile (or a bordered empty circle when no
     `avatar_url`).
   - Channel display name bold + muted handle to its right.
   - A `[NN]` score on the right edge of the row, where `NN ∈
     25..100`.
   - Hovering shows the link cursor; clicking navigates to
     `channel_path(channel)`.
9. Confirm rows are sorted descending by score (top row's score is
   the largest).
10. Open a game whose semantic content does NOT match any channel
    (e.g. a cosy farming sim against a souls-only channel set).
    Confirm the section renders the empty-state copy `no good fits
    yet — sync your channels first.` (every hit dropped below the
    threshold).
11. Open a game with `summary_embedding` still `nil` (a freshly
    seeded game before Voyage runs). Confirm the section renders
    the empty-state copy and `/games/:id` returns 200.
12. Confirm Omnisearch (the everywhere modal) still finds channels
    by text query — the Meilisearch channel index is untouched and
    still serves text autocomplete. Type a channel keyword into
    the modal and verify channel hits appear.
13. Confirm the bundles section, similar shelf, and videos block
    below the new section render identically to before — no
    regression.

Teardown: restore any updated Channel rows from a fresh sync, or
roll back the manual `update` calls via `bin/rails console`.

---

## Open questions (for master to resolve before implementation
dispatch)

1. **Score badge styling — color-graded vs plain bracketed.** The
   spec locks plain bracketed (`[92]`) for v1. The user proposed
   four options (plain, bracketed, bar+number, color-graded).
   **Architect recommends plain bracketed for v1**, with
   color-grading deferred to a v1.1 follow-up if the user wants
   more visual signal. Confirm before dispatch.
2. **Show-more pagination.** The spec locks no show-more in v1; the
   `limit: 8` service-side cap is the hard ceiling. **Architect
   recommends keeping it hard-capped at 8 for v1** — a show-more
   affordance adds Stimulus controller surface area for a section
   that hasn't proven its value yet. Revisit if the user finds 8
   too few.
3. **Sort direction.** Descending by score, locked.
4. **Threshold floor.** Locked at 25. The user can dial this if v1
   feels noisy after manual testing.
5. **Service location.** Spec proposes `app/services/games/
   channel_recommendation.rb`. The alternative would be
   `app/services/channels/recommendation_for_game.rb` if the
   project treats the channels namespace as the "owning" side.
   **Architect recommends `Games::ChannelRecommendation`** because
   the consumer is `/games/:id`; the function returns "channels
   for a game", parallel to `Games::SimilarGames` returning "games
   similar to a game". Confirm before dispatch.
6. **Per-stack add — should the MCP tool surface get a
   `recommended_channels_for_game` companion now?** The current
   memory note "Web polish focus — MCP + TUI paused" suggests NO,
   but flag it for confirmation.
7. **HNSW index parameters.** The spec instructs the implementation
   agent to mirror the bundles HNSW index `m` /
   `ef_construction` knobs verbatim from `db/schema.rb`. If the
   bundles index does NOT yet exist in schema or uses different
   values than the user expects, escalate before running the
   migration.
