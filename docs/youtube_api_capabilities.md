# YouTube API Capabilities

Reference for what Pito's `Youtube::Client` and `Youtube::PublicClient` can and
cannot do against the YouTube Data API v3 and the YouTube Analytics API v2. This
doc seeds Phase 8 (sync) and the Channel/Video schema design.

> **Source caveat — this doc was written without live access to YouTube's
> developer documentation.** WebFetch was denied during the research session.
> Every factual claim below is from training-data recall and should be
> re-verified against the official documentation before being relied on for
> production decisions. URLs cited at the bottom of each section point at
> _where_ to verify, not at fetched citations. Claims that the author is
> uncertain about are marked **[VERIFY]**. Treat the matrix as a starting point,
> not a contract.

Sibling docs:

- `docs/youtube_quota.md` — quota budget, fail-fast posture, sample math.
- `docs/architecture.md` → "Google OAuth + YouTube API foundation (Phase 7)" —
  client tier, audit table, identity model.
- `docs/plans/beta/07-google-oauth-youtube-foundation/specs/7b-youtube-client-and-audit.md`
  — locked decisions on storage shape, retry policy, cost map.

---

## Top-level summary

The YouTube Data API v3 is a **read-mostly** surface. Almost every public
metadata field on a channel or video is _readable_ for anyone with an API key or
OAuth token; a much smaller subset is _writable_, and writes are gated on the
user owning the resource. The Analytics API v2 is **owner-only** and exposes a
dimension/metric query language that is strictly richer than the Data API's
`statistics` part — demographics, traffic sources, geography, device, watch
time, real-time, time-series.

The two operationally important rules of thumb: (1) `search.list` costs 100
units and is functionally banned in normal Pito flows; (2) channel _avatar_
(profile picture) appears to have **no public write API** **[VERIFY]**, while
banner image, watermark, video thumbnail, video metadata, captions, and
playlists all do have write endpoints. The 14-day cooldown most builders
remember sits on the channel **handle** (and historically on `customUrl`); the
title field is updateable more freely **[VERIFY]**.

---

## Channel level capability matrix

