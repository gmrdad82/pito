# Phase 11 — Video Workflow Features

> **Goal:** Build the production-side features that turn Pito from a tracking
> tool into a content management workflow: production calendar with state
> machine, browser-direct resumable upload, metadata management with sync
> reconciliation, scheduling, thumbnail management, and playlists. By the end of
> this phase, Pito is something the user actually uses to _produce_ content, not
> just to _analyze_ it.

**Depends on:** Phase 8 (real video data + sync infrastructure), Phase 10
(related-content via embeddings for AI-assisted suggestions).

**Unblocks:** Phase 12 (full UI for users), Phase 13 (observability of upload
jobs and quota burn from upload-heavy workflows).

---

## Why Phase 11 is now

By Phase 11, Pito knows:

- The user's owned channels and external reference channels (Phase 7-8)
- All the videos and their stats, refreshed daily (Phase 8)
- The user's KB context for each channel and video (Phase 9)
- Semantic relationships between content via embeddings (Phase 10)

Time to make Pito useful for **producing** new content, not just analyzing
existing. Phase 11 adds the workflow layer.

The phase is large but cohesive — every piece serves the production loop. The
user has an idea, plans it, records, edits, uploads, schedules, monitors,
retrospects. Pito should accompany every step. The Phase 4 design language
(locked across web/MCP/terminal/landing) carries through; new screens slot into
existing patterns rather than introducing new vocabulary.

---

## In scope

### Production state machine

A `VideoProduction` model represents a video moving through states from idea to
published. It exists _before_ a `Video` exists (you can plan a video that hasn't
been recorded), and links to a `Video` once the record is uploaded.

**States:**

```
idea → outlined → recorded → edited → ready → scheduled → uploading → published → archived
```

Plus a parallel `cancelled` terminal state from any non-archived state.

**Transitions** are tracked with timestamps. State changes are audited in a
`video_production_state_changes` table with `from_state`, `to_state`, `at`,
`by_user_id`. Use `aasm` gem (mature, expressive) unless the user prefers plain
Ruby.

**Schema:**

- `VideoProduction`: `id`, `tenant_id`, `user_id`, `channel_id`, `video_id`
  (nullable; set when uploaded), `state`, `target_publish_at`,
  `actual_published_at`, `title`, `description`, `metadata` (jsonb for tags,
  category, privacy, scheduling), timestamps
- Linked to `Video` via `video_id` once uploaded — the `VideoProduction` retains
  historical workflow data; the `Video` carries YouTube-side reality

### Production calendar

- Calendar view at `/calendar` showing scheduled, in-progress, and recently
  published videos
- Month / week / day toggles
- Drag-and-drop reschedule via Hotwire + Stimulus (consistent with the rest of
  the stack — no React)
- Filter by channel, by state
- Color coding by state with the existing design language palette (bracketed
  labels with state-specific accent colors documented in `pito/docs/design.md`)
- Each calendar entry links to the production show page

### Resumable browser upload (browser-direct to YouTube)

This is the architecturally most interesting piece. The user's video file does
**not** transit Pito's server — it goes directly from the user's browser to
YouTube. Pito coordinates the upload session, tracks progress, and creates the
`Video` record once YouTube confirms.

**Flow:**

1. User selects file in the browser via the upload form
2. Browser POSTs to Pito (`POST /api/uploads`) with file metadata (size, type,
   title, description, privacy, etc.)
3. Pito calls YouTube `videos.insert` with `uploadType=resumable` to receive a
   YouTube upload URL
4. Pito creates a `VideoUpload` record (`id`, `production_id`, `video_id`
   nullable, `youtube_upload_url`, `status`, `bytes_uploaded`, `total_bytes`,
   `last_progress_at`)
5. Pito returns the `VideoUpload` ID and the YouTube URL to the browser
6. Browser uploads chunks (1 MB recommended) directly to the YouTube URL
7. After each chunk, browser POSTs progress to `/api/uploads/:id/progress`
   (server records `bytes_uploaded`)
8. Browser persists upload state in `localStorage` so a tab refresh can resume
9. On completion, browser POSTs to `/api/uploads/:id/complete` with YouTube's
   response payload; Pito creates the `Video` record from the response and links
   it to the `VideoProduction`
