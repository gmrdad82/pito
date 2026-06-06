# pito — Follow-ups (post-Beta)

Work intentionally **deferred** out of the Beta reboot (Plan 4). These were moved
here so Plan 4 contains only what ships in the Beta. Pick these up after merge.

> Source: split out of `docs/plan-beta-reboot-04-consolidation.md`. Phase numbers
> are kept for traceability; renumber when this becomes its own plan.

---

## A. Videos pipeline (deferred — P31–P34)

### P31 — `/import videos` (smart incremental pull)

> Pull YouTube → `Video` (read-only mirror). Quota-aware. Channel from TAB; period is dead data (carried only).

- [ ] T31.1 `/import videos` handler reads the selected channels (TAB). (Period is carried but unused.) complexity: [low]
- [ ] T31.2 `@all` → one `ImportVideosJob` per channel; single channel → one. complexity: [low]
- [ ] T31.3 Per job: persist + broadcast a per-channel progress Segment. complexity: [low]
- [ ] T31.4 Progress Segment payload updated via Turbo Stream replace (targets its DOM id). complexity: [high]
- [ ] T31.5 `ImportVideosJob` walks the channel's uploads playlist newest-first (`playlistItems.list`), paginating. complexity: [high]
- [ ] T31.6 Batch `videos.list` only for new/changed ids; compare stored `etag`/checksum; skip unchanged. complexity: [high]
- [ ] T31.7 Stop paging after a run of K consecutive known-unchanged videos (incremental tail cutoff). complexity: [high]
- [ ] T31.8 Upsert `Video` (dedupe by `youtube_video_id`); store `etag` + `last_synced_at`. complexity: [low]
- [ ] T31.9 Update the progress Segment; summary (N new / M updated / skipped) on finish. complexity: [low]
- [ ] T31.10 Specs (stubbed API; incremental stop; checksum skip; dedupe; progress). complexity: [high]
- [ ] T31.11 Smoke: `@all` → multiple Segments; single → one. complexity: [manual]
- [ ] T31.12 Commit: `/import videos: smart incremental pull`. complexity: [manual]

### P32 — VideoPreview model + edit UI

> Stage edits without touching `Video`. Full edit experience.

