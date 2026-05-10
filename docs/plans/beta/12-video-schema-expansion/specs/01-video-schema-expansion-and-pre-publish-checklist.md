# Phase 12 — Video Schema Expansion + Edit Surface + Pre-Publish Checklist

> **Status:** dispatched 2026-05-10. Single primary lane: **rails**. CLI parity
> is out of scope (realignment work unit 10). MCP parity is in scope as a
> sub-lane (`mcp-impl`).
>
> **Cross-references:**
>
> - `docs/realignment-2026-05-09.md` — work unit 4. Resolved ambiguities #1
>   (Timeline drop → direct `Video.project_id`), #7 (checklist fires only on
>   publish / schedule transitions), #10 (Path A2 retired; every Video is
>   "owned").
> - `docs/notes/2026-05-09-17-56-06-video-model-youtube-api.md` — Mobile note 1,
>   the Video schema source of truth (Data API v3 fields, destructive-PUT-per-
>   part warning, OAuth scopes, quota costs, Studio-only fields).
> - `docs/notes/2026-05-09-18-02-30-video-model-addendum-end-screen.md` — Mobile
>   note 2, end-screen addendum to the pre-publish checklist.
> - `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — single-
>   install, multi-user; Path A2 retired.
> - `docs/decisions/0006-drop-sign-in-with-google-channel-only-oauth.md` —
>   `YoutubeConnection` (renamed from `GoogleIdentity` in Phase 9). Video
>   reaches the connection through Channel.
> - `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
>   — schema baseline (no `tenant_id`, thin User).
> - `docs/plans/beta/09-login-with-google-drop/specs/01-google-identity-rename.md`
>   — `youtube_connection_id` foreign key naming this phase inherits.
> - `CLAUDE.md` — top-level project rules (yes/no booleans at boundaries, no JS
>   `confirm` / `alert` / `prompt`, secrets in `Rails.application.credentials`,
>   monospace 13px, bracketed link convention, bulk-as-foundation URL pattern).

## Goal

Reverse Path A2's literal full retract for `Video`. Bring back the full Data API
v3-modeled field set (per Note 1's "Suggested `Video` model shape" plus Note 1's
"Fields we model" table) so the YouTube management workflow has real data to
render and edit. Add the writable-subset edit surface in the web app with
read-modify-write semantics on the destructive `videos.update` PUT-per- part
API. Add the four-item pre-publish checklist modal (game / age / paid promotion
/ end screen) gating publish-state transitions. Wire `Video` to `Project`
directly via a nullable `project_id` foreign key — the dropped Timeline model's
intermediary role collapses into this single column.

This is realignment work unit 4. It is the prerequisite for the analytics sync
engine (work unit 5 / Phase 13), since the cross-video-locals queries (when-
to-publish, best-duration, topics-that-work, thumbnail-decay) depend on real
`Video.published_at` / `Video.category_id` / `Video.tags[]` columns to join
against.

