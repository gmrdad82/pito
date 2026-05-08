# Phase 7.5 — Step 06 — Footage Thumbnails Experiment

> Implementation-ready spec. Extracts a film-strip's worth of frames from each
> imported footage file, stores them under `pito-assets` in a two-tier (master
>
> - thumb) layout, renders a representative thumb in the project show page's
>   `_footage_pane.html.erb`, and powers a DaVinci-style scrub UI on both the
>   Rails footage detail page and the `pito` CLI's footage detail screen.
>   Depends on `05-pito-assets-volume.md` landing first. The CLI half also
>   depends on Track B (`02-cli-hygiene-sweep.md`) landing first — see
>   "Sequencing" below.

---

## Goal

Give the user a visual handle on each imported footage row without opening a
video player, AND give them a fast way to scrub a footage clip frame-by-frame to
find the moment they're looking for. The Footage pane today shows filename +
metadata (duration, resolution, fps, codec). This step adds:

1. A representative thumbnail rendered in the row (the frame at 50% duration).
2. A footage detail page with a DaVinci-style scrub layout — big preview area on
   top, fixed center playhead, horizontally-scrolling film strip below — driven
   by a per-footage frame manifest extracted at import.
3. The same scrub layout in the `pito` CLI's footage detail screen, via
   `ratatui-image`, with graphics-protocol auto-detection (Kitty / Sixel /
   iTerm2 inline / halfblocks fallback).

Why now: thumbnails are the kind of UX that compounds — once one surface has
them, every other surface (timelines, future "browse footage" pickers, the
search results page when the search engine grows beyond text) wants them.
Landing the extraction pipeline now means those future surfaces inherit it for
free. And the scrub layout itself is a primitive that future timeline work will
reuse.

## Scope boundary

In-scope:

- Multi-frame extraction per footage at adaptive interval (see Decisions).
- Two-tier output per frame (master 1280x720 + thumb 320x180), letterbox- padded
  to uniform 16:9.
- Storage under `<pito-assets>/footages/<footage_id>/{m,t}/<HH-MM-SS>.jpg`.
- Extraction: importer-side ffmpeg (per-frame seek + decode), thumb derived from
  master via libvips (ImageProcessing) — single ffmpeg pass per timestamp, fast
  Vips downscale.
- Render in `_footage_pane.html.erb`: ONE thumb — the frame at 50% of duration
  (median timestamp).
- Render on the Rails footage detail page: DaVinci-style scrub layout with big
  preview, center playhead, scrolling strip, two scrub interactions
  (hover-on-preview and drag/scroll-the-strip).
- Render on the `pito` CLI footage detail screen: same layout via
  `ratatui-image`, with graphics-protocol capability detection and a halfblocks
  / text-only fallback.

Out of scope:

- User-pickable "pinned" thumbnail for the row preview. Defer.
- Animated thumbnails / gif previews. Defer.
- Server-side video transcoding. ADR 0001 still forbids server-side video bytes
  in. The extraction runs ON THE USER'S MACHINE during import (the importer is
  local, has access to `local_path`, and `ffmpeg` is already a documented system
  dependency for ffprobe). The extracted JPEGs ARE uploaded over the API to
  Pito.
- A 4K master tier or other variants. The directory layout reserves room for a
  future `4k/` peer next to `m/` and `t/` without rename churn, but it is not
  generated in this step.
- A `get_footage_thumbnail` MCP tool. Future surface; not in 7.5.
- Cloudflare Pages website usage of thumbnails.

## Sequencing

This spec has two halves with different prerequisites:

- **Rails half** — depends on spec 05 (`pito-assets` volume). Can land
  independently of CLI work.
- **CLI half** — depends on spec 05 AND on Track B (`02-cli-hygiene-sweep.md`)
  landing first. Track B brings the CLI to ratatui 0.30 and the
  screen-layout-parity baseline that the new `footage_detail` screen builds on.
  Adding `ratatui-image` and a new detail screen on top of an in-flight ratatui
  upgrade is a recipe for rebase pain.

The implementation agent dispatch order is therefore:

1. Spec 05 lands.
2. Spec 06 Rails half lands (importer extraction shape + Rails endpoints + web
   scrub UI).