| Capability                                                                                                 | Read?                                               | Write?                                                    | Owner-only?   | Quota cost (read)      | Quota cost (write)                                                         | Notes / policies                                                                                                                                                                                                                                   |
| ---------------------------------------------------------------------------------------------------------- | --------------------------------------------------- | --------------------------------------------------------- | ------------- | ---------------------- | -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Title (`brandingSettings.channel.title`)                                                                   | yes (snippet)                                       | yes (channels.update)                                     | yes           | 1 unit (channels.list) | 50 units **[VERIFY]**                                                      | Title length cap ~100 chars **[VERIFY]**. Possibly subject to a soft rate limit for very frequent changes **[VERIFY]**.                                                                                                                            |
| Handle (`snippet.customUrl`)                                                                               | yes (snippet)                                       | **no via API**                                            | n/a           | 1 unit                 | n/a                                                                        | Handle changes are UI-only at YouTube Studio. **14-day cooldown** between handle changes **[VERIFY]** — this is the famous "14-day rule".                                                                                                          |
| Description (`brandingSettings.channel.description`)                                                       | yes (snippet, brandingSettings)                     | yes (channels.update)                                     | yes           | 1 unit                 | 50 units **[VERIFY]**                                                      | ~1000 char limit **[VERIFY]**.                                                                                                                                                                                                                     |
| Avatar / profile image (`snippet.thumbnails.{default,medium,high}.url`)                                    | yes (snippet)                                       | **no public write API** **[VERIFY]**                      | n/a           | 1 unit                 | n/a                                                                        | `thumbnails.set` is for VIDEOS, not channel avatars. Avatar updates appear to require YouTube Studio UI. Confirm before relying on this.                                                                                                           |
| Banner image (`brandingSettings.image.bannerExternalUrl`)                                                  | yes (brandingSettings)                              | yes (two-step)                                            | yes           | 1 unit                 | 50 units (channelBanners.insert) + 50 units (channels.update) **[VERIFY]** | Two-step flow: `channelBanners.insert` uploads the image and returns a URL; that URL is then assigned via `channels.update` brandingSettings.image.bannerExternalUrl. Min 2048x1152 **[VERIFY]**, ~6MB max **[VERIFY]**.                           |
| Watermark (overlay on player)                                                                              | partial via brandingSettings.watermark **[VERIFY]** | yes (watermarks.set / watermarks.unset)                   | yes           | 1 unit                 | 50 units each **[VERIFY]**                                                 | Position: enumerated cornerPosition (likely `topLeft`, `topRight`, `bottomLeft`, `bottomRight`) **[VERIFY]**. Timing: type `offsetFromStart` / `offsetFromEnd` with `offsetMs` and `durationMs`, OR type `entireVideo` for always-on **[VERIFY]**. |
| Country (`snippet.country` / `brandingSettings.channel.country`)                                           | yes                                                 | yes                                                       | yes           | 1 unit                 | 50 units **[VERIFY]**                                                      | ISO 3166-1 alpha-2 code.                                                                                                                                                                                                                           |
| Default language (`snippet.defaultLanguage` / `brandingSettings.channel.defaultLanguage`)                  | yes                                                 | yes                                                       | yes           | 1 unit                 | 50 units **[VERIFY]**                                                      | BCP-47 code.                                                                                                                                                                                                                                       |
| Keywords (`brandingSettings.channel.keywords`)                                                             | yes (brandingSettings)                              | yes                                                       | yes           | 1 unit                 | 50 units **[VERIFY]**                                                      | Space-separated string; quote multi-word keywords. ~500 char limit **[VERIFY]**.                                                                                                                                                                   |
| Featured trailer (`brandingSettings.channel.unsubscribedTrailer`)                                          | yes                                                 | yes                                                       | yes           | 1 unit                 | 50 units **[VERIFY]**                                                      | Video ID shown to non-subscribers. Distinct from "for returning subscribers" video which is **UI-only** **[VERIFY]**.                                                                                                                              |
| Featured channels                                                                                          | **deprecated**                                      | **deprecated**                                            | n/a           | n/a                    | n/a                                                                        | YouTube removed the Featured Channels section in 2019. The `brandingSettings.channel.featuredChannelsUrls` field is no longer functional **[VERIFY]**.                                                                                             |
| Channel sections                                                                                           | **deprecated as of ~2023** **[VERIFY]**             | **deprecated**                                            | n/a           | n/a                    | n/a                                                                        | The `channelSections` resource exists in the API but YouTube replaced channel sections in the UI; API behavior is largely no-op **[VERIFY]**.                                                                                                      |
| Localizations (`localizations.<lang>.title/description`)                                                   | yes (localizations part)                            | yes                                                       | yes           | 1 unit                 | 50 units **[VERIFY]**                                                      | Per-language title/description overrides. Locale viewer's language picks the right one.                                                                                                                                                            |
| Statistics (`statistics.subscriberCount, viewCount, videoCount`)                                           | yes                                                 | **no — read-only**                                        | n/a           | 1 unit                 | n/a                                                                        | `subscriberCount` is rounded (3-significant-digit truncation) for channels above 1000 subs **[VERIFY]**. `hiddenSubscriberCount` flag also present.                                                                                                |
| Topic categories (`topicDetails.topicCategories`)                                                          | yes                                                 | **no — read-only**                                        | n/a           | 1 unit                 | n/a                                                                        | Array of Wikipedia URLs. `topicIds` is also returned but largely deprecated **[VERIFY]**.                                                                                                                                                          |
| Upload playlist ID (`contentDetails.relatedPlaylists.uploads`)                                             | yes                                                 | **no — read-only**                                        | n/a           | 1 unit                 | n/a                                                                        | THE most useful read field for sync — feed this id into `playlistItems.list` to walk every public upload by the channel. Free of `search.list` cost.                                                                                               |
| Audit details (`auditDetails`)                                                                             | yes (owner only, special scope)                     | n/a                                                       | yes           | 4 units **[VERIFY]**   | n/a                                                                        | Used by MCN partners during audit; requires `youtubepartner-channel-audit` scope. Almost certainly out of scope for Pito.                                                                                                                          |
| Status (`status.isLinked`, `longUploadsStatus`, `madeForKids`, `selfDeclaredMadeForKids`, `privacyStatus`) | yes                                                 | partial — `selfDeclaredMadeForKids` writable **[VERIFY]** | yes for write | 1 unit                 | 50 units **[VERIFY]**                                                      | `madeForKids` is computed; `selfDeclaredMadeForKids` is the user-set field.                                                                                                                                                                        |
| Content owner details (`contentOwnerDetails`)                                                              | yes (CMS-linked only)                               | n/a                                                       | yes           | 1 unit                 | n/a                                                                        | YouTube CMS / partner-only; not relevant to Pito.                                                                                                                                                                                                  |

Verify against:

- https://developers.google.com/youtube/v3/docs/channels
- https://developers.google.com/youtube/v3/docs/channels/list
- https://developers.google.com/youtube/v3/docs/channels/update
- https://developers.google.com/youtube/v3/docs/channelBanners/insert
- https://developers.google.com/youtube/v3/docs/watermarks/set
- https://developers.google.com/youtube/v3/docs/watermarks/unset

### Special attention items the user asked about

**Avatar (profile picture).** Author belief: there is **no public Data API v3
endpoint for setting a channel's avatar / profile thumbnail.** `thumbnails.set`
in the API explicitly takes a `videoId`, not a channel id. Channel avatars
appear to be Studio-only. **[VERIFY]** — re-check `channels` write fields and
search the API reference for "avatar", "profile", "channel thumbnail".

**Title vs Handle 14-day rule.** Author belief: the 14-day cooldown is a
**handle** rule (the `@username` part of the channel URL) and historically also
applied to the legacy `customUrl`. Title changes via
`brandingSettings.channel.title` are not under that 14-day cooldown
**[VERIFY]**. However, YouTube also enforces a separate "channel name" cooldown
of **3 changes per 14 days** for the YouTube Studio UI **[VERIFY]** — this might
also apply to the API.

**Watermark position values.** Author best guess: the API field is
`position.cornerPosition` with enum values `topLeft`, `topRight`, `bottomLeft`,
`bottomRight` — four corners only, not three horizontal anchors **[VERIFY]**.