10. State machine transitions: `uploading` → `published` (or `scheduled` if
    `publishAt` was set)

**Resume on disconnect:** localStorage holds the upload URL, file hash, and
`bytes_uploaded`. On reload, the browser queries YouTube for the current upload
offset and resumes from there. If the YouTube upload URL has expired (typically
24 hours), the user must re-initiate.

**Bandwidth implication:** Pito server bandwidth is unaffected by upload size. A
4 GB video transits browser → YouTube directly. This is the standard YouTube
upload pattern; Pito just orchestrates.

### Metadata management

Editing video metadata: title, description, tags, category, privacy, scheduled
publish time, thumbnail, playlists.

**Sync reconciliation pattern:**

- Pito's local copy of metadata (`Video` record) and YouTube's copy can drift if
  the user edits via YouTube Studio out of band
- Each `Video` has `metadata_synced_at` and `metadata_locally_modified_at`
  columns
- "Pull from YouTube" button: overwrites local with remote (after confirmation)
- "Push to YouTube" button: overwrites remote with local
- Drift detection: if `metadata_locally_modified_at > metadata_synced_at` AND a
  sync surfaces YouTube-side changes since the last sync, show a banner:
  "YouTube has different data — Pull or Push?"
- Default behavior on save without explicit Push: local-only save (no API call);
  user must explicitly Push to publish changes upstream

This avoids quota burn on every edit while keeping the user in control.

### Thumbnail management

- Video show page: thumbnail upload form with image preview
- Server-side validation:
  - Magic-byte content type check (not extension trust)
  - Dimensions check: must be 1280×720 (resize if not, with user opt-in)
  - File size: under 2 MB per YouTube's spec
  - Format: convert to JPEG if needed
- Image processing via `image_processing` + `ruby-vips` (faster, leaner than
  mini_magick)
- EXIF stripping on every uploaded image
- On save: call `thumbnails.set` via `YouTube::Client` from Phase 7
- Save the processed thumbnail file to the configured video-notes folder under
  `videos/<channel-id>/<video-id>/thumbnails/<timestamp>.jpg`. The original spec
  routed this through `pito-yt-kb` and the Phase 9 sandbox; the YouTube KB repo
  has been dropped — channel/video notes reuse the project-notes pattern from
  Phase 4 — Project Workspace and respect the `yt:write` scope at the tool
  layer.
- Thumbnail history: list past thumbnails with bracketed `[restore]` links

### Scheduling

- YouTube supports scheduled publish via `status.privacyStatus = 'private'` +
  `status.publishAt = ISO8601`
- Pito UI: schedule field on the metadata form accepts a datetime
- Backend translates to YouTube's expected format and pushes via `videos.update`
- The local `VideoProduction` records `target_publish_at` and stays in
  `scheduled` state until YouTube transitions it
- A daily reconciliation job detects state changes (Phase 8's sync
  infrastructure handles this — when a stats sync sees a video that was
  `private` is now `public`, the `VideoProduction` advances to `published`)

### Playlists

- `Playlist` and `PlaylistItem` models (likely already exist from Alpha; verify
  and extend with `tenant_id` per Phase 3 pattern)
- Phase 8's `Sync::OwnedChannelMetadataJob` extends to also sync playlists
- Playlist show page: drag-and-drop reorder via Hotwire + Stimulus
- Add/remove videos via search-and-select (uses Phase 10's hybrid search for
  finding videos)
- All CRUD calls map to YouTube API (`playlists.insert`, `playlistItems.insert`,
  etc.)
- Playlists from external channels are synced too (read-only — can't reorder
  external playlists)

### AI-assisted content suggestions (light touch)

- Use Phase 10's embeddings: "Find similar videos in my library" button when
  starting a new production
- Use Phase 9's `yt:list_channel_context` to surface
  voice/audience/skills/strategy when drafting metadata
- Optional: an MCP-driven "draft a description for this video" tool that:
  - Reads the production's `plan.md` (Phase 9)
  - Reads the channel's voice/audience/skills (Phase 9)
  - Asks Claude (via the user's existing Claude session, not a server-side LLM
    call) to generate a description draft
  - The user reviews and edits before save

