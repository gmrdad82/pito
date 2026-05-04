# ADR 0001 — No Server-Side Video Uploads

## Status

Accepted

## Context

Pito manages YouTube channels and videos. The most obvious naive design would
have the user upload a video file to the Rails app and have Pito forward it to
YouTube on the user's behalf. This naive design fails on several axes at once:

- **Bandwidth.** Video files are large. Routing them through the Rails app
  doubles the upload — user to Pito, then Pito to YouTube — and burns server
  bandwidth that produces no product value.
- **Storage.** Even transient storage of multi-gigabyte files on the Rails
  server forces a class of operations problems (disk pressure, cleanup jobs,
  partial-upload recovery) that we get to avoid entirely.
- **Auth model.** YouTube already authorizes the user's browser via OAuth. The
  browser can talk to YouTube directly with the same token; routing through Pito
  adds nothing to the trust chain.
- **Reliability.** The YouTube Data API client SDK already handles resumable
  uploads, chunking, and retry. Reimplementing this on the Rails side would be
  wasted engineering.

## Decision

Pito never receives video file bytes. Uploads happen entirely browser-side via
the YouTube Data API client SDK. The Rails app participates only by storing
metadata (title, description, tags, scheduling, custom thumbnails routed via
YouTube directly) and by recording that an upload happened.

The terminal app (`pito-sh`) and the MCP tool namespace do **not** expose upload
commands. There is no upload form factor outside the browser.

## Consequences

- **No multipart endpoints in the Rails app.** Controllers and routes never
  accept video file uploads. Forms that look like upload forms are actually
  browser-side YouTube SDK invocations with metadata mirrored to Pito after
  success.
- **`pito-sh` skips upload features.** Per the Lane 2 skip-list rule (see
  `orchestration/lanes.md` and ADR 0002), this skip is recorded as a one-line
  addendum on every spec that touches video creation.
- **MCP namespace omits upload tools.** No `upload_video` tool. Tools like
  `create_video` operate on metadata only, and the LLM caller has no way to push
  bytes through Pito.
- **Storage scope on the Rails server stays small.** The disk budget covers
  thumbnails (small), avatar images, and database storage only. No video files,
  ever.
- **Custom thumbnail flow is browser-mediated.** When the user wants a custom
  thumbnail, the browser pushes it directly to YouTube; Pito records the URL.

## Date

2026-04-29

## Related

- `orchestration/lanes.md` — three-lane model and skip-list rule
- `decisions/0002-app-first-then-terminal-mcp-parallel.md` — parent decision
  that defines the skip mechanism
- `docs/plans/beta/11-video-workflow-features/` — phase that consumes this
  decision

## Addendum (2026-05-04)

**Image assets excepted (2026-05-04).** Phase 4 — Project Workspace — introduces
server-side image uploads (Game cover art) via Active Storage with libvips
variant generation. The original prohibition stands for **video bytes**: video
files never touch the Pito server. ffprobe runs client-side via the
`pito footage` subcommand; only metadata travels over the wire. See
`docs/plans/beta/04-project-workspace/specs/project-workspace.md` §5 for the
Active Storage configuration and §7 for the ffprobe / metadata wire contract.