**Watermark timing values.** Author best guess: `timing.type` enum with
`offsetFromStart`, `offsetFromEnd` (use `offsetMs` and `durationMs` for both),
or omit timing entirely for "always on" / "entireVideo" mode **[VERIFY]**. The
"last 15 seconds" / "5s after start" presets in the YouTube Studio UI are
shorthands for specific offset combinations; the API takes the raw ms values.

---

## Video level capability matrix

| Capability                                                                  | Read?                                           | Write?                                           | Owner-only? | Quota (read)                 | Quota (write)                                                                                    | Notes                                                                                                                                                                                             |
| --------------------------------------------------------------------------- | ----------------------------------------------- | ------------------------------------------------ | ----------- | ---------------------------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Title (`snippet.title`)                                                     | yes                                             | yes (videos.update)                              | yes         | 1 unit                       | 50 units **[VERIFY]**                                                                            | Required at insert. ~100 char limit.                                                                                                                                                              |
| Description (`snippet.description`)                                         | yes                                             | yes                                              | yes         | 1 unit                       | 50 units **[VERIFY]**                                                                            | ~5000 char limit.                                                                                                                                                                                 |
| Tags (`snippet.tags`)                                                       | yes                                             | yes                                              | yes         | 1 unit                       | 50 units **[VERIFY]**                                                                            | Array of strings. ~500 char total budget across all tags **[VERIFY]**.                                                                                                                            |
| Category (`snippet.categoryId`)                                             | yes                                             | yes                                              | yes         | 1 unit                       | 50 units **[VERIFY]**                                                                            | Numeric id; list via `videoCategories.list` (region-dependent).                                                                                                                                   |
| Default language (`snippet.defaultLanguage`)                                | yes                                             | yes                                              | yes         | 1 unit                       | 50 units **[VERIFY]**                                                                            | BCP-47.                                                                                                                                                                                           |
| Default audio language (`snippet.defaultAudioLanguage`)                     | yes                                             | yes                                              | yes         | 1 unit                       | 50 units **[VERIFY]**                                                                            | BCP-47. Distinct from defaultLanguage (which is the metadata language).                                                                                                                           |
| Privacy status (`status.privacyStatus`)                                     | yes                                             | yes                                              | yes         | 1 unit                       | 50 units **[VERIFY]**                                                                            | `public` / `unlisted` / `private`.                                                                                                                                                                |
| Made For Kids (`status.selfDeclaredMadeForKids`)                            | yes                                             | yes                                              | yes         | 1 unit                       | 50 units **[VERIFY]**                                                                            | `madeForKids` is computed (read-only); `selfDeclaredMadeForKids` is the user-settable boolean.                                                                                                    |
| Embeddable (`status.embeddable`)                                            | yes                                             | yes                                              | yes         | 1 unit                       | 50 units **[VERIFY]**                                                                            | Boolean.                                                                                                                                                                                          |
| License (`status.license`)                                                  | yes                                             | yes                                              | yes         | 1 unit                       | 50 units **[VERIFY]**                                                                            | `youtube` (Standard) or `creativeCommon`.                                                                                                                                                         |
| Public stats viewable (`status.publicStatsViewable`)                        | yes                                             | yes                                              | yes         | 1 unit                       | 50 units **[VERIFY]**                                                                            | Whether view counts/likes are visible on the watch page.                                                                                                                                          |
| Schedule publication (`status.publishAt`)                                   | n/a (private until published)                   | yes                                              | yes         | n/a                          | 50 units **[VERIFY]**                                                                            | Only valid when `privacyStatus = private`. Setting `publishAt` flips to public at the timestamp.                                                                                                  |
| Localizations (`localizations.<lang>.title/description`)                    | yes                                             | yes                                              | yes         | 1 unit                       | 50 units **[VERIFY]**                                                                            | Per-language overrides.                                                                                                                                                                           |
| Thumbnail (custom)                                                          | yes (snippet.thumbnails)                        | yes (`thumbnails.set`)                           | yes         | 1 unit                       | **50 units** **[VERIFY]**                                                                        | Account must be verified to set custom thumbnails. JPG/PNG, <2MB, ~1280x720 **[VERIFY]**.                                                                                                         |
| Recording details (`recordingDetails.recordingDate`, `.location`)           | yes                                             | yes                                              | yes         | 1 unit                       | 50 units **[VERIFY]**                                                                            | Geo-tagging.                                                                                                                                                                                      |
| Captions                                                                    | yes (`captions.list`)                           | yes (`captions.insert/update/delete`)            | yes         | **50 units** (captions.list) | 400 units (insert) **[VERIFY]**, 450 units (update) **[VERIFY]**, 50 units (delete) **[VERIFY]** | Caption operations are EXPENSIVE. `captions.list` alone costs 50 units.                                                                                                                           |
| Comments enable/disable                                                     | partial via `status.commentStatus` **[VERIFY]** | **API limitation** **[VERIFY]**                  | yes         | 1 unit                       | n/a                                                                                              | Author belief: there is **no direct toggle** for comment-disabled in `videos.update`. Disabling comments may be UI-only or done via `commentThreads`/`comments` moderation. **VERIFY** carefully. |
| Statistics (`statistics.viewCount, likeCount, commentCount, favoriteCount`) | yes                                             | **no — read-only**                               | n/a         | 1 unit                       | n/a                                                                                              | `dislikeCount` is **no longer returned** publicly (December 2021 deprecation). Owners can still see it via Analytics. `favoriteCount` is always 0 (legacy).                                       |
| Content rating (`contentDetails.contentRating`)                             | yes                                             | partial (some rating systems writable on insert) | yes         | 1 unit                       | 50 units **[VERIFY]**                                                                            | E.g., `mpaaRating`, `tvpgRating`. Most are read-only and assigned by YouTube/regulators.                                                                                                          |
| Content details — duration (`contentDetails.duration`)                      | yes                                             | **no — read-only**                               | n/a         | 1 unit                       | n/a                                                                                              | ISO 8601 duration string (e.g. `PT4M13S`). Computed at upload.                                                                                                                                    |
| Content details — definition, dimension, caption flag                       | yes                                             | **no — read-only**                               | n/a         | 1 unit                       | n/a                                                                                              | `definition` (`hd`/`sd`), `dimension` (`2d`/`3d`), `caption` (`true`/`false` whether captions exist).                                                                                             |
| Content details — region restriction                                        | yes                                             | yes                                              | yes         | 1 unit                       | 50 units **[VERIFY]**                                                                            | `regionRestriction.allowed` / `.blocked`. ISO country codes.                                                                                                                                      |
| Live broadcast (`liveStreamingDetails`)                                     | yes                                             | indirectly via `liveBroadcasts` API              | yes         | 1 unit                       | varies                                                                                           | Live API is its own surface (`liveBroadcasts.*`, `liveStreams.*`); not in scope for Pito Phase 8.                                                                                                 |
| End screens                                                                 | **no API** **[VERIFY]**                         | **no API** **[VERIFY]**                          | n/a         | n/a                          | n/a                                                                                              | YouTube Studio only. No public Data API v3 endpoint.                                                                                                                                              |
| Cards                                                                       | **no API** **[VERIFY]**                         | **no API** **[VERIFY]**                          | n/a         | n/a                          | n/a                                                                                              | YouTube Studio only.                                                                                                                                                                              |
| Insert (upload) — `videos.insert`                                           | n/a                                             | yes                                              | yes         | n/a                          | **1600 units**                                                                                   | Upload is _expensive_. Resumable upload protocol. ~256GB / 12hr limit.                                                                                                                            |
| Delete — `videos.delete`                                                    | n/a                                             | yes                                              | yes         | n/a                          | **50 units**                                                                                     | Hard delete; not recoverable.                                                                                                                                                                     |
| File details (`fileDetails`) / processing (`processingDetails`)             | yes (owner-only)                                | n/a                                              | yes         | 1 unit                       | n/a                                                                                              | Source file metadata (codec, container) and processing progress. Owner-only `part`.                                                                                                               |
| Player (`player.embedHtml`)                                                 | yes                                             | n/a                                              | no          | 1 unit                       | n/a                                                                                              | iframe embed HTML.                                                                                                                                                                                |
| Suggestions (`suggestions`)                                                 | yes (owner)                                     | n/a                                              | yes         | 1 unit                       | n/a                                                                                              | Quality-improvement hints from YouTube.                                                                                                                                                           |
| Topic details (`topicDetails`)                                              | yes                                             | n/a                                              | no          | 1 unit                       | n/a                                                                                              | Same as channel.                                                                                                                                                                                  |