3. Track B / spec 02 lands (CLI hygiene sweep + ratatui 0.30 + layout parity).
4. Spec 06 CLI half lands (ratatui-image, footage_detail screen, scrub parity).

## Architecture

### Frame extraction shape

For each footage, extract N frames at evenly-spaced timestamps. The count adapts
to clip length:

```
count = clamp(duration_seconds / 60, 10, 120)
step_seconds = duration_seconds / count
timestamps = [step * 0.5, step * 1.5, ..., step * (count - 0.5)]
```

In words: roughly one frame per minute, with a soft floor of 10 frames (short
clip — a 3-min file gets 10 frames at ~18 sec interval) and a soft ceiling of
120 frames (long stream — a 5-hour stream caps at 120 frames at ~2.5 min
interval).

Each frame produces TWO JPEG outputs:

- **Master** — 1280x720, JPEG `q:v 4`. ~80–150 KB per frame. Used by the web
  big-preview area at full quality and by the CLI's `ratatui-image` renderer
  (which downsizes for terminal display).
- **Thumb** — 320x180, JPEG `q:v 4`. ~10–18 KB per frame. Used by the film-strip
  cells (web + CLI) and by the project screen `_footage_pane` representative
  thumbnail.

Both outputs are letterbox-padded to a uniform 16:9 aspect ratio so that strip
cells line up cleanly regardless of source orientation. Vertical / portrait
sources get pillarboxed (black bars left + right); 4:3 retro footage gets
letterboxed (black bars top + bottom); 16:9 fills exactly. ffmpeg filter chain:

```
-vf "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=black"
```

Storage budget at scale: 1000 footages × 60 frames × (~110 KB master + ~14 KB
thumb) ≈ 7 GB. Acceptable for any decent VPS.

### Filename convention

Each frame's filename IS its timestamp: `<HH-MM-SS>.jpg` (zero-padded — e.g.
`00-01-30.jpg` for 90 seconds in). No separate metadata file, no DB rows for
individual frames. Filesystem sort order = timeline order. The web frame
manifest (a JSON the scrub controller fetches) is just an array of timestamp
strings or seconds, generated server-side by listing the directory.

### Directory layout

Under `<PITO_ASSETS_PATH>` (resolved via the spec-05 helper):

```
<assets_root>/footages/<footage_id>/m/<HH-MM-SS>.jpg   # masters
<assets_root>/footages/<footage_id>/t/<HH-MM-SS>.jpg   # thumbs
```

Subdirectories `m/` and `t/` keep the two tiers cleanly separated. A future
`4k/` peer (e.g. for a hypothetical retina master) can be added without renaming
any existing file. Tenant scoping moves to a future migration when multi-tenancy
lands; for now the path is flat per the current single-tenant convention.
(Implementation agent: confirm with the spec-05 author whether the tenant prefix
from the notes layout applies here. If so, prepend `<tenant_id>/` to the path.)

### Where extraction runs

**Importer side (`extras/cli/`).** The `pito footage import` subcommand already
runs `ffprobe` per file. It now runs an extraction pass per file:

1. From ffprobe output, compute `count` and `timestamps` per the formula above.
2. For each timestamp, run a single ffmpeg seek+decode that emits the master
   directly:
   ```
   ffmpeg -ss <ts> -i <path> -frames:v 1 \
     -vf "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=black" \
     -q:v 4 <tmp_master.jpg>
   ```
3. Derive the thumb from the master via libvips (ImageProcessing) — a fast
   downscale to 320x180. Pito already has libvips per the Rails image-processing
   pipeline; for the CLI side, the importer can either (a) shell out to
   libvips's `vipsthumbnail` if available, or (b) run ffmpeg again on the master
   to produce the 320x180. Default: option (b), to keep the CLI's
   system-dependency surface to ffmpeg only and avoid a libvips install hint.

   Refinement: if libvips IS available on the importer's system, prefer it for
   the thumb derivation (one fast Vips call beats a second ffmpeg invocation).
   Detect at startup; pick the available tool.

4. Upload both files via the API per the upload shape below.

The importer is the single point of extraction. The Rails server never runs
ffmpeg. ADR 0001 is honored.

### Upload shape

Two endpoints:

- `POST /api/projects/<id>/footages.json` — existing, unchanged. Creates the
  `Footage` row from metadata.