The user is the install operator. There is no per-user data isolation. Every
Video belongs to a Channel which belongs (optional) to a `YoutubeConnection`;
the connection's OAuth grant authorizes the sync-back call. Imported / pre- pito
videos (those that existed before pito's publish flow ever ran) keep
`pre_publish_checked_at = NULL`; the checklist surface never fires on them.

## Resolved design decisions (LOCKED — do not re-litigate)

| Q   | Decision                                                                                                                                                                                                                                                                                                                                            |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q1  | **Project ↔ Video association.** Direct nullable `videos.project_id` foreign key. NO Timeline intermediary. Imported videos: `project_id IS NULL`. Future videos: `project_id` assigned at creation (or by edit). Project page lists linked videos via direct join. `dependent: :nullify` on Project deletion (preserve Videos).                    |
| Q2  | **Pre-publish checklist scope.** Fires ONLY on publish-state transitions: `private` → `public`, `private` → `unlisted`, OR setting `publish_at` while `privacy_status=private` (scheduled publish). Metadata edits on already-`public` / `unlisted` videos skip the checklist. Going `public` → `private` skips the checklist.                      |
| Q3  | **Tenant-free schema.** No `tenant_id` on Video, no `tenant_id` on the new pre-publish-check table, no `tenant_id` on the new `playlist_videos` join. Phase 8 has already dropped tenant scoping at the schema level.                                                                                                                               |
| Q4  | **Connection lookup path.** Video → Channel → YoutubeConnection. Video does NOT carry a direct `youtube_connection_id` foreign key. The sync-back job fetches `video.channel.youtube_connection` and uses that grant.                                                                                                                               |
| Q5  | **Edit surface scope.** Web-app-only in this phase. The edit form covers the writable subset (Note 1's ✅ Write column): `title`, `description`, `tags`, `category_id`, `privacy_status`, `publish_at`, `self_declared_made_for_kids`, `contains_synthetic_media`. Thumbnail upload is a follow-up (separate `thumbnails.set` endpoint, multipart). |
| Q6  | **Imported video shape.** No "imported" boolean column. The semantic is implicit: `pre_publish_checked_at IS NULL AND privacy_status IN ('public', 'unlisted')` describes a video that was already public when pito first synced it. The checklist surface keys on `pre_publish_checked_at IS NULL` AND a publish/schedule transition target.       |
| Q7  | **Pre-publish-check storage shape.** Architect picks: a single `pre_publish_checked_at` timestamp + four boolean columns on `videos` (one per check). A separate join table is over-engineered for four fixed checks that fire once per publish. See "Open questions" #1 for the alternative considered.                                            |
| Q8  | **Sync-back posture.** Background job (`Sidekiq`). Controller enqueues, returns immediately, Turbo-streams the result. Synchronous-in-controller is rejected because `videos.update` is a 50-unit quota call with real network latency; the user shouldn't watch a spinner.                                                                         |
| Q9  | **`videos.update` part assembly.** Read-modify-write the entire `snippet` and `status` parts on every save, per Note 1's destructive-PUT-per-part warning. The job re-reads the video before updating (one extra `videos.list` call per save) to guarantee no field gets stomped.                                                                   |
| Q10 | **Path A2 retired entirely.** No "owned vs. tracked" distinction (per realignment Resolved ambiguity #10). Every video pito tracks is owned. The thin retract shape is replaced wholesale by the expanded shape; the comments referencing Path A2 in `app/models/video.rb` and `spec/factories/videos.rb` get rewritten.                            |
| Q11 | **`star` column survives.** Existing `videos.star` boolean stays as the personal-favorites primitive. Independent of the schema expansion.                                                                                                                                                                                                          |
| Q12 | **Decorator stays.** `VideoDecorator#as_summary_json` / `#as_detail_json` (used by the CLI) get expanded to surface the new fields. CLI parity (consuming the new shape) is realignment work unit 10; this phase only updates the decorator's serialization surface so the new JSON shape is reachable.                                             |

## Migration posture (LOCKED)

**Additive on the post-Phase-8/9 schema.** By the time this phase lands:

- Phase 8 has dropped `tenant_id` everywhere and reseeded the DB.
- Phase 9 has renamed `google_identities` → `youtube_connections` and the FK
  columns to `youtube_connection_id`.
- The `videos` table is in the post-Phase-8/9 thin shape.

This phase therefore migrates **additively**: `add_column` for new fields,
`create_table` for the new `playlist_videos` join, `add_foreign_key` for
`videos.project_id`. No `drop_column`, no `rename_table`. The destructive-
and-reseed posture from ADR 0003 covered the tenant unwind; this phase inherits
a stable post-tenant schema and grows it.

If the implementation agent finds a column already exists (e.g., the user has
run an earlier ad-hoc migration), STOP and surface — do not silently reuse.

Rollback is permitted (the migration is mechanically reversible) but is not a
hard requirement; document a `change` block where Rails can auto-reverse and a
manual `up` / `down` only where it cannot.

## Files touched

### Schema / migration

- `db/migrate/<NN>_expand_videos_for_data_api_v3.rb` (new) — the central schema
  migration. Rails 8.1-conventional `<YYYYMMDDHHMMSS>_*.rb`. Scope per the
  "Schema migration" section below.
- `db/migrate/<NN>_create_playlist_videos.rb` (new, OR folded into the central
  migration — implementation agent picks; recommendation: folded in for
  atomicity).
- `db/schema.rb` — auto-regenerated. Acceptance check: every column listed in
  the "Schema migration" section appears with the declared type + nullability +
  default.

### Models

- `app/models/video.rb` (heavy edit) — see "Model layer" section.
- `app/models/project.rb` (light edit) — add
  `has_many :videos, dependent: :nullify`.
- `app/models/playlist_video.rb` (new) — join model for `playlist_videos`.
- `app/models/playlist.rb` (light edit) — add
  `has_many :playlist_videos, dependent: :destroy` and
  `has_many :videos, through: :playlist_videos`.
- `app/models/channel.rb` (light edit, possibly none) — verify
  `has_many :videos, dependent: :destroy` survives the schema expansion; no
  functional change needed.
- `app/models/youtube_connection.rb` (light edit, possibly none) — verify
  `has_many :videos, through: :channels` reads cleanly. If absent, add it for
  convenience.

### Concerns

- `app/models/concerns/searchable.rb` — already mixed into `Video`. The
  expansion makes it useful for the first time (title / description / tags
  become real). The spec adds `searchable :title, :description`,
  `searchable_array :tags`, `filterable :privacy_status, :category_id`
  declarations on `Video`. (Per the realignment doc, full Meilisearch indexing
  is a separate follow-up; the Searchable concern stays declarative-only here.
  Read CLAUDE.md / `docs/realignment-2026-05-09.md` Modify section for the "keep
  stubbed, re-evaluate" posture.)

### Controllers

- `app/controllers/videos_controller.rb` (heavy edit) — add `edit`, `update`,
  `pre_publish_checklist`, `publish`, `schedule` actions. Existing `index` /
  `show` / `destroy` / `stats` / `panes` survive unchanged in flow but pick up
  new columns in their queries / decorator output.

### Routes

- `config/routes.rb` (light edit) — extend the `resources :videos` block:
  - `member do; get :edit; patch :update; get :pre_publish_checklist; patch :publish; patch :schedule; end`
  - The pre-publish-checklist GET renders the modal partial (Turbo Frame). The
    publish / schedule PATCHes are separate from `update` so a metadata edit can
    never accidentally trigger a publish-state transition without going through
    the checklist gate.

### Views (ERB)

- `app/views/videos/edit.html.erb` (new) — full edit form.
- `app/views/videos/_form.html.erb` (new) — the editable form fragment
  (extracted so MCP / programmatic update can share the strong-params
  declaration via `VideoEditPolicy` or equivalent — see "Open questions" #2).
- `app/views/videos/_pre_publish_modal.html.erb` (new) — the four-item checklist
  modal. Turbo Frame target. NO JS `confirm()`. Stimulus controller drives
  checkbox-state-to-submit-disabled; the dialog itself is rendered with the
  existing action-screen pattern OR a Turbo Frame modal — implementation agent
  picks; see "Open questions" #3.
- `app/views/videos/show.html.erb` (light edit) — surface new fields in read
  mode. If `video.project_id` is set, render a "part of project: [ name ]" link
  near the title.
- `app/views/videos/index.html.erb` (light edit) — surface `privacy_status`
  (icon or text) in the row, surface `pre_publish_checked_at` state for videos
  that have been through the pito publish flow vs. imported.
- `app/views/projects/show.html.erb` (light edit) — list of linked videos via
  `@project.videos.order(published_at: :desc)`.
- `app/views/shared/_studio_link.html.erb` (new) — small partial rendering the
  `https://studio.youtube.com/video/<youtube_video_id>/edit` deep-link with the
  bracketed-link convention and `cursor: pointer`. Reused from the
  pre-publish-modal for each Studio-only field.

### Stimulus controllers

- `app/javascript/controllers/pre_publish_checklist_controller.js` (new) —
  disables the [ confirm publish ] button until all four checkboxes are checked.
  `unsaved-form`-style discipline. NO `window.confirm`, NO `alert`. The Stimulus
  controller mutates a `disabled` attribute and surfaces inline state. The
  `data-turbo-confirm` attribute MUST NOT be used (CLAUDE.md hard rule).
- `app/javascript/controllers/index.js` — register the new controller.

### Jobs

- `app/jobs/video_sync_back.rb` (new) — pulls a Video, reads-modify- writes the
  YouTube `snippet` + `status` parts via the YoutubeConnection grant. Uses
  `Youtube::Client` (Phase 7 foundation, post-Phase-9 rename carried). Records
  the call in `youtube_api_calls`. On success, stamps `last_synced_at` and
  `etag`. On 4xx / 5xx, surfaces the error to the Video record (a
  `last_sync_error` text column — see "Schema migration" #16). Naming follows
  the existing `ChannelSync` flat-name precedent (`channel_sync.rb`); however,
  since this is a write-back job not a read-sync job, the architect names it
  `VideoSyncBack` to keep the semantic explicit. (See "Open questions" #4.)
- `app/jobs/video_publish.rb` (new) — wraps `VideoSyncBack` with the
  publish-state-transition flow: validates the four pre-publish booleans are
  true, sets `privacy_status` (and optionally `publish_at`), enqueues the
  sync-back. If sync-back fails, reverts `privacy_status` to its prior value and
  stamps `last_sync_error`.

### Services / clients

- `app/services/youtube/videos_client.rb` (new, OR extend an existing
  `Youtube::Client` namespace from Phase 7). Single-method surface:
  `update_video(video)` — assembles the read-modify-write payload, hits
  `videos.update?part=snippet,status`, returns the parsed response / raises a
  typed error on failure. Quota: 50 units per call (record in
  `youtube_api_calls` per Phase 7 audit pattern).
- `app/services/youtube/videos_reader.rb` (new, OR extend) — single- method
  surface: `read_video(video)` — hits
  `videos.list?part=snippet, status,contentDetails` for a fresh read before
  write. Quota: 1 unit.

### Decorators

- `app/decorators/video_decorator.rb` (heavy edit) — `as_summary_json` /
  `as_detail_json` extend with the new fields. The CLI will pick them up when
  work unit 10 runs.

### MCP tools

- `app/lib/mcp/tools/update_video.rb` (new, OR extend the placeholder from
  realignment "MCP tool catalog expansion" if any). Declares the writable-subset
  input schema. `confirm: yes/no` two-step pattern (per CLAUDE.md hard rule).
  Gated on the `app` MCP scope (per ADR 0004).
- `app/lib/mcp/tools/pre_publish_check_video.rb` (new) — flips the four
  pre-publish booleans + `pre_publish_checked_at` for a video. Two-step
  `confirm: yes/no`. Gated on `app`.
- `app/lib/mcp/tools/publish_video.rb` (new) — wraps the publish-state
  transition. Validates pre-publish booleans first; rejects with a clear error
  if any are false. Two-step `confirm: yes/no`. Gated on `app`.
- `docs/mcp.md` (light edit, follow-up — docs-keeper handles after user
  validation) — add the three tools to the scope-per-tool table.

### Strong params / authorization

- `app/policies/video_policy.rb` (new, OR extend) — Pundit-style policy if the
  project uses it; otherwise inline strong-params. Declare the permitted
  attributes for `update`. Smuggling guard: `youtube_video_id`, `channel_id`,
  `etag`, `last_synced_at`, `pre_publish_checked_at`, `made_for_kids_effective`,
  `last_sync_error` are NOT permitted via the form. The policy is enforced by
  `videos_controller#video_params`.

### Tests

See "Test sweep" section. New / edited spec files:

- `spec/models/video_spec.rb` (heavy rewrite)
- `spec/models/project_spec.rb` (light edit — `has_many :videos`)
- `spec/models/playlist_video_spec.rb` (new)
- `spec/models/playlist_spec.rb` (light edit — `has_many :videos`)
- `spec/factories/videos.rb` (heavy rewrite — drop tenant, add new fields)
- `spec/factories/playlist_videos.rb` (new)
- `spec/requests/videos_spec.rb` (heavy rewrite — covers `edit`, `update`,
  `pre_publish_checklist`, `publish`, `schedule`)
- `spec/requests/projects_spec.rb` (light edit — linked-videos list)
- `spec/jobs/video_sync_back_spec.rb` (new)
- `spec/jobs/video_publish_spec.rb` (new)
- `spec/services/youtube/videos_client_spec.rb` (new)
- `spec/services/youtube/videos_reader_spec.rb` (new)
- `spec/decorators/video_decorator_spec.rb` (heavy rewrite if it exists,
  otherwise new)
- `spec/lib/mcp/tools/update_video_spec.rb` (new)
- `spec/lib/mcp/tools/pre_publish_check_video_spec.rb` (new)
- `spec/lib/mcp/tools/publish_video_spec.rb` (new)
- `spec/system/video_pre_publish_checklist_spec.rb` (new — Capybara end-to-end
  of the modal flow)

### Out of scope (this phase)

- CLI parity (`extras/cli/`). Realignment work unit 10. The CLI consuming the
  expanded JSON shape is a separate dispatch.
- Channel schema expansion (work unit 3). Channel may also need the `title`,
  `subscriber_count`, etc. expansion before the project-page video listing reads
  cleanly. If Channel is still in the thin shape when this phase ships, the
  project page falls back to displaying the channel's URL slug. See "Open
  questions" #5.
- Analytics tables / sync engine (work unit 5 / Phase 13).
- Game ↔ Video links (work unit 6 / Phase 14).
- Calendar `video_published` / `video_scheduled` derivation (work unit 7).
- Notifications on video state changes (work unit 8).
- Thumbnail upload via `thumbnails.set` (separate multipart endpoint).
- Playlist membership editing UX (the schema lands; the UX to add / remove /
  reorder is a follow-up).
- Captions, recording-date, recording-location, default-language,
  default-audio-language, embeddable, public-stats-viewable, license — Note 1's
  "Fields we model" table only marks 8 fields with ✅ in both Read and Write.
  Stay disciplined: model exactly that set in this phase; everything else is a
  follow-up if-and-when needed.

## Schema migration

The migration adds the columns and tables below. All column types are
Postgres-native unless noted. All `add_index` lines are explicit so the schema
dump is auditable.

### `videos` table — column additions

1. **`youtube_video_id`** — already exists (string, unique). No change. It IS
   the YouTube-side primary key mirror per Note 1's "Suggested `Video` model
   shape" first bullet. Validate
   `presence: true, uniqueness: { case_sensitive: false }` already in place.

2. **`title`** — `add_column :videos, :title, :string, limit: 100`. NOT NULL
   with `default: ""` to allow synced-but-not-yet-populated rows; model- level
   validation enforces `presence: true` for active records (a stronger
   validation runs on `published` records — see "Model layer"). Index: none
   (search via Searchable / Meilisearch when that lands).

3. **`description`** — `add_column :videos, :description, :text`. Nullable. No
   default. Note 1: max 5000 bytes UTF-8, no `<` or `>`. Validation in the
   model.

4. **`tags`** — `add_column :videos, :tags, :jsonb, default: [], null: false`.
   Stored as a JSON array of strings. Note 1: total length ≤ 500 chars; tags
   containing spaces are quoted internally and the quotes count. Validation in
   the model. Index: `add_index :videos, :tags, using: :gin` (so future "videos
   with tag X" queries are cheap; the analytics phase needs this).

5. **`category_id`** — `add_column :videos, :category_id, :string`. Nullable for
   synced-but-not-yet-populated rows; required (model validation) on update of
   the `snippet` part. Numeric string per the YouTube API. Note 1: required when
   updating the `snippet` part. Renaming-conflict note: `category_id` is a
   generic name. Some Rails apps reserve it for a `Category` association. We do
   NOT have a Category model and there's no plan to add one. Acceptable.

6. **`thumbnail_url`** — `add_column :videos, :thumbnail_url, :string`.
   Nullable. Stores the chosen tier (Note 1's recommendation: `maxres` falling
   back to `high`). The `Youtube::VideosReader` resolves the tier. The model has
   a small helper that prefers `maxres` over `high`.

7. **`privacy_status`** —
   `add_column :videos, :privacy_status, :integer, default: 0, null: false`.
   `enum privacy_status: { private: 0, public: 1, unlisted: 2 }`. Note 1:
   `public` | `private` | `unlisted`. Index:
   `add_index :videos, :privacy_status` (filter on the index page).

8. **`publish_at`** — `add_column :videos, :publish_at, :datetime`. Nullable.
   ISO 8601 / `timestamptz`. Note 1: scheduling uses `publishAt` while keeping
   `privacyStatus=private` in the same call; a past `publishAt` publishes
   immediately. Index:
   `add_index :videos, :publish_at, where: "publish_at IS NOT NULL"` — partial
   index for the scheduler-cron job that fires reminders / notifications when a
   scheduled-publish window approaches.

9. **`published_at`** — `add_column :videos, :published_at, :datetime`.
   Nullable. The actual publish time as reported by the API. Distinct from
   `publish_at` (which is the scheduled-publish hint). Index:
   `add_index :videos, :published_at`. Used by the project page (linked videos
   ordered by `published_at desc`) and the future analytics cross-video locals
   (when-to-publish).

10. **`self_declared_made_for_kids`** —
    `add_column :videos, :self_declared_made_for_kids, :boolean, default: false, null: false`.
    Note 1: `status.selfDeclaredMadeForKids`. Owner-only on read. Writable.

11. **`made_for_kids_effective`** —
    `add_column :videos, :made_for_kids_effective, :boolean, default: false, null: false`.
    Note 1: read-only mirror of `status.madeForKids`. Synced-only — never
    accepted from a form. The strong-params policy explicitly omits this.

12. **`contains_synthetic_media`** —
    `add_column :videos, :contains_synthetic_media, :boolean, default: false, null: false`.
    Note 1: `status.containsSyntheticMedia`. Writable.

13. **`etag`** — `add_column :videos, :etag, :string`. Nullable. Note 1: "for
    conditional updates." Stored opaque; passed through on `videos.update` calls
    if/when the API supports `If-Match`-style headers. (Today YouTube returns
    the etag but does not gate updates on it; we still store it for forward
    compatibility.)

14. **`last_synced_at`** — already exists (datetime). No change. Stamped by the
    sync-back job after a successful `videos.update`.

15. **`pre_publish_checked_at`** —
    `add_column :videos, :pre_publish_checked_at, :datetime`. Nullable. Stamped
    when the user ticks all four pre-publish checkboxes AND submits the publish
    / schedule action. NULL means "the checklist has never been completed for
    this video" — either it's a draft, or it's an imported pre-pito video. The
    publish surface keys on this column being non-null AND the four boolean
    columns all being true before allowing the privacy_status transition.

16. **`pre_publish_game_ok`** —
    `add_column :videos, :pre_publish_game_ok, :boolean, default: false, null: false`.
    Stamped true when the user ticks "Game set correctly (if category = Gaming)"
    in the pre-publish modal. The "if category = Gaming" condition is a UI hint;
    the column is set unconditionally when the user ticks the box.

17. **`pre_publish_age_ok`** —
    `add_column :videos, :pre_publish_age_ok, :boolean, default: false, null: false`.
    Stamped true when the user ticks "Age restriction (18+) reviewed".

18. **`pre_publish_paid_promotion_ok`** —
    `add_column :videos, :pre_publish_paid_promotion_ok, :boolean, default: false, null: false`.
    Stamped true when the user ticks "Paid promotion declared if applicable".

19. **`pre_publish_end_screen_ok`** —
    `add_column :videos, :pre_publish_end_screen_ok, :boolean, default: false, null: false`.
    Stamped true when the user ticks "End screen reviewed" (Note 2 addendum).

20. **`last_sync_error`** — `add_column :videos, :last_sync_error, :text`.
    Nullable. Holds the most recent sync-back error message (e.g., "title too
    long", "auth token revoked"). Cleared on successful sync. Surfaced in the
    edit form as an inline warning.

21. **`project_id`** —
    `add_reference :videos, :project, foreign_key: { on_delete: :nullify }, null: true, index: true`.
    Direct nullable foreign key. Per Resolved decision Q1. The Timeline
    intermediary is dropped; this is its replacement.

22. **`duration_seconds`** — `add_column :videos, :duration_seconds, :integer`.
    Nullable. Sourced from `contentDetails.duration` (ISO 8601 duration parsed
    locally). Useful for the analytics best-duration cross-video local.

#### Removed indexes (post-Phase-8 cleanup carryover)

If Phase 8 left any `tenant_id` composite indexes on `videos`, this migration
removes them defensively. Verify against `db/schema.rb` before writing:
post-Phase-8 the schema should already be clean.

### `playlist_videos` join table

Per Note 1's "Playlist membership is a separate join: (video_id, playlist_id,
position)".

```ruby
create_table :playlist_videos do |t|
  t.references :playlist, null: false, foreign_key: { on_delete: :cascade }, index: true
  t.references :video, null: false, foreign_key: { on_delete: :cascade }, index: true
  t.integer :position, null: false, default: 0
  t.string :youtube_playlist_item_id, null: false
  t.timestamps
end

add_index :playlist_videos, [ :playlist_id, :video_id ], unique: true
add_index :playlist_videos, :youtube_playlist_item_id, unique: true
add_index :playlist_videos, [ :playlist_id, :position ]
```

The existing `playlist_items` table (carried from a pre-Path-A2 era — see
`db/schema.rb` lines 261-274) is functionally equivalent. The implementation
agent verifies whether `playlist_items` still exists post-Phase-8/9 and either:

- (a) Renames `playlist_items` → `playlist_videos` (preferred — the new name
  matches Note 1's terminology and avoids two tables for the same concept); OR
- (b) Drops `playlist_items` and creates `playlist_videos` fresh (if the table
  is empty post-reseed and a clean cut is simpler).

Recommendation: (a) rename. See "Open questions" #6.

### `Foreign keys to add`

- `videos.project_id → projects.id` (`ON DELETE SET NULL` — preserve videos when
  a project is deleted).
- `playlist_videos.playlist_id → playlists.id` (`ON DELETE CASCADE` — a
  playlist's join rows go with it).
- `playlist_videos.video_id → videos.id` (`ON DELETE CASCADE` — a deleted
  video's join rows go with it).

### `Foreign keys to verify`

- `videos.channel_id → channels.id` already exists. Confirm.
- `videos.youtube_connection_id → youtube_connections.id` exists post- Phase-9.
  Confirm. (NOT modified in this phase.)

## Model layer

### `Video`

Heavy edit. Replace the Path A2 retract framing wholesale.

Associations:

- `belongs_to :channel`
- `belongs_to :project, optional: true`
- `has_many :video_stats, dependent: :destroy`
- `has_many :playlist_videos, dependent: :destroy`
- `has_many :playlists, through: :playlist_videos`
- `has_one :youtube_connection, through: :channel` (convenience, not a
  belongs_to — the connection is reached transitively)

Validations:

- `youtube_video_id`: presence, uniqueness (case_insensitive). Existing.
- `title`: `length: { maximum: 100 }`. Forbid `<` and `>`
  (`format: { without: /[<>]/ }`). Required-when-published validation:
  `validates :title, presence: true, if: -> { privacy_status_changed? && (public? || unlisted?) }`.
  Less-strict for synced-but-draft rows.
- `description`: `length: { maximum: 5000 }` (UTF-8 byte count is the API's
  metric; Rails `length` validator counts characters by default — the model uses
  `length: { maximum: 5000 }` and a custom validator enforces
  `description.to_s.bytesize <= 5000` for byte-accuracy). Forbid `<` and `>`.
- `tags`: array of strings, total length when joined with quotes-for- spaces ≤
  500 chars. Custom validator (see "Validations: tags" below).
- `category_id`: presence required when `privacy_status` is being set to
  `public` / `unlisted` OR `publish_at` is being set (i.e., on publish- state
  transitions). Numeric string format (`format: { with: /\A\d+\z/ }`).
- `privacy_status`: enum-validated by Rails' enum macro. No additional validator
  needed.
- `publish_at`: must be in the future when set AND `privacy_status = private`
  (scheduled publish). Custom validator. Per Note 1, a past `publishAt`
  publishes immediately — our model still rejects it on the form to make the
  user's intent explicit; if they want immediate publish, they choose
  `privacy_status = public` directly.
- `pre_publish_checked_at`: no validation (set by the controller path).

Validations: `tags` — custom validator class:

```
# total chars when serialized API-side: each tag, plus quote pair if
# the tag contains a space, plus comma separators.
def validate_tags_total_length
  return if tags.blank?
  api_length = tags.sum do |tag|
    base = tag.to_s.length
    base += 2 if tag.to_s.include?(" ") # quotes
    base
  end
  api_length += [ tags.size - 1, 0 ].max # commas between tags
  errors.add(:tags, "are too long (max 500 API-side chars)") if api_length > 500
end
```

Enums:

- `enum privacy_status: { private: 0, public: 1, unlisted: 2 }, prefix: :privacy`.
  The prefix avoids method-name collisions (`Video#private?` is reserved by
  Object). Sources Note 1's three values.

Callbacks:

- `before_save :reset_pre_publish_checked_at_on_metadata_edit` — if any metadata
  field changes BUT privacy_status does not, do NOT reset the checklist. (The
  checklist persists across metadata edits; only re- publish from `private` /
  re-schedule re-asks.) See "Open questions" #7 for the alternative considered.
- `after_update_commit :enqueue_sync_back, if: :writable_field_changed?` —
  enqueues `VideoSyncBack` whenever a user-visible writable field changed. The
  condition method enumerates the writable fields (title, description, tags,
  category_id, privacy_status, publish_at, self_declared_made_for_kids,
  contains_synthetic_media).

Scopes:

- `scope :starred, -> { where(star: true) }` — existing, unchanged.
- `scope :published, -> { where(privacy_status: %i[public unlisted]) }`.
- `scope :draft, -> { where(privacy_status: :private, publish_at: nil) }`.
- `scope :scheduled, -> { where(privacy_status: :private).where.not(publish_at: nil) }`.
- `scope :pre_publish_complete, -> { where(pre_publish_game_ok: true, pre_publish_age_ok: true, pre_publish_paid_promotion_ok: true, pre_publish_end_screen_ok: true).where.not(pre_publish_checked_at: nil) }`.

Public methods:

- `pre_publish_complete?` — returns true when all four booleans are true AND
  `pre_publish_checked_at` is non-null.
- `studio_url` — returns
  `"https://studio.youtube.com/video/#{youtube_video_id}/edit"`.
- `imported?` — returns true when `pre_publish_checked_at IS NULL` AND
  `privacy_status` is `public` or `unlisted`. Used by the index page to surface
  the "imported (pre-pito)" indicator.

Searchable concern hooks:

- `searchable :title, :description`
- `searchable_array :tags`
- `filterable :privacy_status, :category_id, :channel_id, :project_id`

(The Searchable concern stays declarative — Meilisearch indexing is a separate
follow-up per the realignment doc.)

### `Project`

Light edit:

```ruby
has_many :videos, dependent: :nullify
```

Per Resolved decision Q1: deleting a Project does NOT delete its Videos; it just
nullifies their `project_id`.

### `PlaylistVideo` (new)

```ruby
class PlaylistVideo < ApplicationRecord
  belongs_to :playlist
  belongs_to :video

  validates :youtube_playlist_item_id, presence: true,
            uniqueness: { case_sensitive: false }
  validates :video_id, uniqueness: { scope: :playlist_id }
  validates :position, numericality: { only_integer: true,
                                       greater_than_or_equal_to: 0 }
end
```

### `Playlist`

Light edit — add the `has_many :playlist_videos` and
`has_many :videos, through: :playlist_videos` associations. If a
`has_many :playlist_items` declaration exists from the pre-Path-A2 era, replace
or coexist depending on whether the table was renamed (see Schema migration
"playlist_videos" subsection).

### `Channel`

Verify-only — no functional change. The Phase 11 (Channel sync + edit) spec
expands `Channel`. This phase touches Channel only if the `has_many :videos`
association has drifted.

### `YoutubeConnection`

Verify-only — no functional change. Optionally add
`has_many :videos, through: :channels` for convenience.

## Controller layer

### `VideosController` actions added

`edit (GET /videos/:id/edit)`

- `before_action :load_video`
- Renders `app/views/videos/edit.html.erb`.
- HTML format only.

`update (PATCH /videos/:id)`

- `before_action :load_video`
- Permitted params per "Strong params / authorization" section. Smuggled
  attributes (`youtube_video_id`, `channel_id`, `etag`, `last_synced_at`,
  `pre_publish_checked_at`, `made_for_kids_effective`, `last_sync_error`,
  `pre_publish_*`) are silently dropped by the policy.
- Forbids changing `privacy_status` via this path. A controller-level guard
  rejects `params[:video][:privacy_status]` if present (the publish / schedule
  actions are the only paths that change it). 422 on attempt with a clear error.
- Forbids changing `publish_at` via this path. Same posture as `privacy_status`.
- On success: 302 to `video_path(@video)`. The `after_update_commit` callback
  enqueues sync-back. JSON: 200 with the decorator's `as_detail_json`.
- On failure: 422, re-render `edit.html.erb`. JSON: 422 with errors.

`pre_publish_checklist (GET /videos/:id/pre_publish_checklist)`

- `before_action :load_video`
- Renders `app/views/videos/_pre_publish_modal.html.erb` as a Turbo Frame
  partial.
- Reads the four current boolean states and pre-checks the modal accordingly (a
  returning user sees their prior ticks).
- The modal's submit button POSTs to `videos/:id/publish` (or `:schedule` if
  `publish_at` is being set). The form posts the four booleans + the desired
  transition target. The controller validates all four are true; if not,
  re-renders the modal with errors.

`publish (PATCH /videos/:id/publish)`

- `before_action :load_video`
- Permitted params: `pre_publish_game_ok`, `pre_publish_age_ok`,
  `pre_publish_paid_promotion_ok`, `pre_publish_end_screen_ok`,
  `target_privacy_status` (must be `"public"` or `"unlisted"` per the
  yes/no-style boundary discipline; the controller maps to the enum).
- Validates all four booleans are true. If any is false, 422 with a clear error
  message, re-renders the modal.
- Validates the transition is legal: source is `private`, target is `public` or
  `unlisted`. (Going from `public` → `unlisted` or `unlisted` → `public` does
  NOT pass through this action — that's a metadata-edit- level transition
  handled by `update`. See "Open questions" #8.)
- Stamps `pre_publish_checked_at = Time.current`.
- Sets the four booleans on the record.
- Sets `privacy_status` on the record.
- `save!` triggers the `after_update_commit` sync-back job.
- 302 to `video_path(@video)` with a flash. JSON: 200 with the decorator output.
  Turbo Stream: closes the modal frame, replaces the privacy-status badge.

`schedule (PATCH /videos/:id/schedule)`

- Same shape as `publish`, except:
- Permitted params include `publish_at` (must be a future timestamp).
- Validates the transition is legal: source is `private`, `publish_at` is in the
  future, `privacy_status` stays `private` (per Note 1's API semantics —
  scheduling sets `publishAt` and keeps `privacyStatus= private` in the same
  call; the API flips it to `public` at the scheduled time).

#### Strong params

```ruby
def video_params
  params.require(:video).permit(
    :title, :description, :category_id, :self_declared_made_for_kids,
    :contains_synthetic_media, :project_id,
    tags: []
  )
end

def publish_params
  params.require(:video).permit(
    :pre_publish_game_ok, :pre_publish_age_ok,
    :pre_publish_paid_promotion_ok, :pre_publish_end_screen_ok,
    :target_privacy_status
  )
end

def schedule_params
  params.require(:video).permit(
    :pre_publish_game_ok, :pre_publish_age_ok,
    :pre_publish_paid_promotion_ok, :pre_publish_end_screen_ok,
    :publish_at
  )
end
```

#### Boolean boundary discipline (CLAUDE.md hard rule)

External boundary booleans are `"yes"` / `"no"`. The four `pre_publish_*_ok`
booleans, when posted from the form OR from MCP, are strings: `"yes"` / `"no"`.
The controller / MCP tool maps them to internal Boolean before assignment. The
form helper builds checkboxes that submit `"yes"` (checked) / `"no"`
(unchecked-default-via-hidden- input).

## Views (UX)

### Edit form (`edit.html.erb` + `_form.html.erb`)

Sections in order, each a labeled fieldset with the design.md monospace 13px
shape:

1. **Basics**
   - `title` (text input, max 100, character counter)
   - `description` (textarea, max 5000 bytes, character counter showing bytes)
   - `tags` (tag-input UX — Stimulus controller for add/remove. See "Open
     questions" #9 for the input shape.)
   - `category_id` (numeric input today; a select dropdown when
     `videoCategories.list` integration ships — that's a follow-up)

2. **Visibility** (read-only here)
   - Renders the current `privacy_status` and (if set) `publish_at` as read-only
     text. Two bracketed-link CTAs:
     - `[ publish ]` → opens the pre-publish modal targeting `:publish`
     - `[ schedule ]` → opens the pre-publish modal targeting `:schedule` (with
       a date/time input inside the modal)
   - For already-`public` / `unlisted` videos, instead renders:
     - `[ unpublish ]` → directly PATCHes `update` with
       `privacy_status: "private"` (no checklist needed — going down is free per
       Note 1)

3. **Audience**
   - `self_declared_made_for_kids` (yes/no toggle)
   - Read-only display of `made_for_kids_effective` if it disagrees with the
     self-declared value (Note 1: the computed `madeForKids` is read-only; we
     surface both values when they differ)

4. **Disclosures**
   - `contains_synthetic_media` (yes/no toggle)

5. **Studio-only fields** (read-only display + Studio link)
   - "Game tag" — text "Set in YouTube Studio" `[ open in studio ]` deep-link
   - "Age restriction (18+)" — text "Set in YouTube Studio" `[ open in studio ]`
     deep-link
   - "Paid promotion" — text "Set in YouTube Studio" `[ open in studio ]`
     deep-link
   - "End screen" — text "Set in YouTube Studio" `[ open in studio ]` deep-link
   - Each link uses the `_studio_link.html.erb` partial.

6. **Project link** (optional)
   - `project_id` — select dropdown. Options include `(none)` plus every Project
     ordered by name. Default to current value.
   - If currently linked, render "[ unlink ]" inline.

7. **Footer**
   - `[ save changes ]` (primary submit)
   - `[ cancel ]` → `video_path(@video)`
   - Inline `last_sync_error` warning if present

### Pre-publish checklist modal (`_pre_publish_modal.html.erb`)

Shape:

- Heading: "Pre-publish checklist"
- One-paragraph copy: "These four fields live in YouTube Studio. Check each one
  in Studio, then tick the box here to confirm."
- Four checkboxes, each with a Studio deep-link inline:
  - `[ ] Game set correctly (if category = Gaming)` `[ check in studio ]`
  - `[ ] Age restriction (18+) reviewed` `[ check in studio ]`
  - `[ ] Paid promotion declared if applicable` `[ check in studio ]`
  - `[ ] End screen reviewed` `[ check in studio ]`
- For the publish flow: a hidden `target_privacy_status` field set by the
  trigger button (publish-public vs. publish-unlisted).
- For the schedule flow: a date/time input for `publish_at`.
- Submit button: `[ confirm publish ]` (publish flow) or `[ confirm schedule ]`
  (schedule flow). Disabled until all four boxes are checked, enforced by the
  Stimulus controller.
- Cancel button: `[ cancel ]` — closes the modal frame, no state change.
- NO JS `confirm()` / `alert()` / `prompt()`. NO `data-turbo-confirm`. The modal
  IS the confirmation surface.

The modal is rendered as a Turbo Frame inside the edit / show page. Initial GET
to `/videos/:id/pre_publish_checklist?action=publish` (or `?action=schedule`)
populates it. Submit posts to `:publish` / `:schedule`. On success, the
controller responds with a Turbo Stream that closes the frame and updates the
privacy-status badge.

### Show page (`show.html.erb`)

Light edit:

- Add a "Project" line near the title rendering `[ project name ]` as a link to
  `project_path(@video.project)` if `@video.project_id` is present. If absent,
  render nothing.
- Add a small "Imported" indicator if `@video.imported?` returns true. Subtle —
  design.md muted color.
- Surface `last_sync_error` as an inline warning if non-null.

### Index page (`index.html.erb`)

Light edit:

- Add a `privacy_status` column showing `private` / `public` / `unlisted` in
  plain text (no icons in this phase to keep scope tight).
- Add the `[ edit ]` bracketed-link to each row.
- Replace the placeholder Title surface (currently `Video#id.to_s`) with
  `Video#title` post-migration. (The current decorator uses the YouTube ID stub
  — the new shape replaces it.)

### Project page (`projects/show.html.erb`)

Light edit:

- New section "Linked videos" listing
  `@project.videos.published.order(published_at: :desc)`.
- Each row: `[ title ]` link to the video page + privacy status + published_at
  date.
- If empty, render "No videos linked yet."

## Sync-back to YouTube

### Job: `VideoSyncBack`

Sidekiq worker. Single argument: `video_id`.

```ruby
class VideoSyncBack
  include Sidekiq::Job
  sidekiq_options queue: :default, retry: 3

  def perform(video_id)
    video = Video.find(video_id)
    connection = video.channel.youtube_connection
    return mark_no_connection(video) if connection.nil?
    return mark_needs_reauth(video) if connection.needs_reauth?

    fresh = Youtube::VideosReader.new(connection).read_video(video)
    payload = Youtube::VideosClient.new(connection).update_video(video, fresh: fresh)

    video.update!(
      etag: payload["etag"],
      last_synced_at: Time.current,
      last_sync_error: nil,
      made_for_kids_effective: payload.dig("status", "madeForKids")
    )
  rescue Youtube::QuotaExceededError => e
    video.update!(last_sync_error: "YouTube quota exceeded; will retry tomorrow")
    raise # let Sidekiq retry with backoff
  rescue Youtube::AuthRevokedError => e
    connection.update!(needs_reauth: true)
    video.update!(last_sync_error: "YouTube connection needs re-auth")
  rescue Youtube::ValidationError => e
    video.update!(last_sync_error: e.message)
    # do NOT raise — re-trying the same payload won't help
  end

  private

  def mark_no_connection(video)
    video.update!(last_sync_error: "No YouTube connection on this video's channel")
  end

  def mark_needs_reauth(video)
    video.update!(last_sync_error: "YouTube connection needs re-auth")
  end
end
```

### Read-modify-write semantics

Per Note 1's destructive-PUT-per-part warning: every `videos.update` call sends
the full `snippet` and `status` parts. The flow:

1. Fetch the current API state (`Youtube::VideosReader#read_video`).
2. Build the `snippet` payload from `video.title`, `video.description`,
   `video.tags`, `video.category_id` — overwriting whatever the API returned.
   (The user's local edits ARE the source of truth.)
3. Build the `status` payload from `video.privacy_status`, `video.publish_at`
   (if set), `video.self_declared_made_for_kids`,
   `video.contains_synthetic_media`.
4. POST `videos.update?part=snippet,status` with the full payload.
5. On success, parse the response, update `video.etag`,
   `video.made_for_kids_effective`, `video.last_synced_at`.

The "fetch first" step costs 1 quota unit. It guards against scenarios where the
API has additional snippet fields we don't model (default language, etc.) that
would be wiped if we sent a partial payload. We preserve those by reading them
and re-sending them unchanged.

### Quota tracking

Every call records a `youtube_api_calls` row per the Phase 7 audit pattern.
`videos.list` (1 unit), `videos.update` (50 units). Total per save: 51 units.

### Failure modes (rolled into the job's rescue blocks)

- Quota exceeded — Sidekiq retries with exponential backoff. Surfaces the error
  on `last_sync_error`.
- Auth revoked (401) — flips `needs_reauth = true` on the connection. Surfaces
  the error.
- Validation error (4xx, e.g., title too long, description has `<>`) — surfaces
  the error; does NOT retry (re-sending the same payload won't succeed).
- 5xx server error — Sidekiq retries.
- Network error — Sidekiq retries.

### Job: `VideoPublish`

Wraps the publish-state transition. Sequence:

1. Validate the four pre-publish booleans are true. (Defense-in-depth; the
   controller already validates.)
2. Stamp `pre_publish_checked_at`, set the four booleans, set `privacy_status`
   (and optionally `publish_at`).
3. Save. The `after_update_commit` callback enqueues `VideoSyncBack`.
4. If `VideoSyncBack` fails with a non-retriable error, revert `privacy_status`
   to its prior value and stamp `last_sync_error`. (See "Open questions" #10 for
   the alternative considered — let the local state be optimistic, surface the
   error, let the user retry.)

## MCP layer

Three new tools, all gated on the `app` scope (per ADR 0004). Two-step
`confirm: yes/no` for write tools (CLAUDE.md hard rule).

### `update_video` (Mcp::Tools::UpdateVideo)

Input schema:

```json
{
  "video_id": "string (uuid or numeric)",
  "title": "string?",
  "description": "string?",
  "tags": ["string"]?,
  "category_id": "string?",
  "self_declared_made_for_kids": "yes|no?",
  "contains_synthetic_media": "yes|no?",
  "project_id": "string?",
  "confirm": "yes|no"
}
```

Flow:

- `confirm: no` (or unset) → returns a preview of the diff (current vs.
  proposed) and a hint to retry with `confirm: yes`.
- `confirm: yes` → validates the proposed changes, performs the ActiveRecord
  update, returns the new decorator output. The same `after_update_commit`
  callback enqueues sync-back.

Cannot change `privacy_status` or `publish_at` via this tool.

### `pre_publish_check_video` (Mcp::Tools::PrePublishCheckVideo)

Input schema:

```json
{
  "video_id": "string",
  "game_ok": "yes|no",
  "age_ok": "yes|no",
  "paid_promotion_ok": "yes|no",
  "end_screen_ok": "yes|no",
  "confirm": "yes|no"
}
```

Sets the four booleans + stamps `pre_publish_checked_at`. Does NOT trigger
publish — that's `publish_video`.

### `publish_video` (Mcp::Tools::PublishVideo)

Input schema:

```json
{
  "video_id": "string",
  "target": "public|unlisted|scheduled",
  "publish_at": "iso8601?",
  "confirm": "yes|no"
}
```

Validates pre-publish booleans + `pre_publish_checked_at` are all set. If
`target=scheduled`, requires `publish_at` in the future. Performs the
privacy_status transition. The `after_update_commit` callback enqueues
sync-back.

If pre-publish state is incomplete, returns a clear error listing which checks
are missing — the operator must call `pre_publish_check_video` first.

### Per-domain MCP coverage matrix

Per realignment Resolved ambiguity #2: web is canonical; MCP is best- effort
parity. This phase declares:

| Action                       | Web | MCP | CLI        |
| ---------------------------- | --- | --- | ---------- |
| List videos                  | yes | yes | (existing) |
| Show video                   | yes | yes | (existing) |
| Edit metadata                | yes | yes | unit 10    |
| Pre-publish check            | yes | yes | unit 10    |
| Publish / schedule           | yes | yes | unit 10    |
| Unpublish (`public→private`) | yes | yes | unit 10    |
| Thumbnail upload             | no  | no  | no         |
| Playlist membership edit     | no  | no  | no         |

YouTube upload itself remains web-app-only and is also not in this phase's
scope.

## Test sweep

Exhaustive — per the architect-spec discipline. Each line is one or more test
cases.

### `Video` model unit specs

**Associations:**

- `belongs_to :channel` (existing, retain)
- `belongs_to :project, optional: true` (new)
- `has_many :video_stats, dependent: :destroy` (existing)
- `has_many :playlist_videos, dependent: :destroy` (new)
- `has_many :playlists, through: :playlist_videos` (new)
- `has_one :youtube_connection, through: :channel` (new)

**Validations — `youtube_video_id`:**

- Presence (existing)
- Uniqueness, case-insensitive (existing)

**Validations — `title`:**

- Length ≤ 100
- Rejects `<` character
- Rejects `>` character
- Allows unicode (e.g., emoji)
- Allowed when blank for a draft (`privacy_status = private`,
  `publish_at = nil`)
- Required when `privacy_status` is being set to `public` (custom validator)
- Required when `privacy_status` is being set to `unlisted`

**Validations — `description`:**

- Length ≤ 5000 chars
- Rejects when `bytesize > 5000` (UTF-8 multi-byte case)
- Rejects `<` character
- Rejects `>` character
- Allows blank

**Validations — `tags`:**

- Empty array allowed
- Single tag allowed
- Multiple tags allowed
- Total API length ≤ 500 — boundary cases:
  - 500 chars exactly: allowed
  - 501 chars: rejected
  - Single tag with space ("hello world") counts 13 (with quotes)
  - Multiple tags with commas counted
- Non-string element rejected

**Validations — `category_id`:**

- Required when transitioning to `public` / `unlisted`
- Required when `publish_at` is being set
- Optional for drafts
- Numeric-string format only (`/\A\d+\z/`)
- Rejects "abc"
- Rejects "12.5"
- Allows "20" (Gaming category)

**Validations — `privacy_status`:**

- Enum-validated: rejects unknown values (Rails enum macro)
- Default `:private`

**Validations — `publish_at`:**

- Allows nil
- Allows future timestamp
- Rejects past timestamp when `privacy_status = private`
- Rejects when `privacy_status` is `public` (mutually exclusive — a scheduled
  publish stays private until the API flips it)

**Enum behavior:**

- `Video.privacy_private`, `Video.privacy_public`, `Video.privacy_unlisted`
  scopes work
- `video.privacy_private?`, `.privacy_public?`, `.privacy_unlisted?` predicates
  work

**Callbacks:**

- `after_update_commit :enqueue_sync_back` fires when `title` changes
- Fires when `description` changes
- Fires when `tags` changes
- Fires when `category_id` changes
- Fires when `privacy_status` changes
- Fires when `publish_at` changes
- Fires when `self_declared_made_for_kids` changes
- Fires when `contains_synthetic_media` changes
- Does NOT fire when `last_synced_at` changes (system-managed)
- Does NOT fire when `etag` changes (system-managed)
- Does NOT fire when `made_for_kids_effective` changes
- Does NOT fire when only `pre_publish_*` booleans change (those are user-tick
  state, not API-syncable)

**Scopes:**

- `.starred` (existing, retain)
- `.published` returns `public` and `unlisted` rows
- `.draft` returns `private` rows with `publish_at IS NULL`
- `.scheduled` returns `private` rows with `publish_at IS NOT NULL`
- `.pre_publish_complete` returns rows where all four booleans are true AND
  `pre_publish_checked_at IS NOT NULL`

**Public methods:**

- `pre_publish_complete?` true when all four + timestamp
- `pre_publish_complete?` false when any boolean is false
- `pre_publish_complete?` false when timestamp is nil
- `studio_url` returns the correct URL pattern
- `imported?` true when `pre_publish_checked_at IS NULL` AND `privacy_status` is
  `public`
- `imported?` true when `unlisted`
- `imported?` false when `private`
- `imported?` false when `pre_publish_checked_at IS NOT NULL`

### `Project` model unit specs

- `has_many :videos, dependent: :nullify`
- Deleting a Project: linked videos survive with `project_id = NULL`
- Deleting a Project with N linked videos: all N have `project_id = NULL` after
  the destroy

### `PlaylistVideo` model unit specs

- `belongs_to :playlist`
- `belongs_to :video`
- `youtube_playlist_item_id` presence + uniqueness (case_insensitive)
- `(playlist_id, video_id)` uniqueness
- `position` numericality, integer, ≥ 0

### `Playlist` model unit specs

- `has_many :playlist_videos, dependent: :destroy`
- `has_many :videos, through: :playlist_videos`

### Request specs (`VideosController`)

**`GET /videos/:id/edit` (happy):**

- 200, renders the edit form
- Form contains `title`, `description`, `tags`, `category_id`,
  `self_declared_made_for_kids`, `contains_synthetic_media`, `project_id` inputs
- Form does NOT contain `privacy_status` input (publish path only)
- Form does NOT contain `publish_at` input (schedule path only)
- Studio deep-links present for the four Studio-only fields

**`GET /videos/:id/edit` (sad):**

- 404 when the video does not exist

**`PATCH /videos/:id` (happy):**

- Valid params → 302 to `/videos/:id`
- Updates `title`
- Updates `description`
- Updates `tags`
- Updates `category_id`
- Updates `self_declared_made_for_kids`
- Updates `contains_synthetic_media`
- Updates `project_id`
- Enqueues `VideoSyncBack` once
- JSON request → 200 with `as_detail_json`

**`PATCH /videos/:id` (sad):**

- Invalid title (>100 chars) → 422
- Invalid description (5001 bytes UTF-8) → 422
- Invalid tags (501 chars total) → 422
- Invalid category_id ("abc") → 422
- 404 when the video does not exist

**`PATCH /videos/:id` (smuggling guards):**

- `youtube_video_id` in params: silently dropped, value unchanged
- `channel_id` in params: silently dropped
- `etag` in params: silently dropped
- `last_synced_at` in params: silently dropped
- `pre_publish_checked_at` in params: silently dropped
- `pre_publish_game_ok` in params: silently dropped
- `made_for_kids_effective` in params: silently dropped
- `last_sync_error` in params: silently dropped
- `privacy_status` in params: 422 with explicit error ("use [ publish ] or [
  schedule ]")
- `publish_at` in params: 422 with explicit error

**`GET /videos/:id/pre_publish_checklist` (happy):**

- 200, renders the modal partial
- Pre-checks any boxes whose corresponding boolean is already true
- Renders four Studio deep-links

**`PATCH /videos/:id/publish` (happy):**

- All four booleans `"yes"`, `target_privacy_status="public"` → 302
- Stamps `pre_publish_checked_at`
- Sets `privacy_status` to `:public`
- Enqueues `VideoSyncBack`
- Same flow with `target_privacy_status="unlisted"` → 302, sets `:unlisted`

**`PATCH /videos/:id/publish` (sad):**

- Any boolean `"no"` → 422, modal re-renders with errors
- Missing `target_privacy_status` → 422
- Invalid `target_privacy_status="private"` → 422 (illegal target)
- Invalid `target_privacy_status="scheduled"` → 422 (use `:schedule`)
- Already-published video (current `privacy_status=public`) → 422 (illegal
  source — re-publishing a public video makes no sense)
- Video on a channel without a `YoutubeConnection` → action proceeds locally
  (the privacy_status flips), but `last_sync_error` is set to "No YouTube
  connection on this video's channel" by the sync-back job

**`PATCH /videos/:id/schedule` (happy):**

- All four booleans, valid future `publish_at` → 302
- Stamps `pre_publish_checked_at`
- Keeps `privacy_status = :private`
- Sets `publish_at`
- Enqueues `VideoSyncBack`

**`PATCH /videos/:id/schedule` (sad):**

- Past `publish_at` → 422
- Missing `publish_at` → 422
- Any boolean `"no"` → 422
- Already-published video → 422

**`DELETE /videos/:id` (existing flow, retain):**

- Single delete route via `DeletionsController` per the bulk-as- foundation
  pattern (CLAUDE.md hard rule). Verify this still works with the expanded model
  — the destroy callbacks should fire on `playlist_videos` (cascade) and
  `video_stats` (existing dependent).

### Pre-publish checklist scenarios (system spec — Capybara)

`spec/system/video_pre_publish_checklist_spec.rb`:

1. **First publish — all checks required.** Visit edit page for a private draft.
   Click `[ publish ]`. Modal opens. Confirm publish button is disabled. Tick
   all four boxes. Confirm button enables. Click. Confirms publish. Privacy
   badge updates to `public`.

2. **Schedule (publish in future).** Visit edit page for a private draft. Click
   `[ schedule ]`. Modal opens with date/time input. Tick all four. Set future
   date. Submit. Privacy stays `private`, `publish_at` set, success flash.

3. **Metadata edit on already-published video.** Open published video. Edit form
   does NOT show `[ publish ]` button (already public). Edit `title`, save.
   Modal does NOT fire. Update succeeds.

4. **User dismisses modal.** Click `[ publish ]`, modal opens. Click
   `[ cancel ]`. Modal closes. Privacy unchanged.

5. **User confirms with one box unchecked.** Tick only three. Submit button
   stays disabled. (The Stimulus controller enforces this client-side; the
   server also rejects it as a defense-in-depth.)

6. **User confirms all boxes — publish proceeds.** Already covered by #1.

7. **Re-opening modal after partial completion.** Tick two boxes, close.
   Re-open. Check that prior boxes are still ticked (server-side persistence via
   the four boolean columns; this is the "checklist state survives across modal
   opens" behavior).

8. **Imported video edit (`pre_publish_checked_at IS NULL` AND
   `privacy_status = public`).** Open the edit form. The `[ publish ]` button is
   NOT shown (already public). The edit form shows the "Imported" indicator.
   Edit metadata, save — modal does NOT fire. Update succeeds.

9. **Privacy transition `public` → `private` (unpublish).** From the edit form
   on a public video, click `[ unpublish ]`. NO modal fires (going down is free
   per Note 1). PATCH fires; privacy_status flips to `private`. Sync-back
   enqueued.

10. **Privacy transition `unlisted` → `public`.** From the edit form on an
    unlisted video. Per "Open questions" #8, this MAY require the checklist or
    MAY skip it — the spec resolves this ambiguity before implementation.
    Recommendation: skip the checklist (the video has been published before; the
    four checks were either run or the video is imported — re-running adds
    friction without safety value).

### Sync-back to YouTube (job + service specs)

`spec/jobs/video_sync_back_spec.rb`:

- **Successful sync.** Stub `Youtube::VideosClient` to return 200 with a fresh
  etag. Job stamps `last_synced_at`, `etag`, `made_for_kids_effective`. Clears
  `last_sync_error`.

- **Read-modify-write integrity.** Stub the reader to return a snippet with
  extra fields (e.g., `defaultLanguage="en"`) we don't model. The client payload
  merges those through unchanged. Verify the API call body includes them.

- **Quota exceeded.** Stub the client to raise `Youtube::QuotaExceededError`.
  Job stamps `last_sync_error`. Re- raises so Sidekiq retries.

- **Auth revoked (401).** Stub the client to raise `Youtube::AuthRevokedError`.
  Connection's `needs_reauth` flips to true. Video's `last_sync_error` reflects
  the state.

- **Validation error (e.g., title too long for the API even though we validated
  locally).** Stub the client to raise
  `Youtube::ValidationError("title exceeds 100")`. Video's `last_sync_error`
  set; job does NOT re-raise (no retry).

- **5xx server error.** Stub raises a generic `Youtube::ServerError`. Job
  re-raises so Sidekiq retries.

- **Network timeout.** Stub raises `Net::ReadTimeout` (or similar). Job
  re-raises.

- **No YouTube connection.** `video.channel.youtube_connection IS NULL`. Job
  sets `last_sync_error: "No YouTube connection on this video's channel"`. Does
  NOT call the API. Does NOT raise.

- **Connection in `needs_reauth=true` state.** Job sets
  `last_sync_error: "YouTube connection needs re-auth"`. Does NOT call the API.

- **Audit log row.** Each successful call writes a `youtube_api_calls` row with
  `endpoint=videos.list` (1 unit) AND `endpoint=videos.update` (50 units).
  Failed calls also log (with `outcome=error`).

`spec/services/youtube/videos_client_spec.rb`:

- Builds the correct `snippet` payload from the local Video.
- Builds the correct `status` payload.
- Hits the URL `videos.update?part=snippet,status`.
- Authorization header is `Bearer <connection.access_token>`.
- 200 response: returns parsed JSON.
- 401 response: raises `Youtube::AuthRevokedError`.
- 403 with `quotaExceeded` reason: raises `Youtube::QuotaExceededError`.
- 400 with validation reason: raises `Youtube::ValidationError`.
- 5xx response: raises `Youtube::ServerError`.

`spec/services/youtube/videos_reader_spec.rb`:

- Hits `videos.list?part=snippet,status,contentDetails&id=<id>`.
- Returns the parsed item JSON.
- 404 raises `Youtube::NotFoundError` (video gone from YouTube — likely deleted
  in Studio).
- 401 raises `Youtube::AuthRevokedError`.

### Project ↔ Video integration

`spec/requests/projects_spec.rb` (light additions):

- Linked video appears on the project show page.
- Multiple linked videos appear, ordered by `published_at desc`.
- Project page renders nothing in the "Linked videos" section when none exist.

Model integration:

- Setting `video.project_id` to a project's id, save, project's `videos`
  collection includes the video.
- Unlinking (`video.project_id = nil`, save), project's `videos` collection
  excludes the video.
- Deleting the project: video survives with `project_id = NULL` (verifies the FK
  `ON DELETE SET NULL`).

### Imported video edge

`spec/models/video_spec.rb` (within the `imported?` describe block):

- `pre_publish_checked_at = NULL`, `privacy_status = :public` →
  `imported? == true`.
- `pre_publish_checked_at = NULL`, `privacy_status = :unlisted` →
  `imported? == true`.
- `pre_publish_checked_at = NULL`, `privacy_status = :private` →
  `imported? == false`.
- `pre_publish_checked_at = Time.current`, `privacy_status = :public` →
  `imported? == false`.

`spec/system/video_pre_publish_checklist_spec.rb` (already covered #8 above —
imported video edit does NOT fire the modal).

### MCP tool specs

`spec/lib/mcp/tools/update_video_spec.rb`:

- `confirm: "no"` → returns dry-run preview. No DB mutation.
- `confirm: "yes"` → mutates. Same validation surface as the controller path.
- Smuggling guards (`youtube_video_id`, `channel_id`, etc.) silently dropped.
- `privacy_status` in input rejected with clear error.
- `app` scope required (gate test). `dev` scope token rejected.
- `pre_publish_*` boolean inputs rejected (separate tool).

`spec/lib/mcp/tools/pre_publish_check_video_spec.rb`:

- `confirm: "no"` → preview.
- `confirm: "yes"` → flips the four booleans + stamps `pre_publish_checked_at`.
- All four required (any missing → error).
- Boolean inputs are `"yes"` / `"no"` strings (not `true` / `false`).
- `app` scope gate.

`spec/lib/mcp/tools/publish_video_spec.rb`:

- Pre-publish complete → publishes, enqueues sync-back.
- Pre-publish incomplete → error, lists missing checks.
- `target=public` → flips to public.
- `target=unlisted` → flips to unlisted.
- `target=scheduled` requires `publish_at` → flips `publish_at` (privacy stays
  private).
- `target=scheduled` with past `publish_at` → error.
- `target=scheduled` without `publish_at` → error.
- `app` scope gate.
- `confirm: yes/no` two-step.

### Decorator spec

`spec/decorators/video_decorator_spec.rb`:

- `as_summary_json` includes `id`, `youtube_video_id`, `title`,
  `privacy_status`, `published_at`, `star`, `total_views`, ...
- `as_detail_json` includes the full writable subset + `description`, `tags`,
  `category_id`, `made_for_kids_effective`, `etag`, `last_synced_at`,
  `last_sync_error`, `pre_publish_*` booleans + the `pre_publish_checked_at`
  timestamp.
- Boolean fields serialized as `"yes"` / `"no"` strings (CLAUDE.md yes/no
  boundary discipline).
- `studio_url` exposed.
- `imported` flag (yes/no) exposed.

### Factory updates

`spec/factories/videos.rb` rewritten:

```ruby
FactoryBot.define do
  factory :video do
    channel
    sequence(:youtube_video_id) { |n| "vid_#{Faker::Alphanumeric.alphanumeric(number: 8)}#{n}" }
    title { Faker::Lorem.sentence(word_count: 5).first(100) }
    description { Faker::Lorem.paragraph(sentence_count: 5) }
    tags { [] }
    category_id { "20" } # Gaming
    privacy_status { :private }
    publish_at { nil }
    self_declared_made_for_kids { false }
    contains_synthetic_media { false }
    star { false }

    trait :starred do
      star { true }
    end

    trait :public do
      privacy_status { :public }
      published_at { 1.day.ago }
    end

    trait :unlisted do
      privacy_status { :unlisted }
      published_at { 1.day.ago }
    end

    trait :scheduled do
      privacy_status { :private }
      publish_at { 1.day.from_now }
    end

    trait :imported do
      # public/unlisted but never went through pito's publish flow
      privacy_status { :public }
      published_at { 30.days.ago }
      pre_publish_checked_at { nil }
    end

    trait :pre_publish_complete do
      pre_publish_game_ok { true }
      pre_publish_age_ok { true }
      pre_publish_paid_promotion_ok { true }
      pre_publish_end_screen_ok { true }
      pre_publish_checked_at { Time.current }
    end

    trait :with_sync_error do
      last_sync_error { "title too long" }
    end
  end
end
```

`spec/factories/playlist_videos.rb` (new):

```ruby
FactoryBot.define do
  factory :playlist_video do
    playlist
    video
    sequence(:youtube_playlist_item_id) { |n| "pli_#{n}" }
    position { 0 }
  end
end
```

## Documentation impact (post-implementation)

Docs-keeper handles after user validation. Targets:

- `docs/architecture.md` — replace the Path A2 framing for `Video` with the
  expanded shape. Add a "YouTube management" section pointing at this spec +
  Note 1.
- `docs/design.md` — add a "Pre-publish checklist" UX pattern entry. The entry
  documents:
  - The four-item modal shape (Studio deep-links per item).
  - The Stimulus-driven submit-disabled-until-all-checked discipline.
  - The CLAUDE.md no-`confirm()` rule reaffirmed.
  - The bracketed-link convention for Studio links.
- `docs/mcp.md` — add `update_video`, `pre_publish_check_video`, `publish_video`
  to the scope-per-tool table.
- `docs/realignment-2026-05-09.md` — note that work unit 4 has shipped (or, more
  accurately, point at this spec from the unit's "Delivers" paragraph).

ADR consideration: the pre-publish-check storage shape (separate columns vs.
JSONB vs. join table) is a structural decision worth a decision record IF the
architect wants to lock it explicitly. The current spec recommends "four boolean
columns + one timestamp" inline. If a future change wants to add a fifth check
(e.g., "captions present"), the spec calls for a column-add migration, not a
schema overhaul. This is a low-volatility shape; ADR is optional. Architect's
recommendation: defer ADR unless the fifth check arrives. (See "Open questions"
#1.)

## Manual playbook outline

After implementation, the user runs:

1. `bin/setup` — install deps, start Docker, prepare DB. (Reseed if needed:
   `bin/rails db:reset` is fine since Phase 8 has already reseeded; this phase's
   migration is additive.)
2. `bin/rails db:migrate` — applies the new columns + tables.
3. `bin/dev` — start the Rails app + Sidekiq.
4. Connect a YouTube channel via Settings → YouTube (the Phase 7 + Phase 9
   surface). Pick a channel with at least one private draft video and at least
   one published video.
5. Visit `/videos`. Confirm:
   - The new `privacy_status` column shows `private` / `public` / `unlisted` per
     row.
   - Imported videos (public, never went through pito publish) show the
     `Imported` indicator.
   - Each row has an `[ edit ]` bracketed link.
6. Click `[ edit ]` on a private draft video. Confirm the edit form renders all
   the new fields (Basics, Visibility, Audience, Disclosures, Studio-only,
   Project link, Footer).
7. Edit the `title`, save. Confirm:
   - 302 to the show page.
   - Sidekiq dashboard at `/sidekiq` shows a `VideoSyncBack` job enqueued and
     processed.
   - In YouTube Studio, the title has updated.
   - `last_synced_at` updated on the video.
8. On the same draft video, click `[ publish ]`. Confirm the modal opens with
   four checkboxes + four Studio deep-links.
9. Click `[ confirm publish ]` without checking any boxes. Confirm the button is
   disabled. Tick three boxes. Still disabled. Tick the fourth. Button enables.
10. Click `[ confirm publish ]`. Confirm:
    - The privacy badge updates to `public`.
    - In YouTube Studio, the privacy is `Public`.
    - `pre_publish_checked_at` stamped.
    - All four boolean columns set to true.
11. On a published video, click `[ edit ]`. Confirm:
    - No `[ publish ]` button (it's already public).
    - `[ unpublish ]` button is present.
    - Edit the description, save. Confirm the modal does NOT fire. Update
      succeeds.
12. On a draft video, click `[ schedule ]`. Confirm the modal opens with a
    date/time input. Set a future date, tick all four boxes, submit. Confirm:
    - `privacy_status` stays `private`.
    - `publish_at` is set.
    - In YouTube Studio, the video is "Scheduled".
13. Visit a project page. Edit a draft video and link it to the project (set
    `project_id`). Save. Confirm the project page now shows the linked video.
14. Delete the project. Confirm the linked video survives at `/videos` with
    `project_id IS NULL`.
15. (Sad path) On a draft video, click `[ publish ]`, tick all four boxes,
    submit. Stub the YouTube API to return 401 (auth revoked — this requires
    either a manual token revocation in Google Console OR a temporary stub in
    code). Confirm:
    - The local privacy_status DOES flip to public (optimistic).
    - `last_sync_error` shows on the show page.
    - The connection's `needs_reauth` flips to true.
    - The Settings → YouTube banner appears with the re-auth prompt.
    - (Open question #10 — the architect MAY decide to roll back the local
      privacy flip on sync-back failure. The current spec keeps it optimistic.)
16. (MCP path) From an MCP-aware client (Claude Mobile / Web MCP), invoke
    `update_video` with `confirm: "no"`. Confirm dry-run preview returns. Invoke
    with `confirm: "yes"`. Confirm the change persists.
17. Run `bundle exec rspec` — all green.
18. Run `bundle exec rubocop` — clean.

## Cross-stack scope

- **Web app (`app/`):** in scope. Primary lane.
- **MCP layer (`app/lib/mcp/`):** in scope. Sub-lane (`mcp-impl`).
- **CLI (`extras/cli/`):** out of scope. Realignment work unit 10.
- **Cloudflare Pages site (`extras/website/`):** out of scope. Marketing
  surface, not affected.

## Copy questions to escalate

These are real copy choices. Architect surfaces; master agent decides.

1. **Pre-publish modal heading.** Recommend: "Pre-publish checklist".
   Alternatives: "Confirm publish", "Before publishing".
2. **Pre-publish modal one-paragraph copy.** Recommend: "These four fields live
   in YouTube Studio. Check each one in Studio, then tick the box here to
   confirm." Should it mention pito doesn't enforce them — i.e., make the
   manual-reminder posture explicit?
3. **Checkbox labels.** Recommend (verbatim from Note 1 + Note 2):
   - "Game set correctly (if category = Gaming)"
   - "Age restriction (18+) reviewed"
   - "Paid promotion declared if applicable"
   - "End screen reviewed"
4. **Studio deep-link label.** Recommend: `[ check in studio ]`. Per
   bracketed-link convention. Alternatives: `[ open in studio ]`, `[ studio ]`.
5. **Confirm button label.** Recommend: `[ confirm publish ]` (publish flow) and
   `[ confirm schedule ]` (schedule flow). Alternatives: `[ publish ]` (less
   explicit), `[ ok ]` (against design.md).
6. **Cancel button label.** Recommend: `[ cancel ]`.
7. **Edit form section headings.** Recommend: "Basics", "Visibility",
   "Audience", "Disclosures", "Studio-only", "Project". Alternatives if the user
   prefers other groupings.
8. **`[ unpublish ]` label.** For the `public` → `private` direct path on the
   edit form. Recommend `[ unpublish ]` (verb-based per design conventions).
   Alternative: `[ make private ]`.
9. **Imported video indicator copy.** Recommend the small muted-color text
   "Imported" on index + show. Alternatives: "Pre-pito", "(legacy)",
   "(pre-pito)". The user picks the term that aligns with their mental model.
10. **Last-sync-error inline warning copy template.** Recommend: "YouTube sync
    failed: <error>". Alternatives: "Sync error: <error>", "Could not save to
    YouTube: <error>".
11. **Validation error messages (per-field).** Standard Rails
    `errors.full_messages` shape with model labels. Specific custom messages:
    - Tags too long: "are too long (max 500 API-side chars)"
    - Title bracket characters: "cannot contain `<` or `>`"
    - Description bytesize: "is too long (max 5000 bytes)"
    - Category required for publish: "is required when publishing"
    - Past publish_at: "must be in the future" Master agent confirms.
12. **MCP update_video preview copy.** When `confirm: "no"`, the tool returns a
    structured diff. Architect surfaces the JSON shape for the master agent to
    confirm.

## Open questions

The architect surfaces structural decisions; master agent decides via the
autonomy rule.

1. **Pre-publish-check storage shape — separate columns vs. JSONB vs. separate
   join table.** Architect recommends: four boolean columns
   - one timestamp on `videos`. Rationale:
   * Four checks is a small fixed set; columns are cheap.
   * Per-check filtering (e.g., "videos awaiting end-screen review") is a
     one-column WHERE clause vs. a JSONB path expression.
   * Audit trail: the `audit-log` follow-up (if it ever lands) can log the
     writes via Active Record's standard mechanisms.
   * JSONB pays its rent only when the schema is volatile or when per-row keys
     differ — neither is true here.
   * A separate join table
     (`video_pre_publish_checks(video_id,   check_kind, ok)`) is over-engineered
     for a fixed set. The alternative considered is JSONB. If the user wants
     extensibility for future checks (a "captions present" check landing later),
     the column-add migration is still cheap; the JSONB advantage is real only
     if we expect frequent additions. Recommendation: stay with columns.

2. **Edit form / strong params shared between web and MCP.** Today
   `app/lib/mcp/tools/update_video.rb` and the controller both declare the
   writable subset. Recommend extracting to `app/policies/video_policy.rb` (or
   similar) so the surface is declared once. Alternative: leave duplicated; less
   abstraction at the cost of two places to keep in sync.

3. **Modal rendering shape.** Two options:
   - (a) Turbo Frame modal with the existing `_action_screen.html.erb` pattern
     (full-page confirmation screen, like deletions / syncs). Pro: matches the
     existing CLAUDE.md hard-rule confirmation framework. Con: full-page
     navigation feels heavy for a checklist.
   - (b) Turbo Frame in-page modal overlay (CSS + a `_pre_publish_modal`
     partial, NOT a JS dialog API). Pro: lighter UX. Con: a new pattern not yet
     present in the repo. Architect recommends (b) — a Turbo Frame in-page modal
     is cleaner for a checklist. The CLAUDE.md hard rule against `confirm()` /
     `alert()` / `prompt()` is upheld either way (the modal is a Turbo- rendered
     DOM element, not a browser API). User confirms.

4. **Sync-back job naming.** Existing precedent: `ChannelSync` (read- sync flat
   name). This phase's job is a write-back, semantically distinct. Architect
   proposes `VideoSyncBack` to make the direction explicit. Alternative:
   `VideoSync` (matches the existing pattern, loses the directional hint). User
   confirms.

5. **Channel schema dependency.** This phase's project-page "linked videos"
   listing renders the channel's display surface. If Channel is still in the
   thin shape (no `title`, `subscriber_count`, etc.) when this phase ships, the
   project page falls back to displaying the channel URL slug. The Channel
   sync + edit phase (work unit 3) is supposed to land before this one per the
   ordered roadmap; the architect surfaces this here to confirm the ordering
   holds. Alternative: relax the project page to use whatever Channel surfaces
   today and update later.

6. **`playlist_items` vs. `playlist_videos` table naming.** The existing
   `playlist_items` table (pre-Path-A2) is functionally the `playlist_videos`
   join Note 1 calls for. Architect recommends renaming for terminology
   alignment with Note 1. Alternative: keep `playlist_items`; the difference is
   semantic only. User confirms.

7. **Pre-publish state lifecycle on metadata edit.** The current spec keeps the
   four booleans + timestamp persistent across metadata edits — once the user
   has ticked through the modal once, those values stay set. The alternative is
   to RESET the booleans whenever ANY metadata field changes, forcing a re-tick
   on every publish. Architect recommends persistent (lower friction; the user
   has already confirmed the four out-of-band facts; re-asking on every edit is
   cargo-cult safety). User confirms.

8. **`unlisted` ↔ `public` transitions — checklist or no?** Going `private` →
   `public/unlisted` requires the checklist. Going `public` → `private`
   (unpublish) does not. What about `unlisted` → `public`, or `public` →
   `unlisted`? The video has been published before; the four checks were either
   run or the video is imported (pre-pito). Architect recommends: skip the
   checklist for these transitions — they're functionally a metadata edit. User
   confirms.

9. **Tags input UX.** Recommendations:
   - (a) Comma-separated text input + Stimulus controller that splits on comma
     and renders pills. Lightweight.
   - (b) A proper tag-picker library (e.g., Tagify). Heavier; pulls in a JS
     dependency. Architect recommends (a) — minimal JS, no new dependency. User
     confirms.

10. **Sync-back failure rollback.** When `VideoSyncBack` fails (e.g., "title too
    long" — local validation didn't catch it because YouTube's UTF-8 byte
    counting differs from ours by some edge case), should the local
    `privacy_status` flip be rolled back? Two options:
    - (a) Optimistic — local state stays as the user requested;
      `last_sync_error` surfaces; user sees the error and re-edits. The video is
      "out of sync with YouTube" until they fix it.
    - (b) Pessimistic — sync-back failure reverts the local `privacy_status` to
      its prior value. The user sees a flash: "publish failed — see error and
      retry." Architect recommends (a) — simpler reasoning. The sync-back error
      is visible; the user re-edits. The "out of sync" gap is bounded by the
      user's response time, not a permanent inconsistency. User confirms.

11. **Project-deletion-side `dependent` posture.** The spec locks
    `dependent: :nullify` on `Project#has_many :videos`. Per Resolved decision
    Q1. Re-confirming here for the open-questions record: Master agent has
    already decided nullify; flagged for final user-validation in the manual
    playbook step #14.

12. **`youtube_video_id` uniqueness — case-sensitive vs. insensitive.** Existing
    validation is case-insensitive. YouTube IDs are technically case-sensitive
    (the URL `youtu.be/Abc` and `youtu.be/abc` are different videos). Architect
    recommends SWITCHING to case-sensitive uniqueness in this phase.
    Alternative: leave case-insensitive (current state). The risk of leaving it
    is low (collisions across cases are unlikely in practice) but the semantic
    is wrong. User confirms.

13. **Tags column type — `jsonb` vs. Postgres native `text[]`.** The spec
    recommends `jsonb` for consistency with the existing
    `tenants.notes_syncing_at`-era choices and the `app_settings` table's other
    jsonb columns. Postgres native `text[]` would also work. The functional
    difference is GIN index syntax and JSON pass-through to the API. Architect
    recommends `jsonb`. User confirms.

## Master agent decisions (2026-05-10)

Master agent has resolved every copy question and open question above per the
autonomy rule. The decisions below override any "TBD" / "user picks" framing.
Implementation agent treats these as the contract.

### Copy decisions (lock these into the spec)

1. **Pre-publish modal heading** → `pre-publish checklist` (lowercase per
   project tone).
2. **Pre-publish modal paragraph copy** →
   `these four fields live in youtube studio. check each one in studio, then tick the box here to confirm. pito does not enforce them — this is a manual reminder.`
   (lowercase project tone; explicit manual-reminder posture).
3. **Checkbox labels** → Verbatim from architect's recommendation:
   - `Game set correctly (if category = Gaming)`
   - `Age restriction (18+) reviewed`
   - `Paid promotion declared if applicable`
   - `End screen reviewed`
4. **Studio deep-link label** → `[ check in studio ]`.
5. **Confirm button labels** → `[ confirm publish ]` (publish flow) /
   `[ confirm schedule ]` (schedule flow).
6. **Cancel button label** → `[ cancel ]`.
7. **Edit form section headings** → Lowercase: `basics`, `visibility`,
   `audience`, `disclosures`, `studio-only`, `project`.
8. **Unpublish label** → `[ unpublish ]`.
9. **Imported video indicator** → `imported` (small, muted color, on index +
   show pages).
10. **Last-sync-error inline warning template** →
    `youtube sync failed: <error>`.
11. **Validation error messages** → Architect's recommendations verbatim:
    - tags too long: `are too long (max 500 API-side chars)`
    - title bracket characters: `cannot contain \`<\` or \`>\``
    - description bytesize: `is too long (max 5000 bytes)`
    - category required for publish: `is required when publishing`
    - past publish_at: `must be in the future`
12. **MCP update_video preview shape (when `confirm: "no"`)** → Structured diff:
    `{ "changes": { "<field_name>": { "old": <previous_value>, "new": <proposed_value> }, ... }, "video_id": "<id>" }`.
    Implementation agent picks the exact JSON encoding; structure is the goal.

### Open-question decisions (lock these into the spec)

1. **Pre-publish-check storage** → Four boolean columns + one timestamp on
   `videos`. Concur with architect; columns.
2. **Edit form / strong params abstraction** → Extract to
   `app/policies/video_policy.rb` (or equivalent single-source location) so the
   controller and the MCP `update_video` tool reference the same writable-field
   set.
3. **Modal rendering** → Turbo Frame in-page modal overlay (option b). Lighter
   UX than a full-page action screen. The CLAUDE.md hard rule against
   `confirm()` / `alert()` / `prompt()` is upheld — the modal is a
   Turbo-rendered DOM element, not a browser API.
4. **Sync-back job naming** → `VideoSyncBack`. Directional name disambiguates it
   from the read-side sync precedent.
5. **Channel schema dependency** → Relax. Phase 12 implementation does NOT block
   on Phase 11 (Channel sync) landing first. The project-page "linked videos"
   listing renders whatever Channel surfaces today (channel URL slug as
   fallback). When Phase 11 lands, the listing automatically renders the richer
   Channel surface. No double-pass implementation needed.
6. **`playlist_items` vs `playlist_videos` table** → Rename to
   `playlist_videos`. Aligns with Note 1's terminology.
7. **Pre-publish state lifecycle on metadata edit** → Persistent. Once the four
   booleans + timestamp are set, they stay set across subsequent metadata edits.
   Re-asking on every edit is cargo-cult.
8. **`unlisted` ↔ `public` transitions** → Skip the checklist for these. They
   are functionally metadata edits; the four manual-reminder checks have already
   happened (or the video is imported, in which case they're N/A).
9. **Tags input UX** → Comma-separated text input + Stimulus controller that
   splits on comma and renders pills. No new JS dependency.
10. **Sync-back failure rollback** → Optimistic (option a). Local state stays as
    the user requested; `last_sync_error` surfaces inline; user re-edits to
    recover. The "out of sync with YouTube" gap is bounded by user response
    time.
11. **`Project#has_many :videos` `dependent:`** → `:nullify`. Confirming the Q1
    lock. Videos survive project deletion with `project_id` nulled.
12. **`youtube_video_id` uniqueness** → Switch to case-sensitive. YouTube IDs
    are case-sensitive on the URL side; the existing case-insensitive uniqueness
    is semantically wrong. Migration changes the unique index.
13. **Tags column type** → `jsonb`. Consistent with existing `app_settings.*`
    jsonb columns; GIN-indexable; serializes cleanly through to the YouTube API.

## Acceptance

A reviewer agent or the user can verify each line:

- [ ] Migration runs cleanly on a post-Phase-9 schema. `db/schema.rb` shows
      every new column with the declared type, nullability, and default per the
      "Schema migration" section.
- [ ] `videos` table has `project_id`, `title`, `description`, `tags`,
      `category_id`, `thumbnail_url`, `privacy_status`, `publish_at`,
      `published_at`, `self_declared_made_for_kids`, `made_for_kids_effective`,
      `contains_synthetic_media`, `etag`, `pre_publish_checked_at`,
      `pre_publish_game_ok`, `pre_publish_age_ok`,
      `pre_publish_paid_promotion_ok`, `pre_publish_end_screen_ok`,
      `last_sync_error`, `duration_seconds`. (`star`, `last_synced_at`,
      `youtube_video_id`, `channel_id`, `youtube_connection_id` survive
      untouched.)
- [ ] `playlist_videos` table exists with the column shape per "Schema
      migration".
- [ ] `Video` model has the associations + validations + enums + callbacks +
      scopes + public methods listed in "Model layer".
- [ ] `Project#has_many :videos, dependent: :nullify` works (deleting a project
      nullifies linked videos).
- [ ] `VideosController` exposes `edit`, `update`, `pre_publish_checklist`,
      `publish`, `schedule` actions, each gated by the strong-params policy.
- [ ] Edit form renders the writable subset; smuggled attributes
      (privacy_status, publish_at, etag, etc.) silently dropped or explicitly
      rejected.
- [ ] Pre-publish modal renders with four checkboxes + four Studio deep-links.
      Submit button disabled until all four checked.
- [ ] NO JS `confirm()` / `alert()` / `prompt()` / `data-turbo-confirm` anywhere
      in the new code. CLAUDE.md hard rule upheld.
- [ ] Boundary booleans serialize as `"yes"` / `"no"` strings (form params,
      decorator output, MCP tool I/O).
- [ ] `VideoSyncBack` job: read-modify-write semantics; fails-cleanly on quota /
      auth / validation / network errors; records each call in
      `youtube_api_calls`.
- [ ] Three new MCP tools (`update_video`, `pre_publish_check_video`,
      `publish_video`) gated on the `app` scope, two-step `confirm:     yes/no`.
- [ ] Test sweep: every test case in "Test sweep" lands as a green example.
      RSpec is green. Rubocop is clean.
- [ ] Manual playbook (steps 1-18) passes end-to-end.
- [ ] Decorator surfaces the new fields with `"yes"` / `"no"` boolean
      serialization.

## Non-goals (explicit)

- Channel sync surface (work unit 3 / Phase 11 spec).
- Analytics sync engine (work unit 5 / Phase 13).
- Game ↔ Video links (work unit 6 / Phase 14).
- CLI parity (work unit 10).
- Calendar / Notifications (work units 7-8).
- Thumbnail upload via `thumbnails.set` (separate multipart endpoint —
  follow-up).
- Playlist membership editing UX (schema lands; UX is a follow-up).
- Captions / recording-date / recording-location / default-language /
  default-audio-language / embeddable / public-stats-viewable / license — Note 1
  marks only 8 fields as both readable AND writable; this phase models exactly
  that set.
- Re-introducing the Timeline model. Per realignment Resolved ambiguity #1,
  Timeline is permanently dropped; `Video.project_id` replaces it.