- [ ] T32.1 Confirm the `VideoPreview` model + `has_one_attached :thumbnail`. complexity: [low]
- [ ] T32.2 Edit surface: `/edit video <id>` opens the edit form (or `/edit video` with no id opens the video picker, reusing P34's). complexity: [high]
- [ ] T32.3 Form fields (YouTube Studio parity): title, description, tags, category + game title, made-for-kids, paid promotion, AI/altered-content, allow embedding, automatic chapters/places/concepts, notify subscribers, Shorts remixing, thumbnail upload (Active Storage). complexity: [high]
- [ ] T32.4 Save creates/updates a `VideoPreview` (status `draft`); never mutates `Video`. complexity: [low]
- [ ] T32.5 Show a diff/preview of the draft vs current `Video` values. complexity: [high]
- [ ] T32.6 Thumbnail preview render. complexity: [low]
- [ ] T32.7 Stimulus for the form (keyboard + mouse). complexity: [high]
- [ ] T32.8 i18n all copy. complexity: [low]
- [ ] T32.9 Model/component/request specs. complexity: [low]
- [ ] T32.10 Smoke: compose a preview; persists as draft; `Video` unchanged. complexity: [manual]
- [ ] T32.11 Commit: `VideoPreview model + edit UI`. complexity: [manual]

### P33 — `/update videos` (publish previews → re-import)

> Push pending VideoPreviews to YouTube; on success re-import that video.

- [ ] T33.1 `/update videos` handler reads channels + period; collects pending (`draft`) previews in scope. complexity: [low]
- [ ] T33.2 Per channel → one `PublishPreviewsJob` + one progress Segment (reuse P31's fan-out). complexity: [low]
- [ ] T33.3 Job maps preview → **API-supported fields** and publishes (`videos.update` snippet/status + `thumbnails.set`); flags staged Studio-only fields as not-published; status `publishing` → `published`/`failed`. complexity: [high]
- [ ] T33.4 On each success → enqueue a single-video `ImportVideosJob` to refresh `Video`. complexity: [low]
- [ ] T33.5 On failure → mark `failed` + surface the error in the Segment. complexity: [low]
- [ ] T33.6 Progress Segment updates; summary on finish. complexity: [low]
- [ ] T33.7 Specs (stubbed API; publish → reimport enqueued; failure path). complexity: [high]
- [ ] T33.8 Smoke. complexity: [manual]
- [ ] T33.9 Commit: `/update videos: publish previews → re-import`. complexity: [manual]

### P34 — Video lifecycle (`/publish` `/schedule` `/unlist` `/delete`)

> Each command opens a **sidebar picker** of eligible videos → select → echo + async job → Braille → result Segment **with a link to the video**.

- [ ] T34.1 Shared video-picker sidebar (reuse the `Pito::Sidebar` picker pattern). complexity: [high]
- [ ] T34.2 `/publish` → picker of publishable videos (private/draft, unlisted, scheduled). complexity: [low]
- [ ] T34.3 On select → set privacy `public` (`videos.update`). complexity: [high]
- [ ] T34.4 `/schedule` → same picker + a **date step** → privacy `private` + `status.publishAt`. complexity: [high]
- [ ] T34.5 `/unlist` → picker of public/unlisted → privacy `unlisted`. complexity: [low]
- [ ] T34.6 After publish/schedule/unlist → enqueue a single-video import. complexity: [low]
- [ ] T34.7 `/delete` → picker → `confirmation` Segment → `videos.delete`. complexity: [high]
- [ ] T34.8 On delete success → remove the local `Video` (+ dependents). complexity: [low]
- [ ] T34.9 Common flow: echo + async job → Braille → result Segment with a video link. complexity: [low]
- [ ] T34.10 Specs (eligible-set per command; stubbed state changes; schedule date; delete confirm). complexity: [high]
- [ ] T34.11 Smoke each command. complexity: [manual]
- [ ] T34.12 Commit: `Video lifecycle via picker (publish/schedule/unlist/delete)`. complexity: [manual]

---

## B. Games pipeline → promoted to `docs/games.md`

The games pipeline (formerly P35–P38: IGDB re-wire, search UI, add→sync, nightly
refresh) is **promoted to its own plan** at `docs/games.md` — expanded into the
full games domain (chat verbs + `/games import` sidebar + follow-ups +
recommendations), plus the `Stat`/`Pito::Stack`/`Pito::Suggestions` engines and
the phantom video/analytics dead-code removal. In progress on PR #62.

---

## C. AGENTS.md conventions (deferred — P43)

> Document the conventions established across the reboot. Do once the video/game
> pipelines land (several sections describe them).

- [ ] T43.1 `## Auth` — cookie session (24h idle, no hard max), no Session model, TOTP retained. complexity: [low]
- [ ] T43.2 `## Factories` — every model; `factories_spec` auto-validates. complexity: [low]
- [ ] T43.3 `## Rake` — `pito:test:*` / `pito:tools:*`; seeds prepare/populate; specced. complexity: [low]
- [ ] T43.4 `## Component CSS` — `data-accent`; no inline `style=`; **extract components, no spaghetti** (see InlineSeparator/Shortcut/Hint/Filter precedent). complexity: [low]
- [ ] T43.5 `## Footage / ffprobe` — Probe, `pito:tools:probe`, needs_grading/orientation. complexity: [low]
- [ ] T43.6 `## Dispatch` — async, persist-before-broadcast, turn timing, backend elapsed, command context. complexity: [low]
- [ ] T43.7 `## Conversations` — uuid routing, naming, sidebar grouping, `/new`/`/resume`, rename, history (↑/↓), localStorage panel persistence, cross-instance cable sync. complexity: [low]
- [ ] T43.8 `## Chatbox` — TAB channels, Shift+TAB periods (dead), thinking indicator + dictionaries, autocomplete (palette + ghost), typing phase-in, typewriter reveal. complexity: [low]
- [ ] T43.9 `## Videos` — read-only mirror; `/import`; `VideoPreview` + `/edit video`; `/update`; lifecycle. complexity: [low]
- [ ] T43.10 `## Games` — IGDB search sidebar, `/add game`, async sync, nightly refresh. complexity: [low]
- [ ] T43.11 `## Notifications` — model, `ctrl+/` sidebar, daily cleanup job, cross-instance sync. complexity: [low]
- [ ] T43.12 `## Analytics namespaces` — `Pito::Stats` vs `Pito::Analytics` (directional). complexity: [low]
- [ ] T43.13 Commit: `AGENTS.md conventions`. complexity: [manual]

---

## D. Playlists (future — full management)

> **Dropped for the Beta** — no `Playlist` model in the DB yet. Confirmed feasible
> end-to-end via the **YouTube Data API v3**. API mapping (all OAuth, `youtube` scope):
>
> | Operation                            | Endpoint                                | Notes                                                                                          |
> | ------------------------------------ | --------------------------------------- | ---------------------------------------------------------------------------------------------- |
> | Create playlist                      | `playlists.insert`                      | `snippet.title/description`, `status.privacyStatus`. ~50 units.                                |
> | Update playlist (title/desc/privacy) | `playlists.update`                      | full `snippet`+`status` (read-modify-write). ~50.                                              |
> | **Delete playlist**                  | `playlists.delete`                      | by playlist id; removes the whole playlist (items go with it). ~50.                            |
> | List playlists                       | `playlists.list` (`mine=true`)          | paginate; ~1 unit/page.                                                                        |
> | Add video                            | `playlistItems.insert`                  | `snippet.playlistId` + `resourceId{kind:youtube#video, videoId}` (+ optional `position`). ~50. |
> | Remove video                         | `playlistItems.delete`                  | by **playlistItem id** (not videoId) — must look it up first. ~50.                             |
> | List items                           | `playlistItems.list`                    | paginate; gives each item's id + `position`. ~1/page.                                          |
> | Reorder                              | `playlistItems.update`                  | set `snippet.position` (0-based); reordering N items = N updates. ~50 each.                    |
> | Public/Private/Unlisted              | `status.privacyStatus` on insert/update | `public` \| `unlisted` \| `private`.                                                           |
>
> Quota: a single playlist is cheap; **bulk reorder / bulk add is expensive** (50 units/write) — batch + debounce, and consider a "dirty position" diff so only moved items update. Watch the daily 10k-unit default quota.

### Data model

- [ ] PL.1 `Playlist` model: `youtube_playlist_id` (unique, nullable until created), `title`, `description`, `privacy_status` (enum public/unlisted/private), `position` (channel ordering, optional), `belongs_to :channel`, `last_synced_at`. complexity: [high]
- [ ] PL.2 `PlaylistItem` model: `belongs_to :playlist`, `belongs_to :video` (or `youtube_video_id` mirror), `youtube_playlist_item_id` (needed for delete/reorder), `position` (0-based), unique on (playlist, video); `playlist has_many :playlist_items, -> { order(:position) }, dependent: :destroy`. complexity: [high]
- [ ] PL.3 Factories + `factories_spec` coverage. complexity: [low]

### API client

- [ ] PL.4 `Channel::Youtube::Client` playlist methods: `create_playlist`, `update_playlist`, `delete_playlist`, `list_playlists`, `list_playlist_items`, `insert_item`, `delete_item`, `update_item_position`. WebMock-stubbed specs for each. complexity: [high]

### Commands (chat/slash) — each: echo → async job → Braille → result Segment

- [ ] PL.5 `/playlist new <title> [public|private|unlisted]` → `playlists.insert` + mirror a `Playlist`. complexity: [high]
- [ ] PL.6 `/playlist rename <playlist> <title>` and `/playlist privacy <playlist> <public|private|unlisted>` → `playlists.update`. complexity: [low]
- [ ] PL.7 **`/playlist delete <playlist>`** → `confirmation` Segment ("Delete playlist '<title>' (<N> videos)? This removes it on YouTube.") → on confirm `playlists.delete` → destroy the local `Playlist` (+ items). complexity: [high]
- [ ] PL.8 `/playlist add <video> [to <playlist>]` → sidebar pickers (video + target playlist) → `playlistItems.insert` (append at end) → mirror item. complexity: [high]
- [ ] PL.9 `/playlist remove <video> [from <playlist>]` → picker → look up the `playlistItem id` → `playlistItems.delete` → drop the mirror item → renumber positions. complexity: [high]
- [ ] PL.10 Reorder UI: a playlist sidebar with keyboard (↑/↓ to move a selected item) + drag → diff changed positions → minimal `playlistItems.update` calls → persist mirror order. complexity: [high]

### Sync

- [ ] PL.11 Import existing playlists: `playlists.list(mine)` + `playlistItems.list` per playlist → upsert mirror (id/title/privacy/items/positions); run on connect + via `/playlist sync`. complexity: [high]
- [ ] PL.12 Optional: include playlist sync in the daily channel sync (P60) cadence. complexity: [low]

### Quality

- [ ] PL.13 Specs: every command (stubbed API), confirmation on delete, position renumber on remove, reorder diff, privacy round-trip, dedupe on add. complexity: [high]
- [ ] PL.14 i18n all copy (incl. the delete confirmation + witty empty/error states). complexity: [low]
- [ ] PL.15 Commit(s), one per cohesive slice: models → client → create/update/delete → add/remove → reorder → sync. complexity: [manual]

---

## E. Still to cover (not yet designed)

- Further UI enhancements beyond those listed.
- `Pito::Stats` design (daily snapshot tables/jobs for channel + video totals) — pairs with P60.
- `Pito::Analytics` (wire TAB channel + Shift+TAB period into real queries).
- Real chat/slash domain handlers (list videos, channel overview…).
- ~~Centralized message-generation engine~~ → promoted to its own plan:
  `docs/copy-engine.md` (in progress on PR #62).
- Games detail screen (host for ScoreBar + TTB + probe snippet + `/add game` detail pane).
- A **videos list screen** (host for `/edit video` + lifecycle actions + a friendlier video picker).
- `Calendar` / `CalendarEntry` models — add when needed.
- Remote footage ingest (script + HTTP endpoint) if/when on Hetzner.

## F. Query-language ideas (chat/slash, later)

- `list` / `show` / `view|show @handle`.
- `list top channels` [`by subs|subscribers` | `by views and watched hours|time`].
- `list channels ordered by subs|subscribers (count)`.
- `list first|last 3 channels ordered|sorted by subs|subscribers (count)`.
- `force` / `refresh stats` with a `--fresh` argument.
- "Game in main screen"; "sidebar only for preview".

## G. Component extraction backlog

> From the ERB-spaghetti audit. Extract following the InlineSeparator/Shortcut/Hint precedent.

- [ ] Phase 1 (high ROI): `Pito::Separator::DividerLineComponent` (5+ `border-t border-line-default` sites); `Pito::Table::KeyValueRowComponent` (4+ key/value rows in keybinding/system/error/expandable); `Pito::Section::SectionHeaderComponent` (`font-bold mb-1` + yellow/orange, 4+ sites).
- [ ] Phase 2: `Pito::Badge::CodeBadgeComponent`; `Pito::List::PaletteItemComponent` (slash + autocomplete rows); shortcut+value display unification.
- [ ] Phase 3: `Pito::Table::CredentialRowComponent`; `Pito::Status::StatusIndicatorComponent` (●/○ dot); `Pito::List::NotificationRowComponent`.

## H. At merge

- Delete `docs/plan-beta-reboot-*.md` once Beta is merged; fold durable content into `architecture.md` / `design.md` / `installation.md` / `tools.md`.

Estra:

- for each /slash command I should have in the help the possible Follow-ups
- list commands should have filter, rm, show
- show should have rm, update

## I. Revisit & tighten `/help`

> Deferred during the games build. Once games + chat verbs land, do a focused
> pass on `/help`: make it accurate and complete for the new surface.

- [ ] Audit `/help` against the live command surface (slash + chat verbs +
      follow-ups): `/themes`, `/games import`, `list games`/`show game`/`delete
game`, and each message's `#<handle>` follow-ups.
- [ ] For each command/message, list its possible follow-ups in `/help` (per the
      Extra notes above: list → filter/rm/show; show → rm/update/resync/owned/…).
- [ ] Tighten formatting/grouping; ensure copy goes through `Pito::Copy`.
