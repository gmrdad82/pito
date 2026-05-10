# Phase 7.5 — Step 11 — Channel Management + Multi-Layout Preview

> Pre-implementation spec. Locks the design intent for Pito's channel-level data
> model, management surface, and multi-layout preview UX BEFORE any code lands.
> Surfaces the editable subset of YouTube Channel resource fields, the
> display-only subset, and the Pito-rendered preview that lets the user see
> pending edits across web / mobile / TV layouts before committing them. This
> spec is intentionally NOT a single-dispatch specification — it enumerates the
> sub-specs (11a–11i) that the architect will write once the user resolves the
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
as columns on `Channel` and refreshes via channel sync. Avatar is **display-only
PENDING live API verification** — a research dispatch confirms the read-only
posture before any 11c (edit form) work begins, and the spec is amended if the
research turns up an edit path (see D2 + Q9).

Pair the management surface with a multi-layout preview component that renders
the channel page across three viewports — web (desktop), mobile, TV — using
Pito's own HTML, NOT a YouTube embed. The Pito-rendered preview is what makes
"see pending edits before pushing them" possible: a YouTube embed shows the
current live state of the channel, while a Pito mockup shows the form's
in-flight values. The preview surfaces as a **wide modal with top nav
`[desktop] [mobile] [tv]` selectors** (see D23), NOT side-by-side. The preview
includes a "couple of videos" row beneath the channel header so the user can
feel the visual rhythm of the channel page; that row uses real `Video` rows when
the channel has linked videos with titles, and falls back to static JPEG
thumbnails committed under `public/preview/video_thumbnails/` paired with
curated random titles when it does not (Q2 default; see D8).

## Scope boundary

### In-scope

**Schema additions to `Channel`:**

- `title :string` — channel display name. Mutable via API (verify against live
  API per Q1; YouTube rate-limits to 1 change per 14 days).
- `handle :string` — `@handle`. Mutable via API (verify per Q1).
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
  Display-only **pending live API verification** (D2 / Q9); no edit path under
  the current posture.
- `watermark_url :string` — cache pointer to the watermark image YouTube hosts.
- `watermark_timing :string` — enum-as-string (`always`, `entire_video`,
  `offset_from_start`, `offset_from_end` — verified live, all four exposed if
  the API accepts them, per Q4).
- `watermark_offset_ms :integer` — offset in milliseconds when timing is offset-
  based.
- ~~`watermark_position`~~ — **DROPPED per D21.** YouTube only supports the
  right-hand corner (image evidence + live-API verification — see Q3). The
  column is removed from this spec entirely; the UX shrinks to "watermark image
  - display time" with no position selector.
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

- `id`, `channel_id`, `field` (string — `title` or `handle`), `old_value`
  (string), `new_value` (string), `changed_at` (timestamp), `changed_by_user_id`
  (FK to `users`), timestamps. Append-only; no UPDATE or DELETE in normal flow.
  No `tenant_id` (single-install + multi-user).

**Channel show page** (`/channels/:id`):

- Renders all 10 field groups from the user's intent:
  - banner (opens the wide-modal multi-layout preview — see D23)
  - avatar (display-only, no edit affordance, no YouTube Studio link — pending
    live-API verification per D2)
  - title (display + `[edit]` link, with the 14-day gate)
  - handle (display + `[edit]` link, with the 14-day gate)
  - description (display + `[edit]` link)
  - links (display + `[edit]` link)
  - watermark (display + `[edit]` link, with player-mockup preview)
  - subscribers (display-only; "Hidden" when `hidden_subscriber_count`)
  - views (display-only)
  - video count (display-only)
- **Daily diff-check banner** (D20). When the daily diff-check job (sub-spec
  11i) detects YouTube-side values that diverge from Pito's cached columns, a
  flash-style in-page banner appears with `[review changes]` linking to
  `/channels/:id/diff`. No overwrite without user confirmation.

**Channel edit page** (`/channels/:id/edit`):

- Form fields for: banner upload, title, handle, description, country, default
  language, keywords, links (repeatable), watermark upload + timing.
- Submission goes through `ChannelsController#update`, which calls
  `Youtube::Client#update_channel(channel, field_set)` and on success caches the
  response into the local columns. On 14-day rate-limit hit (defense-in-depth),
  surfaces the YouTube error with a friendly message.
- **14-day-gate reminder hook (D19).** When the gate fires on
  `/channels/:id/edit` (title or handle within window), render a
  `[remind me on YYYY-MM-DD]` link that silently POSTs to
  `/calendar/entries.json` and auto-creates a `CalendarEntry` of kind
  `:reminder` with prefilled values
  (`title = "Channel title unlock — <channel name>"`,
  `starts_at = unlock_date`). The user stays on `/channels/:id/edit`; a
  flash-style toast confirms "Reminder created for YYYY-MM-DD". NO redirect. The
  user can edit the entry later by visiting `/calendar` directly. Calendar
  integration lives in **sub-spec 11h**.

**Channel diff page** (`/channels/:id/diff`):

- New page introduced by D20. Three-column layout: `Pito` | `YouTube` |
  `decision`. The decision column carries two radio buttons per field row —
  `[accept pito]` / `[accept youtube]` — pre-selected to `accept youtube`
  (preserves YouTube-as-source-of-truth posture). A single `[apply changes]`
  button at the bottom submits ALL field decisions bidirectionally in one
  transaction: `accept pito` rows push Pito's value to YouTube via
  `Youtube::Client#update_channel` (Pito wins; overwrite YouTube);
  `accept youtube` rows update Pito's local cached column (YouTube wins;
  overwrite Pito). Powered by the daily diff-check job's findings; see sub-spec
  11i for the data flow.

**Multi-layout preview component:**

- Three layouts: web (desktop, ~1280px wide), mobile (~390px wide), TV
  (~1920x1080 with TV-specific YouTube spacing). **UX shape locked by D23: a
  wide modal with top nav `[desktop] [mobile] [tv]`, NOT side-by-side.** If the
  existing modal partial is too narrow, a `--wide` modifier OR a new shared
  `_wide_modal.html.erb` partial ships in sub-spec 11d.
- Pito-rendered HTML, NOT a YouTube embed. Inputs: a `Channel` plus an optional
  "pending edits" hash. When the pending hash is present, the preview renders
  the would-be state; when it is absent, it renders the cached state.
- "Couple of videos" row underneath the channel header, using real
  `channel.videos` rows (with titles and derived thumbnails) when present,
  otherwise static JPEG thumbnails from `public/preview/video_thumbnails/` +
  curated titles per D8 (Q2).
- NO safe-zone overlays (user explicitly excluded these).
- NO YouTube Studio replication — Pito only shows the post-upload result.

**Watermark preview:**

- Sub-spec 11e. A video player mockup (play button + progress bar + faux control
  bar) with the watermark image overlaid at the YouTube-mandated right-hand
  corner (D21 — position selector removed).
