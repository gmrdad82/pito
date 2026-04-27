# Beta Build Plan

YouTube integration phases — moved from alpha. These require real YouTube API credentials and connected channels.

## Phase 1 — Settings + OAuth

- [ ] **Step 1:** OAuth service objects — Youtube::OauthClient for token exchange/refresh, WebMock-stubbed specs
- [ ] **Step 2:** Channel OAuth connect — `/channels/:id/oauth/connect` with breadcrumb, initiates OAuth flow, stores tokens, sets connected=true
- [ ] **Step 3:** Channel OAuth disconnect — action screen, dry-run preview, revokes tokens, sets connected=false

## Phase 2 — Sync

- [ ] **Step 4:** Youtube::ChannelFetcher service — fetch channel metadata via Data API, WebMock specs
- [ ] **Step 5:** Youtube::VideoFetcher service — fetch video list + metadata for a channel, WebMock specs
- [ ] **Step 6:** Youtube::AnalyticsFetcher service — fetch daily stats per video via Analytics API, WebMock specs
- [ ] **Step 7:** Youtube::PlaylistManager service — fetch playlists + items, WebMock specs
- [ ] **Step 8:** SyncChannelJob — orchestrates channel metadata + video list sync, job specs
- [ ] **Step 9:** SyncVideoStatsJob — daily stats sync (last 30 days, idempotent), job specs
- [ ] **Step 10:** SyncPlaylistsJob — playlist + items sync, job specs

## Phase 3 — Video Management Action Screens

- [ ] **Step 11:** Youtube::VideoUpdater service — update title/description/tags/category/privacy/schedule via Data API, WebMock specs
- [ ] **Step 12:** Youtube::ThumbnailUpdater service — set custom thumbnail, WebMock specs
- [ ] **Step 13:** MetadataEditsController — action screen for editing video metadata (bulk: prefix/suffix, tags add/remove, category set)
- [ ] **Step 14:** SchedulingsController — action screen for scheduling publish (bulk: stagger option)
- [ ] **Step 15:** PrivacyChangesController — action screen for changing privacy status
- [ ] **Step 16:** ThumbnailChangesController — action screen for changing thumbnails
- [ ] **Step 17:** PlaylistAdditionsController — action screen for adding videos to playlists

## Phase 4 — Video Upload

Upload architecture: browser uploads directly to YouTube API via resumable upload. Backend never touches file bytes — only provides the resumable URI (using channel's OAuth token) and tracks upload status. Each connected channel also gets a direct YouTube Studio link as fallback.

- [ ] **Step 18:** Youtube::ResumableUploadInitiator service — uses channel OAuth token to get resumable upload URI from YouTube, WebMock specs
- [ ] **Step 19:** Upload page — `/videos/upload`, channel selector, file picker, metadata form (title/description/privacy/tags)
- [ ] **Step 20:** Client-side upload Stimulus controller — browser streams file directly to YouTube via resumable URI, chunked with progress bar
- [ ] **Step 21:** Upload status tracking — VideoUpload record updated via Turbo Stream, completion links to synced Video
- [ ] **Step 22:** YouTube Studio links — per-channel `[ YouTube Studio ]` link on channel detail (studio.youtube.com/channel/{id})
