# Phase 7.5 — Step 11 — Channel Management + Multi-Layout Preview

> Pre-implementation spec. Locks the design intent for Pito's channel-level data
> model, management surface, and multi-layout preview UX BEFORE any code lands.
> Surfaces the editable subset of YouTube Channel resource fields, the
> display-only subset, and the Pito-rendered preview that lets the user see
> pending edits across web / mobile / TV layouts before committing them. This
> spec is intentionally NOT a single-dispatch specification — it enumerates the
> sub-specs (11a–11g) that the architect will write once the user resolves the
> Open Questions below.
>
> **Depends on:** Phase 7 (Google OAuth + `Youtube::Client` + audit + quota)
> committed. Path A2 (thin Channel/Video schema) committed. (Spec 05
> `pito-assets` volume is no longer required by this spec — watermark preview
> frames now ship as static files under `public/preview/`; see D9.)
>
> **Unblocks:** Phase 8's channel sync work — once the schema is in place, Phase
> 8 populates it from real API calls. Also unblocks any future channel-detail
> surface (search results, dashboard widgets, MCP `get_channel` tool).
>
> **Not in this spec:** Phase 8 mass video sync, live YouTube embed previews
> (Pito renders its own mockups), aggregations from video-level data,
> `Video.published_at` / `Video.duration_seconds` / other Phase 8 columns. Only
> `Video.title` is added here, and only because the preview's "real videos" row
> requires it (Q1 = yes).

---

## Goal

Ship a channel-management surface that exposes every YouTube Channel resource
field Pito needs to display or mutate — banner, avatar, title, handle,
description, links, watermark, plus the four read-only statistics (subscribers,
views, video count, hidden_subscriber_count). The editable subset (banner,
title, handle, description, links, watermark) goes through a Pito edit form that
pushes changes to YouTube via `Youtube::Client`; the display-only subset caches
as columns on `Channel` and refreshes via channel sync. Avatar is display-only
because YouTube's API does not expose a write path (verify against live API —
see Open Questions).

Pair the management surface with a multi-layout preview component that renders
the channel page across three viewports — web (desktop), mobile, TV — using
Pito's own HTML, NOT a YouTube embed. The Pito-rendered preview is what makes
"see pending edits before pushing them" possible: a YouTube embed shows the
current live state of the channel, while a Pito mockup shows the form's
in-flight values. The preview includes a "couple of videos" row beneath the
channel header so the user can feel the visual rhythm of the channel page; that
row uses real `Video` rows when the channel has linked videos with titles, and
falls back to static JPEG thumbnails committed under
`public/preview/video_thumbnails/` paired with curated random titles when it
does not (Q2 default; see D8).

## Scope boundary

### In-scope

**Schema additions to `Channel`:**

- `title :string` — channel display name. Mutable via API (verify; YouTube
  rate-limits to 1 change per 14 days).
- `handle :string` — `@handle`. Mutable via API (verify).
- `description :text` — channel description. Mutable.
- `country :string` — ISO 3166-1 alpha-2. Mutable.
- `default_language :string` — BCP-47 tag. Mutable.
- `keywords :text` — channel keywords (space-separated by YouTube convention).
  Mutable.
- `banner_url :string` — cache pointer to the YouTube-hosted banner CDN URL.
  Pito does NOT host the banner image; YouTube returns the URL after
  `channelBanners.insert` + `channels.update`. Pito caches it for fast page
  rendering.
- `avatar_url :string` — cache pointer to the YouTube-hosted avatar CDN URL.
  Display-only; no edit path.