- Three size variants matching the three preview layouts (web / mobile / TV).
- The mockup background is a static JPEG drawn at random per render from
  `public/preview/watermark_frames/` (e.g., `frame-01.jpg`, `frame-02.jpg`,
  ...). The user commits 2–4 real frames at ~1920×1080 16:9 (gameplay-style or
  visually busy content so the watermark overlay is visible). No `ffmpeg lavfi`
  generation, no `bin/setup` extension, no runtime ffmpeg call. See D9.

**Banner upload flow** (sub-spec 11f):

- **File-picker AND drag-drop zone** (D22 / Q2). NO inline crop. User pre-crops
  in Canva.
- **Pre-upload spec info surfaced in the UI**: expected dimensions (2048×1152
  minimum, 16:9), accepted file types, max file size.
- **Hard-reject on failure (D14 flipped per Q5)**: if the file fails any
  pre-flight check, the upload is rejected with a clear reason — `file type`,
  `file size`, `aspect ratio`, or `pixel dimensions`. NOT warn-but-submit. The
  user sees exactly which constraint was violated.
- Multi-size preview renders the uploaded image at web / mobile / TV dimensions
  before the user submits (inside the wide modal per D23).
- Server-side: `Youtube::Client#upload_banner(channel, io)` calls
  `channelBanners.insert` (which returns a `bannerExternalUrl`), then
  `channels.update` with `brandingSettings.image.bannerExternalUrl` set to that
  URL.

**Watermark upload flow:**

- Client-side validates dimensions per YouTube's spec (verify — typically
  800x800 PNG/JPEG). Same hard-reject posture as banner upload (D14 / D22).
- Server-side: `Youtube::Client#set_watermark(channel, io, timing, offset_ms)`
  calls `watermarks.set` (no position parameter — D21). Removal calls
  `watermarks.unset`.

**Sync strategy:**

- On-demand `[sync]` button on the show page, routing through the existing
  `/syncs/channel/:ids` confirmation framework.
- Auto-sync on first connect (when `youtube_connection_id` is set on the channel
  for the first time).