Verify against:

- https://developers.google.com/youtube/v3/docs/videos
- https://developers.google.com/youtube/v3/docs/videos/list
- https://developers.google.com/youtube/v3/docs/videos/update
- https://developers.google.com/youtube/v3/docs/videos/insert
- https://developers.google.com/youtube/v3/docs/videos/delete
- https://developers.google.com/youtube/v3/docs/thumbnails/set
- https://developers.google.com/youtube/v3/docs/captions

---

## Analytics API delta — what Data API does NOT give you

The YouTube Analytics API v2 is **OAuth-only, owner-only**. It exposes a single
`reports.query` endpoint with a dimension/metric grammar. Everything below is
unavailable through the Data API at all (or is much coarser).

| Capability                                | Owner-only? | Granularity                          | Quota cost | Notes                                                                                                              |
| ----------------------------------------- | ----------- | ------------------------------------ | ---------- | ------------------------------------------------------------------------------------------------------------------ |
| Demographics (age, gender)                | yes         | channel or video                     | 1 unit     | Aggregated buckets; YouTube hides them when the audience is too small.                                             |
| Traffic sources (where viewers came from) | yes         | channel or video                     | 1 unit     | Dimension `insightTrafficSourceType` (e.g. `YT_SEARCH`, `EXTERNAL`, `RELATED_VIDEO`, `BROWSE`).                    |
| Geography (country, province)             | yes         | channel or video                     | 1 unit     | Dimensions `country`, `province`. ISO codes.                                                                       |
| Device types                              | yes         | channel or video                     | 1 unit     | Dimension `deviceType` (`MOBILE`, `DESKTOP`, `TABLET`, `TV`, `GAME_CONSOLE`).                                      |
| Operating system                          | yes         | channel or video                     | 1 unit     | Dimension `operatingSystem`.                                                                                       |
| Playback locations                        | yes         | channel or video                     | 1 unit     | Dimension `insightPlaybackLocationType` (`WATCH`, `EMBEDDED`, `MOBILE`, etc.).                                     |
| Subscriber gains/losses                   | yes         | channel (per-video subs gained also) | 1 unit     | Metrics `subscribersGained`, `subscribersLost`.                                                                    |
| Watch time / average view duration        | yes         | channel, video, playlist             | 1 unit     | Metrics `estimatedMinutesWatched`, `averageViewDuration`, `averageViewPercentage`.                                 |
| Real-time stats (last 48 hours)           | yes         | channel, video                       | 1 unit     | Specific report set; lower latency than the standard reports.                                                      |
| Time-series data                          | yes         | day/week/month per metric            | 1 unit     | Dimension `day`, `month`. The Data API's `statistics` only gives you a current snapshot — Analytics gives history. |
| Earnings (partner only)                   | yes         | channel, video                       | 1 unit     | Metrics `estimatedRevenue`, `estimatedAdRevenue`, `cpm`, etc. Requires monetization-enabled account.               |
| Cards / End screens engagement            | yes         | video                                | 1 unit     | `cardClicks`, `cardImpressions`, `endScreenClicks`, `endScreenImpressions`.                                        |
| Audience retention (relative)             | yes         | video                                | 1 unit     | Per-video retention curves. Dimension `elapsedVideoTimeRatio`.                                                     |
| Sharing service breakdown                 | yes         | video, channel                       | 1 unit     | Dimension `sharingService`.                                                                                        |
| Subscribed status segmentation            | yes         | most reports                         | 1 unit     | Dimension `subscribedStatus` (`SUBSCRIBED` vs `UNSUBSCRIBED`).                                                     |

