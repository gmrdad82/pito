# Video model: YouTube Data API v3 fields

Reference for modeling the `Video` in our app and wiring it to the YouTube Data API v3. Assumes OAuth as the channel owner with scope `https://www.googleapis.com/auth/youtube.force-ssl`.

Source: <https://developers.google.com/youtube/v3/docs/videos> (last updated by Google 2025-12-03) and <https://developers.google.com/youtube/v3/docs/videos/update>.

## Fields we model

These are the fields the app will read and (where possible) write:

| # | Field | API path | Read | Write | Endpoint | Notes |
|---|---|---|---|---|---|---|
| 1 | Title | `snippet.title` | ✅ | ✅ | `videos.update` (`part=snippet`) | Max 100 chars UTF-8, no `<` or `>`. **Required** when updating the `snippet` part. |
| 2 | Description | `snippet.description` | ✅ | ✅ | `videos.update` (`part=snippet`) | Max 5000 bytes UTF-8, no `<` or `>`. |
| 3 | Thumbnail | `snippet.thumbnails.{default,medium,high,standard,maxres}.{url,width,height}` | ✅ | ✅ | Read: `videos.list`. Write: `thumbnails.set` (separate endpoint, multipart upload). | JPEG/PNG, ≤ 2 MB. Channel must be verified to upload custom thumbnails. |
| 4 | Made for kids | `status.selfDeclaredMadeForKids` | ✅ | ✅ | `videos.update` (`part=status`) | Owner-only on read. The computed `status.madeForKids` is read-only and reflects the current effective state. |
| 7 | Altered/synthetic content disclosure | `status.containsSyntheticMedia` | ✅ | ✅ | `videos.update` (`part=status`) | Boolean. |
| 11 | Tags | `snippet.tags[]` | ✅ | ✅ | `videos.update` (`part=snippet`) | Total length ≤ 500 chars. Tags containing spaces are quoted internally and the quotes count toward the limit. |
| 15 | Category | `snippet.categoryId` | ✅ | ✅ | `videos.update` (`part=snippet`) | Numeric string. Valid IDs come from `videoCategories.list`. **Required** when updating the `snippet` part. |
| 19 | Visibility | `status.privacyStatus`, `status.publishAt` | ✅ | ✅ | `videos.update` (`part=status`) | `privacyStatus` ∈ `public` \| `private` \| `unlisted`. To schedule, set `publishAt` (ISO 8601) **and** keep `privacyStatus=private` in the same call. The video must never have been published before. A past `publishAt` publishes immediately. |
| 20 | Playlist membership | n/a — separate resource | ✅ | ✅ | `playlistItems.list` (read), `playlistItems.insert` / `playlistItems.delete` (write) | A video can sit in many playlists. Modeled as a join table on our side. |

## Critical gotcha for writes

`videos.update` is a **destructive PUT per part**. Sending `part=snippet` without `tags` wipes existing tags. Sending `part=status` without `embeddable` resets it to default. Always **read-modify-write the entire part** — never send a partial part body.

When updating the `snippet` part, both `title` and `categoryId` are required or the API returns 400.

## Fields we do NOT model (API does not expose them)

These are real Studio features but the Data API v3 has no read or write surface for them. Do not put them in the model; surface them via a Studio deep link instead.

| Field | Status | What to do |
|---|---|---|
| Game (when category = Gaming) | Not in API | Studio link |
| Age restriction (18+) | `contentDetails.contentRating.ytRating` is read-only; cannot be set | Studio link |
| Paid promotion check | `paidProductPlacementDetails.hasPaidProductPlacement` is read-only; cannot be set | Studio link |

**Studio deep link pattern:** `https://studio.youtube.com/video/{videoId}/edit`

The UI should show these three fields with a "Check in Studio" link rather than an editable control, so the user knows the values exist somewhere but aren't ours to manage.

## Publish flow: extra confirmation step

Before flipping `status.privacyStatus` from `private` → `public` (or before scheduling via `publishAt`), the UI must show a confirmation step listing each of the three Studio-only fields and asking the user to tick them off:

- [ ] Game set correctly (if category = Gaming)
- [ ] Age restriction (18+) reviewed
- [ ] Paid promotion declared if applicable

Each item in the checklist deep-links to the Studio edit page for that video. The "Publish" / "Schedule" button stays disabled until all three are ticked. The reasoning: we cannot read or set those fields, so the human has to confirm them out-of-band before we make the video public.

This check applies to:
- Direct publish (`privacyStatus` → `public` or `unlisted`)
- Scheduled publish (setting `publishAt` while `privacyStatus=private`)

It does not apply to going from `public` → `private`/`unlisted` (taking down) or to metadata edits on an already-public video.

## OAuth scopes

| Scope | When |
|---|---|
| `https://www.googleapis.com/auth/youtube.readonly` | Read-only flows. |
| `https://www.googleapis.com/auth/youtube.force-ssl` | Anything that writes, plus `thumbnails.set` and `captions.*`. Use this as the default. |

## Quota costs to budget

- `videos.list` = 1 unit
- `videos.update` = 50 units
- `thumbnails.set` ≈ 50 units
- `playlistItems.insert` / `delete` = 50 units each
- Default daily quota: 10,000 units

A read-modify-write save = 1 + 50 = 51 units. A publish that also re-uploads a thumbnail and adds the video to a playlist = 1 + 50 + 50 + 50 = 151 units. Budget for the worst case.

## Suggested `Video` model shape

Minimum fields to mirror locally so we never depend on the API for a render:

- `youtube_video_id` (PK from YouTube's side)
- `title`, `description`, `tags` (array), `category_id`
- `thumbnail_url` (pick one tier — usually `maxres` falling back to `high`)
- `privacy_status`, `publish_at` (nullable)
- `self_declared_made_for_kids` (bool)
- `contains_synthetic_media` (bool)
- `made_for_kids_effective` (bool, read-only mirror of `status.madeForKids`)
- `etag` (for conditional updates)
- `last_synced_at`

Playlist membership is a separate join: `(video_id, playlist_id, position)`.

Studio-only fields (game, age restriction, paid promotion) are **not** stored locally. Read them on demand only if needed; otherwise skip and rely on the publish-time checklist.
