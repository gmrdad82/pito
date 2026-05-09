# YouTube Analytics: channel + video metrics for pito

Reference for modeling channel and video analytics in our app and wiring them to the YouTube Analytics API v2. Assumes OAuth as the channel owner with scope `https://www.googleapis.com/auth/yt-analytics.readonly`. Owned channels and videos only — no public/third-party analytics.

Source: <https://developers.google.com/youtube/analytics/channel_reports> and <https://developers.google.com/youtube/analytics/data_model>.

## Mental model

One endpoint does all the work: `reports.query` on `https://youtubeanalytics.googleapis.com/v2/reports`. Five parameters shape every call:

- `ids` — `channel==MINE` (the OAuth'd channel) or `channel==UC...` (must be owned)
- `startDate`, `endDate` — `YYYY-MM-DD`, Pacific Time day boundaries
- `metrics` — comma-separated, what to measure
- `dimensions` — comma-separated, how to slice (`GROUP BY`)
- `filters` — semicolon-separated, what subset (`WHERE`)

Pseudocode for any query:

```
SELECT {metrics}
FROM youtube_analytics
WHERE channel = MINE AND date BETWEEN start AND end AND {filters}
GROUP BY {dimensions}
```

Channel-level vs video-level uses the same endpoint — the only difference is whether you pass `filters=video==<id>`.

## Metrics we care about

Annotations are skipped (deprecated, always zero for any video uploaded after 2019). Monetization is included in the schema as nullable / feature-flagged but not synced yet (see "Monetization posture" below).

| Group | Metrics | Notes |
|---|---|---|
| Views | `views`, `engagedViews`, `redViews`, `uniques` | `redViews` = YouTube Premium views. `uniques` only available on certain reports. |
| Watch time | `estimatedMinutesWatched`, `estimatedRedMinutesWatched`, `averageViewDuration`, `averageViewPercentage` | `averageViewPercentage` is the only non-summable headline metric. See windowing rules. |
| Engagement | `likes`, `dislikes`, `comments`, `shares`, `videosAddedToPlaylists`, `videosRemovedFromPlaylists` | All summable. |
| Subscribers | `subscribersGained`, `subscribersLost` | Net = gained − lost. |
| Impressions / CTR | `videoThumbnailImpressions`, `videoThumbnailImpressionsClickRate` | Rate is non-summable; query the window directly. |
| Cards | `cardImpressions`, `cardClicks`, `cardClickRate`, `cardTeaserImpressions`, `cardTeaserClicks`, `cardTeaserClickRate` | Rates are derivable: `cardClicks / cardImpressions`. |
| Audience retention | `audienceWatchRatio`, `relativeRetentionPerformance`, `startedWatching`, `stoppedWatching`, `totalSegmentImpressions` | Per-video only. Not time-summable; sliced by `elapsedVideoTimeRatio`. |
| Demographics | `viewerPercentage` | Only metric for the demographics report. Not summable. |
| Live | `averageConcurrentViewers`, `peakConcurrentViewers` | Only for live broadcasts. Sliced by `livestreamPosition`. |
| Playlist-specific | `playlistStarts`, `viewsPerPlaylistStart`, `averageTimeInPlaylist` | Require `isCurated==1` filter (see Playlist queries). |
| Revenue (deferred) | `estimatedRevenue`, `estimatedAdRevenue`, `grossRevenue`, `estimatedRedPartnerRevenue`, `monetizedPlaybacks`, `playbackBasedCpm`, `adImpressions`, `cpm` | Requires `yt-analytics-monetary.readonly`. **Per Google docs, channel-scoped revenue is content-owner only — non-YPP creators get empty results.** Schema-ready, sync-disabled. |

## Dimensions cheat-sheet

A dimension is a `GROUP BY`. `dimensions=day` returns one row per day; `dimensions=country` returns one row per country; `dimensions=day,country` returns one row per (day, country) pair.

| Group | Dimensions |
|---|---|
| Time | `day`, `month` (mutually exclusive) |
| Geography | `country`, `province` (US states only), `city`, `dma`, `continent`, `subContinent` |
| Audience | `ageGroup`, `gender`, `subscribedStatus` |
| Device | `deviceType`, `operatingSystem` |
| Playback context | `liveOrOnDemand`, `youtubeProduct`, `creatorContentType` |
| Discovery | `insightTrafficSourceType`, `insightTrafficSourceDetail`, `insightPlaybackLocationType`, `insightPlaybackLocationDetail` |
| Sharing | `sharingService` |
| Retention (per video) | `elapsedVideoTimeRatio` |
| Live | `livestreamPosition` |
| Identity | `video`, `playlist`, `group` |

## Storage strategy

Three table shapes cover everything:

```
channel_daily(channel_id, date, [all numeric metrics])
video_daily(video_id, date, [all numeric metrics])
video_daily_by_<slice>(video_id, date, slice_value, [metrics])
  where <slice> ∈ country, device_type, operating_system, traffic_source,
                  subscribed_status, age_group_gender
```

Plus three "windowed summary" tables for the ratio metrics that don't sum cleanly:

```
video_window_summary(video_id, window, [all metrics])
  where window ∈ '7d', '28d', '90d', 'lifetime'
channel_window_summary(channel_id, window, [all metrics])
top_videos_window(channel_id, window, video_id, rank, [metrics])
```

Plus one specialty table:

```
video_retention(video_id, elapsed_ratio_bucket, audienceWatchRatio,
                relativeRetentionPerformance, startedWatching,
                stoppedWatching, totalSegmentImpressions, computed_at)
```

Daily sync writes new rows for "yesterday" and **rewrites the last 3 days** because YouTube revises numbers for ~48-72h, especially views and watch time.

## Channel queries (Goal 1: at-a-glance dashboard)

### C1. Channel daily time-series — the spine

```
ids=channel==MINE
startDate=<2 years ago or channel creation>  endDate=<yesterday>
dimensions=day
metrics=views,engagedViews,redViews,
        estimatedMinutesWatched,estimatedRedMinutesWatched,
        averageViewDuration,
        likes,dislikes,comments,shares,
        videosAddedToPlaylists,videosRemovedFromPlaylists,
        subscribersGained,subscribersLost,
        videoThumbnailImpressions,
        cardImpressions,cardClicks,cardTeaserImpressions,cardTeaserClicks
```

Daily sync: only fetch last 3-4 days and upsert. Feeds every line/bar on the channel dashboard.

Note: `videoThumbnailImpressionsClickRate`, `cardClickRate`, `cardTeaserClickRate`, and `averageViewPercentage` are intentionally absent — they're non-summable and should come from C2 instead.

### C2. Channel windowed summaries (for ratio metrics)

For each window in {7d, 28d, 90d, lifetime}:

```
ids=channel==MINE
startDate=<window start>  endDate=<yesterday>
[no dimensions]
metrics=<all C1 metrics> + averageViewPercentage,
        videoThumbnailImpressionsClickRate,
        cardClickRate,cardTeaserClickRate
```

One row per window. Stored in `channel_window_summary`. These give Studio-faithful ratios.

### C3. Top videos leaderboard (per window)

For each window in {7d, 28d, 90d, lifetime}:

```
ids=channel==MINE
startDate=<window start>  endDate=<yesterday>
dimensions=video
metrics=views,estimatedMinutesWatched,averageViewDuration,
        averageViewPercentage,subscribersGained,likes,comments
sort=-estimatedMinutesWatched
maxResults=50
```

Stored in `top_videos_window`. Drives the "rising" / "all-time" leaderboards.

### C4. Channel geography

```
ids=channel==MINE
dimensions=country
metrics=views,estimatedMinutesWatched,averageViewDuration
```

For the audience map.

### C5. Channel demographics

```
ids=channel==MINE
dimensions=ageGroup,gender
metrics=viewerPercentage
```

Age × gender heatmap. `viewerPercentage` is non-additive and not normalized across `subscribedStatus` / `liveOrOnDemand` / `youtubeProduct` — if you add those as dimensions, totals will exceed 100%.

## Video queries (Goal 2: per-video detail)

Same vocabulary, scoped with `filters=video==<id>`. Run for each "active" video on daily sync. **Active** = uploaded in last 90 days OR > 100 views in last 7 days. Inactive videos: refresh V1 only, weekly.

### V1. Video daily time-series

Same shape as C1 with `filters=video==<id>` appended. The per-video spine.

### V2. Video windowed summaries

Same shape as C2 with `filters=video==<id>`. One row per (video, window). Stored in `video_window_summary`. **This is the source of truth for `averageViewPercentage` and CTR ratios per window** — do not compute these from `video_daily` SUMs.

### V3. By country

```
filters=video==<id>
dimensions=country
metrics=views,estimatedMinutesWatched,averageViewDuration,
        averageViewPercentage
```

### V4. By device + OS

```
filters=video==<id>
dimensions=deviceType,operatingSystem
metrics=views,estimatedMinutesWatched,averageViewDuration,
        averageViewPercentage
```

"Which devices to optimize for."

### V5. By traffic source

```
filters=video==<id>
dimensions=insightTrafficSourceType
metrics=views,estimatedMinutesWatched,
        videoThumbnailImpressions,videoThumbnailImpressionsClickRate
```

Discovery breakdown: Search vs Browse vs Suggested vs External vs Shorts feed, etc.

### V6. By subscribed status × content type

```
filters=video==<id>
dimensions=subscribedStatus,creatorContentType
metrics=views,estimatedMinutesWatched,averageViewPercentage
```

Subscriber-vs-stranger split, plus how the video counted (Shorts/VOD/Live).

### V7. Audience retention — weekly, not daily

```
filters=video==<id>
dimensions=elapsedVideoTimeRatio
metrics=audienceWatchRatio,relativeRetentionPerformance,
        startedWatching,stoppedWatching,totalSegmentImpressions
```

The drop-off curve. Returns ~100 rows per video so it's expensive in time though cheap in quota. Refresh **weekly** for active videos; the shape stabilizes after the first week.

### V8. Video demographics

```
filters=video==<id>
dimensions=ageGroup,gender
metrics=viewerPercentage
```

### V9. Live concurrents (live broadcasts only)

```
filters=video==<id>
dimensions=livestreamPosition
metrics=averageConcurrentViewers,peakConcurrentViewers
```

Skip for non-live videos.

## Playlist queries

Different filter shape — `isCurated==1` is currently mandatory:

```
ids=channel==MINE
filters=isCurated==1;playlist==<id>
dimensions=day
metrics=views,estimatedMinutesWatched,averageViewDuration,
        playlistStarts,viewsPerPlaylistStart,averageTimeInPlaylist
```

Watch the [Analytics revision history](https://developers.google.com/youtube/analytics/revision_history) — `isCurated` is being deprecated and the filter shape will change. The metrics `playlistStarts` / `viewsPerPlaylistStart` / `averageTimeInPlaylist` only work on playlist queries.

## Cross-video questions (computed locally)

These don't come from the Analytics API directly. They come from joining `video_daily` and `video_window_summary` against video metadata stored from Data API v3 (`publishedAt`, `tags`, `duration`, `categoryId`).

- **When to publish**: bucket videos by day-of-week and hour of `publishedAt`, compare median first-7-days `views` and `estimatedMinutesWatched`.
- **Best duration**: bucket videos by `duration` ranges (0-60s, 1-5min, 5-15min, 15min+), compare median `estimatedMinutesWatched` and `averageViewPercentage` from `video_window_summary`.
- **Topics that work**: group by `categoryId` (cleaner than tags), compare median first-28-days views.
- **Thumbnail decay**: track `videoThumbnailImpressionsClickRate` over time per video from `video_window_summary` — drops mean the thumbnail is getting stale.

## Windowing: which metrics sum, which don't

**Summable across days** (window total = `SUM(daily values)`):
`views`, `engagedViews`, `redViews`, `estimatedMinutesWatched`, `estimatedRedMinutesWatched`, `likes`, `dislikes`, `comments`, `shares`, `videosAddedToPlaylists`, `videosRemovedFromPlaylists`, `subscribersGained`, `subscribersLost`, `videoThumbnailImpressions`, `cardImpressions`, `cardClicks`, `cardTeaserImpressions`, `cardTeaserClicks`, `monetizedPlaybacks`, `adImpressions`, `estimatedRevenue`, `estimatedAdRevenue`, `grossRevenue`, `estimatedRedPartnerRevenue`.

**Derivable from sums**:
- `averageViewDuration` = `SUM(estimatedMinutesWatched) * 60 / SUM(views)`
- `cardClickRate` = `SUM(cardClicks) / SUM(cardImpressions)`
- `cardTeaserClickRate` = `SUM(cardTeaserClicks) / SUM(cardTeaserImpressions)`

**NOT derivable — query the window directly** (this is why C2 / V2 exist):
- `averageViewPercentage`
- `videoThumbnailImpressionsClickRate`
- `playbackBasedCpm`, `cpm`
- `viewerPercentage`
- `audienceWatchRatio`, `relativeRetentionPerformance` (and other retention metrics — query per video, not summable across time)

For custom user-picked windows that aren't 7/28/90/lifetime, compute additives from `video_daily` and label ratio metrics with a "based on daily totals — may differ slightly from Studio" hint.

## Sync schedule

**Nightly per channel:**
- C1, C2 (all four windows), C3 (all four windows), C4, C5
- Refetch last 3 days for the time-series tables (revision lag)

**Nightly per active video:**
- V1, V2 (all four windows), V3, V4, V5, V6, V8

**Nightly per inactive video:**
- V1 only (keeps time-series fresh)

**Weekly per active video:**
- V7 retention

**On-demand (user clicks "refresh" on a video):**
- V1-V8 for that video

**Once at first sync per video:**
- Compute lifetime row in `video_window_summary`

## Quota

Analytics v2 has its own quota separate from Data API v3. Each `reports.query` is 1 unit. A 200-active-video channel runs ~1800 queries/night including C1-C5 + V1-V6,V8 — well below limits. Bottleneck is wall-clock; sequence with 3-5 parallel workers.

## Mutual-exclusion gotchas

These will bite if you don't centralize the query builder:

1. `liveOrOnDemand` and `averageViewPercentage` cannot coexist in one query. Split into two queries if you need both.
2. `day` and `month` are mutually exclusive as time dimensions.
3. Audience retention (V7) requires a single video filter — no `video==a,b,c`.
4. Province / DMA reports require `country==US`.
5. City report: `maxResults ≤ 250`, `sort` required.
6. Top videos / playback-location-detail / traffic-source-detail: `sort` required, `maxResults` capped (200 / 25 / 25 respectively).
7. Data lag: refetch last 3 days each sync, not just yesterday.
8. Pacific Time day boundaries — match Studio.

## Data freshness UX

Show a "data as of <last sync, in user's local TZ>" indicator on the dashboard. For the most recent 1-3 days of any chart, render with a hint that those values may revise. Studio implies this; we should make it explicit.

## Monetization posture (deferred)

We are not syncing revenue today, but the schema and code are designed to enable it without migration:

- **Schema**: revenue columns (`estimatedRevenue`, `estimatedAdRevenue`, `grossRevenue`, `estimatedRedPartnerRevenue`, `monetizedPlaybacks`, `playbackBasedCpm`, `adImpressions`, `cpm`) included as nullable on `channel_daily`, `video_daily`, `channel_window_summary`, `video_window_summary`. They stay NULL until enabled.
- **OAuth scope**: only `yt-analytics.readonly` requested initially. When enabling monetization, add `yt-analytics-monetary.readonly` and force a re-auth flow. Do not bundle the monetary scope upfront.
- **Query builder**: monetary metrics live behind a `MONETIZATION_ENABLED` feature flag. When false, the metric list omits them. When true, the same builder appends them with no other change.
- **UI**: revenue cards/charts hidden when flag is off — do not render zero-rows as "$0", render "monetization not connected" or omit the section.
- **API caveat**: per Google's docs, channel-scoped revenue metrics are content-owner-only. Non-YPP creators with the right scope still get empty results. Worth documenting in error messages so future-debugging-self doesn't lose a day. Test with a small date range on first enable.

## Auth scopes summary

| Scope | When |
|---|---|
| `https://www.googleapis.com/auth/yt-analytics.readonly` | Default. All non-revenue metrics. |
| `https://www.googleapis.com/auth/yt-analytics-monetary.readonly` | Future. Adds revenue metrics. Requires re-auth. |
| `https://www.googleapis.com/auth/youtube` | Required only if we manage Analytics groups via API. Not in scope for v1. |