- `watermark_url :string` — cache pointer to the watermark image YouTube hosts.
- `watermark_position :string` — enum-as-string (`top_left`, `top_right`,
  `bottom_left`, `bottom_right` per YouTube's actual options — verify).
- `watermark_timing :string` — enum-as-string (`always`, `entire_video`,
  `offset_from_start`, `offset_from_end` per YouTube's actual options — verify).
- `watermark_offset_ms :integer` — offset in milliseconds when timing is offset-
  based.
- `links :jsonb` — array of `{ title, url }` objects. Mutable. Backed by
  YouTube's `brandingSettings.channel.unsubscribedTrailer` /
  `featuredChannelsUrls` (verify the actual link-storage shape against the live
  API).
- `subscriber_count :bigint` — display-only.
- `view_count :bigint` — display-only.
- `video_count :integer` — display-only. Includes unlisted (per user's
  acceptance — no filtering on Pito's side).
- `hidden_subscriber_count :boolean` — display-only. When `true`, render the
  subscriber count as "Hidden" rather than the cached number.
- `published_at :timestamp` — channel creation date. Display-only.
- `title_changed_at :timestamp` — last time Pito pushed a title change.
  Client-side gate for the 14-day rate limit.
- `handle_changed_at :timestamp` — same shape for handle.

**Schema addition to `Video`:**

- `title :string` (nullable). Populated by Phase 8 sync; rendered as "untitled"
  placeholder when nil. No `thumbnail_url` column —
  `https://img.youtube.com/vi/<youtube_video_id>/mqdefault.jpg` is derived at
  render time from the existing video URL parsing. (Q1 = yes — add `Video.title`
  now.)

**New table — `channel_change_logs`:**

- `id`, `tenant_id`, `channel_id`, `field` (string — `title` or `handle`),
  `old_value` (string), `new_value` (string), `changed_at` (timestamp),
  `changed_by_user_id` (FK to `users`), timestamps. Append-only; no UPDATE or
  DELETE in normal flow.

**Channel show page** (`/channels/:id`):

- Renders all 10 field groups from the user's intent:
  - banner (web/mobile/TV preview tabs or side-by-side; user picks UX shape in
    sub-spec 11d)
  - avatar (display-only, no edit affordance, no YouTube Studio link)
  - title (display + `[ edit ]` link, with the 14-day gate)
  - handle (display + `[ edit ]` link, with the 14-day gate)
  - description (display + `[ edit ]` link)
  - links (display + `[ edit ]` link)
  - watermark (display + `[ edit ]` link, with player-mockup preview)
  - subscribers (display-only; "Hidden" when `hidden_subscriber_count`)
  - views (display-only)
  - video count (display-only)

**Channel edit page** (`/channels/:id/edit`):

- Form fields for: banner upload, title, handle, description, country, default
  language, keywords, links (repeatable), watermark upload + position
  - timing.
- Submission goes through `ChannelsController#update`, which calls
  `Youtube::Client#update_channel(channel, field_set)` and on success caches the
  response into the local columns. On 14-day rate-limit hit (defense-in- depth),
  surfaces the YouTube error with a friendly message.

**Multi-layout preview component:**

- Three layouts: web (desktop, ~1280px wide), mobile (~390px wide), TV
  (~1920x1080 with TV-specific YouTube spacing). UX shape is sub-spec 11d's call
  (side-by-side vs. tabbed; user can confirm or re-direct in Open Questions).
- Pito-rendered HTML, NOT a YouTube embed. Inputs: a `Channel` plus an optional
  "pending edits" hash. When the pending hash is present, the preview renders
  the would-be state; when it is absent, it renders the cached state.
- "Couple of videos" row underneath the channel header, using real
  `channel.videos` rows (with titles and derived thumbnails) when present,
  otherwise static JPEG thumbnails from `public/preview/video_thumbnails/`
  - curated titles per D8 (Q2).
- NO safe-zone overlays (user explicitly excluded these).
- NO YouTube Studio replication — Pito only shows the post-upload result.

**Watermark preview:**

- Sub-spec 11e. A video player mockup (play button + progress bar + faux control
  bar) with the watermark image overlaid at the configured position.
- Three size variants matching the three preview layouts (web / mobile / TV).
- The mockup background is a static JPEG drawn at random per render from
  `public/preview/watermark_frames/` (e.g., `frame-01.jpg`, `frame-02.jpg`,
  ...). The user commits 2–4 real frames at ~1920×1080 16:9 (gameplay-style or
  visually busy content so the watermark overlay is visible). No `ffmpeg lavfi`
  generation, no `bin/setup` extension, no runtime ffmpeg call. See D9.

**Banner upload flow** (sub-spec 11f):

- Client-side validates 2048x1152 minimum (or proportional 16:9). User pre-crops
  in Canva per their stated workflow; Pito does NOT bundle a cropper.
- Multi-size preview renders the uploaded image at web / mobile / TV dimensions
  before the user submits.
- Server-side: `Youtube::Client#upload_banner(channel, io)` calls
  `channelBanners.insert` (which returns a `bannerExternalUrl`), then
  `channels.update` with `brandingSettings.image.bannerExternalUrl` set to that
  URL.

**Watermark upload flow:**

- Client-side validates dimensions per YouTube's spec (verify — typically
  800x800 PNG/JPEG).
- Server-side:
  `Youtube::Client#set_watermark(channel, io, position, timing, offset_ms)`
  calls `watermarks.set`. Removal calls `watermarks.unset`.

**Sync strategy:**

- On-demand `[ sync ]` button on the show page, routing through the existing
  `/syncs/channel/:ids` confirmation framework.
- Auto-sync on first connect (when `oauth_identity_id` is set on the channel for
  the first time).
- Daily background job is **out of scope** for this dispatch — captured as a
  follow-up. (Q7.)

**Change history tracking:**

- Sub-spec 11g. Title and handle changes write a `channel_change_logs` row.
- The 14-day rate-limit gate is **client-side**: if `channel.title_changed_at`
  is within 14 days of now, the edit form hides the title input and shows "Title
  was changed on YYYY-MM-DD; YouTube limits changes to 1 per 14 days." YouTube's
  API enforces server-side too — that is defense in depth, not the primary gate.
- Same shape for handle.

**Statistics fetch:**

- `Youtube::Client#fetch_channel(channel)` calls `channels.list` with
  `part: "snippet,statistics,brandingSettings,contentDetails,status"` (or
  whatever combination minimizes calls — verify quota cost). Caches the response
  into the local columns in one transaction.

### Out of scope

- **Avatar editing.** YouTube Data API v3 does not expose a write path for
  channel avatars (verify against live API; if it turns out editable, this spec
  gets revised). No edit affordance, no YouTube Studio link per user intent.
- **Statistics-only edit.** `subscribers`, `views`, `video_count`,
  `hidden_subscriber_count` are read-only on YouTube; no edit form.
- **Phase 8 mass video sync.** Channel sync ≠ video sync. This spec only fetches
  channel-level fields plus the channel's own statistics; it does NOT walk the
  uploads playlist or hydrate per-video metadata.
- **Live YouTube embed previews.** Pito renders its own mockups (the whole point
  of the preview is to show pending edits, which an embed cannot).
- **Aggregations from video-level data** (e.g., total view count derived from
  summing per-video views). Phase 8+ territory.
- **Daily channel-sync background job.** On-demand button + auto-on-connect
  ships here; the daily Sidekiq cron is a follow-up.
- **Channel deletion / unlinking.** Out of scope for the management surface; if
  needed, surfaces through the existing bulk-delete framework.
- **Banner cropping UI.** User pre-crops in Canva.

## Sequencing

This spec produces seven sub-specs (11a–11g) which can be split across multiple
architect-spec dispatches. The dependency graph:

```
11a  schema + sync             (foundation)
 │
 ├─ 11b  show page              (depends on 11a's columns)
 │
 ├─ 11c  edit form              (depends on 11a's columns + Youtube::Client)
 │
 ├─ 11d  preview component      (depends on 11a's columns + Video.title)
 │       │
 │       └─ 11e  watermark preview  (depends on 11d's layout primitives)
 │
 ├─ 11f  banner upload          (depends on 11a + 11c)
 │
 └─ 11g  change history         (depends on 11a's columns + 11c's edit flow)
```

Implementation dispatches kick off in this order:

1. **11a** lands first (schema migration, `Channel` model additions,
   `Youtube::Client#fetch_channel`, sync button wiring). Without it, every other
   sub-spec is blocked.
2. **11b**, **11c**, **11d** can run in parallel after 11a (they touch different
   files).
3. **11e** depends on 11d's preview primitives.
4. **11f** depends on 11a + 11c.
5. **11g** depends on 11a + 11c (the gate logic lives in 11c, but the log
   table + UI are 11g).

## Decisions (locked)

### D1 — `Video.title` added now

Rationale: title is load-bearing for multiple future surfaces — search
re-introduction, channel preview's "real videos" branch, dashboard rebuild, MCP
`get_video` tool, the watch-history surface in a future phase. Adding it here
costs one column + one population path in Phase 8 sync; adding it three more
times costs three migrations and three sync-path edits. The thumbnail URL is
derived at render time from `youtube_video_id` via YouTube's deterministic CDN
URL pattern (`https://img.youtube.com/vi/<id>/mqdefault.jpg`), so no
`thumbnail_url` column is needed.

Implementation: `db/migrate/<TS>_add_title_to_videos.rb` adds `title :string`
(nullable; populated by Phase 8 sync; displayed as "untitled" when nil).

### D2 — Avatar display-only

Rationale: YouTube Data API v3 does not expose a write path for channel avatars
as of the spec's authoring date. Per user intent — research-verify read-only via
API; if confirmed, do not show an edit affordance and do NOT link to YouTube
Studio. The spec carries this as locked **pending verification** in Open
Questions; if the verification flips, the spec is revised before any 11c (edit
form) work begins.

Reference: `https://developers.google.com/youtube/v3/docs/channels/update` lists
`brandingSettings`, `localizations`, `status`, `contentOwnerDetails`, and `id`
as the parts that can be passed to `update`. Avatar (`thumbnails`) is part of
`snippet` and the API documents `snippet` as **not** part of the update part
list.

Implementation: `Channel#avatar_url` is cached for performance (so the channel
list page does not live-fetch from YouTube every paginate — D12), but no edit
path exists.

### D3 — Banner mutable via API

Rationale: `channelBanners.insert` uploads the bytes; the response includes a
`bannerExternalUrl`; `channels.update` with
`brandingSettings.image.bannerExternalUrl` set to that URL associates the upload
with the channel. Two API calls, both authenticated through `Youtube::Client`,
both audited through `youtube_api_calls`. Pito caches the resulting URL in
`channels.banner_url` for fast page rendering.

References:

- `https://developers.google.com/youtube/v3/docs/channelBanners/insert`
- `https://developers.google.com/youtube/v3/docs/channels/update`

### D4 — Watermark mutable via API

Rationale: `watermarks.set` uploads the watermark image and configures
position + timing; `watermarks.unset` removes it. Both calls are authenticated
and audited the same way. Pito caches `watermark_url` + `watermark_position` +
`watermark_timing` + `watermark_offset_ms` locally.

References:

- `https://developers.google.com/youtube/v3/docs/watermarks/set`
- `https://developers.google.com/youtube/v3/docs/watermarks/unset`

### D5 — Title / handle 14-day rate limit gate is client-side

Rationale: YouTube limits title and handle changes to 1 per 14 days server-side
(verify the exact limit and which fields it applies to). Pito also enforces the
gate client-side: the edit form hides the title input when
`channel.title_changed_at` is within 14 days of now and renders an explanatory
message instead. Same for handle. This is UX, not security: a determined user
could call YouTube's API directly via the browser console or curl and would get
YouTube's own rate-limit response, which Pito surfaces as a friendly error.
Defense in depth, not the primary gate.

### D6 — `channel_change_logs` table tracks title / handle changes

Rationale: per user intent, "keep change history" for title (and by extension
handle, since they have the same rate-limit shape). One table for both fields;
`field` column distinguishes them. Append-only — the table records "what was the
title before, what is it now, when did Pito push the change, which user pushed
it." No UPDATE / DELETE in normal flow; if the user revokes a Google identity,
the rows survive (they reference `user_id`, not `google_identity_id`).

### D7 — Preview is Pito-rendered, three layouts, no safe zones

Rationale: a YouTube embed shows the channel's current live state. The whole
point of the preview is "see pending edits before committing them", which an
embed cannot show. Pito renders the preview as plain HTML/CSS parameterized by a
`Channel` + an optional "pending edits" hash — when the form is dirty, the
preview reflects the form's current values, not the cached database values.

Three layouts — web, mobile, TV — match YouTube's three primary delivery
surfaces. Side-by-side vs. tabbed UX is 11d's call; the user can override in
Open Questions.

NO safe-zone overlays. User explicitly excluded these. The user uses Canva for
image prep and does not need Pito to replicate YouTube Studio's guides. Pito's
job is "show the post-upload result", not "duplicate Studio".

### D8 — Preview's "videos" row uses real videos when available, static JPEG thumbnails otherwise

Rationale: per Q2 default. When `channel.videos` has rows with titles populated
(Phase 8+ scenario), the preview renders ~6 of them under the channel header.
When the channel has no linked videos with titles (Phase 7.5 + early Phase 8
scenario), the preview falls back to **static JPEG files committed under
`public/preview/video_thumbnails/`** (e.g., `thumb-01.jpg`, `thumb-02.jpg`, ...)
paired with random titles drawn from a curated array (e.g., "How I built X in a
weekend", "Devlog #42", "Friday gaming session", "Setting up my new studio",
"Why I switched to Linux", "Reacting to my old videos", "Building a PC under
$1000", "Behind the scenes — channel intro").

**No CSS gradients** — the user explicitly wants natural-looking thumbnails, not
artificial-looking placeholders. The user drops 4–8 JPEG files at ~1280×720
(16:9) into `public/preview/video_thumbnails/`. A Ruby helper
(`PreviewHelper#random_video_thumbnail`) globs the directory and picks one per
render so each refresh shows a different mix (fake dynamicity from a small fixed
pool). If the directory is empty (the user has not dropped files yet), the
preview shows a small `[ no preview thumbnails yet ]` text fallback in place of
each thumbnail.

The curated title array is a Ruby constant in `app/helpers/preview_helper.rb`
(per Q10). About 20 entries; sampling is deterministic per channel id so the
same channel always gets the same title set across reloads (no flicker as the
user drags between layouts). The curated titles also pair with the random
thumbnail when no backing `Video.title` exists.

### D9 — Watermark preview uses static JPEG frames committed in the repo

Rationale: per Q3 / Q11. **Static JPEG files committed under
`public/preview/watermark_frames/`** (e.g., `frame-01.jpg`, `frame-02.jpg`, ...)
supply the player-mockup background. The user provides real frames — recommended
2–4 files at ~1920×1080 (16:9), gameplay-style or visually busy content (not
solid-color, so the watermark overlay is visible against the frame). Random pick
per render via the same `PreviewHelper#random_watermark_frame` that backs D8's
thumbnails. The watermark preview component composes the user's watermark image
over the chosen frame at the configured position.

**No `ffmpeg lavfi` generation, no runtime ffmpeg call, no `bin/setup` step.**
The frames ship in the repo; every install renders them as-is. If
`public/preview/watermark_frames/` is empty, the watermark preview shows the
same `[ no preview frames yet ]` text fallback as the thumbnails branch (D8).

The frames live under `public/preview/` rather than the `pito-assets` volume
(spec 05) because they are static design fixtures, not user-generated content —
they belong with the app source, not in the mounted-volume runtime tree.

### D10 — Statistics fetch on every channel sync

Rationale: `channels.list` returns snippet, statistics, brandingSettings,
contentDetails, status all in a single 1-unit call (per `docs/youtube_quota.md`
cost table). There is no separate per-stat endpoint to call; one `channels.list`
invocation refreshes everything Pito caches. No micro-optimization for "only
fetch statistics, not branding" because the cost is identical.

### D11 — Channel sync: on-demand button + auto-on-connect

Rationale: the existing `/syncs/channel/:ids` framework handles on-demand sync
via the bulk-as-foundation pattern. Auto-on-connect runs when a channel
transitions from `oauth_identity_id IS NULL` to non-NULL (the
`after_update_commit` hook on `Channel`). A daily background job is deferred —
captured as a follow-up — because (a) the user explicitly flagged "on-demand
`sync now` button, plus optional daily Sidekiq job" which already implies the
daily job is optional, and (b) Phase 8 will build the broader sync orchestration
that includes channels and videos together.

### D12 — Avatar URL still cached for performance

Rationale: the channel list page (`/channels`) renders N rows; each row shows a
small avatar. Live-fetching from YouTube on every paginate would add N \*
round-trip latency and burn N quota units per page load. Caching the URL in
`channels.avatar_url` lets the page render with `<img>` tags that point directly
at YouTube's CDN — Pito's server is bypassed entirely for the actual image
bytes. The cached URL refreshes on every sync.

### D13 — `links` stored as `jsonb` array of `{ title, url }`

Rationale: YouTube's links surface (the channel banner's "Links" section) takes
an array of titled URLs. Postgres `jsonb` is the established storage shape for
array+object data in Pito (per `docs/architecture.md` "json vs jsonb"). Schema
constraint: each entry validates `title` is present and `url` matches a strict
URL regex; the whole array is capped at 5 entries (YouTube's documented limit —
verify).

### D14 — Banner upload accepts any image; client-side warns on aspect-ratio mismatch

Rationale: YouTube's API itself validates dimensions (2048x1152 minimum, 16:9
ratio). Pito's UI warns the user with a non-blocking message if the uploaded
image is below 2048x1152 or off-ratio, but submits anyway. If YouTube rejects,
the rejection surfaces as a form error. This avoids the "Pito's pre-validation
is stricter than YouTube's" trap. (Q5 default.)

### D15 — Watermark position uses YouTube's actual options

Rationale: per Open Question Q3 — the user wants "three position options
(left/center/right OR top/middle/bottom)" but YouTube's API documents specific
corners (likely 4 corners). The spec uses YouTube's actual options as truth; the
UI surfaces them with the user's preferred labels. Verify against
`https://developers.google.com/youtube/v3/docs/watermarks/set`.

### D16 — Watermark timing uses YouTube's actual options

Rationale: same as D15 for timing. YouTube's documented options likely include
`always`, `entire_video`, `offset_from_start`, `offset_from_end` (verify). Pito
surfaces all of them.

### D17 — Change history retention is keep-all

Rationale: Q6 default. The volume is tiny (1 row per title change per channel,
plus 1 per handle change; the 14-day gate caps the rate at 26 rows per channel
per year). Pruning logic costs more than the storage saved. If the volume ever
becomes a problem, a follow-up spec adds a retention policy.

### D18 — `published_at` cached separately from `created_at`

Rationale: `channels.created_at` is when Pito first saw the channel.
`channels.published_at` is when YouTube shows the channel was created on
YouTube. Two different timestamps, both useful — display the YouTube one on the
show page, use Pito's for internal sorting.

## Open questions

These must be answered before implementation dispatches kick off. Numbered
locally; the master agent rolls them into the phase-overview Open Questions list
and pings the user for resolution.

**Q1 — Handle / title editability via live API.** YouTube's documented update
behavior for channel title and `@handle` should be re-verified against the live
API. Specifically: (a) is title mutable via `channels.update` with
`brandingSettings.channel.title`, or only via YouTube Studio? (b) is handle
mutable via the API at all, or YouTube-Studio-only? (c) what is the exact
rate-limit window — is it 14 days, 1 change per N days, or something else? A
research dispatch resolves this; the spec may need amendment depending on the
answer. If handle / title turn out to be Studio-only, the edit form shrinks
accordingly and the show page shows them read-only with a "edit on YouTube
Studio" link (in tension with the user's no-Studio-link directive for avatar;
will need user re-confirm).