- `PATCH /api/footages/<id>/frames.json` — new. Multipart upload of the full
  frame set for one footage. Body shape:
  - `frames[]` — array of file parts, each named for its tier and timestamp,
    e.g. `m/00-01-30.jpg` and `t/00-01-30.jpg`. The endpoint parses the part
    name to determine tier + timestamp and writes to the right path.

  Alternative: one PATCH per frame. Simpler API surface but N round- trips per
  footage. Default: bulk PATCH to keep import fast. The implementation agent
  picks; if bulk PATCH proves awkward in multipart parsing, fall back to
  per-frame PATCH and accept the latency.

The endpoint:

1. Authenticates via the existing API token auth.
2. Validates each part is a JPEG (mime sniff + per-file size <2MB, total payload
   <500MB).
3. Writes each file via `File.binwrite(path, part.read)` atomically
   (`tmp + rename`) to its tier+timestamp path under
   `<assets_root>/footages/<footage_id>/{m,t}/<HH-MM-SS>.jpg`.
4. Returns `200 OK` with the manifest (array of timestamps in seconds).

### Where rendering happens

**`_footage_pane.html.erb`** (project show page) — adds a
`<td class="thumb-cell">` with an `<img>` tag pointing at a server-side route
that streams the median-timestamp THUMB:

```erb
<td class="thumb-cell">
  <img src="<%= footage_pane_thumbnail_path(footage) %>"
       alt="thumbnail"
       loading="lazy"
       width="160" height="90">
</td>
```

The route resolves the median timestamp (frame at 50% duration) by listing the
`t/` directory and picking the middle entry.

**Footage detail page** — new or extended view at `/footages/:id`. Layout:

```
+-----------------------------------------+
|                                         |
|         big preview frame               |
|        (changes with scrub)             |
|                                         |
+-----------------------------------------+
                   +                          <- playhead fixed at center
| | | | | | | | | | | | | | | | | | | | |    <- film strip scrolls
                                                horizontally
```

The big preview's `<img>` `src` swaps as `active_timestamp` changes. The film
strip is a scroll container with one cell per frame; cells are images (`t/`
tier) at fixed pixel size. CSS:
`scroll-snap-type: x mandatory; scroll-snap-align: center` makes the strip click
onto the nearest cell as the user releases the drag.

**Two scrub interactions** (must work consistently across web and CLI):

1. **Hover/cursor on big preview** → cursor X position relative to the preview
   width maps to a normalized `0..1` time ratio →
   `active_timestamp = duration_seconds * x_ratio` → big preview swaps to the
   nearest frame.
2. **Drag/scroll the strip horizontally** → strip translates under the fixed
   center playhead → playhead's logical position over the strip determines
   `active_timestamp`. Strip scroll-snaps to nearest cell on release.

Both interactions update the same `active_timestamp` state.

**Frame routes** — Rails serves frames via:

- `GET /footages/:id/frames/:tier/:timestamp.jpg` — `tier` is `m` or `t`,
  `timestamp` is `HH-MM-SS`. Streams the file from
  `<assets_root>/footages/<id>/<tier>/<timestamp>.jpg` with
  `Cache-Control: max-age=86400`. 404 if absent (no placeholder for individual
  frames; the manifest endpoint is the source of truth for what exists).
- `GET /footages/:id/frames.json` — manifest. Returns
  `{ "duration": 1234.5, "timestamps": [0, 60, 120, ...] }` (seconds as floats).
  The web Stimulus controller fetches this once at connect.