Most Analytics queries cost **1 unit** per `reports.query` call **[VERIFY]** —
this is what Pito's quota cost map already encodes. Some "advanced" reports
historically cost more **[VERIFY]**; the per-call cost should always be checked
against the Analytics quota docs at implementation time.

Verify against:

- https://developers.google.com/youtube/analytics
- https://developers.google.com/youtube/analytics/dimsmets/dims
- https://developers.google.com/youtube/analytics/dimsmets/metrics
- https://developers.google.com/youtube/analytics/quotas

---

## Public vs Owned access matrix

A side-by-side comparison of what each Pito client tier can access.

| Surface                                                          | `Youtube::PublicClient` (API key)            | `Youtube::Client` (OAuth, identity owns the resource) |
| ---------------------------------------------------------------- | -------------------------------------------- | ----------------------------------------------------- |
| Channel snippet (title, description, custom URL, thumbnails)     | yes                                          | yes                                                   |
| Channel statistics (subs, views, video count) — public-rounded   | yes                                          | yes (and **exact** subscriber count in Analytics)     |
| Channel `brandingSettings`                                       | partial — public surface only **[VERIFY]**   | yes (full)                                            |
| Channel `auditDetails`                                           | no                                           | yes (special scope only)                              |
| Channel writes (title, description, banner, watermark, keywords) | no                                           | yes                                                   |
| Channel uploads playlist id                                      | yes (via `contentDetails`)                   | yes                                                   |
| Video snippet / contentDetails / status (public-visible parts)   | yes                                          | yes                                                   |
| Video statistics (`viewCount`, `likeCount`, `commentCount`)      | yes                                          | yes                                                   |
| Video `fileDetails` / `processingDetails` / `suggestions`        | no                                           | yes (owner-only parts)                                |
| Video writes (title, description, privacy, thumbnail, tags)      | no                                           | yes                                                   |
| Video upload (`videos.insert`)                                   | no                                           | yes                                                   |
| Video delete (`videos.delete`)                                   | no                                           | yes                                                   |
| Captions (read list / read body / write)                         | partial (read public list only) **[VERIFY]** | yes                                                   |
| Playlists (`playlists.list`)                                     | yes (public + unlisted **[VERIFY]**)         | yes (incl. private)                                   |
| Subscriptions (`subscriptions.list`)                             | yes (when public) **[VERIFY]**               | yes (incl. own private subs)                          |
| Comments / commentThreads (read)                                 | yes                                          | yes                                                   |
| Comment moderation (delete, mark as spam, set status)            | no                                           | yes                                                   |
| Analytics API v2 (any report)                                    | **no — entire API requires OAuth**           | yes                                                   |
| PubSubHubbub subscription                                        | yes (no auth required for the hub itself)    | yes                                                   |
| `search.list`                                                    | yes (100 units)                              | yes (100 units)                                       |