**Q2 — Banner upload UX.** Drag-drop, file-picker `<input type="file">`, or
both? Inline cropping support, or assume the user pre-cropped in Canva (per
user's stated workflow)? Default: file-picker only, no cropping (user uses
Canva). Confirm.

**Q3 — Watermark position options.** YouTube's actual options are most likely 4
corners (`top_left`, `top_right`, `bottom_left`, `bottom_right`) per the
`watermarks.set` documentation. The user mentioned "three position options
(left/center/right OR top/middle/bottom)" which does not match. Resolve: which
set of options does the API actually accept, and does the user want Pito to
expose all of them or a curated subset? Verify against
`https://developers.google.com/youtube/v3/docs/watermarks/set`.

**Q4 — Watermark timing options.** Likely `always` / `entire_video` /
`offset_from_start` / `offset_from_end` per YouTube standard; confirm against
the live API and decide whether Pito surfaces all four or curates. The "last
15s" / "5s after start" defaults the user mentioned map to `offset_from_end`
with `offset_ms = 15_000` and `offset_from_start` with `offset_ms = 5_000`;
expose both.

**Q5 — Banner aspect-ratio enforcement.** Reject the upload client-side if not
2048x1152 (or proportional 16:9), or accept any size and let YouTube's API
reject? D14's locked answer is "warn but submit" — confirm or flip.