- `GET /footages/:id/thumb.jpg` — convenience route returning the median thumb
  (used by `_footage_pane.html.erb`'s helper). `send_file` with
  `Cache-Control: max-age=86400`. Falls back to the placeholder SVG if no frames
  exist yet.

### Web Stimulus controller

`app/javascript/controllers/footage_scrub_controller.js`:

- Targets: `bigPreview` (img), `strip` (scrollable div with cells), `playhead`
  (the fixed `+` marker, decorative).
- Values: `manifestUrl` (string), `frameUrlTemplate` (string with `%{tier}` and
  `%{timestamp}` placeholders), `durationSeconds` (number).
- State: `activeTimestamp` (number, seconds), `manifest` (array of timestamps).
- On connect: fetch the manifest JSON; preload the median frame's master into
  `bigPreview`.
- Events:
  - `mousemove` on `bigPreview` → recompute `activeTimestamp` from
    `event.offsetX / target.clientWidth`.
  - `pointerdown` + `pointermove` on `strip` → update strip `scrollLeft`;
    recompute `activeTimestamp` from
    `(scrollLeft + clientWidth/2) / scrollWidth`.
  - `wheel` on `strip` → translate to horizontal scroll.
- Render: derive the closest manifest timestamp to `activeTimestamp`, swap
  `bigPreview.src` to the master at that timestamp.

### CLI scope (depends on Track B)

Adds `ratatui-image` to `extras/cli/Cargo.toml`. The crate auto-detects terminal
capability and uses Kitty graphics protocol (best — for Kitty / Ghostty /
WezTerm), Sixel, iTerm2 inline, or halfblocks fallback (Unicode block chars in
24-bit color, works in Alacritty / plain xterm).

**Files (CLI):**

- `extras/cli/Cargo.toml` — add `ratatui-image` dependency.
- `extras/cli/src/ui/footage_detail.rs` (new) — the new screen. Mirrors the web
  layout: big preview area on top, fixed center playhead glyph,
  horizontally-scrolling strip below.
- `extras/cli/src/ui/screens.rs` (or wherever the screen registry lives
  post-Track B) — register `FootageDetail` as a navigable screen.
- `extras/cli/src/api/footage.rs` — add `fetch_manifest`,
  `fetch_frame(tier, timestamp)`. Image bytes fetched over HTTP from Rails.
- `extras/cli/src/cache/frames.rs` (new) — local cache at
  `~/.cache/pito/thumbnails/<footage_id>/{m,t}/<HH-MM-SS>.jpg` to avoid
  re-fetching on every render. LRU eviction with a reasonable size cap (e.g. 500
  MB total cache); implementation agent picks the exact cap. Cache key is
  `<footage_id>/<tier>/<timestamp>`.
- `extras/cli/src/app.rs` — extend `App` state with terminal capability
  (`Kitty | Sixel | ITerm2 | Halfblocks | TextOnly`), detected once at boot and
  reused.

**Scrub interactions (CLI):**

- `MouseEventKind::Moved` over the big preview rect → cursor X relative to rect
  width → `active_timestamp` update.
- `MouseEventKind::ScrollUp` / `ScrollDown` over the strip → translate strip
  scroll position; recompute `active_timestamp` from playhead alignment.
- `MouseEventKind::Down` + `Drag` + `Up` over the strip → drag-to- scrub; snap
  to nearest cell on release.
- Keyboard fallback (no mouse): `h`/`l` or `←`/`→` step one frame; `H`/`L` jump
  10 frames; `g`/`G` jump to start/end.

**Fallback UX in non-graphics terminals:**

When the terminal can't render images (capability = `TextOnly`, or `Halfblocks`
is detected but the user has opted out via a config flag), keep the layout shape
but show the timestamp text inside the big- preview area instead of the image.
Strip cells become tiny text labels (`00-01-30`) instead of image cells.
Functional, less visually rich. `Halfblocks` is the default fallback when
graphics protocol is unavailable; it works in Alacritty / plain xterm.

### Failure handling

- **ffmpeg missing on user machine.** The importer prints the install hint
  (matches the existing ffprobe-missing message shape) and skips frame
  extraction entirely. The footage row is imported with metadata only.
  Re-running import after installing ffmpeg fills in the frames.
- **ffmpeg fails on a specific timestamp** (corrupt frame, bad seek). Importer
  logs the error, skips that timestamp, continues with the rest. Manifest
  reflects only the timestamps that succeeded.
- **Frame upload fails** (network, server error). Importer logs; footage exists
  with whatever frames did upload. Re-import retries (server-side write is
  idempotent — `tmp + rename` overwrites).
- **Server has a partial frame set.** The web manifest endpoint reports exactly
  what's on disk; the scrub UI works with whatever's available (a sparse strip
  is still navigable).

## Files touched

### Rails

- `app/controllers/footages_controller.rb` — extend with `#show` (footage detail
  page), `#thumb` (median thumb), `#frames_index` (manifest JSON),
  `#frames_show` (single frame stream).
- `app/controllers/api/footages_controller.rb` — add `#frames_update` (PATCH
  bulk upload).