Pito itself does **not** call an LLM directly. The AI assistance is delivered
through Claude clients calling Pito's MCP tools — the
user-as-Claude-conversation pulls context, drafts, and writes back. This keeps
Pito stateless on the LLM side and respects the user's existing Claude
subscription costs.

### Out of scope

- Video editing features (way out of scope; user uses external editors)
- Caption / subtitle generation (interesting Theta; not Beta)
- A/B thumbnail testing (YouTube Studio does this; not duplicating)
- Live streaming workflow (out of Beta)
- YouTube Shorts-specific features (treated as regular videos; differentiation
  can come later if useful)
- Multi-channel batch publishing (out of scope; one video at a time)
- AI-generated metadata that isn't user-mediated (Pito does not call LLMs
  server-side; all AI assistance flows through user-driven Claude conversations
  via MCP)

---

## Plan checklist

### Production state machine

- [ ] Migration: create `video_productions` table per the schema above
- [ ] Migration: create `video_production_state_changes` audit table
- [ ] Add `aasm` gem (or implement plain Ruby state machine; `aasm` recommended
      for clarity)
- [ ] `VideoProduction` model with state machine, transitions, audit hook
- [ ] Specs: every state transition (valid + invalid), audit row created on each
      transition

### Calendar

- [ ] `/calendar` route and controller
- [ ] Calendar view with month/week/day toggles
- [ ] Hotwire + Stimulus drag-and-drop with persistence via PATCH endpoint
- [ ] Filter UI (channel, state)
- [ ] State color coding documented in `pito/docs/design.md`
- [ ] Specs: date filtering, channel filtering, drag-drop endpoint, state
      filtering

### Resumable upload

- [ ] Migration: ensure `VideoUpload` exists with required columns
- [ ] `POST /api/uploads` — initiates resumable session via YouTube API; returns
      YouTube URL + Pito upload ID
- [ ] `POST /api/uploads/:id/progress` — records `bytes_uploaded`
- [ ] `POST /api/uploads/:id/complete` — creates `Video` from YouTube response,
      links to `VideoProduction`, transitions state
- [ ] Frontend: file picker form, chunked upload to YouTube URL, progress bar,
      localStorage persistence
- [ ] Resume logic: on reload, query YouTube for offset, resume
- [ ] Specs: initiation, progress, completion, error recovery, resume after
      disconnect simulation

### Metadata management

- [ ] Video show page: editable metadata form (title, description, tags,
      category, privacy, scheduled time)
- [ ] Save behavior: local-only by default; explicit Push button to send to
      YouTube
- [ ] "Pull from YouTube" button with confirmation
- [ ] Drift detection banner when local and remote have both changed
- [ ] Specs: local save, push, pull, drift detection, conflict resolution UX

### Thumbnail management

- [ ] Video show page: thumbnail upload form with preview
- [ ] Backend validation: magic bytes, dimensions, file size, format
- [ ] Image processing via `image_processing` + `ruby-vips`
- [ ] EXIF stripping
- [ ] Save processed file under
      `videos/<channel-id>/<video-id>/thumbnails/<timestamp>.jpg` in the
      configured video-notes root (originally `pito-yt-kb` via the Phase 9
      sandbox; the YouTube KB repo has been dropped — reuse the Phase 4 —
      Project Workspace project-notes pattern)
- [ ] Push to YouTube via `thumbnails.set`
- [ ] Thumbnail history list with restore action
- [ ] Specs: validation pass/fail, conversion correctness, sandbox enforcement,
      YouTube push

### Scheduling

- [ ] Metadata form schedule field
- [ ] Backend translation to YouTube `publishAt` format
- [ ] Production calendar shows scheduled videos with countdown indicators
- [ ] Reconciliation: Phase 8's sync detects published-state transition;
      `VideoProduction` advances accordingly
- [ ] Specs: schedule create, schedule modify, schedule cancel, reconciliation
      trigger

### Playlists

- [ ] Verify `Playlist` and `PlaylistItem` models exist; add `tenant_id` if
      missing
- [ ] Extend Phase 8's `Sync::OwnedChannelMetadataJob` to sync playlists
- [ ] Playlist show page: drag-and-drop reorder
- [ ] Add/remove videos with hybrid search-and-select (uses Phase 10 search)
- [ ] CRUD calls map to YouTube API
- [ ] External playlists are read-only; UI clearly indicates this
- [ ] Specs: create, add item, remove item, reorder, external read-only
      enforcement