**Q6 — Change history retention.** Keep all (D17), keep last 5, time-bounded
(last 90 days), rolling delete after a year? D17's locked answer is keep- all;
confirm.

**Q7 — Sync strategy default.** D11's locked answer is on-demand button +
auto-on-connect, no daily background job in scope. Confirm; the daily job is
captured as a follow-up regardless.

**Q8 — Preview UX shape.** Side-by-side (all three layouts visible at once,
~horizontal scroll on smaller windows) or tabbed (one layout visible,
`[ web ] [ mobile ] [ TV ]` selectors)? Ergonomic preference is the user's;
sub-spec 11d picks the default and the user can override.

**Q9 — Avatar editability.** D2 marks it display-only **pending live API
verification**. If the verification turns up an edit path Pito missed, the spec
gets revised before 11c lands. Confirm research dispatch covers this.

**Q10 — Pre-loaded "channel videos" curated titles. RESOLVED.** **Resolution:**
Ruby constant in `app/helpers/preview_helper.rb` for now. Move to i18n if/when
localization becomes a concern. The curated array provides random titles when
D8's "no real Video records linked" branch fires AND when the random thumbnail
is shown without a backing `Video.title`.

**Q11 — Watermark preview frame: regenerate per-install or ship in repo?
RESOLVED.** **Resolution:** Ship in repo. Static JPEG files live under
`public/preview/watermark_frames/` (per D9). No `ffmpeg lavfi` step, no
`bin/setup` extension, no regeneration.