- `config/routes.rb` — add the routes:
  - `GET /footages/:id` (detail page).
  - `GET /footages/:id/thumb.jpg`.
  - `GET /footages/:id/frames.json`.
  - `GET /footages/:id/frames/:tier/:timestamp.jpg`.
  - `PATCH /api/footages/:id/frames.json`.
- `app/views/footages/show.html.erb` (new) — DaVinci-style scrub layout.
- `app/views/projects/_footage_pane.html.erb` — add the
  `<td class="thumb-cell">` with the median-thumb `<img>`.
- `app/javascript/controllers/footage_scrub_controller.js` (new).
- `app/assets/images/footage_thumbnail_placeholder.svg` (new) — fallback for the
  median-thumb route when no frames exist.
- `app/helpers/footages_helper.rb` (new or extend) — path helpers for thumb /
  frames / manifest.
- Stylesheet — `.thumb-cell` rule with fixed dimensions
  (`width: 160px; height: 90px;`); `.scrub-layout`, `.scrub-big-preview`,
  `.scrub-strip`, `.scrub-playhead` rules for the detail page.
- `spec/requests/footages_spec.rb` — cover the GET routes (file present, file
  missing → placeholder for thumb, 404 for individual frame), manifest shape,
  PATCH validation (success, non-JPEG → 422, oversize → 413).
- `spec/system/projects_show_spec.rb` — assert the median-thumb `<img>` renders
  in the footage pane.
- `spec/system/footages_show_spec.rb` (new) — assert the scrub layout renders,
  the manifest is fetched, and a hover on the big preview swaps the `src` (use
  the existing JS-capable system spec pattern).

### CLI

Track B (spec 02) MUST land before this CLI work begins.

- `extras/cli/Cargo.toml` — add `ratatui-image`.
- `extras/cli/src/footage/probe/ffmpeg_frames.rs` (new) — extract one master
  JPEG per timestamp via ffmpeg with the letterbox-pad filter chain.
- `extras/cli/src/footage/probe/thumb_derive.rs` (new) — derive the 320x180
  thumb from a master, via libvips if available, ffmpeg otherwise.
- `extras/cli/src/footage/api/client.rs` — add `upload_frames` (bulk PATCH
  multipart).
- `extras/cli/src/commands/footage.rs` — orchestrate: after each successful
  create, run extraction across all timestamps, then upload. Failures log +
  continue.
- `extras/cli/src/ui/footage_detail.rs` (new) — the scrub screen.
- `extras/cli/src/ui/screens.rs` — register the new screen.
- `extras/cli/src/api/footage.rs` — add `fetch_manifest`, `fetch_frame`.
- `extras/cli/src/cache/frames.rs` (new) — local image cache.
- `extras/cli/src/app.rs` — capability detection + state.
- Tests: `cargo test` covers the ffmpeg-binding seam (mock the process call via
  the existing test pattern in `extras/cli/src/footage/probe/`), the PATCH wire
  (mock via `wiremock`), and the cache LRU.

## Acceptance

- [ ] Importer extracts frames at adaptive interval per the count / step formula
      (clamp 10..120, ~1 per minute baseline).
- [ ] Each frame produces both a master (1280x720) and a thumb (320x180), each
      letterbox-padded to uniform 16:9.
- [ ] Filenames encode `<HH-MM-SS>.jpg` (zero-padded) and are sorted-
      discoverable on the filesystem.
- [ ] Files land at `<assets_root>/footages/<footage_id>/{m,t}/<HH-MM-SS>.jpg`.
- [ ] `_footage_pane.html.erb` renders the median thumb (frame at 50% duration)
      with `loading="lazy"` and explicit `width`/`height`.
- [ ] `GET /footages/:id` renders the DaVinci-style scrub layout: big preview
      area, center playhead glyph, scrolling strip.
- [ ] Hover on the big preview swaps the displayed master to the frame whose
      timestamp matches the cursor X ratio.
- [ ] Drag / scroll the strip moves cells under the fixed playhead and updates
      the big preview to the centered cell's frame.
- [ ] Strip scroll-snaps to nearest cell on release.
- [ ] `GET /footages/:id/frames.json` returns the manifest
      (`{duration, timestamps[]}`).
