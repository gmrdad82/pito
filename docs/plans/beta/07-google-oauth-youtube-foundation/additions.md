# Phase 7 — Google OAuth + YouTube API Foundation · Additions

> Items added to this phase's downstream scope by the 2026-05-09 realignment.
> See `docs/realignment-2026-05-09.md` for the top-level direction map.

## 2026-05-09 — Substantial Channel + Video schema expansion incoming

The Mobile notes session on 2026-05-09 commits to a **substantial expansion of
the `Channel` and `Video` schema** for owned content, reversing the Phase 7 Path
A2 retraction for OAuth-connected channels and videos. Phase 7 itself stays
as-is (the Google OAuth + `GoogleIdentity` + `Youtube::Client` +
`Youtube::PublicClient` + `youtube_api_calls` audit foundation is sound). The
expansion lives downstream of Phase 7 as standalone realignment work units.

### Channel data sync + edit surface (downstream)

Reversing Path A2 for owned `Channel`. Restored / new columns:

- `title`, `description`
- `subscriber_count`, `view_count`, `video_count`
- `thumbnail_url`, `banner_url`, `watermark_url`
- `country`
- `youtube_channel_id` (canonical, separate from `url`)
- `last_synced_at` (already exists)

Plus edit forms for the writable subset, plus a `[ sync ]` trigger that goes
through `Youtube::Client` (Phase 7's foundation), plus banner / avatar /
watermark preview rendering on the channel detail page.

The MCP `update_channel` tool's writable surface expands accordingly.

### Video schema expansion + edit surface + pre-publish checklist

(downstream)

Reversing Path A2 for owned `Video`. Per the Mobile note
`docs/notes/2026-05-09-17-56-06-video-model-youtube-api.md` the full field set:

- `youtube_video_id` (PK from YouTube's side)
- `title`, `description`, `tags[]` (jsonb), `category_id`
- `thumbnail_url` (`maxres` falling back to `high`)
- `privacy_status`, `publish_at` (nullable)
- `self_declared_made_for_kids`, `contains_synthetic_media`
- `made_for_kids_effective` (read-only mirror of `status.madeForKids`)
- `etag` (for conditional updates)
- `last_synced_at`

Plus the playlist join: `playlist_videos(video_id, playlist_id, position)`.

Plus edit forms for the writable subset, with read-modify-write semantics for
the destructive-PUT-per-part `videos.update` endpoint (per note 1's gotcha
section: sending `part=snippet` without `tags` wipes existing tags).

Plus the four-item pre-publish checklist modal (game / age / paid promotion /
end screen) gating publish-state transitions (`private` → `public` / `unlisted`,
or scheduling via `publishAt`). Studio deep-links per item:
`https://studio.youtube.com/video/{videoId}/edit`. Manual reminder, not
enforcement (the user ticks each; pito doesn't validate). Skipped on `public` →
`private`/`unlisted` transitions and on metadata edits to already-public videos.

The MCP `update_video` tool's writable surface expands accordingly.

### Analytics sync engine + tables + dashboard (downstream)

Per the Mobile note
`docs/notes/2026-05-09-18-19-27-analytics-model-youtube-api.md`. The full Phase
8 scope locks here: `channel_daily`, `video_daily`, `video_daily_by_<slice>` × 6
slice tables, `channel_window_summary`, `video_window_summary`,
`top_videos_window`, `video_retention`. C1-C5 + V1-V9 query implementations.
Daily nightly sync (refresh last 3 days for revision lag). Weekly retention
refresh. Active-video classification (uploaded in last 90 days OR > 100 views in
last 7 days). Cross-video locals computed locally. Monetization schema-ready /
sync-disabled. Dashboard renders Studio-faithful ratios from the
windowed-summary tables.

This was always-going-to-be-Phase-8 work; the Mobile note locks the specific
shape.

## What stays

Phase 7's foundation is unchanged:

- `GoogleIdentity` model + encrypted access / refresh token storage
- OAuth authorization code flow at `/auth/google/*`
- `Youtube::Client` + `Youtube::PublicClient`
- `youtube_api_calls` audit table
- `needs_reauth` flag + Settings UI banner
- Quota chokepoint via the client tier
- `[ disconnect ]` deletes the `GoogleIdentity` row

Only `tenant_id` columns drop from `google_identities` and `youtube_api_calls`
per ADR 0003. See `dropped.md` in this phase folder.

## Cross-references

- `docs/realignment-2026-05-09.md`
- Mobile notes (intact in `docs/notes/`):
  - `2026-05-09-17-56-06-video-model-youtube-api.md`
  - `2026-05-09-18-02-30-video-model-addendum-end-screen.md`
  - `2026-05-09-18-19-27-analytics-model-youtube-api.md`