**Q12 — Auto-sync on connect: blocking or async?** When the user connects a
channel to a Google identity, should the page wait for the sync to finish
(blocking, ~1–2 sec) or return immediately and let the user reload? Default:
async, surface a `[ syncing... ]` indicator that swaps to the hydrated state via
Turbo Stream. Confirm.

## Implementation plan

Seven sub-specs split the work. Each is a separate architect-spec dispatch once
the user resolves the Open Questions above; each in turn becomes a rails-impl
dispatch.

### 11a · `channel-schema-and-sync.md`

**Scope:** schema migration adding all new `Channel` columns + the
`channel_change_logs` table + the `Video.title` column. `Channel` model
additions (validations on title length / description length / links shape /
country format / language tag format / watermark enums). Extend
`Youtube::Client` with `fetch_channel(channel)` calling `channels.list` with
full part set, parsing the response, caching to local columns. Wire the existing
`[ sync ]` button on `/channels/:id` so it triggers the new fetch path through
the existing `BulkSyncJob` framework. Auto-sync on connect via
`after_update_commit` hook detecting `oauth_identity_id` transition.

**Files touched:** `db/migrate/<TS>_add_channel_resource_fields.rb`,
`db/migrate/<TS>_create_channel_change_logs.rb`,
`db/migrate/<TS>_add_title_to_videos.rb`, `app/models/channel.rb`,
`app/models/channel_change_log.rb`, `app/models/video.rb`,
`app/services/youtube/client.rb`, `app/jobs/channel_sync.rb`, RSpec coverage for
all of the above.

**Effort estimate:** medium. Schema is the bulk; sync wiring extends an existing
path.

### 11b · `channel-show-page.md`

**Scope:** render the cached fields on `/channels/:id` (read-only). All 10 field
groups visible. Avatar shown without edit affordance per D2. Stats shown
including the `hidden_subscriber_count` "Hidden" treatment. Watermark section
shows the cached image + position + timing in a small preview; banner section
shows the cached banner with the multi-layout preview tabs (or side-by-side per
Q8). `[ edit ]` links to the editable subset point at
`/channels/:id/edit#<field>`.