- **Daily diff-check cron (D11 updated per Q7)**. A daily Sidekiq cron walks
  every connected channel, fetches the live YouTube state, diffs against the
  cached columns, and on divergence raises a notification + flash banner on
  `/channels/:id`. NO automatic overwrite without user confirmation. The
  resolution page (`/channels/:id/diff`) presents per-field `[accept pito]` /
  `[accept youtube]` radio toggles and a single `[apply changes]` button that
  commits ALL decisions bidirectionally in one transaction (Pito-wins rows push
  to YouTube; YouTube-wins rows overwrite Pito's cache). Sub-spec **11i** owns
  the job + diff-resolution page.

**Change history tracking:**

- Sub-spec 11g. Title and handle changes write a `channel_change_logs` row.
- The 14-day rate-limit gate is **client-side**: if `channel.title_changed_at`
  is within 14 days of now, the edit form hides the title input and shows "Title
  was changed on YYYY-MM-DD; YouTube limits changes to 1 per 14 days." YouTube's
  API enforces server-side too — that is defense in depth, not the primary gate.
  The gate also exposes the **`[remind me on YYYY-MM-DD]` affordance** (D19 /
  sub-spec 11h).
- Same shape for handle.

**Statistics fetch:**

- `Youtube::Client#fetch_channel(channel)` calls `channels.list` with
  `part: "snippet,statistics,brandingSettings,contentDetails,status"` (or
  whatever combination minimizes calls — verify quota cost). Caches the response
  into the local columns in one transaction.

**Auto-sync UX (D12 / Q12 resolved):**

- Async, with Turbo indicator. The form on `/channels/:id/edit` is disabled
  while `syncing: true`. Reuses the same Stimulus + Turbo Stream pattern already
  shipped in `sync_indicator_controller.js`.

### Out of scope

- **Avatar editing.** YouTube Data API v3 does not expose a write path for
  channel avatars **per current evidence** — verification (Q9 / D2) confirms or
  flips this before 11c lands. If verification turns up an edit path, the spec
  gets revised. No edit affordance, no YouTube Studio link per user intent.
- **Statistics-only edit.** `subscribers`, `views`, `video_count`,
  `hidden_subscriber_count` are read-only on YouTube; no edit form.
- **Phase 8 mass video sync.** Channel sync ≠ video sync. This spec only fetches
  channel-level fields plus the channel's own statistics; it does NOT walk the
  uploads playlist or hydrate per-video metadata.
- **Live YouTube embed previews.** Pito renders its own mockups (the whole point
  of the preview is to show pending edits, which an embed cannot).
- **Aggregations from video-level data** (e.g., total view count derived from
  summing per-video views). Phase 8+ territory.
- **Channel deletion / unlinking.** Out of scope for the management surface; if
  needed, surfaces through the existing bulk-delete framework.
- **Banner cropping UI.** User pre-crops in Canva.
- **Watermark position selector.** YouTube only supports right-hand corner
  (D21). The selector / `watermark_position` column / `[top_left][top_right]...`
  radio UI is all out of scope.

## Sequencing

This spec produces **nine** sub-specs (11a–11i) which can be split across
multiple architect-spec dispatches. The dependency graph:

```
11a  schema + sync             (foundation)
 │
 ├─ 11b  show page              (depends on 11a's columns)
 │
 ├─ 11c  edit form              (depends on 11a's columns + Youtube::Client)
 │       │
 │       └─ 11h  calendar reminder integration  (depends on 11c's gate + Calendar model)
 │
 ├─ 11d  preview component      (depends on 11a's columns + Video.title)
 │       │
 │       └─ 11e  watermark preview  (depends on 11d's layout primitives)
 │
 ├─ 11f  banner upload          (depends on 11a + 11c + 11d wide modal)
 │
 ├─ 11g  change history         (depends on 11a's columns + 11c's edit flow)
 │
 └─ 11i  daily diff-check + /diff page  (depends on 11a + 11b's show page banner)
```

Implementation dispatches kick off in this order:

1. **11a** lands first (schema migration, `Channel` model additions,
   `Youtube::Client#fetch_channel`, sync button wiring). Without it, every other
   sub-spec is blocked.
2. **11b**, **11c**, **11d** can run in parallel after 11a (they touch different
   files).
3. **11e** depends on 11d's preview primitives.
4. **11f** depends on 11a + 11c + 11d's wide-modal partial.
5. **11g** depends on 11a + 11c (the gate logic lives in 11c, but the log
   table + UI are 11g).
6. **11h** depends on 11c (the gate is where the `[remind me]` link sits) and on
   the existing `CalendarEntry` model (it adds a new `kind: :reminder` value or
   equivalent).
7. **11i** depends on 11a (it diffs against the cached columns) and on 11b's
   show page (banner slot).

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

### D2 — Avatar display-only PENDING live API verification

Posture: avatar is treated as **display-only PENDING live API verification** —
the research dispatch (Q9) confirms the read-only stance before any 11c (edit
form) work begins. If the research turns up an edit path, the spec is amended
(the edit form gains an avatar field; the show page gains an `[edit]`
affordance) before 11c is dispatched.

Reference: `https://developers.google.com/youtube/v3/docs/channels/update` lists
`brandingSettings`, `localizations`, `status`, `contentOwnerDetails`, and `id`
as the parts that can be passed to `update`. Avatar (`thumbnails`) is part of
`snippet` and the API documents `snippet` as **not** part of the update part
list — but documented behavior and live behavior can diverge, so the
verification is mandatory.

Implementation: `Channel#avatar_url` is cached for performance (so the channel
list page does not live-fetch from YouTube every paginate — D12). The edit-path
question stays open until verification lands.

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

Rationale: `watermarks.set` uploads the watermark image and configures timing;
`watermarks.unset` removes it. Both calls are authenticated and audited the same
way. Pito caches `watermark_url` + `watermark_timing` + `watermark_offset_ms`
locally. **No `watermark_position` per D21** — YouTube only supports the
right-hand corner.

References:

- `https://developers.google.com/youtube/v3/docs/watermarks/set`
- `https://developers.google.com/youtube/v3/docs/watermarks/unset`

### D5 — Title / handle 14-day rate limit gate is client-side

Rationale: YouTube limits title and handle changes to 1 per 14 days server-side
(verify the exact limit and which fields it applies to — Q1 research dispatch).
Pito also enforces the gate client-side: the edit form hides the title input
when `channel.title_changed_at` is within 14 days of now and renders an
explanatory message instead. Same for handle. This is UX, not security: a
determined user could call YouTube's API directly via the browser console or
curl and would get YouTube's own rate-limit response, which Pito surfaces as a
friendly error. Defense in depth, not the primary gate. Paired with D19's
`[remind me]` calendar affordance.

### D6 — `channel_change_logs` table tracks title / handle changes

Rationale: per user intent, "keep change history" for title (and by extension
handle, since they have the same rate-limit shape). One table for both fields;
`field` column distinguishes them. Append-only — the table records "what was the
title before, what is it now, when did Pito push the change, which user pushed
it." No UPDATE / DELETE in normal flow; if the user revokes a Google identity,
the rows survive (they reference `user_id`, not `youtube_connection_id`).

### D7 — Preview is Pito-rendered, three layouts, no safe zones

Rationale: a YouTube embed shows the channel's current live state. The whole
point of the preview is "see pending edits before committing them", which an
embed cannot show. Pito renders the preview as plain HTML/CSS parameterized by a
`Channel` + an optional "pending edits" hash — when the form is dirty, the
preview reflects the form's current values, not the cached database values.

Three layouts — web (desktop), mobile, TV — match YouTube's three primary
delivery surfaces. UX shape locked by **D23**: a wide modal with top nav
`[desktop] [mobile] [tv]`, not side-by-side.

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
preview shows a small `[no preview thumbnails yet]` text fallback in place of
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
over the chosen frame at the YouTube-mandated right-hand corner (D21).

**No `ffmpeg lavfi` generation, no runtime ffmpeg call, no `bin/setup` step.**
The frames ship in the repo; every install renders them as-is. If
`public/preview/watermark_frames/` is empty, the watermark preview shows the
same `[no preview frames yet]` text fallback as the thumbnails branch (D8).

The frames live under `public/preview/` rather than the `pito-assets` volume
(spec 05) because they are static design fixtures, not user-generated content —
they belong with the app source, not in the mounted-volume runtime tree.

### D10 — Statistics fetch on every channel sync

Rationale: `channels.list` returns snippet, statistics, brandingSettings,
contentDetails, status all in a single 1-unit call (per `docs/youtube_quota.md`
cost table). There is no separate per-stat endpoint to call; one `channels.list`
invocation refreshes everything Pito caches. No micro-optimization for "only
fetch statistics, not branding" because the cost is identical.

### D11 — Channel sync: on-demand + on-connect + daily diff-check cron

Rationale (updated per Q7 resolution): the existing `/syncs/channel/:ids`
framework handles on-demand sync via the bulk-as-foundation pattern. Auto-on-
connect runs when a channel transitions from `youtube_connection_id IS NULL` to
non-NULL (the `after_update_commit` hook on `Channel`). Additionally, a **daily
Sidekiq cron** (sub-spec 11i) walks every connected channel, fetches the live
YouTube state, and **diffs** against the cached columns.

Diff resolution flow (refined per Q7):

- On divergence, the job emits a notification AND surfaces a flash-style in-page
  banner on `/channels/:id` saying "YouTube has X newer values".
- The banner contains a `[review changes]` link that opens `/channels/:id/diff`
  — a dedicated page with a three-column layout: `Pito` | `YouTube` |
  `decision`.
- The decision column carries two radio buttons per field row — `[accept pito]`
  / `[accept youtube]` — pre-selected to `accept youtube` (preserves the
  YouTube-as-source-of-truth posture). A single `[apply changes]` button at the
  bottom commits ALL decisions bidirectionally in one transaction:
  - For each field marked `accept pito`: push Pito's cached value back to
    YouTube via `Youtube::Client#update_channel` (Pito wins; overwrite YouTube).
  - For each field marked `accept youtube`: update Pito's local cached column
    with YouTube's value (YouTube wins; overwrite Pito).
- The whole batch runs inside a single transaction; any Pito-wins push to a
  title or handle also writes a `channel_change_logs` row (since the push
  originates from a user-confirmed decision).
- **No automatic overwrite without user confirmation.** The cached values remain
  untouched until the user clicks `[apply changes]`.

Sub-spec **11i** owns the cron job, the diff data structure, the notification
plumbing, and the `/channels/:id/diff` page.

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

### D14 — Banner / watermark upload HARD REJECTS on validation failure

Rationale (flipped from earlier "warn but submit" per Q5 resolution): Pito's
upload UI surfaces expected dimensions / file types / max size **before** the
user picks a file. On submission, Pito pre-flights every constraint client-side
AND server-side; any failure rejects the upload with a **clear, specific
reason**: `file type`, `file size`, `aspect ratio`, or `pixel dimensions`. NOT a
warning that submits anyway. This avoids the "user submits a 4 MB 720p banner,
waits for the YouTube round-trip, gets a generic API rejection" frustration.
Pito tells the user exactly which constraint failed, before any network call to
YouTube.

Server-side hard-reject is the authoritative gate (a determined user can bypass
client-side checks); client-side rejection is UX, surfacing the same verdict
instantly.

### D15 — Watermark position uses YouTube's actual options — **SUPERSEDED by D21**

Originally: "use YouTube's documented corners (4 corners) but surface the user's
preferred labels". Q3 resolution turned up that YouTube only supports the
**right-hand corner**, period. D21 supersedes this — the `watermark_position`
column and the corresponding form selector are dropped entirely.

### D16 — Watermark timing uses YouTube's actual options

Rationale: per Q4 resolution. Expose **all four** options if the live API
accepts them: `always`, `entire_video`, `offset_from_start`, `offset_from_end`.
Research dispatch verifies the option set against the live API before 11c lands;
if YouTube has deprecated any of them, the spec is amended.

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

### D19 — Calendar reminder integration (`[remind me on YYYY-MM-DD]`)

Rationale: per Q1 resolution (refined). When the 14-day rate-limit gate fires on
`/channels/:id/edit` (title or handle within window), Pito renders a
`[remind me on YYYY-MM-DD]` link alongside the "Title was changed on YYYY-MM-DD;
YouTube limits changes to 1 per 14 days." message.

Behavior (silent auto-create, no redirect):

- One-click POSTs to `/calendar/entries.json` with prefilled body:
  - `kind: :reminder` (new value on the existing CalendarEntry model — sub-spec
    11h confirms whether this is a new `entry_type` enum value, a new `source`,
    or a `metadata`-flagged custom entry; current model uses `entry_type` enums
    including `custom`).
  - `title = "Channel title unlock — <channel name>"` (or "Channel handle unlock
    —" for the handle case).
  - `starts_at = unlock_date` (= `title_changed_at + 14.days`, or
    `handle_changed_at + 14.days` for the handle case).
  - `all_day: true`, `channel_id: channel.id`, `created_by_user: current_user`.
- The server creates the entry and returns minimal JSON
  (`{ id, title, starts_at }`).
- A Stimulus controller renders a flash-style toast on the same page: "Reminder
  created for YYYY-MM-DD".
- **NO redirect.** The user stays on `/channels/:id/edit`. If the user wants to
  tweak the reminder (change title, add notes, change notification time), they
  visit `/calendar` directly and edit the entry there.
- Sub-spec **11h** owns the integration: the `kind: :reminder` model change (if
  needed), the JSON endpoint on `/calendar/entries`, the `[remind me]` Stimulus
  controller that POSTs + renders the toast, and the spec coverage.

### D20 — Daily diff-check + `/channels/:id/diff` page

Rationale: per Q7 resolution (refined — bidirectional accept-pito /
accept-youtube). A daily Sidekiq cron walks every connected channel, fetches the
live YouTube state via `Youtube::Client#fetch_channel`, and diffs against the
cached columns. On any divergence:

- Emit a notification (channel-scoped; surfacing via the existing notification
  framework — sub-spec 11i picks the exact surface).
- Render a flash-style in-page banner on `/channels/:id` saying "YouTube has X
  newer values" with `[review changes]` linking to `/channels/:id/diff`.
- `/channels/:id/diff` is a dedicated page with a three-column layout: `Pito` |
  `YouTube` | `decision`. The decision column has two radio buttons per field
  row — `[accept pito]` / `[accept youtube]` — and the default selection is
  `accept youtube` (preserves the YouTube-as-source-of-truth posture for the
  user who simply clicks `[apply changes]` without touching individual radios).
- A single `[apply changes]` button at the bottom of the page commits ALL
  decisions bidirectionally in one transaction (`ChannelDiffsController#apply`):
  - For each field marked `accept pito` → call `Youtube::Client#update_channel`
    to push Pito's value to YouTube (Pito wins; overwrite YouTube). Title /
    handle pushes also append a `channel_change_logs` row since they originate
    from a user-confirmed decision.
  - For each field marked `accept youtube` → update the local cached column with
    YouTube's value (YouTube wins; overwrite Pito).
  - All field decisions execute inside the same transaction; the diff rows are
    marked resolved on success.
- **No automatic overwrite.** The user's cached values are sacrosanct until the
  user clicks `[apply changes]`. The single-button design is deliberate — the
  user reviews every row, clicks the appropriate radios, then commits once.

Sub-spec **11i** owns the job, the diff data model (a small `channel_diffs`
table or a transient in-memory shape — 11i decides), the notification plumbing,
and the `/diff` page (including the radio-toggle UI and the
`ChannelDiffsController#apply` action).

### D21 — Drop `watermark_position` entirely

Rationale: per Q3 resolution. YouTube only supports the right-hand corner (image
evidence + live-API verification). The original D15 (which assumed 4 corners) is
wrong. The `watermark_position` column never lands in the schema; the form
selector never renders; the watermark preview composes the overlay in the
bottom-right corner unconditionally. The watermark UX shrinks to "watermark
image + display time (timing + offset_ms)".

Supersedes D15.

### D22 — Banner upload UX = file-picker + drag-drop + pre-upload spec info

Rationale: per Q2 / Q5 resolution. The upload surface offers BOTH a file- picker
(`<input type="file">`) AND a drag-drop zone (Stimulus controller for the drop
target). **No inline crop** — user pre-crops in Canva per their stated workflow.

Pre-upload UX shows:

- Expected dimensions ("2048 × 1152 minimum, 16:9 aspect ratio").
- Accepted file types ("JPEG, PNG").
- Max file size (per YouTube's documented limit — verify).

On reject (D14 hard-reject), the error message names the specific failing
constraint: `file type`, `file size`, `aspect ratio`, or `pixel dimensions`.

Same posture for the watermark upload (different dimension spec — 800×800
PNG/JPEG per YouTube's documented spec; verify live).

### D23 — Preview is a wide modal with top-nav layout selectors

Rationale: per Q8 resolution. The preview surfaces as a **wide modal** (not
side-by-side, not a separate page) with a top nav of `[desktop] [mobile] [tv]`
selectors. Switching the selector swaps the rendered layout in place inside the
modal.

If the existing modal partial (`shared/_modal.html.erb` or equivalent) is too
narrow, sub-spec **11d** ships either:

- a `--wide` modifier class on the existing modal, OR
- a new shared `_wide_modal.html.erb` partial.

11d picks one and locks it. The decision is local to 11d; both options are
acceptable.

## Open questions

All Open Questions originally listed here are now RESOLVED. Resolutions baked
into the decisions above. Kept inline for paper-trail:

**Q1 — Handle / title editability via live API. RESOLVED.** Verify via research
dispatch against the live YouTube API. PLUS new feature: when the 14-day gate
fires on `/channels/:id/edit`, render `[remind me on YYYY-MM-DD]` that silently
auto-creates a CalendarEntry with prefilled values; a flash-style toast confirms
creation. **NO redirect** — the user stays on `/channels/:id/edit` and can edit
the entry later by visiting `/calendar` directly (sub-spec 11h, D19).

**Q2 — Banner upload UX. RESOLVED.** File-picker AND drag-drop zone. No inline
crop. See D22.

**Q3 — Watermark position options. RESOLVED.** YouTube only supports the
right-hand corner. `watermark_position` column dropped. See D21.

**Q4 — Watermark timing options. RESOLVED.** Expose all four (`always`,
`entire_video`, `offset_from_start`, `offset_from_end`) if the live API allows.
Verify before 11c lands. See D16.

**Q5 — Banner aspect-ratio enforcement. RESOLVED.** HARD reject with clear
reason (file type / file size / aspect ratio / pixel dimensions). Pre-upload UX
shows expected dimensions / type / size. See D14 / D22.

**Q6 — Change history retention. RESOLVED.** Keep all. See D17.

**Q7 — Sync strategy default. RESOLVED.** On-connect + on-demand + **daily
diff-check cron** (NEW). Diff result → notification + flash banner. No overwrite
without user confirmation. Resolution via dedicated `/channels/:id/diff` page
with a three-column `Pito` | `YouTube` | `decision` layout, per-row
`[accept pito]` / `[accept youtube]` radio toggles (default `accept youtube`),
and a single `[apply changes]` button that commits ALL decisions bidirectionally
in one transaction (Pito-wins rows push to YouTube; YouTube-wins rows overwrite
Pito's cache). See D11 / D20 / sub-spec 11i.

**Q8 — Preview UX shape. RESOLVED.** Per-layout views with top nav
`[desktop] [mobile] [tv]` inside a **wide modal**. NOT side-by-side. See D23.

**Q9 — Avatar editability. RESOLVED.** Research dispatch verifies against the
live API. Anything not editable via API is display-only, sync-pulled. D2 posture
for avatar holds **pending verification**; the spec is updated if the research
turns up an edit path. See D2.

**Q10 — Pre-loaded "channel videos" curated titles. RESOLVED.** Ruby constant in
`app/helpers/preview_helper.rb`. Move to i18n if/when localization becomes a
concern.

**Q11 — Watermark preview frame: regenerate per-install or ship in repo?
RESOLVED.** Ship in repo. Static JPEG files under
`public/preview/watermark_frames/`. No `ffmpeg lavfi`. No `bin/setup` extension.

**Q12 — Auto-sync on connect: blocking or async? RESOLVED.** Async with Turbo
indicator. The form is disabled while `syncing: true`. Same Stimulus + Turbo
Stream pattern as the existing `sync_indicator_controller.js`.

## Implementation plan

Nine sub-specs split the work. Each is a separate architect-spec dispatch; each
in turn becomes a rails-impl dispatch.

### 11a · `channel-schema-and-sync.md`

**Scope:** schema migration adding all new `Channel` columns (NO
`watermark_position` per D21) + the `channel_change_logs` table + the
`Video.title` column. `Channel` model additions (validations on title length /
description length / links shape / country format / language tag format /
watermark timing enum). Extend `Youtube::Client` with `fetch_channel(channel)`
calling `channels.list` with full part set, parsing the response, caching to
local columns. Replace the current `ChannelSync` placeholder job with the real
fetch path through the existing `BulkSyncJob` framework. Auto-sync on connect
via `after_update_commit` hook detecting `youtube_connection_id` transition.

**Files touched:** `db/migrate/<TS>_add_channel_resource_fields.rb`,
`db/migrate/<TS>_create_channel_change_logs.rb`,
`db/migrate/<TS>_add_title_to_videos.rb`, `app/models/channel.rb`,
`app/models/channel_change_log.rb`, `app/models/video.rb`,
`app/services/youtube/client.rb`, `app/jobs/channel_sync.rb`, RSpec coverage for
all of the above per the project's spec pyramid (model + service + job +
migration rollback specs, happy + sad + edge).

**Effort estimate:** medium. Schema is the bulk; sync wiring extends an existing
path.

### 11b · `channel-show-page.md`

**Scope:** render the cached fields on `/channels/:id` (read-only). All 10 field
groups visible. Avatar shown without edit affordance per D2. Stats shown
including the `hidden_subscriber_count` "Hidden" treatment. Watermark section
shows the cached image + timing in a small preview; banner section shows the
cached banner with a `[preview]` link that opens the wide modal (D23). `[edit]`
links to the editable subset point at `/channels/:id/edit#<field>`. Includes the
diff-check banner slot (D20 / 11i) — the banner Turbo-frames in when 11i posts
new diff findings.

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
days, hide the title input, explain, AND render the `[remind me on YYYY-MM-DD]`
link (D19 / sub-spec 11h). Same for handle. Banner input is the file-picker +
drag-drop combo (D22); it hands off to sub-spec 11f. The watermark upload itself
goes through `watermarks.set` which is part of 11c (single-call flow).

**Files touched:** `app/views/channels/edit.html.erb`,
`app/controllers/channels_controller.rb`, `app/services/youtube/client.rb`
(extend with `update_channel`, `set_watermark`, `unset_watermark`), RSpec
request + system specs.

**Effort estimate:** medium-large. The form touches every editable field; the
controller dispatches multiple API calls.

### 11d · `channel-preview-component.md`

**Scope:** the multi-layout preview component. Renders a Pito-built channel-
page mockup at three viewport sizes. Inputs: a `Channel` plus an optional
pending-edits hash. Output: HTML/CSS that approximates YouTube's channel page
across web / mobile / TV.

**UX shape locked by D23**: a **wide modal** with top nav
`[desktop] [mobile] [tv]` selectors that swap the rendered layout in place. 11d
picks between a `--wide` modifier on the existing modal partial OR a new
`_wide_modal.html.erb` partial; the choice is local to 11d.

The "couple of videos" row uses `channel.videos.where.not(title: nil)` when
present (taking up to 6); falls back per D8 to **static JPEG files under
`public/preview/video_thumbnails/`** (random pick per render via
`PreviewHelper#random_video_thumbnail`) paired with curated titles. The curated
title array is a Ruby constant in `app/helpers/preview_helper.rb` per Q10. If
`public/preview/video_thumbnails/` is empty, each slot falls back to a
`[no preview thumbnails yet]` text marker.

NO safe-zone overlays. NO YouTube Studio replication. NO CSS-gradient
placeholders — the user explicitly wants natural thumbnails, not
artificial-looking ones.

**Files touched:** `app/components/channel_preview_component.{rb,html.erb}`,
`app/components/channel_preview/{web,mobile,tv}_layout_component.*` (or a single
component with a layout flag — implementation agent picks),
`app/helpers/preview_helper.rb` (new — houses `random_video_thumbnail`,
`random_watermark_frame`, and the curated title constant),
`app/views/shared/_wide_modal.html.erb` (or a `--wide` modifier on the existing
modal partial — 11d picks), `app/assets/stylesheets/channel_preview.css`, the
static JPEG fixtures under `public/preview/video_thumbnails/` (the user drops
these in; the implementation agent ensures the directory exists and the helper
handles the empty case), RSpec component + helper specs.

**Effort estimate:** large. CSS is the bulk; getting three layouts to feel right
is iterative.

### 11e · `watermark-preview.md`

**Scope:** the player-mockup preview that overlays the user's watermark on a
static frame at the YouTube-mandated right-hand corner (D21 — no position
selector). Three size variants (web / mobile / TV). Reads a random JPEG from
`public/preview/watermark_frames/` per render via
`PreviewHelper#random_watermark_frame` (the helper introduced in 11d). **No
`bin/setup` extension. No `ffmpeg lavfi` filter chain. No runtime ffmpeg call.**
The frames are static fixtures the user drops in (recommended 2–4 files at
~1920×1080 16:9, gameplay-style or visually busy so the watermark overlay
reads).

If `public/preview/watermark_frames/` is empty, the component renders a
`[no preview frames yet]` text fallback in place of the frame.

**Files touched:** `app/components/watermark_preview_component.{rb,html.erb}`,
`app/helpers/preview_helper.rb` (extend with `random_watermark_frame` if 11d did
not already), the static JPEG fixtures under `public/preview/watermark_frames/`
(user-supplied), RSpec component + helper specs. Also reaches into 11d's preview
component to render the watermark inside the channel-page mockup's video-row
thumbnails (one watermark, all three layouts). **`bin/setup` is NOT touched.**

**Effort estimate:** small. With ffmpeg out of the picture this is straight
component + helper work.

### 11f · `banner-upload-flow.md`

**Scope:** the banner upload flow specifically. **File-picker + drag-drop zone**
(D22). Pre-upload UX surfaces expected dimensions / file type / max size.
Client-side image-dimension read (`HTMLImageElement` natural dimensions or
`createImageBitmap`-then-measure). Multi-size client-side preview before
submission (rendered inside the wide modal per D23). Server-side upload through
`Youtube::Client#upload_banner` (which calls `channelBanners.insert` and then
`channels.update` with the resulting URL). Caches `banner_url` on success.

Per D14 (flipped from earlier "warn but submit"), Pito's UI **hard-rejects** on
aspect-ratio / dimension / type / size mismatch with a clear specific reason
(`file type` / `file size` / `aspect ratio` / `pixel dimensions`). Server-side
hard-reject is the authoritative gate; client-side is UX.

**Files touched:** `app/javascript/controllers/banner_upload_controller.js`,
`app/javascript/controllers/drag_drop_zone_controller.js` (if not already
shipped), `app/views/channels/_banner_upload.html.erb` (partial included by
11c's edit form), `app/services/youtube/client.rb` (extend with
`upload_banner`), RSpec system spec.

**Effort estimate:** medium. The Stimulus controllers for client-side preview

- drag-drop + hard-reject error surfacing are the bulk.

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

### 11h · `calendar-reminder-integration.md`

**Scope:** per D19 / Q1 resolution (refined — no redirect; silent auto-create
with toast). When the 14-day rate-limit gate fires on `/channels/:id/edit`
(title or handle within window), Pito surfaces a `[remind me on YYYY-MM-DD]`
link. Clicking the link POSTs to `/calendar/entries.json` (a JSON endpoint on
the existing `CalendarEntriesController`, or a dedicated
`Channels::RemindersController#create` — 11h picks) that:

1. Computes `unlock_date = (title_changed_at || handle_changed_at) + 14.days`.
2. Builds a `CalendarEntry` with `kind: :reminder` (sub-spec 11h confirms
   whether this requires a new `entry_type` enum value, a new `source`, a
   `metadata`-flagged custom entry, or a dedicated `kind` column — the current
   model uses `entry_type` enums including `custom`, and 11h must pick the
   lowest-friction option that keeps the existing `CalendarEntry` validators
   happy).
3. Sets `title = "Channel title unlock — <channel name>"` (or "Channel handle
   unlock —" for the handle case), `starts_at = unlock_date`, `all_day: true`,
   `channel_id: channel.id`, `created_by_user: current_user`.
4. Persists and returns minimal JSON (`{ id, title, starts_at }`). **No
   redirect.**
5. A Stimulus controller (`reminder_link_controller.js`) issues the POST, reads
   the JSON response, and renders a flash-style toast on the same page:
   "Reminder created for YYYY-MM-DD". The user stays on `/channels/:id/edit`.
   The user can edit the reminder later by visiting `/calendar` directly.

**Files touched:** possibly
`db/migrate/<TS>_add_reminder_to_calendar_entry_*.rb` (if a new enum value or
column is needed), `app/models/calendar_entry.rb` (new enum value or metadata
branch), `app/controllers/calendar_entries_controller.rb` (JSON create branch)
OR `app/controllers/channels/reminders_controller.rb` (new dedicated
controller), `app/javascript/controllers/reminder_link_controller.js` (new
Stimulus controller — POSTs the prefilled body, reads JSON, renders the toast),
`app/views/channels/edit.html.erb` (the `[remind me on YYYY-MM-DD]` link plus
the toast target element), `config/routes.rb` (the new route), RSpec model +
request + system specs (system spec covers the silent-create + toast flow
without page navigation).

**Effort estimate:** small-medium. Most of the work is the `CalendarEntry`-model
decision (enum vs metadata) and the Stimulus-driven silent-create + toast
wiring.

### 11i · `daily-diff-check-and-resolution.md`

**Scope:** per D11 / D20 / Q7 resolution (refined — bidirectional accept-pito /
accept-youtube). A daily Sidekiq cron walks every connected channel, fetches the
live YouTube state via `Youtube::Client#fetch_channel`, diffs against the cached
columns, and on divergence:

1. Records the diff (a small `channel_diffs` table is the most likely shape —
   see "Concerns flagged during writing"; 11i locks the choice). Per-field rows
   persist `channel_id`, `field`, `pito_value`, `youtube_value`, `detected_at`,
   `resolved_at`, `resolution` (`accept_pito` / `accept_youtube` / `null` until
   resolved).
2. Emits a notification (channel-scoped; surfacing via the existing notification
   framework).
3. Surfaces a flash-style in-page banner on `/channels/:id` saying "YouTube has
   X newer values" with `[review changes]` linking to `/channels/:id/diff`.

`/channels/:id/diff` page:

- Three columns: `Pito` | `YouTube` | `decision`.
- The decision column carries two radio buttons per field row — `[accept pito]`
  / `[accept youtube]` — pre-selected to `accept youtube` (preserves
  YouTube-as-source-of-truth posture).
- A single `[apply changes]` button at the bottom of the page commits ALL
  decisions.
- **No per-row submit buttons. No `[ignore]` action.** A user who wants to keep
  Pito's value for a particular row leaves the radio on `accept pito`; a user
  who wants to accept YouTube's value leaves the radio on `accept youtube` (the
  default).

`ChannelDiffsController#apply`:

- Reads the submitted radio decisions (one per `channel_diffs` row).
- Opens a single `Channel.transaction`:
  - For each field marked `accept_pito`: calls
    `Youtube::Client#update_channel(channel, { field => pito_value })` to push
    Pito's value to YouTube. If the field is `title` or `handle`, also appends a
    `channel_change_logs` row (since this is a user-confirmed push, identical in
    shape to an edit-form push).
  - For each field marked `accept_youtube`: updates the local cached column with
    `youtube_value`.
  - Marks each `channel_diffs` row resolved (`resolved_at = now`,
    `resolution = accept_pito | accept_youtube`).
- On any YouTube API error during Pito-wins pushes, the whole transaction rolls
  back; the user sees the YouTube error surfaced as a flash and the diff rows
  remain unresolved so they can retry.
- **No automatic overwrite.** Pito never silently blows away cached values;
  every change goes through `[apply changes]`.

**Files touched:** `app/jobs/channel_diff_check.rb` (new), `config/sidekiq.yml`
or wherever sidekiq-cron entries live (new cron entry),
`db/migrate/<TS>_create_channel_diffs.rb` (new — the persistence shape is
required, see "Concerns flagged during writing"), `app/models/channel_diff.rb`
(new), `app/controllers/channels/diffs_controller.rb` (new — `show` renders the
three-column page; `apply` commits the batched decisions), `config/routes.rb`
(`get/post /channels/:id/diff`), `app/views/channels/diffs/show.html.erb` (the
three-column layout + radios + `[apply changes]`),
`app/views/channels/_diff_banner.html.erb` (rendered on `/channels/:id`),
`app/services/youtube/client.rb` (extend `#update_channel` if 11c hasn't already
— same call shape, batched fields), RSpec job + model + request + view specs
covering:

- Happy: all `accept_youtube`, transaction succeeds, every diff row marked
  resolved, every cached column updated.
- Happy: mixed `accept_pito` / `accept_youtube`, transaction succeeds, Pito-wins
  fields pushed to YouTube via WebMock-stubbed `channels.update`, YouTube-wins
  fields overwritten locally, every diff row marked resolved.
- Happy: title or handle marked `accept_pito` → `channel_change_logs` row
  appended.
- Sad: YouTube `channels.update` returns 429 for one of the Pito-wins pushes →
  whole transaction rolls back, no cached columns changed, no diff rows
  resolved, flash error surfaces the YouTube response.
- Edge: all radios stay on the default `accept_youtube` → equivalent to "accept
  all YouTube changes" with one click.
- Edge: no diffs to resolve (empty `channel_diffs` for the channel) → the page
  renders an empty state, no `[apply changes]` button.

**Effort estimate:** medium-large. The diff data shape, the radio-toggle UI, the
bidirectional `apply` transaction, and the notification + Turbo Stream wiring is
the bulk.

## Acceptance

These boxes must check before this spec closes (i.e., before the last sub-spec's
implementation lands and Phase 7.5 advances).

- [ ] All schema additions land via reversible migrations. `down` cleanly
      reverses every column add and table create. Migration rollback specs
      verify both directions.
- [ ] Existing Phase 4 + 5 + 6 + 7 features unbroken — `bundle exec rspec`
      passes.
- [ ] Channel show page (`/channels/:id`) displays all 10 field groups, plus the
      diff-check banner slot.
- [ ] Channel edit page (`/channels/:id/edit`) exposes the editable subset
      (banner, title, handle, description, country, default language, keywords,
      links, watermark + timing). NO `watermark_position` (D21). Avatar has no
      edit affordance pending Q9 verification.
- [ ] Preview component renders correctly across web / mobile / TV layouts
      inside the wide modal with top nav selectors (D23). Pending-edits hash
      shifts the rendered state without database writes.
- [ ] Watermark preview renders correctly across the three sizes; overlay sits
      in the right-hand corner unconditionally (D21).
- [ ] Banner / watermark uploads HARD-REJECT on mismatch with specific reasons
      (file type / file size / aspect ratio / pixel dimensions). Pre-upload UI
      surfaces expected spec info.
- [ ] All flows have aggressive validation specs (per the user's standing
      directive on spec coverage): unit specs for model validations, request
      specs for controller actions, service specs for `Youtube::Client`
      extensions, job specs for `ChannelSync` and the new `ChannelDiffCheck`,
      component specs for the preview component, system specs for the form +
      preview + scrub interactions.
- [ ] 14-day rate limit enforced client-side: the form hides the title / handle
      inputs when within the window AND surfaces a `[remind me on YYYY-MM-DD]`
      link (D19). Direct-API bypass attempts (curl, browser console) return
      YouTube's own 429, which the controller surfaces as a flash error.
- [ ] `[remind me]` link silently auto-creates a CalendarEntry with prefilled
      values and renders a flash-style toast on `/channels/:id/edit`. **No
      redirect.** The user can edit the entry later by visiting `/calendar`
      directly (D19 / sub-spec 11h).
- [ ] Daily diff-check cron runs, emits notifications + banner on divergence,
      and the `/channels/:id/diff` page renders the three-column `Pito` |
      `YouTube` | `decision` layout with per-row `[accept pito]` /
      `[accept youtube]` radios (default `accept youtube`) and a single
      `[apply changes]` button that commits all decisions bidirectionally in one
      transaction (D20 / sub-spec 11i).
- [ ] Auto-sync on connect is async with Turbo Stream indicator; form disabled
      while `syncing: true` (Q12).
- [ ] Change history table records every title / handle push. Show page renders
      the recent N entries.
- [ ] No JS `alert` / `confirm` / `prompt` introduced. No `data-turbo-confirm`.
      All destructive or significant actions go through the existing
      `_action_screen` framework.
- [ ] Bracketed-link convention (`[label]`, no inner spaces — per pito
      architect-spec extension A) on every clickable element. Monospace font.
      Yes/no boundary on any external surface (none in this spec, but verify if
      any MCP tools are added).
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
Each sub-spec writes a tighter recipe; this is the cumulative walk- through.

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
   fine; the preview shows `[no preview frames yet]` /
   `[no preview thumbnails yet]` text fallbacks rather than broken images.
2. `bin/dev`. Open `/channels`.
3. Connect the test channel to a Google identity (Phase 7 flow).
4. Watch the channel row transition through `[syncing...]` to a hydrated state
   (Turbo Stream, per Q12). Avatar + title + subscriber count appear inline.
5. Click into the channel → `/channels/:id`. The show page renders all 10 field
   groups: banner (with `[preview]` link opening the wide modal), avatar (no
   edit affordance, no Studio link), title, handle, description, links,
   watermark (with the player-mockup preview, right-corner only), subscribers,
   views, video count. The diff-check banner slot is empty (no diffs detected
   yet).
6. Click `[preview]` next to the banner. The wide modal opens with top nav
   `[desktop] [mobile] [tv]`. Switching tabs swaps the rendered layout in place.
7. Click `[edit]` next to title. Change the title. Submit. Watch the form
   succeed; the page reloads and the new title is visible.
8. Click `[edit]` next to title again. The input is hidden; the page shows
   "Title was changed on YYYY-MM-DD; YouTube limits changes to 1 per 14 days." A
   `[remind me on YYYY-MM-DD]` link sits next to the message. Same for handle.
9. Click `[remind me on YYYY-MM-DD]`. A CalendarEntry is silently created with
   title "Channel title unlock — <channel name>" and `starts_at` at the unlock
   date. A flash-style toast appears: "Reminder created for YYYY-MM-DD". The
   page does **not** navigate; the user stays on `/channels/:id/edit`. Open
   `/calendar` in a new tab to confirm the entry exists; tweak it there if
   desired.
10. Open `/channels/:id/edit`. Try to upload a 1280×720 banner (off-spec). The
    UI hard-rejects with "aspect ratio: 16:9 required; uploaded 16:9 but pixel
    dimensions below 2048×1152 minimum". Try a .gif. Hard-reject with "file
    type: JPEG or PNG required". Try a 50 MB JPEG. Hard-reject with "file size:
    exceeds max". Upload a valid 2048×1152 JPEG. The multi-size preview renders
    in three layouts inside the wide modal before submission. Submit. Wait for
    the YouTube CDN to flush; reload; the new banner renders.
11. Edit the watermark — upload a new image (no position selector renders; only
    timing + offset_ms), set timing to `offset_from_start` with
    `offset_ms = 5000`. Submit. The watermark preview updates immediately to
    reflect the new state with the overlay in the right-hand corner.
12. Edit description. Add a long description with multiple paragraphs. Submit.
    Show page renders the new description.
13. Edit links. Add 3 links with titles + URLs. Submit. Show page renders the
    link list.
14. Click `[sync]` on the show page. Watch the sync confirmation page; confirm.
    Watch the channel re-fetch and statistics update (subscribers, views, video
    count).
15. Inspect the change history section on the show page. The two title pushes
    (or one title + one handle) appear in the list.
16. Trigger the daily diff-check job manually (or wait for the cron). On
    divergence, the banner appears on `/channels/:id` saying "YouTube has X
    newer values". Click `[review changes]` → land on `/channels/:id/diff`.
    Three-column layout: `Pito` | `YouTube` | `decision`. Every row's decision
    is pre-selected to `accept youtube`. Flip one row to `accept pito` (Pito's
    value wins). Leave another on `accept youtube` (YouTube's value wins). Click
    the single `[apply changes]` button at the bottom. Watch the page commit ALL
    decisions in one transaction: Pito-wins fields push to YouTube (verify via
    the YouTube Studio side afterwards), YouTube-wins fields overwrite Pito's
    cached column. Reload `/channels/:id` — the diff banner is gone; the cached
    values reflect the resolved state. Title/handle Pito-wins pushes appear in
    the change history section.
17. Resize the browser window to mobile dimensions. The preview modal's top nav
    remains accessible.
18. Disconnect the Google identity (Phase 7 flow). Reload `/channels/:id`. The
    cached fields still render; the `[edit]` links are hidden (or disabled with
    a "reconnect to edit" message). Reconnect; edit works again.
19. Try to submit a title change directly via curl with the Phase 5 API token,
    bypassing Pito's UI gate. YouTube's 429 surfaces; Pito's API response
    includes a friendly error message.
20. `bundle exec rspec` green; `bundle exec rubocop` green.

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
  Q9. The Q1 resolution mandates a live-API research dispatch before 11c lands;
  if handle is Studio-only, the form shrinks. If title is Studio-only, the form
  shrinks more, the 14-day gate logic still applies to the show page's "last
  changed at" display + `[remind me]` affordance, and the change-history table
  degrades to a manual log of "user reported a YouTube-Studio change at this
  time."
- **Q3 — watermark position image evidence (D21).** YouTube only supports the
  right-hand corner per the user's image evidence + live-API verification
  mandate. The `watermark_position` column never lands. If YouTube broadens the
  option set in the future, the column gets added back as a forward migration;
  nothing currently caches a position value, so the migration is trivially
  additive.
- **`Video.title` is the only Phase 8 column reaching forward.** Adding it here
  is a deliberate exception — it unlocks the preview's "real videos" branch, and
  Phase 8 will populate it during sync. No other Phase 8 columns are added. If
  during sub-spec writing it becomes clear that another column is also
  load-bearing for the preview (e.g., a per- video view count display), the spec
  gets amended; otherwise it stays narrow.
- **Banner / watermark URL caching is a sync trust issue.** `banner_url` /
  `avatar_url` / `watermark_url` are YouTube CDN URLs that YouTube can rotate
  without notice. If the cached URL goes stale (YouTube reassigns the CDN host,
  the bytes 404), Pito's preview shows a broken image silently. Mitigation:
  every channel sync refreshes the URLs AND the daily diff-check job (D20 / 11i)
  catches divergence within 24 hours of YouTube rotating the CDN URL.
- **The 14-day rate-limit window is on YouTube's clock, not Pito's.** Pito
  records `title_changed_at` from the API response timestamp, not from Pito's
  wall clock. If the user changed the title via YouTube Studio outside of Pito,
  Pito's `title_changed_at` is stale and the gate is wrong (Pito shows the form
  open, YouTube returns 429). Mitigation: a channel sync refreshes
  `title_changed_at` from YouTube's response if YouTube exposes it (verify);
  otherwise the gate is best- effort and the fallback is YouTube's own
  server-side 429. The daily diff-check job (11i) also catches this since it
  sees the YouTube-side title change.
- **Path A2 contradiction risk.** Path A2 deliberately stripped Channel / Video
  metadata to "thin reference records". This spec adds back many of the columns
  Path A2 removed. The architectural justification is that Path A2 was a retract
  to clear noise before Phase 8 / 7.5 rebuilt intentionally — this spec IS the
  intentional rebuild. The phase- overview out-of-scope clause "no Path A2
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
- **CalendarEntry `kind: :reminder` model shape (D19 / sub-spec 11h).** The
  existing `CalendarEntry` enum (`entry_type`) doesn't include `:reminder` —
  current values are `channel_published`, `video_published`, `video_scheduled`,
  `game_release`, `purchase_planned`, `milestone_manual`, `milestone_auto`,
  `custom`. Sub-spec 11h must pick: add a new enum value (`reminder: 8`), reuse
  `custom` with `metadata.reminder = true`, or introduce a dedicated `kind`
  column. The lowest-friction option is likely adding `reminder: 8` to the
  enum + adjusting the `CalendarEntryMetadataValidator` and
  `CalendarEntryCrossReferenceValidator` to allow the new shape. 11h locks the
  choice.
- **Daily diff-check storage shape (D20 / sub-spec 11i).** The diff results need
  to survive job runs so the banner persists across reloads of `/channels/:id`
  until the user resolves each field, and the `[apply changes]` submission needs
  a stable per-row identifier to process radio decisions. A `channel_diffs`
  table (id, channel_id, field, pito_value, youtube_value, detected_at,
  resolved_at, resolution {`accept_pito` / `accept_youtube`}) is the locked
  shape per the refined D20. 11i ships the migration.