- [ ] `GET /footages/:id/frames/:tier/:timestamp.jpg` streams the requested
      frame; 404 when absent.
- [ ] `PATCH /api/footages/:id/frames.json` accepts a multipart bulk upload,
      validates each part as JPEG (mime + size), writes atomically. Per-file
      size <2MB; total payload <500MB.
- [ ] CLI `pito footage import` extracts the full frame set per file, derives
      thumbs (libvips if available, ffmpeg otherwise), and uploads them.
- [ ] CLI: ffmpeg-missing prints the install hint and skips frames; metadata
      import still succeeds.
- [ ] CLI: ffmpeg-fails-on-this-timestamp logs and skips that frame; others
      still upload.
- [ ] CLI footage detail screen renders the same scrub layout via
      `ratatui-image`, with capability detection (Kitty / Sixel / iTerm2 /
      Halfblocks).
- [ ] CLI fallback (Halfblocks) renders the layout shape with text-only cells
      when graphics protocol is unavailable.
- [ ] CLI mouse scrub interactions (move over big preview, drag / scroll the
      strip) update `active_timestamp` consistently with the web behavior.
- [ ] CLI keyboard scrub (`h`/`l`, `H`/`L`, `g`/`G`) works in all terminals.
- [ ] CLI image cache lives at `~/.cache/pito/thumbnails/` with LRU eviction.
- [ ] Storage at scale stays under ~10 GB for 1000 footages × ~60 frames each
      (verified by spot calculation in the manual recipe).
- [ ] No `target="_blank"` or destructive-action hard-rule violations
      introduced. No JS `alert` / `confirm` / `prompt`.
- [ ] `bundle exec rspec` and `cargo test` green.

## Manual test recipe

Prereq: spec 05 (`pito-assets` volume) shipped. For the CLI half, Track B (spec
02, CLI hygiene sweep) shipped.

1. `bin/setup`, then `bin/dev`. Confirm `pito-assets` is mounted in the Rails
   container.
2. Build a fresh `pito` CLI binary:
   `cargo build --release --manifest-path extras/cli/Cargo.toml`.
3. Pick a project. Run:
   ```
   pito footage import --project <id> --path /path/to/footage
   ```
   The TUI confirmation overlay shows N additions. Confirm with `y`. The
   importer logs ffmpeg invocations (one per timestamp per file) alongside the
   API POSTs.
4. From host:
   `docker exec <rails-container> ls -lah /var/lib/pito-assets/footages/<footage_id>/m/`.
   Confirm masters exist with `HH-MM-SS.jpg` filenames. Repeat for `t/`.
5. Visit `/projects/<id>` in the browser. The Footage pane renders. Each row has
   a thumbnail (the median frame).
6. Click into a footage row → `/footages/:id`. The scrub layout renders. The big
   preview shows a frame; the strip shows cells along the bottom; the `+`
   playhead is centered.
7. Hover the cursor across the big preview from left edge to right edge. The
   displayed frame walks through the timeline.
8. Drag the strip horizontally. Cells move under the playhead; the big preview
   updates. Release the drag — strip snaps to nearest cell.
9. Scroll-wheel over the strip — same scrub behavior.
10. Inspect the storage budget: pick a 60-min footage, count frames
    (`ls .../m/ | wc -l` should be ~60), measure size (`du -sh .../m/` ~6 MB,
    `.../t/` ~840 KB). Multiply by 1000 to project — should land under 10 GB.
11. Delete a footage's frame directory
    (`docker exec <c> rm -rf /var/lib/pito-assets/footages/<id>/`). Reload the
    project page — the placeholder SVG renders for that row's thumb. The footage
    detail page shows an empty manifest gracefully.
12. Re-run `pito footage import` for the same path. Frames return.
13. ffmpeg-missing simulation: rename `/usr/bin/ffmpeg` to `/usr/bin/ffmpeg.bak`
    on the user's host. Run `pito footage import`. The CLI prints the install
    hint and proceeds with metadata-only. Restore.
14. CLI scrub test: in the `pito` CLI, navigate to the footage detail screen for
    the imported footage. Confirm:
    - In Kitty / Ghostty / WezTerm: the big preview renders as a proper image;
      cells render as small images.
    - In Alacritty / plain xterm: halfblocks fallback renders the same layout
      with chunkier pixels.
    - In a TTY without color: text-only fallback shows timestamps instead of
      images, layout intact.
    - Mouse hover and drag work in all three.
    - Keyboard `h`/`l`/`H`/`L`/`g`/`G` scrub works in all three.