**Files touched:** `app/views/channels/show.html.erb`,
`app/components/channel_preview_component.{rb,html.erb}` (or partial, sub-spec
11d's call), `app/helpers/channels_helper.rb`, RSpec system spec.

**Effort estimate:** small. Pure view work.

### 11c · `channel-edit-form.md`

**Scope:** the edit form at `/channels/:id/edit`. Form fields for the editable
subset. `ChannelsController#update` dispatches to
`Youtube::Client#update_channel` with the dirty subset; on success caches the
response into local columns; on rate-limit / quota / unauthorized, renders a
friendly form error. The 14-day gate logic: if `title_changed_at` is within 14
days, hide the title input and explain. Same for handle. Banner and watermark
inputs are file-pickers (per Q2/Q3 defaults); they hand off to sub-specs 11f and
(the watermark portion of) 11c respectively (the watermark upload itself goes
through `watermarks.set` which is part of 11c since it is a single-call flow).

**Files touched:** `app/views/channels/edit.html.erb`,
`app/controllers/channels_controller.rb`, `app/services/youtube/client.rb`
(extend with `update_channel`, `set_watermark`, `unset_watermark`), RSpec
request + system specs.

**Effort estimate:** medium-large. The form touches every editable field; the
controller dispatches multiple API calls.

### 11d · `channel-preview-component.md`

**Scope:** the multi-layout preview component. Renders a Pito-built channel-page
mockup at three viewport sizes. Inputs: a `Channel` plus an optional
pending-edits hash. Output: HTML/CSS that approximates YouTube's channel page
across web / mobile / TV.

UX shape: Q8 default is tabbed (one layout visible, switch via
`[ web ] [ mobile ] [ TV ]` selectors); side-by-side is the alternative. The
sub-spec picks the default and surfaces the choice for confirmation.

The "couple of videos" row uses `channel.videos.where.not(title: nil)` when
present (taking up to 6); falls back per D8 to **static JPEG files under
`public/preview/video_thumbnails/`** (random pick per render via
`PreviewHelper#random_video_thumbnail`) paired with curated titles. The curated
title array is a Ruby constant in `app/helpers/preview_helper.rb` per Q10
(resolved). If `public/preview/video_thumbnails/` is empty, each slot falls back
to a `[ no preview thumbnails yet ]` text marker.

NO safe-zone overlays. NO YouTube Studio replication. NO CSS-gradient
placeholders — the user explicitly wants natural thumbnails, not
artificial-looking ones.

**Files touched:** `app/components/channel_preview_component.{rb,html.erb}`,
`app/components/channel_preview/{web,mobile,tv}_layout_component.*` (or a single
component with a layout flag — implementation agent picks),
`app/helpers/preview_helper.rb` (new — houses `random_video_thumbnail`,
`random_watermark_frame`, and the curated title constant),
`app/assets/stylesheets/channel_preview.css`, the static JPEG fixtures under
`public/preview/video_thumbnails/` (the user drops these in; the implementation
agent ensures the directory exists and the helper handles the empty case), RSpec
component + helper specs.

**Effort estimate:** large. CSS is the bulk; getting three layouts to feel right
is iterative.

### 11e · `watermark-preview.md`

**Scope:** the player-mockup preview that overlays the user's watermark on a
static frame at the configured position. Three size variants (web / mobile /
TV). Reads a random JPEG from `public/preview/watermark_frames/` per render via
`PreviewHelper#random_watermark_frame` (the helper introduced in 11d). **No
`bin/setup` extension. No `ffmpeg lavfi` filter chain. No runtime ffmpeg call.**
The frames are static fixtures the user drops in (recommended 2–4 files at
~1920×1080 16:9, gameplay-style or visually busy so the watermark overlay
reads).

If `public/preview/watermark_frames/` is empty, the component renders a
`[ no preview frames yet ]` text fallback in place of the frame.

**Files touched:** `app/components/watermark_preview_component.{rb,html.erb}`,
`app/helpers/preview_helper.rb` (extend with `random_watermark_frame` if 11d did
not already), the static JPEG fixtures under `public/preview/watermark_frames/`
(user-supplied), RSpec component + helper specs. Also reaches into 11d's preview
component to render the watermark inside the channel-page mockup's video-row
thumbnails (one watermark, all three layouts). **`bin/setup` is NOT touched.**

**Effort estimate:** small. With ffmpeg out of the picture this is straight
component + helper work.

### 11f · `banner-upload-flow.md`

**Scope:** the banner upload flow specifically. Client-side image-dimension read
(`HTMLImageElement` natural dimensions or `createImageBitmap`-then-measure).
Multi-size client-side preview before submission. Server-side upload through
`Youtube::Client#upload_banner` (which calls `channelBanners.insert` and then
`channels.update` with the resulting URL). Caches `banner_url` on success.

Per D14, Pito's UI warns the user on aspect-ratio / dimension mismatch but does
not block submission; YouTube's API is the authoritative validator.

**Files touched:** `app/javascript/controllers/banner_upload_controller.js`,
`app/views/channels/_banner_upload.html.erb` (partial included by 11c's edit
form), `app/services/youtube/client.rb` (extend with `upload_banner`), RSpec
system spec.

**Effort estimate:** medium. The Stimulus controller for client-side preview is
the bulk.

### 11g · `change-history.md`

**Scope:** title / handle change tracking. `ChannelChangeLog` model.
`Channel#record_change!(field, old, new, user)` helper called by 11c's update
path on every successful title or handle push. Write `title_changed_at` /
`handle_changed_at` as a side effect. Render the recent changes (last N) on the
channel show page below the field. The 14-day gate logic itself is part of 11c;
the LOG and the UI to view it are 11g.

**Files touched:** `app/models/channel_change_log.rb` (defined in 11a, but
extended here with scopes / display helpers),
`app/views/channels/_change_history.html.erb` (new partial, included on the show
page), `app/views/channels/show.html.erb` (add the partial), RSpec request +
view specs.

**Effort estimate:** small. Append-only table; minimal UI.

## Acceptance

These boxes must check before this spec closes (i.e., before the last sub-spec's
implementation lands and Phase 7.5 advances).

- [ ] All schema additions land via reversible migrations. `down` cleanly
      reverses every column add and table create.
- [ ] Existing Phase 4 + 5 + 6 + 7 features unbroken — `bundle exec rspec`
      passes including the cross-tenant leak spec.
- [ ] Channel show page (`/channels/:id`) displays all 10 field groups.
- [ ] Channel edit page (`/channels/:id/edit`) exposes the editable subset
      (banner, title, handle, description, country, default language, keywords,
      links, watermark + position + timing). Avatar has no edit affordance.
- [ ] Preview component renders correctly across web / mobile / TV layouts.
      Pending-edits hash shifts the rendered state without database writes.
- [ ] Watermark preview renders correctly across the three sizes and all
      configured positions.
- [ ] All flows have aggressive validation specs (per the user's standing
      directive on spec coverage): unit specs for model validations, request
      specs for controller actions, system specs for the form + preview + scrub
      interactions.
- [ ] 14-day rate limit enforced client-side: the form hides the title / handle
      inputs when within the window. Direct-API bypass attempts (curl, browser
      console) return YouTube's own 429, which the controller surfaces as a
      flash error.
- [ ] Change history table records every title / handle push. Show page renders
      the recent N entries.
- [ ] No JS `alert` / `confirm` / `prompt` introduced. No `data-turbo-confirm`.
      All destructive or significant actions go through the existing
      `_action_screen` framework.
- [ ] Bracketed-link convention (`[ label ]`) on every clickable element.
      Monospace font. Yes/no boundary on any external surface (none in this
      spec, but verify if any MCP tools are added).
- [ ] `Youtube::Client` calls all flow through the audit + quota chokepoint per
      Phase 7's contract.
- [ ] Banner / watermark uploads do NOT touch Pito's `pito-assets` volume for
      the source image — YouTube hosts the canonical bytes, Pito only caches the
      URL.
- [ ] `public/preview/video_thumbnails/` and `public/preview/watermark_frames/`
      exist as committed directories. The `PreviewHelper` random-pick methods
      handle both populated and empty states (text fallback) without raising.
- [ ] `Video.title` migration + `Video#title` column exist; render path handles
      nil gracefully ("untitled").
- [ ] Manual playbook for end-to-end validation runs cleanly on the user's live
      Google account.

## Manual test plan

What the user does in a browser to validate the work after every sub-spec lands.
Each sub-spec writes a tighter recipe; this is the cumulative walk-through.

### Prereqs

- Phase 7 OAuth identity connected with at least one owned channel.
- A test channel on YouTube the user controls (NOT the user's main channel, to
  avoid accidental rate-limit hits on title changes).
- (Optional, for non-empty preview rendering) the user has dropped a handful of
  JPEGs into `public/preview/video_thumbnails/` and
  `public/preview/watermark_frames/`. If empty, the preview surfaces text
  fallbacks instead of broken images — both cases are valid.

### Walk-through

1. `bin/setup` (fresh install) — no watermark-preview-frame generation step
   runs. Confirm `public/preview/watermark_frames/` and
   `public/preview/video_thumbnails/` exist as directories in the repo checkout
   (they ship in the repo, populated with the user's static JPEG fixtures). If
   the user has not yet dropped files in, the directories may be empty — that is
   fine; the preview shows `[ no preview frames yet ]` /
   `[ no preview thumbnails yet ]` text fallbacks rather than broken images.
2. `bin/dev`. Open `/channels`.
3. Connect the test channel to a Google identity (Phase 7 flow).
4. Watch the channel row transition through `[ syncing... ]` to a hydrated
   state. Avatar + title + subscriber count appear inline.
5. Click into the channel → `/channels/:id`. The show page renders all 10 field
   groups: banner (multi-layout preview tabs or side-by-side per Q8), avatar (no
   edit affordance, no Studio link), title, handle, description, links,
   watermark (with the player-mockup preview), subscribers, views, video count.
6. Click `[ edit ]` next to title. Change the title. Submit. Watch the form
   succeed; the page reloads and the new title is visible.
7. Click `[ edit ]` next to title again. The input is hidden; the page shows
   "Title was changed on YYYY-MM-DD; YouTube limits changes to 1 per 14 days."
   Same for handle.
8. Open `/channels/:id/edit`. Upload a new banner image. The multi-size preview
   renders in three layouts before submission. Submit. Wait for the YouTube CDN
   to flush; reload; the new banner renders.
9. Edit the watermark — upload a new image, change position to `bottom_right`
   (or whatever YouTube's options are), set timing to `offset_from_start` with
   `offset_ms = 5000`. Submit. The watermark preview updates immediately to
   reflect the new state.
10. Edit description. Add a long description with multiple paragraphs. Submit.
    Show page renders the new description.
11. Edit links. Add 3 links with titles + URLs. Submit. Show page renders the
    link list.
12. Click `[ sync ]` on the show page. Watch the sync confirmation page;
    confirm. Watch the channel re-fetch and statistics update (subscribers,
    views, video count).
13. Inspect the change history section on the show page. The two title pushes
    (or one title + one handle) appear in the list.
14. Resize the browser window to mobile dimensions. The preview tabs (or
    side-by-side layout, per Q8) remain accessible.
15. Disconnect the Google identity (Phase 7 flow). Reload `/channels/:id`. The
    cached fields still render; the `[ edit ]` links are hidden (or disabled
    with a "reconnect to edit" message). Reconnect; edit works again.
16. Try to submit a title change directly via curl with the Phase 5 API token,
    bypassing Pito's UI gate. YouTube's 429 surfaces; Pito's API response
    includes a friendly error message.
17. `bundle exec rspec` green; `bundle exec rubocop` green.

## Cross-stack scope

- **Rails (Web Puma)** — **in scope.** All sub-specs land here.
- **MCP** — **out of scope** for this dispatch. A future
  `update_channel_metadata` MCP tool could expose the editable subset; captured
  as a follow-up. Avatar / stats fall under any future `get_channel` tool but
  are not in 7.5.
- **`pito` CLI** — **out of scope** for this dispatch. The CLI's channel surface
  is read-only today; surfacing the edit form on the TUI is a later concern.
- **Cloudflare Pages website** — **out of scope.**

## Follow-ups created

- **Daily channel-sync background job.** D11 / Q7. A sidekiq-cron entry that
  walks every channel with a connected Google identity and re-fetches every N
  hours / daily. Park.
- **`get_channel` and `update_channel_metadata` MCP tools.** When the MCP
  surface is ready to expose channel-level data + edits to non-browser
  consumers. Park.
- **CLI channel detail screen with edit form parity.** When the TUI grows beyond
  read-only. Park.
- **Channel avatar editability.** If Q9 verification turns up an edit path, open
  a focused spec to add it (with the YouTube Studio link the user currently
  rejected, since it would no longer apply if Pito itself can edit).
- **Banner cropper UI.** If the user moves away from Canva, a Pito-side cropper.
  Park.
- **Per-video watermark.** YouTube's watermark is channel-level; per-video
  branding lives in InfoCards / EndScreens. Future Phase. Park.
- **Localization fields.** YouTube exposes `localizations` for title /
  description per locale. Pito treats only the default locale today; multi-
  locale is a Theta concern. Park.

## Concerns flagged during writing

- **D2 / Q9 — avatar editability assumption is not verified.** The spec marks it
  locked-pending-verification. If the verification turns up that avatar IS
  editable via API, the spec needs amendment before 11c lands — the edit form
  shape changes (one extra field). The user's "no YouTube Studio link" directive
  becomes consistent in either branch (if Pito can edit, no Studio link is
  needed; if Pito cannot, the user has explicitly said no link).
- **Q1 — handle / title editability assumption is not verified.** Same shape as
  Q9. If handle is Studio-only, the form shrinks. If title is Studio-only, the
  form shrinks more, the 14-day gate logic still applies to the show page's
  "last changed at" display, and the change-history table degrades to a manual
  log of "user reported a YouTube-Studio change at this time." The user should
  resolve this BEFORE 11c is dispatched.
- **`Video.title` is the only Phase 8 column reaching forward.** Adding it here
  is a deliberate exception — it unlocks the preview's "real videos" branch, and
  Phase 8 will populate it during sync. No other Phase 8 columns are added. If
  during sub-spec writing it becomes clear that another column is also
  load-bearing for the preview (e.g., a per-video view count display), the spec
  gets amended; otherwise it stays narrow.
- **Banner / watermark URL caching is a sync trust issue.** `banner_url` /
  `avatar_url` / `watermark_url` are YouTube CDN URLs that YouTube can rotate
  without notice. If the cached URL goes stale (YouTube reassigns the CDN host,
  the bytes 404), Pito's preview shows a broken image silently. Mitigation:
  every channel sync refreshes the URLs. If a sync has not run in a while, the
  user's preview can break. Phase 8's daily sync background job (deferred
  follow-up) closes this gap.
- **The 14-day rate-limit window is on YouTube's clock, not Pito's.** Pito
  records `title_changed_at` from the API response timestamp, not from Pito's
  wall clock. If the user changed the title via YouTube Studio outside of Pito,
  Pito's `title_changed_at` is stale and the gate is wrong (Pito shows the form
  open, YouTube returns 429). Mitigation: a channel sync refreshes
  `title_changed_at` from YouTube's response if YouTube exposes it (verify);
  otherwise the gate is best-effort and the fallback is YouTube's own
  server-side 429.
- **Path A2 contradiction risk.** Path A2 deliberately stripped Channel / Video
  metadata to "thin reference records". This spec adds back many of the columns
  Path A2 removed. The architectural justification is that Path A2 was a retract
  to clear noise before Phase 8 / 7.5 rebuilt intentionally — this spec IS the
  intentional rebuild. The phase-overview out-of-scope clause "no Path A2
  reversal" needs nuance: Path A2 is not reversed, but the columns it dropped
  are re-added with explicit ownership and explicit sync paths. Surface this for
  user acknowledgement.
- **Spec 05 dependency on `Pito::AssetsRoot` — RESOLVED / DROPPED.** Earlier
  drafts of D9 routed the watermark preview frame through
  `Pito::AssetsRoot.path("system", ...)`, which would have required spec 05 to
  ship a `system/` subdir. The corrected D9 ships static JPEG frames under
  `public/preview/watermark_frames/` in the repo, so this spec no longer depends
  on the `pito-assets` volume. Left here as a paper-trail entry so future
  readers know why the dependency was removed.
- **`channels.list` part set quota cost.** The cost table says `channels.list`
  is 1 unit regardless of part set; verify this is still true. If it changes to
  per-part billing, the sync strategy is unchanged but
  `youtube_api_calls.quota_cost` reflects the actual cost.