OAuth scopes Pito would touch (matching `docs/architecture.md` §"GoogleIdentity
model"):

- `https://www.googleapis.com/auth/youtube.readonly` — read access to owned
  channel data.
- `https://www.googleapis.com/auth/youtube` — read + write to owned channel
  resources (videos, playlists, etc.).
- `https://www.googleapis.com/auth/youtube.force-ssl` — required for some write
  endpoints (captions, comments) **[VERIFY]**.
- `https://www.googleapis.com/auth/youtubepartner` — content ID / partner
  features (CMS). Out of scope for Pito.
- `https://www.googleapis.com/auth/yt-analytics.readonly` — Analytics reports.
- `https://www.googleapis.com/auth/yt-analytics-monetary.readonly` —
  monetization reports.

---

## Aggregation possibilities

What Pito **can** derive from per-video data without an extra API call:

- **Total video count** — already in `channels.statistics.videoCount`, but also
  derivable by counting `playlistItems` of the uploads playlist. The two may
  disagree slightly because the uploads playlist excludes private/deleted
  uploads while `videoCount` historically includes some of them **[VERIFY]**.
- **Sum of view counts across the catalog** — sum of
  `videos.statistics.viewCount` across all videos. NOT the same as
  `channels.statistics.viewCount`, which also includes views on deleted videos
  **[VERIFY]**.
- **Sum of like counts**, sum of comment counts, average duration, etc. — all
  derivable.
- **Per-video published-at timeline** — straight from `snippet.publishedAt`.
- **Most-viewed / most-liked / most-commented video** — sort the local cache by
  the relevant statistic. No API support for "give me my top 10" ranking outside
  the Analytics API.
- **Engagement rate** — `(likes + comments) / views` per video; aggregate up.
  Pito-owned metric, not a YouTube field.

What Pito **cannot** derive from per-video data — must come from Analytics or
channel-level reads:

- **Subscriber count history** — `channels.statistics.subscriberCount` is a
  rounded snapshot. Per-video Analytics reports give `subscribersGained`/`Lost`
  per video, but to reconstruct the channel's subscriber timeline you need the
  channel-level Analytics report.
- **Watch time** — only available via Analytics. The Data API does not expose
  watch time on either the channel or video resource.
- **Demographics, geography, traffic sources, devices** — Analytics-only. No way
  to derive these from public per-video data.
- **Click-through rate on impressions** — Analytics-only.
- **Real-time recent views** — Analytics-only (the 48-hour real-time report).
- **Earnings** — Analytics-only (with monetary scope).

---

## PubSubHubbub (push notifications for new uploads)

YouTube provides a PubSubHubbub (now WebSub) hub for new-video notifications.
This is **separate from the Data API quota** and **does not require OAuth or an
API key for the subscription itself** **[VERIFY]**.

- **Hub URL**: `https://pubsubhubbub.appspot.com/subscribe` **[VERIFY]**.
- **Topic URL pattern**:
  `https://www.youtube.com/xml/feeds/videos.xml?channel_id=UC...` **[VERIFY]**.
- **Subscription method**: HTTP POST to the hub with `hub.callback`,
  `hub.topic`, `hub.verify`, `hub.mode=subscribe`, `hub.lease_seconds`, and
  optionally `hub.secret` for HMAC validation of incoming pings.
- **Verification**: hub sends a GET to your callback with `hub.challenge` — echo
  it back to confirm.
- **Lease**: subscriptions expire (typically ~5 days, max 10 days **[VERIFY]**).
  Resubscribe before expiration.
- **Auth**: none on the topic side — the hub trusts whoever proves callback
  ownership via the verification challenge. Use `hub.secret` to HMAC-sign pings
  so your callback can verify they actually came from YouTube.
- **What you receive**: an Atom XML push with the new video's ID, title,
  channel, publish timestamp, and a few other snippet-equivalent fields — but
  **not** the full `videos.list` payload. After receiving a push, Pito would
  still call `videos.list?id=...` (1 unit) to hydrate.
- **Reliability**: the hub retries on callback failure but is not infinitely
  durable — sustained outages mean missed pushes. Treat PubSubHubbub as a
  _latency optimization_ over polling, not a replacement.
- **Quota cost**: zero for the subscription/notification path itself. The
  per-event `videos.list` hydration is 1 unit.
- **Events surfaced**: new public uploads. **[VERIFY]** — privacy changes,
  deletions, and metadata edits do NOT trigger pings (only fresh uploads). Going
  from private to public on a scheduled video may or may not trigger; this is
  the canonical "verify in production" question.

Verify against:

- https://developers.google.com/youtube/v3/guides/push_notifications

---

## Quota cost reference

Reproduced from training-data recall — **VERIFY against the live quota cost page
before relying on any single number**. Pito's frozen `Youtube::Quota::COSTS`
hash already encodes the subset Pito actually calls.

### YouTube Data API v3

| Method                                    | Cost (units)         | Notes                                                                                                  |
| ----------------------------------------- | -------------------- | ------------------------------------------------------------------------------------------------------ |
| `channels.list`                           | 1                    | Per call. Up to 50 ids per call. Cost is independent of `part` count for reads **[VERIFY]**.           |
| `channels.update`                         | 50                   | **[VERIFY]**                                                                                           |
| `channelBanners.insert`                   | 50                   | **[VERIFY]** Plus the `channels.update` to actually attach the banner URL = 100 total to set a banner. |
| `videos.list`                             | 1                    | Up to 50 ids per call.                                                                                 |
| `videos.insert`                           | 1600                 | Expensive. Resumable upload.                                                                           |
| `videos.update`                           | 50                   | **[VERIFY]**                                                                                           |
| `videos.delete`                           | 50                   | **[VERIFY]**                                                                                           |
| `videos.rate`                             | 50                   | Like/dislike on behalf of the user.                                                                    |
| `videos.getRating`                        | 1                    | **[VERIFY]**                                                                                           |
| `videos.reportAbuse`                      | 50                   | **[VERIFY]**                                                                                           |
| `thumbnails.set`                          | 50                   | **[VERIFY]**                                                                                           |
| `watermarks.set`                          | 50                   | **[VERIFY]**                                                                                           |
| `watermarks.unset`                        | 50                   | **[VERIFY]**                                                                                           |
| `playlists.list`                          | 1                    |                                                                                                        |
| `playlists.insert`                        | 50                   |                                                                                                        |
| `playlists.update`                        | 50                   |                                                                                                        |
| `playlists.delete`                        | 50                   |                                                                                                        |
| `playlistItems.list`                      | 1                    | Up to 50 per page. Pages walk; sum quota across pages.                                                 |
| `playlistItems.insert`                    | 50                   |                                                                                                        |
| `playlistItems.update`                    | 50                   |                                                                                                        |
| `playlistItems.delete`                    | 50                   |                                                                                                        |
| `search.list`                             | **100**              | Forbidden in normal Pito flows (`docs/youtube_quota.md`).                                              |
| `subscriptions.list`                      | 1                    |                                                                                                        |
| `subscriptions.insert`                    | 50                   |                                                                                                        |
| `subscriptions.delete`                    | 50                   |                                                                                                        |
| `captions.list`                           | **50**               | Listing captions is expensive (likely because metadata-rich).                                          |
| `captions.insert`                         | 400                  | **[VERIFY]**                                                                                           |
| `captions.update`                         | 450                  | **[VERIFY]**                                                                                           |
| `captions.delete`                         | 50                   | **[VERIFY]**                                                                                           |
| `captions.download`                       | 200                  | **[VERIFY]**                                                                                           |
| `commentThreads.list`                     | 1                    |                                                                                                        |
| `commentThreads.insert`                   | 50                   |                                                                                                        |
| `comments.list`                           | 1                    |                                                                                                        |
| `comments.insert`                         | 50                   |                                                                                                        |
| `comments.update`                         | 50                   |                                                                                                        |
| `comments.delete`                         | 50                   |                                                                                                        |
| `comments.markAsSpam`                     | 50                   |                                                                                                        |
| `comments.setModerationStatus`            | 50                   |                                                                                                        |
| `videoCategories.list`                    | 1                    | Region-dependent.                                                                                      |
| `i18nLanguages.list`                      | 1                    |                                                                                                        |
| `i18nRegions.list`                        | 1                    |                                                                                                        |
| `videoAbuseReportReasons.list`            | 1                    |                                                                                                        |
| `channelSections.*`                       | 1 (read), 50 (write) | Largely deprecated UX-side **[VERIFY]**.                                                               |
| `liveBroadcasts.*`                        | varies               | Out of scope for Pito Phase 8.                                                                         |
| `liveStreams.*`                           | varies               | Out of scope.                                                                                          |
| `members.list` / `membershipsLevels.list` | 1                    | Channel memberships (Patreon-style).                                                                   |

**Per-`part` cost note.** Author belief: for the `*.list` family, the cost is
**1 unit per call**, _independent_ of how many `part` values are requested. Some
old Google blog posts and SO answers reference "1 unit per part" or per-part
quota costs — those reflect a pre-2020 model that has since been flattened
**[VERIFY THIS — it's a meaningful difference for sync planning]**.

### YouTube Analytics API v2

| Method                                      | Cost (units) | Notes                                                           |
| ------------------------------------------- | ------------ | --------------------------------------------------------------- |
| `reports.query`                             | 1            | Most reports. Some advanced reports may cost more **[VERIFY]**. |
| `groups.list / .insert / .update / .delete` | 1 each       | **[VERIFY]**                                                    |
| `groupItems.list / .insert / .delete`       | 1 each       | **[VERIFY]**                                                    |

Verify against:

- https://developers.google.com/youtube/v3/determine_quota_cost
- https://developers.google.com/youtube/v3/getting-started
- https://developers.google.com/youtube/analytics/quotas

---

## Pito recommendations — top columns to add

> This section is **Pito-recommendation, not YouTube-fact.** It interprets the
> capability matrix above against the Phase 7 schema (`docs/architecture.md`
> §"Channel / Video schema philosophy" + spec 7B's column list) and proposes
> what to add when Phase 8's sync work lands.

### Channel — beyond the additive set already locked in spec 7B

Spec 7B already locks `title`, `description`, `subscriber_count`, `video_count`,
`view_count`, `thumbnail_url`, `etag`, `synced_at` on `channels`. The following
are the next-most-useful columns:

1. **`youtube_channel_id`** (string, indexed). Currently the URL holds it; a
   denormalized column makes API calls and joins simpler. Already implied by the
   URL regex but not stored separately.
2. **`handle`** (string, nullable). `snippet.customUrl` — the `@handle` form.
   Useful for display and for resolving Studio-pasted URLs. Read-only via API
   but worth caching.
3. **`country`** (string(2), nullable). ISO 3166-1 alpha-2.
4. **`default_language`** (string, nullable). BCP-47.
5. **`uploads_playlist_id`** (string, nullable, indexed). From
   `contentDetails.relatedPlaylists.uploads`. **The single most important sync
   field** — it's the cheap path to walk every public upload via
   `playlistItems.list` (1 unit/page) instead of `search.list` (100 units).
6. **`hidden_subscriber_count`** (boolean, default false). Distinguishes "0
   subs" from "creator hid the count".
7. **`topic_categories`** (jsonb array). From `topicDetails.topicCategories`.
   Useful for grouping/filtering in the workspace UI.
8. **`banner_url`** (string, nullable). From
   `brandingSettings.image.bannerExternalUrl`. Worth caching for display.
9. **`keywords`** (string, nullable). From `brandingSettings.channel.keywords`.
   Useful for embedding/search down the line.

### Video — beyond spec 7B's redesigned set

Spec 7B already has `youtube_video_id`, `title`, `description`, `published_at`,
`duration_seconds`, `view_count`, `like_count`, `comment_count`,
`thumbnail_url`, `privacy_status`, `etag`, `synced_at`. Next most useful:

1. **`tags`** (jsonb array). `snippet.tags`. Embedding-relevant.
2. **`category_id`** (integer). `snippet.categoryId`.
3. **`default_language`** / **`default_audio_language`** (strings).
4. **`made_for_kids`** (boolean). `status.madeForKids` — computed by YouTube,
   useful for filtering.
5. **`embeddable`** (boolean). `status.embeddable`.
6. **`license`** (string). `status.license` — `youtube` or `creativeCommon`.
7. **`live_broadcast_content`** (string enum: `none`/`live`/`upcoming`).
   `snippet.liveBroadcastContent`.
8. **`channel_handle_at_publish`** (string, nullable). For UX where a video is
   shown out of channel context.
9. **`captions_available`** (boolean). `contentDetails.caption == "true"`.
10. **`region_restriction`** (jsonb, nullable).
    `contentDetails.regionRestriction` — interesting for tracked content where
    Pito users may want to flag geo-blocked items.

### Owned-only video columns (for Analytics-rooted enrichment)

When the channel is **owned** (`oauth_identity_id NOT NULL`), Phase 8's
analytics aggregate table (deferred per spec 7B §"Per-channel data storage")
should store at least:

1. **`watch_time_minutes`** (bigint, nullable). From Analytics
   `estimatedMinutesWatched`.
2. **`average_view_duration_seconds`** (integer, nullable).
3. **`average_view_percentage`** (decimal, nullable).
4. **`subscribers_gained`** / **`subscribers_lost`** (integers, nullable). At
   the per-video level if Phase 8 walks per-video reports; at the channel level
   always.
5. **`impressions`** / **`impressions_ctr`** (integer / decimal). For "thumbnail
   performance" displays.

Per Phase 7 closeouts, these belong in a daily-grain table
(`youtube_analytics_daily` or similar), not on `videos` directly — the spec
language calls that out explicitly.

---

## Open questions for live-API verification

Items in this doc that author flagged **[VERIFY]** and where the answer
materially affects Phase 8 design:

1. **Channel avatar**: is there ANY public Data API write path? If yes, name the
   endpoint, scope, quota cost, and image format. If no (likely), confirm and
   bake "avatar = read-only" into Pito's UI affordances from day one.
2. **Title / handle 14-day cooldown**: which field carries the cooldown, and
   does the API enforce it or only the Studio UI? Pito should warn the user
   before submitting a write that will be rejected.
3. **Watermark cornerPosition values**: enumerate the exact valid string values.
   Pito's UI radio buttons need the right labels.
4. **Watermark timing**: confirm the `offsetFromStart` / `offsetFromEnd` /
   `entireVideo` model and the exact field names (`offsetMs` vs `durationMs`).
5. **Per-`part` quota**: does requesting
   `parts=snippet,statistics,brandingSettings,topicDetails` on `channels.list`
   cost 1 unit or 4? Pito's daily-budget math depends on this.
6. **`channels.update` write fields**: spec 7B treats it as a single-call write.
   Confirm which `parts` are mutable in one call — at minimum
   `brandingSettings`, `localizations`, `status` **[VERIFY]** — vs which require
   separate dedicated endpoints (e.g., `channelBanners.insert`).
7. **Captions.insert / update cost**: 400 / 450 / 200 are author-recall numbers.
   Verify before designing a captions sync.
8. **PubSubHubbub events**: confirm whether privacy flips (private→public)
   trigger pings and whether `videos.update` metadata edits trigger pings.
   Pito's "is the cache stale" logic differs depending.
9. **`subscriberCount` precision**: is it always rounded for >1000 subs in the
   Data API? Is the exact count visible only via Analytics? This affects what
   the channel show page can claim.
10. **Comments enable/disable via API**: does `videos.update` carry a
    `status.publicCommentsEnabled` or similar field? Or is comment-disable
    Studio-only?

---

## Pito callout — keep `search.list` out of normal flows

This bears repeating from `docs/youtube_quota.md`: `search.list` costs **100x**
a `videos.list` call. Pito's discovery UX is **paste a URL**, never type a name.
Any Phase 8 design that wants to "find a channel by display name" must go
through a YouTube redirect (the user clicks a link to YouTube, copies the URL
back) rather than a `search.list` shortcut. The 10,000-unit project budget
cannot survive a search-typeahead UX.