15. CLI cache: run the scrub UI for one footage, then check
    `~/.cache/pito/thumbnails/<footage_id>/`. Confirm files cached. Re-run;
    confirm no re-fetch (instrument with `RUST_LOG=debug` or similar).
16. `bundle exec rspec` green; `cargo test` green.

## Cross-stack scope

- Rails — **in scope.**
- `pito` CLI — **in scope** (after Track B lands).
- MCP — **out of scope** for this dispatch. A future `get_footage_thumbnail` /
  `get_footage_frame` tool could be added but is not in 7.5.
- Cloudflare Pages website — **out of scope.**

## Open questions

- **Tenant prefix on the assets path.** Spec 05's notes layout uses a tenant
  prefix; this spec's draft layout does not. Implementation agent: confirm with
  the spec-05 author whether `<tenant_id>/` should prepend the
  `footages/<id>/...` segment. If yes, use it consistently in routes, helpers,
  and uploads.
- **Bulk PATCH vs. per-frame PATCH.** Bulk is faster but multipart parsing of N
  file parts may be awkward. If bulk proves messy, fall back to per-frame PATCH.
- **CLI cache size cap.** A 500 MB default is suggested; the implementation
  agent picks the exact number based on observed per-footage cache footprint.
- **Halfblocks opt-out flag.** Should there be a config flag to force text-only
  mode even when halfblocks is available? Park unless the user requests it;
  default behavior is auto-detect with halfblocks fallback.

## Follow-ups created

- **User-pickable "pinned" thumbnail for the row preview.** Today the row uses
  the median frame; let the user override by clicking a frame in the scrub UI
  and pinning it. Park.
- **`get_footage_thumbnail` / `get_footage_frame` MCP tools.** If/when the MCP
  surface wants to expose frames to a non-browser consumer. Park.
- **Animated thumbnails / gif previews.** A short looping preview on hover,
  instead of a still. Park.
- **4K master tier.** The directory layout reserves a `4k/` peer; if a retina
  master tier becomes desirable, add the extraction pass and the route. Park.
- **Re-extraction without re-import.** A targeted "regenerate frames for footage
  X" path that doesn't require re-walking the source directory. Park.

## Decisions (locked)

- **JPEG, not PNG / WebP / AVIF.** JPEG is universal, compressed by default, and
  the per-frame budget (~14 KB thumb, ~110 KB master) is comfortable. WebP /
  AVIF saves a bit more but adds browser-compat surface; not worth in this
  iteration.
- **Multi-frame extraction at adaptive interval.** ~1 frame per minute, clamped
  to [10, 120]. Resolves Q8: not "one frame at 50%", not "three frames at
  25/50/75%", but a film strip's worth of frames scaled to clip length.
- **Two-tier output (master + thumb).** Resolves Q8 Option C. Master serves
  big-preview at full quality; thumb serves strip cells and the row preview.
  Storage budget acceptable at scale.
- **Letterbox-padded uniform 16:9.** Strip cells line up regardless of source
  orientation. Vertical / 4:3 / 16:9 sources all produce the same output
  dimensions.
- **Filename IS the timestamp** (`<HH-MM-SS>.jpg`). No frame metadata table, no
  sidecar JSON. Filesystem sort = timeline order.
- **Importer-side ffmpeg + libvips-or-ffmpeg thumb derivation.** Resolves Q9.
  Single ffmpeg seek+decode per timestamp produces the master; thumb derived via
  libvips if available, ffmpeg otherwise. ADR 0001 honored (Pito server never
  receives raw video bytes).
- **`ratatui-image` for CLI rendering.** Auto-detects Kitty / Sixel / iTerm2
  inline / halfblocks. Halfblocks is the universal fallback; text-only mode
  covers the no-color edge case.
- **Direct files on `pito-assets`, not Active Storage.** No variant generation,
  no polymorphic attachment. Single-purpose direct storage. If a future need
  arises, migrate then.
- **CLI half depends on Track B.** ratatui 0.30 + screen-layout parity must land
  before `footage_detail` builds on top.