### AI-assisted suggestions (light)

- [ ] "Find similar videos" button on new production form (uses Phase 10 related
      endpoint)
- [ ] Channel context summary panel on production form (uses Phase 9
      `yt:list_channel_context`)
- [ ] Optional: MCP tool `yt:draft_description` that returns a structured prompt
      the user's Claude conversation can use (no server-side LLM call)
- [ ] Document the AI-assist pattern in `pito/docs/architecture.md`: AI is
      user-mediated through Claude clients, not server-initiated

### Documentation

- [ ] Update `pito/docs/architecture.md`: workflow features, state machine,
      upload architecture, AI-assist pattern
- [ ] `pito/docs/upload.md` (new): resumable upload flow diagram, error
      recovery, expected user experience
- [ ] Update `pito/docs/design.md`: calendar UI, state colors, multi-stage form
      patterns, drift indicator
- [ ] Update `pito/docs/mcp.md`: any new `yt:*` tools added (e.g.,
      `yt:draft_description`)

### Validation

- [ ] Manual: end-to-end production flow from idea → outlined → recorded →
      edited → ready → scheduled → uploading → published, with state changes
      captured
- [ ] Manual: schedule a test video for 5 minutes from now; verify YouTube
      schedules it; verify the `VideoProduction` advances to `published` after
      actual publish (within minutes of the scheduled time)
- [ ] Manual: upload a 500 MB test video via browser; refresh mid-upload; verify
      resume works; final `Video` record created
- [ ] Manual: edit metadata locally without Push; verify YouTube unchanged;
      click Push; verify YouTube updated
- [ ] Manual: induce drift (edit on YouTube Studio, then edit locally without
      Pull); verify drift banner; resolve via Pull or Push
- [ ] Manual: upload custom thumbnail; verify YouTube updated and KB folder
      records the file
- [ ] Manual: create playlist, add videos via search-and-select, reorder; verify
      YouTube reflects
- [ ] Manual: open new production form; click "Find similar videos"; verify
      Phase 10 results show
- [ ] All RSpec specs pass; new specs cover state machine, upload flow (with
      fixture multipart), metadata sync reconciliation
- [ ] Brakeman, bundler-audit, Dependabot — clean

---

## Specs requirements

- `VideoProduction` state machine: every transition, every invalid transition,
  side effects (audit row, timestamps).
- Upload flow: initiation, progress recording, completion, error recovery,
  resume after disconnect, expired URL handling.
- Metadata sync reconciliation: Pito edit pushes to YouTube, out-of-band YouTube
  edit detected and surfaced, drift resolution paths.
- Thumbnail: image validation (pass and fail cases), dimensions resize, EXIF
  stripping, sandbox enforcement on KB folder write.
- Playlist CRUD: create, add item, remove item, reorder; YouTube API calls via
  VCR; external playlist write rejection.
- Calendar: date filtering, channel filtering, drag-drop endpoint, state filter.
- Schedule reconciliation: scheduled video transitions to published in
  production state when YouTube publishes.

## Security requirements

- Resumable upload URL is sensitive — anyone with the URL can upload arbitrary
  content as the user. Treat as a secret. Never log the full URL. Browser
  receives the URL only after successful authentication on `POST /api/uploads`.
  URLs expire per YouTube's spec (~24 hours).
- Image upload: validate dimensions and content-type server-side via magic
  bytes; never trust browser-reported MIME.
- Image processing in `ruby-vips` is safer than shell-out variants; verify no
  shell-out for filename manipulation.
- File system writes (thumbnail history) sandboxed via Phase 9's
  `Yt::KbSandbox`.
- EXIF stripping: prevents accidental location/timestamp leakage in uploaded
  thumbnails.
- Brakeman: especially around file upload paths and image processing.
- bundler-audit: clean. Verify image processing libs (`image_processing`,
  `ruby-vips`).
- Dependabot: review.
- `pito/docs/design.md`: calendar, upload form, metadata edit, thumbnail
  manager, drift indicator — all documented.

## Manual testing checklist

The user runs through this before commit:

1. Create a new `VideoProduction` from the productions index; advance through
   `idea → outlined → recorded → edited → ready` via UI buttons; check audit
   table for state-change rows
2. Drag the production to a different date on the calendar; verify persistence
3. Upload a real video (10–60s clip): file picker → progress bar → completion →
   `Video` record created with YouTube ID
4. Mid-upload refresh: tab close → reopen → upload resumes from last chunk
5. Edit title locally (no Push); verify YouTube unchanged; click Push; verify
   YouTube reflects within seconds
6. Edit on YouTube Studio out of band; trigger a sync; verify drift banner
   appears in Pito; choose Pull → local matches remote
7. Upload custom 1280×720 thumbnail; verify YouTube updated; verify the
   configured video-notes folder records the file at
   `videos/.../thumbnails/<timestamp>.jpg` (originally under `pito-yt-kb`; the
   YouTube KB repo has been dropped — reuse the Phase 4 — Project Workspace
   project-notes pattern)
8. Schedule a video for 2 minutes from now; wait; verify Pito's production
   advances to `published` state after the scheduled time
9. Create a playlist; add 3 videos via search-and-select; reorder via drag-drop;
   verify YouTube reflects
10. New production form: click "Find similar videos" → Phase 10 related results
    appear
11. Channel context summary panel shows voice/audience/skills/strategy when
    drafting (Phase 9 integration)
12. `bundle exec rspec` — green
13. Sidekiq web shows no errors

---

## Challenges to anticipate

- **Resumable upload from browser is non-trivial.** YouTube's resumable upload
  protocol is well-documented but the browser-side implementation requires
  careful chunk management, retry logic, and state persistence. Look into
  `tus-js-client` or similar — but the stack is Hotwire + Stimulus (no
  React/Vue), so dependencies must be vanilla-JS-compatible.
- **Network failures during upload.** Must handle disconnect, server 5xx,
  browser tab close. localStorage holds state so refresh resumes; expired URLs
  need re-initiation with clear UX.
- **Sync conflicts (drift).** Last-write-wins is acceptable but the drift banner
  should make the choice explicit. Don't auto-resolve.
- **Thumbnail file size limits.** YouTube allows up to 2 MB. Resizer must
  respect this; if a 1280×720 JPG exceeds 2 MB after resize, increase JPEG
  compression rather than rejecting.
- **Scheduled publish edge cases.** YouTube can fail to publish at scheduled
  time (rare but documented). Pito's reconciliation must detect and surface
  failure (not silently leave the video in `scheduled` forever).
- **YouTube quota cost of upload.** `videos.insert` is 1600 units. A power user
  uploading multiple times a day uses significant quota. Track in Phase 7's
  audit table; surface in Phase 13's observability.
- **External playlist writes are not allowed.** Synced from external channels
  but read-only in Pito's UI. Prevent the UI from offering edit actions on
  external playlists; tool-side enforcement rejects with clear error.
- **`aasm` adds a dependency.** It's mature and widely used. Plain Ruby state
  machine is feasible but `aasm` reads better for complex state spaces.
  Recommend `aasm`; capture in `challenges.md` if user prefers plain Ruby.
- **Both Pumas and the upload coordination.** Web Puma handles upload
  initiation, progress, completion (browser hits these endpoints). MCP Puma
  might also expose upload-related tools (e.g., `yt:start_upload`) for advanced
  users. Decide whether MCP exposes upload at all in Phase 11; if not, capture
  in `additions.md` for Phase 12 consideration.

---

## Confirmation gates for Claude Code

Before executing, confirm with the user:

1. The user is OK with browser-direct upload (file content does not pass through
   Pito server). This is the standard YouTube upload pattern — flagging it just
   to be sure.
2. The user accepts the quota cost of upload-heavy workflows (1600 units per
   upload). With the default 10k/day quota, that's ~6 uploads/day before
   exhaustion.
3. State machine library: `aasm` is the recommendation. Confirm or prefer plain
   Ruby.
4. Thumbnail processing library: `image_processing` + `ruby-vips`. Confirm or
   alternative.
5. AI assistance is user-mediated only (Pito does not call LLMs server-side).
   Confirm.
6. Phase 11's scope is large; the user is OK with this being a multi-session
   phase.
