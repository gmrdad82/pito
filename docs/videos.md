# Videos domain: commands, sync, reindex, recommendations

> Status: Signed off 2026-06-08 — executing on `beta-videos`. Phases 1–10 + 12–16 DONE (Recommendation v2 complete: channel-personality model, user-validated). Phase 11 SUPERSEDED. Remaining: Phase 17 (list videos UI polish) + Help A/B. D2 → 3×/day.

## Sign-off

- [x] Drafted
- [x] Audited — 2026-06-08 (clean for Phases 1, 10, 2–8; Phase 9 gates on D2). **Phase 11 added 2026-06-08 post-audit — re-audit + α/β anchors required before executing it.**

## North star

Bring Video to parity with Game as a first-class chat-driven domain: slim the
Video model to its editable essence, give it the same verb surface games have
(show / delete / publish / schedule / unlist / link), make game↔video links
first-class in both directions, surface reindex as user-visible messages +
follow-ups, list upcoming games and local videos with smart genre/platform
mapping, and run the right nightly/intraday syncs within YouTube's 10K/day
quota. Channel↔game recommendation already reads through videos AND their
linked games (built on `beta-videos`).

## Decisions needing confirmation (before Phase 2 / Phase 9 start)

These shape several tasks; flagged here so they can be corrected before work begins.

- **D1 — Video columns (Phase 2) — RESOLVED 2026-06-08.** Keep the content fields
  (`title`, `description`, `tags`; thumbnail is derived from `youtube_video_id`)
  and the operational columns (`channel_id`, `youtube_video_id`, `privacy_status`,
  `publish_at`, `published_at`, `last_synced_at`, `summary_embedding`,
  `embedded_digest`, `search_vector`). **Also keep** `duration_seconds` (intrinsic,
  not a stat) and `category_id` (surfaced via a new id→name map: Gaming,
  People & Blogs, …). **Migrate** `comment_count` → `Pito::Stats` (`comments` kind)
  and `like_count` → `Pito::Stats` (`likes` kind) — both come from the Data API
  (`videos.list?part=statistics`), so they belong in Stats next to `views`.
  **Drop** `etag` (dead — `Video#etag_changed?` has zero callers; re-embed is
  digest-gated) and scrub its references. Net column drops: `etag`,
  `comment_count`, `like_count` (the last two only after their Stats backfill).
- **D2 — Intraday Video stats cadence (Phase 9 / task 11).** 6 channels, ~N videos,
  10K units/day YouTube quota. `videos.list` is 1 unit per call (up to 50 ids per
  call), so snapshotting all videos 3×/day (01:00 / 09:00 / 17:00 UTC) is cheap
  on quota. Recommend: **adopt 3×/day** — it fits quota comfortably. Confirm, or
  fall back to the 1-video/day option.

## Locked decisions

- L1 — Plan runs on `beta-videos`, current branch, no new branches/tags.
- L2 — Never drop/reset the DB. Schema changes via additive migrations only;
  column drops use a reversible `change_table`. Data is curated by hand.
- L3 — Verb surface mirrors Game: new Video verbs reuse the existing chat
  handler + grammar + ActionRegistry patterns (`app/services/pito/chat/handlers`,
  `lib/pito/grammar/specs.rb`, `config/initializers/pito_actions.rb`).
- L4 — `link` is one verb taking either side: `link video <ref> <game>` and
  `link game <ref> <video>` resolve to the same `VideoGameLink`.
- L5 — Lists have no pagination (list all) and query LOCAL data only (no YouTube).
- L6 — Nightly base slot stays 01:00 UTC alongside the existing fan-out.
- L7 — Reindex = re-embed via the existing `VideoVoyageIndexJob` /
  `GameVoyageIndexJob` (both now `retry_on VoyageEmbeddingNil`).

## Already done (prerequisites on `beta-videos`)

- Channel recommendation reads videos + their linked games; explicit link → 100.
- `VideoVoyageIndexJob` / `GameVoyageIndexJob` retry on transient Voyage nil.
- `ScoreBarComponent` `show_label:` kwarg; shared `Pito::Channel::ItemComponent`.

## Companion plan

The full multi-signal recommendation engine (game↔channel both ways + game↔game,
blending embedding / link / genre / developer / publisher / score, one smart SQL
query per direction, exhaustive specs) is specified separately in
**[docs/recommendations.md](recommendations.md)**. The link verbs here (Phase 5)
feed that engine.

## Phase index

- Phase 1 — Drop Game ownership (task 3)
- Phase 10 — Purge pre-reboot video-diff legacy (independent — recommended next)
- Phase 2 — Slim the Video model (task 4)
- Phase 3 — Reindex messages + follow-up for channel & game (tasks 1, 2)
- Phase 4 — Video verbs: show / delete / publish / schedule / unlist (task 5)
- Phase 5 — Game↔Video link both directions (tasks 5 link, 6)
- Phase 6 — `list games upcoming [genres] [platforms]` (task 9)
- Phase 7 — `list videos published|unlisted` scoped by shift+tab channel (task 10)
- Phase 8 — Nightly: Video stats sync + Game upcoming-only refresh (tasks 7, 8)
- Phase 9 — Intraday Video stats cadence (task 11) [decision D2]
- Phase 11 — Dynamic graded-link channel scoring — SUPERSEDED by Phases 12–16 (graded-K folded into Phase 15; α=5, β=1)
- Phase 12 — Recommendation v2: signal library (score/TTB smile, era/platform, dynamic embedding)
- Phase 13 — Recommendation v2: kernel re-weight + recompute game↔game (validate numbers)
- Phase 14 — Recommendation v2: channel personality profile (TF-weighted aggregate)
- Phase 15 — Recommendation v2: channel recommendation rebuild (profile-fit + graded-K, both ways; validate)
- Phase 16 — Recommendation v2: golden scenario matrix + harden the flaky pool spec
- Phase Copy — Pito::Copy 1-or-50 guard (foundation — run FIRST, before Phase 17)
- Phase 17 — Lists v2: N-col kv-table + headings + `with`/`sorted by` + `list games` channel scope
- Phase 18 — Unified dispatch: one handler interprets chat ≡ #hashtag (resolution + adapter + action gating)
- Phase 19 — Migrate show / show video / delete / link / unlink onto the unified handler
- Phase 20 — `reindex` (Voyage re-embed only); drop `resync`
- Phase 21 — YouTube write-through: delete / publish / unlist / schedule (Confirmable)
- Phase 22 — `import game` (IGDB sidebar → dispatch show game) + `footage` only
- Phase 23 — Cleanup: unify `/themes preview|apply`, drop `similar`, Pito::Copy 50-variant sweep
- Phase 24 — `sync` family (full refresh) + `import videos`; Confirmable, done-only broadcast
- Help A — `/help` for commands (keep) [TO DISCUSS]
- Help B — `#help` + `help` for hashtags & free messages [TO DISCUSS]

---

## Phase 1 — Drop Game ownership (task 3)

- [x] T1.1 Write a migration to drop the `game_platform_ownerships` table (reversible). complexity: [low]
- [x] T1.2 Delete `app/models/game_platform_ownership.rb`. complexity: [low]
- [x] T1.3 Remove `has_many :game_platform_ownerships` from `app/models/game.rb`. complexity: [low]
- [x] T1.4 Remove ownership branch from `app/services/pito/chat/handlers/update.rb`. complexity: [high]
- [x] T1.5 Remove ownership rendering from `app/components/pito/game/detail_component.rb`. complexity: [low]
- [x] T1.6 Remove ownership markup from `app/components/pito/game/detail_component.html.erb`. complexity: [low]
- [x] T1.7 Remove ownership branch from `app/services/pito/follow_up/handlers/game_detail.rb`. complexity: [high]
- [x] T1.8 Remove ownership grammar from `lib/pito/grammar/specs.rb`. complexity: [high]
- [x] T1.9 Remove ownership keys from `config/locales/pito/grammar/en.yml`. complexity: [low]
- [x] T1.10 Remove ownership keys from `config/locales/pito/game/en.yml`. complexity: [low]
- [x] T1.11 Remove ownership copy from `config/locales/pito/copy/en.yml`. complexity: [low]
- [x] T1.12 Remove any ownership reference in `app/services/game/igdb/importer.rb`. complexity: [low]
- [x] T1.13 Delete ownership specs and assertions across `spec/`. complexity: [high]
- [x] T1.14 Run `bundle exec rspec` for game model/handler/component specs; make green. complexity: [low]
- [x] T1.15 Commit: "Drop Game platform ownership". complexity: [manual]

## Phase 2 — Slim the Video model (task 4) [D1 resolved]

- [x] T2.1 Add `comments` + `likes` to `Stat::KINDS` in `app/models/stat.rb`. complexity: [low]
- [x] T2.2 Write `comment_count`/`like_count` to `Pito::Stats` (`comments`/`likes`) in `ImportVideosJob`. complexity: [high]
- [x] T2.3 Write `comment_count`/`like_count` to `Pito::Stats` in `NightlyVideoSyncJob`. complexity: [high]
- [x] T2.4 Write a data migration backfilling existing `videos.comment_count`/`like_count` into `stats` (combined with T2.9). complexity: [high]
- [x] T2.5 Add `Video#category_name` (reuses the existing `Video::EmbedText::YOUTUBE_CATEGORIES` id→name table). complexity: [low]
- [x] T2.6 Remove `etag` from `app/models/video.rb` (drop `etag_changed?`). complexity: [low]
- [x] T2.7 Remove `etag` writes from `ImportVideosJob`, `NightlyVideoSyncJob`, `VideoSyncBack`. complexity: [high]
- [x] T2.8 Remove `comment_count`/`like_count` column writes from jobs; model readers now source from `Pito::Stats`. complexity: [high]
- [x] T2.9 Write a reversible migration dropping `etag`, `comment_count`, `like_count` from `videos`. complexity: [low]
- [x] T2.10 Confirm `Video::EmbedText` uses title + description + tags + category (category retained → embed text unchanged). complexity: [low]
- [x] T2.11 Update the video factory + specs to the slim column set (counts via Stats). complexity: [high]
- [x] T2.12 Reindex one video locally to confirm the embed text is unchanged (digest match). complexity: [low]
- [x] T2.13 Run `bundle exec rspec` for video model/job/component specs; make green. complexity: [low]
- [x] T2.14 Commit: "Slim Video: migrate comments/likes to Stats, add category map, drop etag". complexity: [manual]

## Phase 3 — Reindex messages + follow-up (tasks 1, 2)

- [x] T3.1 ~~reindex channel <ref> grammar verb~~ DESCOPED → follow-up `#<handle> reindex @<handle>` on channel_list (mirrors game reindex's follow-up UX). complexity: [high]
- [x] T3.2 ~~reindex video <ref> grammar verb~~ DESCOPED → follow-up `#<handle> reindex` on video_detail. complexity: [high]
- [x] T3.3 Add reindex copy keys for channel + video to `config/locales/pito/copy/en.yml`. complexity: [low]
- [x] T3.4 Add a `confirm_channel_reindex` branch to `Pito::Confirmation::Executor` (enqueues VideoVoyageIndexJob per video). complexity: [high]
- [x] T3.5 Add a `confirm_video_reindex` branch to `Pito::Confirmation::Executor` (sync Video::VoyageIndexer force). complexity: [high]
- [x] T3.6 Reindex result message for channel broadcast via the confirmation flow's outcome text. complexity: [high]
- [x] T3.7 Reindex result message for video broadcast via the confirmation flow's outcome text. complexity: [high]
- [x] T3.8 Add a reindex follow-up action to `channel_list` (`reindex @<handle>`). complexity: [high]
- [x] T3.9 Add a `video_detail` follow-up handler with a `reindex` action. complexity: [high]
- [x] T3.10 Add specs for channel + video reindex confirm + follow-up. complexity: [high]
- [x] T3.11 Run the new specs; make green. complexity: [low]
- [x] T3.12 Commit: "Add reindex messages + follow-up for channel and video". complexity: [manual]

## Phase 4 — Video verbs: show / delete / publish / schedule / unlist (task 5)

- [x] T4.1 Add `show video <ref>` grammar spec entry. complexity: [high]
- [x] T4.2 Implement `show video` in `app/services/pito/chat/handlers/show.rb`. complexity: [high]
- [x] T4.3 Build a `Pito::MessageBuilder::Video::Detail` payload. complexity: [high]
- [x] T4.4 Build a `Pito::Video::DetailComponent` (title/description/tags/thumbnail + stats). complexity: [high]
- [x] T4.5 Add `delete|rm video <ref>` grammar + confirm branch. complexity: [high]
- [x] T4.6 Implement `delete video` in `handlers/delete.rb` with confirmation. complexity: [high]
- [x] T4.7 Add `publish video <ref>` grammar entry. complexity: [low]
- [x] T4.8 Implement `publish video` (set `privacy_status: public`, clear `publish_at`). complexity: [high]
- [x] T4.9 Add `unlist video <ref>` grammar entry. complexity: [low]
- [x] T4.10 Implement `unlist video` (set `privacy_status: unlisted`). complexity: [high]
- [x] T4.11 Add `schedule video <ref> <when>` grammar entry with a time vocabulary. complexity: [high]
- [x] T4.12 Implement `schedule video` (set `privacy_status: private` + `publish_at`). complexity: [high]
- [x] T4.13 Write-through decision: **LOCAL-ONLY** — publish/schedule/unlist update the row only, no YouTube call (write-back path exists for later). complexity: [manual]
- [x] T4.14 Add copy keys for each video verb result. complexity: [low]
- [x] T4.15 Add specs for show/delete/publish/schedule/unlist. complexity: [high]
- [x] T4.16 Run the new specs; make green. complexity: [low]
- [x] T4.17 Commit: "Add Video verbs: show, delete, publish, schedule, unlist". complexity: [manual]

## Phase 5 — Game↔Video link both directions (tasks 5 link, 6)

> Already satisfied by existing `handlers/link.rb` + `handlers/unlink.rb` (the `link/unlink <noun> <ref> to/from <noun> <ref>` forms split on `to`/`from` and resolve either side). Grammar `:link`/`:unlink` specs exist; discoverability is automatic (suggestions catalog derives from `Pito::Grammar::Registry.specs`). Verified: 23 link/unlink specs green.

- [x] T5.1 `link video <ref> … to game <ref>` parses via the existing `:link` grammar spec (the `to` keyword separates the two refs). complexity: [high]
- [x] T5.2 `link game <ref> … to video <ref>` — same `:link` spec, reversed nouns. complexity: [high]
- [x] T5.3 video→game linking in `handlers/link.rb` (find-or-create `VideoGameLink`). complexity: [high]
- [x] T5.4 game→video linking in `handlers/link.rb` (same row, reversed args). complexity: [high]
- [x] T5.5 `unlink` both directions in `handlers/unlink.rb`. complexity: [high]
- [x] T5.6 ~~`pito_actions.rb` `:videos`/`:games` scopes~~ N/A — that's unused pre-reboot palette legacy; chat-action registration is the grammar Registry (present) → auto-surfaced in suggestions. complexity: [high]
- [x] T5.7 link/unlink result copy keys (present: `games.linked`/`games.unlinked`). complexity: [low]
- [x] T5.8 Specs for link/unlink both directions + idempotency (present). complexity: [high]
- [x] T5.9 Run the specs; green (23 examples). complexity: [low]
- [x] T5.10 Commit: "Add bidirectional game↔video link verb + actions". complexity: [manual]

## Phase 6 — `list games upcoming [genres] [platforms]` (task 9)

- [x] T6.1 Widen platform mapping so `ps` matches ALL PlayStation (PS5 + PS4) — in `Pito::Chat::GameListFilter`. complexity: [high]
- [x] T6.2 Add a genre alias set (rpg/action/etc → canonical ILIKE on `Genre#name`). complexity: [low]
- [x] T6.3 Parse `list games [upcoming] [genres…] [platforms…]` order-independent in the list handler. complexity: [high]
- [x] T6.4 `Game.upcoming` scope (already existed). complexity: [high]
- [x] T6.5 Implement filtering in `handlers/list.rb` (genre/platform OR within type, AND across types + upcoming). complexity: [high]
- [x] T6.6 Resolve platform filter tokens through the synonym map (match any synonym). complexity: [high]
- [x] T6.7 Render the filtered relation via the existing `Game::List` message. complexity: [high]
- [x] T6.8 Add the filtered empty-state copy key. complexity: [low]
- [x] T6.9 Specs: upcoming-only, genre, platform mapping (ps → PS5 + PS4), combined, order-independent (28 examples). complexity: [high]
- [x] T6.10 Run the new specs; make green. complexity: [low]
- [x] T6.11 Commit: "Add list games upcoming with genre + platform mapping". complexity: [manual]

## Phase 7 — `list videos published|unlisted` by shift+tab channel (task 10)

- [x] T7.1 `list videos [published|unlisted]` handled in the list handler (free-body parse). complexity: [high]
- [x] T7.2 Thread the `channel` param through `ChatDispatchJob → Chat::Dispatcher → Handler` (optional kwarg). complexity: [high]
- [x] T7.3 Resolve `@all`/nil → all channels; `@<handle>` → that channel (handle-normalized); unknown → not-found copy. complexity: [high]
- [x] T7.4 Implement `list videos` filtering in `handlers/list.rb` by privacy_status + channel scope (local only). complexity: [high]
- [x] T7.5 Build `Video::List` message + `Pito::Video::ListComponent` (id/title/@channel/privacy, list all). complexity: [high]
- [x] T7.6 Add copy keys for the videos list + empty states. complexity: [low]
- [x] T7.7 Add specs: @all lists all, @handle scopes to one channel, published vs unlisted, threading regression. complexity: [high]
- [x] T7.8 Run the new specs; make green. complexity: [low]
- [x] T7.9 Commit: "Add list videos published/unlisted scoped by channel". complexity: [manual]

## Phase 8 — Nightly: Video stats sync + Game upcoming-only (tasks 7, 8)

- [x] T8.1 `NightlyVideoSyncJob` snapshots views/likes/comments to `Pito::Stats` per video (done in Phase 2). complexity: [high]
- [x] T8.2 Confirmed: `NightlySyncJob` (01:00 UTC) fans out `NightlyVideoSyncJob` per connected channel. complexity: [low]
- [x] T8.3 Add `.upcoming` to `GameIgdbNightlyRefresh`'s `Game.synced.stale` scope. complexity: [high]
- [x] T8.4 Nightly Game refresh now iterates `Game.synced.stale.upcoming` only (released games skip — data final). complexity: [high]
- [x] T8.5 Spec the upcoming-only filter (upcoming enqueued; released/fresh/never-synced skipped). complexity: [high]
- [x] T8.6 Run the new specs; make green. complexity: [low]
- [x] T8.7 Commit: "Nightly: snapshot video stats + refresh only upcoming games". complexity: [manual]

## Phase 9 — Intraday Video stats cadence (task 11) [D2 resolved → 3×/day]

- [x] T9.1 Add recurring entries for `VideoStatsSnapshotJob` at 09:00 + 17:00 UTC (01:00 full sync covers the third). complexity: [low]
- [x] T9.2 `VideoStatsSnapshotJob` — lightweight stats-only snapshot for existing videos (no upsert/embed). complexity: [high]
- [x] T9.3 Batch ≤50 youtube_video_ids per `videos.list` call (1 quota unit each); per-channel error isolation. complexity: [high]
- [x] T9.4 Specs: batching (51 → 2 calls), stats written, skip reauth/empty, per-channel error resilience. complexity: [high]
- [x] T9.5 Run the new specs; make green (14 examples). complexity: [low]
- [x] T9.6 Commit: "Add 3×/day video stats snapshot (01:00 / 09:00 / 17:00 UTC)". complexity: [manual]

## Phase 10 — Purge pre-reboot video-diff legacy (independent — recommended next)

The bidirectional video-diff dialog is Phase-23 (pre-reboot, ~2026-05-11) code the
chat-first reboot inherited but never wired into its surface. Purge the diff layer
whole. KEEP the shared OAuth `VideosClient` + youtube error classes +
`ServiceFactory` + `VideoSyncBack` (write-back primitive used by publish/schedule);
only the diff-specific files go. There is no `VideoDiff` model/table to drop.

- [x] T10.1 Delete `app/jobs/bulk_video_diff_check_job.rb`. complexity: [low]
- [x] T10.2 Delete `app/jobs/video_diff_check_job.rb`. complexity: [low]
- [x] T10.3 Delete `app/services/channel/youtube/diff_computer.rb`. complexity: [low]
- [x] T10.4 Delete `app/services/channel/youtube/video_diff_apply.rb`. complexity: [low]
- [x] T10.5 Delete `app/services/channel/youtube/video_diff_persister.rb`. complexity: [low]
- [x] T10.6 Remove the `video_diff_check_bulk` recurring entry from `config/recurring.yml`. complexity: [low]
- [x] T10.7 Delete the `video_diff_detected` notification template + unregister it in `templates.rb`. complexity: [low]
- [x] T10.8 Remove `video_diff_detected` keys from the notifications locale files (none present). complexity: [low]
- [x] T10.9 Delete the diff specs under `spec/` (diff_computer, video_diff_apply/persister, video_diff_detected). complexity: [low]
- [x] T10.10 Grep `DiffComputer`/`VideoDiff`/`video_diff` for stragglers; scrub dead refs + comments. complexity: [low]
- [x] T10.11 Run `bundle exec rspec` for the channel/youtube + notifications slices; make green. complexity: [low]
- [x] T10.12 Commit: "Purge pre-reboot video-diff system". complexity: [manual]

## Phase 11 — Dynamic graded-link channel scoring (game↔channel both ways) — SUPERSEDED

> SUPERSEDED 2026-06-08 by the Recommendation v2 phases (12–16). The graded-link
> formula `K = 100·d/(d+α+β·o)` survives as the small link BONUS in Phase 15
> (α=5, β=1 confirmed), but it is no longer the whole story — channel scoring is
> now a personality-profile fit, not `max(K, GG, E)`. Do NOT execute Phase 11 as
> written; its intent lives in Phases 12–16.

North star: the **game↔game kernel stays frozen** (intrinsic facets + embedding;
locked weights; golden fixtures NEVER touched). All time-variance lives in the
two channel directions, driven by the live video corpus — recomputed on read, no
re-embedding (pure Postgres counts + already-stored vectors; zero new Voyage cost).

Replace the flat `K = LINK_SCORE (100)` hard-override with a **graded, channel-
normalized link score**:

```
K(game, channel) = 100 × d / (d + α + β·o)
  d = PUBLISHED videos on the channel linked to THIS game   (depth)
  o = PUBLISHED videos on the channel linked to OTHER games (competing breadth)
  α = depth smoothing (1 video ≠ max);  β = dilution strength
```

Locked design decisions (override before execution if needed):
- **Composition unchanged:** `score = max(K, GG, E)`, but K is now graded — a
  diluted link can legitimately lose to a strong GG similar-fit. **No floor.**
- **Dilution unit = videos** (effort-weighted), not game count.
- **Published only:** scheduled/unlisted videos do NOT count toward K.
- **Symmetric:** applies to BOTH `Game::ChannelRecommendation` (game→channel) and
  `Channel::GameRecommendation` (channel→game).
- **α/β** fitted by grid-search against user anchors — GATE: needs anchors before
  T11.15 (e.g. "Pragmata-alone ≈ 90", "lone diluted video ≈ 15", "3-video vs
  1-video home ≈ 25pt apart"). [like decision D2]

Companion engine spec: **[docs/recommendations.md](recommendations.md)**.

- [ ] T11.1 Add `DEPTH_ALPHA` (α) + `DILUTION_BETA` (β) constants to `Pito::Recommendation::Weights`. complexity: [low]
- [ ] T11.2 Add `Pito::Recommendation::LinkScore.call(depth:, other:)` returning `100·d/(d+α+β·o)`. complexity: [high]
- [ ] T11.3 Add a `Video.published` scope (privacy_status public) if missing. complexity: [low]
- [ ] T11.4 Query per-channel published-link depth/other for a target game in `Game::ChannelRecommendation`. complexity: [high]
- [ ] T11.5 Replace the flat `LINK_SCORE` K with graded `LinkScore` in `Game::ChannelRecommendation`. complexity: [high]
- [ ] T11.6 Keep `max(K, GG, E)`; remove the unconditional 100 override. complexity: [high]
- [ ] T11.7 Apply the same graded K in `Channel::GameRecommendation` (reverse direction). complexity: [high]
- [ ] T11.8 Build a diverse recommendation fixture: focused channel, broad channel, a game linked to two channels at different depths, plus unpublished videos. complexity: [high]
- [ ] T11.9 Spec: a game on a 3-video channel scores higher than the same game on a 1-video channel. complexity: [high]
- [ ] T11.10 Spec: publishing+linking a new game's videos dilutes a pre-existing game's channel score (before/after). complexity: [high]
- [ ] T11.11 Spec: unpublished (scheduled/unlisted) linked videos do NOT contribute to K. complexity: [high]
- [ ] T11.12 Spec: a diluted weak link is overtaken by a strong GG similar-fit (max composition holds). complexity: [high]
- [ ] T11.13 Spec: symmetric graded behavior in the channel→game direction. complexity: [high]
- [ ] T11.14 Spec: game↔game golden fixtures still pass unchanged (frozen-kernel regression guard). complexity: [low]
- [ ] T11.15 Grid-search α/β against the agreed anchors; lock the constants. complexity: [manual]
- [ ] T11.16 Run the recommendation specs; make green. complexity: [low]
- [ ] T11.17 Commit: "Graded video-driven channel link scoring (replaces flat 100)". complexity: [manual]

---

# Recommendation v2 — channel-personality model (Phases 12–16)

> "This is literally 50% of pito." Channels are **genre/personality buckets**
> (good / hard / fighting / survival / strategy), not homes for a single game.
> The recommendation answers: *which channel's accumulated personality does this
> game fit?* — and the reverse. game↔game stays a **static intrinsic kernel**;
> game↔channel is a **dynamic personality-profile fit** recomputed live from the
> video corpus (counts + stored vectors — zero new Voyage cost).

Locked decisions (from the design discussion, 2026-06-08):
- **D-rec-1** Channel scoring = **personality-profile fit**, NOT max-similarity to a linked game.
- **D-rec-2** Composition = profile-fit **blend** + graded-K **bonus** (α=5, β=1), not `max`.
- **D-rec-3** **Score smile**: tails >90 (elite) / <60 (bad) count far more than the 60–90 mid. **TTB smile**: ≤short and **≥150h** are extreme; ~30–40h is generic. Same-side only (both great / both bad / both long).
- **D-rec-4** Embedding is a **dynamic fallback**: weight rises only as structured facets go missing, capped so it never outranks the important signals.
- **D-rec-5** **Validation by output**: rebuild, run against the existing 7-game fixtures, REPORT recomputed numbers (game↔game once — static; game↔channel — dynamic). User confirms/adjusts; no golden input required. Reuse `spec/fixtures/recommendation_games.yml`.
- Signal priority: genre / theme / perspective (high) · score-smile · TTB-smile · developer (≈2× publisher) · publisher (least) · year+platform (shared additive slice, capped) · embedding (dynamic-minor) · explicit link (graded, small).

## Phase 12 — Signal library v2 (game-facet signal helpers)

- [x] T12.1 Add `Signals.score_smile(a, b)` — same-side extremity-amplified score similarity (>90 / <60 tails ≫ mid). complexity: [high]
- [x] T12.2 Add `Signals.ttb_smile(a_seconds, b_seconds)` — log-hours similarity, extremity-amplified (short / ≥150h tails). complexity: [high]
- [x] T12.3 Add `Signals.era(year_a, year_b)` — release-year proximity (0–100). complexity: [low]
- [x] T12.4 Add `Signals.platform_overlap(a, b)` — platform Jaccard (reuse `jaccard`). complexity: [low]
- [x] T12.5 Add a dynamic-embedding weight helper — E weight scales with facet sparsity, capped below the important signals. complexity: [high]
- [x] T12.6 Spec each helper: curve shape, tail monotonicity, same-side gating, nil/edge, cap behavior. complexity: [high]
- [x] T12.7 Commit: "Recommendation v2: signal library (score/TTB smile, era, platform, dynamic embedding)". complexity: [manual]

## Phase 13 — Kernel re-weight (game↔game) + recompute baseline

- [x] T13.1 Add TTB / release_year / platforms into the `GameSimilarity` breakdown. complexity: [high]
- [x] T13.2 Define Weights v2: genre/theme/perspective high, score-smile + TTB-smile high-at-tails, dev ≈2× pub, year+platform shared slice, embedding dynamic-minor. complexity: [high]
- [x] T13.3 Wire score→score_smile, ttb→ttb_smile, year+platform additive shared slice, dynamic E into the blend. complexity: [high]
- [x] T13.4 Recompute game↔game over the 7-game fixture; REPORT the full matrix for user confirmation. complexity: [manual]
- [x] T13.5 Re-lock the golden game↔game spec to the confirmed numbers. complexity: [high]
- [x] T13.6 Commit: "Recommendation v2: re-weighted game↔game kernel (TTB/year/platform + smiles)". complexity: [manual]

## Phase 14 — Channel personality profile

- [x] T14.1 Build `Pito::Recommendation::ChannelProfile.call(channel)` — TF-weighted aggregate per facet (genre/theme/perspective freq-weights; score band; TTB band; era; platforms; dev/pub sets; embedding centroid) over PUBLISHED-video-linked games. complexity: [high]
- [x] T14.2 Spec the reinforce property: more confirming games → higher profile weight on the shared facets. complexity: [high]
- [x] T14.3 Commit: "Recommendation v2: channel personality profile". complexity: [manual]

## Phase 15 — Channel recommendation rebuild (both directions)

- [x] T15.1 Add the graded-K link helper `K = 100·d/(d+α+β·o)` (α=5, β=1; published videos; d=this game, o=other games). complexity: [high]
- [x] T15.2 Rebuild `Game::ChannelRecommendation` = profile-fit blend (game facets vs channel profile) + graded-K bonus. complexity: [high]
- [x] T15.3 Rebuild `Channel::GameRecommendation` symmetrically (game facets vs channel profile + graded-K). complexity: [high]
- [x] T15.4 Recompute game→channel over the fixtures; REPORT numbers for user confirmation. complexity: [manual]
- [x] T15.5 Spec dilute/reinforce + the "same game, two channels, two scores" behavior on the fixtures. complexity: [high]
- [x] T15.6 Commit: "Recommendation v2: channel scoring as personality-profile fit + graded-K". complexity: [manual]

## Phase 16 — Golden scenario matrix + harden the flaky pool

- [x] T16.1 Build the exhaustive golden matrix (game↔game + game→channel) over the fixtures, locked to confirmed numbers. complexity: [high]
- [x] T16.2 Harden the order-dependent `GameSimilarity` pool/limit spec (deterministic clean slate). complexity: [high]
- [x] T16.3 Run the FULL suite to completion green (no abort, deterministic count); commit. complexity: [manual]

# Command & dispatcher unification + Lists v2 (Phases 17–24)

> The chat verb set and the `#<handle>` follow-up set are THE SAME COMMANDS from
> different locations. Unify so each command is built + sent ONE way, from one
> handler, regardless of entry. No duplication. Decisions (2026-06-08):
> Q1 YouTube write-through = YES (delete/publish/unlist/schedule write to YouTube,
> each Confirmable). Q3 resolution: free-chat by typed ref; `#<list> <verb> <ref>`
> resolves the ref AMONG that list's rows (id/title); `#<detail> <verb>` uses the
> card's entity (no ref). Q4 link/unlink autosuggested by link existence (suggest
> `link` if unlinked, `unlink` if linked). Q5 `sorted by|ordered by` = asc implicit
> / desc explicit; ERROR if the column isn't visible. Q6 heading row on EVERY
> kv-table. Q7 `import` = IGDB import only (overloaded by noun: `import game` =
> IGDB; `import videos` = YouTube). Every command's copy = **50-variant `Pito::Copy`**.
>
> Q8 DROP `resync`. Keep `reindex` = Voyage re-embed ONLY (rebuild the vector, no
> field refetch, no stats). Q9 `sync` does EVERYTHING for its target: refetch
> fields (IGDB/YouTube) + dispatch a Voyage re-embed IF embedded fields changed +
> refresh `Pito::Stats`. Q10 the bulk/background verbs (`sync …`, `import videos`)
> are **Confirmable** and publish a **single Standard "done" message on completion**
> (no up-front ack, no page refresh).
>
> **UNIVERSAL INVARIANT — EVERYTHING PRODUCES AT LEAST ONE STANDARD MESSAGE.** No
> verb is ever silent. If it resolves locally (fast) it replies with its Standard
> message immediately; if it needs a slower background job, the job broadcasts the
> Standard message when it finishes. Every handler + every job is responsible for
> emitting/publishing at least one Standard message — this is a spec assertion on
> every command.
>
> **BULK = ONE SUMMARY.** For a multi-entity verb (`sync videos`, `sync channel
> with videos`, `import videos`, any `@all` fan-out) the "at least one" is
> **exactly ONE Standard summary** message (Pito::Copy 50, with affected counts) —
> per-entity messages are SUPPRESSED. 40 affected videos → 1 message, never 40.
> (Enhanced summary is future.) Singular verbs keep their normal per-entity messages.
>
> **Pito::Copy is 1-or-50.** Every `Pito::Copy` key holds EITHER exactly 1 entry
> (single/fixed copy) OR a full ≥50-variant dictionary — nothing between. A spec
> guard enforces this across all keys (Phase Copy, built FIRST).
>
> Canonical verb + repliable-action matrix:
> - `list|ls channels|videos|games` → repliable. Allowed reply actions:
>   - channels: `visit`
>   - videos: `show`, `rm|delete`, `publish`, `unlist`, `schedule`, `reindex`, `sync`, `link`, `unlink`
>   - games: `show`, `rm|delete`, `reindex`, `sync`, `link`, `unlink`
> - `show video|game` → Standard + Enhanced (video Enhanced = Pito::Copy intro
>   placeholder for now; Analytics later). Repliable:
>   - show game: `rm|delete`, `reindex`, `sync`, `link`, `footage`
>   - show video: `rm|delete`, `publish`, `unlist`, `schedule`, `reindex`, `sync`, `link`
> - `rm|delete video|game` → Confirmable (video also deletes on YouTube)
> - `reindex video|game` → Voyage re-embed only, **Confirmable** (Phase 20)
> - `sync game|video|videos|channel|channel with videos` → Confirmable, full refresh, done-only broadcast (Phase 24)
> - `link video|game` / `unlink video|game` (autosuggested by existence)
> - `footage game` (snippet) · `import game` (IGDB sidebar → dispatch show game)
> - `import videos` (Confirmable, newer-only YouTube import, done-only broadcast)
> - `publish video` / `unlist video` (Confirmable, YouTube) · `schedule video <when>` (Confirmable, YouTube, ≥30m future)

## Phase Copy (foundation — run FIRST, before Phase 17) — Pito::Copy 1-or-50 guard

> Front-load the copy infrastructure so every later task inherits the floor. RULE:
> each `Pito::Copy` key holds EITHER exactly **1** entry (single/fixed copy) OR a
> full **≥50**-variant dictionary — nothing between. A spec guard enforces this
> across ALL keys and fails the suite on any violation; bring every existing
> dictionary key up to ≥50 now. This replaces the old end-of-run copy sweep, and
> every later phase's "50-variant Pito::Copy" task inherits this guard.

- [x] TC.1 Ensure `Pito::Copy` exposes a discoverable registry of every key (for the guard to enumerate). — DONE: `Pito::Copy::Audit.call.registered` already gives `{key, variants, single, below_standard}` per leaf under `pito.copy.*`. complexity: [high]
- [x] TC.2 Fill the 10 sub-50 dictionary offenders up to ≥50 variants (preserve each key's placeholders + tone); single-copy keys stay at 1. complexity: [high]
- [x] TC.3 Add a spec guard: each registered key's variant count is `== 1` OR `>= 50`; fail otherwise, naming the offending keys + counts. complexity: [high]
- [x] TC.4 Run the guard + suite green. complexity: [low]
- [x] TC.5 Commit. complexity: [manual]

## Phase 17 — Lists v2: N-column kv-table + headings + `with`/`sorted by` + channel scope

> Lists render via the system component's `table_rows` **kv-table** (a CSS grid of
> `KeyValueRowComponent` spans — VERIFIED: NO `<table>`), capped at 3 cols today.
> Extend to N, add a heading row, add `with <cols>` + `sorted by|ordered by` to
> `list games`/`list videos`, scope `list games` by the shift+tab channel.
> Discard the prior one-shot grid attempt. Repliable actions on these lists are
> wired by the unified handler (Phases 18–19).
>
> SCOPE (discovered + decided 2026-06-08): today only `list games` is a kv-table;
> `list videos` is a separate `Video::ListComponent` grid (migrate it — T17.1b) and
> `list channels` is rich avatar cards (`Channel::ListComponent`). **Channels STAY
> avatar cards** — the kv-table machinery (heading/`with`/`sorted by`) applies to
> **games + videos only**. So "every kv-table" = games + videos.

- [x] T17.1 Extend `table_rows` + the system component to render N ordered cells per row; keep 2/3-col back-compat. complexity: [high]
- [x] T17.1b Migrate `list videos` onto the kv-table (`table_rows`), replacing the separate `Video::ListComponent` grid. Base columns: title, `@handle` (cyan), privacy, `#id` (for follow-up). complexity: [high]
- [x] T17.2 Add a heading row to the kv-table lists — **games + videos only** (channels stay avatar cards, see T17.7). complexity: [low]
- [x] T17.3 Extract `Pito::Video::DurationFormat` (`H:MM:SS`/`M:SS`: 9:34 / 1:02:22 / 43:23 / 1:00:32); reuse in `Video::DetailComponent`. complexity: [low]
- [x] T17.4 Shared `with <cols>` parser: magic word `with`, comma enumerator (`,` and `, `, split `/\s*,\s*/`), order-preserving, dedup, unknown-ignored. complexity: [high]
- [x] T17.5 `list games with` → columns: platform, genre, developer, publisher, release date, year (release date + year are TWO columns). complexity: [high]
- [x] T17.6 `list videos with` → columns: game, duration, views, likes, comments (counts via Stats; `@handle` cyan; duration via DurationFormat). complexity: [high]
- [x] T17.7 `list channels` — STAYS avatar cards (`Channel::ListComponent`), the kv-table exception: NO kv-table, NO heading row, NO `with`/`sorted by` (decided 2026-06-08). Ignore/reject any such clause. complexity: [low]
- [x] T17.8 `sorted by|ordered by <col> [asc|desc]` — asc implicit; desc explicit; ERROR when the column isn't VISIBLE. complexity: [high]
- [x] T17.9 `list games` channel scope from the shift+tab `channel` param (`@all`/none → all; `@handle` → games with ≥1 video on that channel). complexity: [high]
- [x] T17.10 Stamp the list messages that HAVE follow-up handlers: `game_list` + `channel_list` are already stamped (handlers exist). `video_list` stamping is DEFERRED to Phase 19 — it has no follow-up handler yet, and stamping now would render a dangling reply handle (router finds the event, but the controller's Registry lookup for `video_list` would miss). Decided 2026-06-08. complexity: [low]
- [x] T17.11 Autosuggest: after `with ` → per-list columns; after `sorted by`/`ordered by ` → the visible columns. complexity: [high]
- [x] T17.12 Specs: N-col kv-table + heading row, both `with` sets, channels-excluded, sort (asc/desc + not-visible error), list-games channel scope, duration format, autosuggest. — built incrementally per task (system_component, game/video list_columns, sort_clause, list_clause_ghost, handler scope/sort/combination, duration_format). complexity: [high]
- [x] T17.13 Run the new specs; make green. — full suite 3905 green. complexity: [low]
- [x] T17.14 Commit: "Lists v2: N-col kv-table + headings + `with`/`sorted by` + list-games channel scope". — landed incrementally (commit-after-every-task); this closes the phase. complexity: [manual]

## Phase 18 — Unified dispatch: one handler interprets chat ≡ #hashtag

> A verb handler interprets BOTH free-chat (`show game X`) and a `#<handle>` reply
> (`#<handle> show X`) → SAME parsed command, SAME handler, SAME built + sent
> events. No duplicated handler logic, no extra "core" class (the verb handler IS
> the orchestrator; the follow-up reuses it). Resolution (Q3): free-chat by typed
> ref; `#<list> <verb> <ref>` resolves the ref among the list message's rows
> (id/title); `#<detail> <verb>` uses the card's entity (no ref).

- [x] T18.1 Give each verb handler a unified entry accepting EITHER a free-chat message OR a follow-up context (`{ source_event, rest }`). complexity: [high]
- [x] T18.2 Resolution: free-chat → typed ref; list context → ref resolved among the list message's row ids/titles; detail context → the card's entity (no ref). complexity: [high]
- [x] T18.3 Result adapter: map a verb handler's `Chat::Result::Ok` events → `FollowUp::Result::Append` (Confirmable verbs → confirmation event) so one handler serves both paths. complexity: [high]
- [x] T18.4 Follow-up dispatch: after resolving the live event + handle, hand `<verb> <rest>` to the matching verb handler with the context. complexity: [high]
- [x] T18.5 Gate allowed reply actions per message to the canonical matrix (channels: visit; videos: show/rm/publish/unlist/schedule/resync/link/unlink; games: show/rm/resync/link/unlink; show game: rm/resync/link/footage; show video: rm/publish/unlist/schedule/resync/link). — gating enforced in VerbDelegator via `Registry.actions_for(reply_target)`; the per-target action lists get set to the canonical matrix as handlers migrate (T19). complexity: [high]
- [ ] T18.6 Spec: free-chat and `#<handle>` produce IDENTICAL built+sent events for a representative verb (per resolution mode). complexity: [high]
- [ ] T18.7 Commit. complexity: [manual]

## Phase 19 — Migrate show / show video / delete / link / unlink onto the unified handler

> Collapse the duplicated follow-up actions onto the verb handlers (Phase 18),
> then DELETE the reimplementations. `show video` now emits Standard + Enhanced
> (Enhanced = `Pito::Copy` intro placeholder — Analytics later).

- [ ] T19.1 `show game` (verb + `game_list` show) → one handler, Standard + Enhanced. complexity: [high]
- [ ] T19.2 `show video` (verb + `video_list` show) → one handler, Standard + Enhanced (Enhanced = `Pito::Copy` intro placeholder). complexity: [high]
- [ ] T19.2b Stamp `list videos` follow-up-able (`reply_target: "video_list"`) NOW that the `video_list` handler exists (deferred from T17.10); flip the video/list builder + its "NOT follow-up-able" spec. complexity: [low]
- [ ] T19.3 `delete|rm game|video` (verb + `game_list` delete + `game_detail` rm) → one handler (Confirmable). complexity: [high]
- [ ] T19.4 `link game|video` (verb + `game_detail` link) → one handler. complexity: [high]
- [ ] T19.5 `unlink game|video` (verb + new detail/list action) → one handler. complexity: [high]
- [ ] T19.6 Autosuggest `link` vs `unlink` by link existence (offer the one that applies). complexity: [high]
- [ ] T19.7 Delete the dead duplicated resolve/build logic from the follow-up handlers. complexity: [high]
- [ ] T19.8 50-variant `Pito::Copy` for any new/changed outcome lines. complexity: [low]
- [ ] T19.9 Specs: chat ≡ `#<handle>` identical for show / show video / delete / link / unlink. complexity: [high]
- [ ] T19.10 Commit. complexity: [manual]

## Phase 20 — `reindex` (Voyage re-embed only); drop `resync`

> Keep ONLY `reindex` as the narrow Voyage op: force-rebuild a game/video vector in
> Voyage, regardless of whether fields changed (use when the embedding model or the
> embed text changed). NO IGDB/YouTube refetch, NO `Pito::Stats` — the full refresh
> lives in `sync` (Phase 24). Drop the `resync` verb/alias entirely. **Confirmable.**

- [ ] T20.1 Keep `reindex <game|video> <ref>` as the Voyage re-embed verb; remove the `resync` verb/alias + its grammar. complexity: [high]
- [ ] T20.2 Confirmable: emit a confirmation event; on confirm, enqueue the Voyage re-embed. complexity: [high]
- [ ] T20.3 Point the existing follow-up `reindex` actions (`game_enhanced` / `video_detail`) at the unified handler; delete any `resync` follow-up action. complexity: [high]
- [ ] T20.4 50-variant `Pito::Copy` for the reindex confirm + outcome. complexity: [low]
- [ ] T20.5 Specs: confirm → reindex enqueues the Voyage re-embed; `resync` is gone; chat ≡ `#<handle>`. complexity: [high]
- [ ] T20.6 Commit. complexity: [manual]

## Phase 21 — YouTube write-through: delete / publish / unlist / schedule (Confirmable)

> REVERSES the earlier local-only choice (T4.13). Each Confirmable, each writes to
> YouTube for real via the existing `VideoSyncBack` / `VideosClient` primitives:
> `delete|rm video` → destroy locally AND `videos.delete` on YouTube (Pito::Copy
> MUST state it deletes on YouTube); `publish video` → public on YouTube now;
> `unlist video` → unlisted on YouTube; `schedule video <when>` → private +
> `publishAt` on YouTube, `<when>` must be ≥ 30 minutes in the future (else error).

- [ ] T21.1 `delete video` executor: destroy locally + `videos.delete` on YouTube; copy says so. complexity: [high]
- [ ] T21.2 `publish video` → Confirmable; executor sets public locally + pushes privacy to YouTube. complexity: [high]
- [ ] T21.3 `unlist video` → Confirmable; executor sets unlisted locally + pushes to YouTube. complexity: [high]
- [ ] T21.4 `schedule video <when>` → Confirmable; validate `<when>` ≥ 30m future; set private + publishAt locally + push to YouTube. complexity: [high]
- [ ] T21.5 50-variant `Pito::Copy` for each confirm + outcome (delete/publish/unlist/schedule) — delete copy states YouTube deletion. complexity: [low]
- [ ] T21.6 Specs: each writes through (stub the YouTube client), ≥30m guard, confirm flow, chat ≡ `#<handle>`. complexity: [high]
- [ ] T21.7 Commit. complexity: [manual]

## Phase 22 — `import game` (IGDB sidebar → dispatch `show game`) + `footage` only

> `/games import` becomes the chat verb **`import game`**: opens the existing IGDB
> search Sidebar; on completion it DISPATCHES THE `show game` EVENT (unified
> Standard + Enhanced) — it must NOT reimplement those messages. `import` now means
> IGDB import, so the footage action is **`footage` only** (drop `import` alias).

- [ ] T22.1 `import game` verb → opens the IGDB search Sidebar (reuse the current one). complexity: [high]
- [ ] T22.2 On import completion, dispatch the unified `show game` event (Standard + Enhanced); delete any reimplemented post-import message. complexity: [high]
- [ ] T22.3 Rename the footage action/verb to `footage` only; drop `import` as its alias (grammar + copy + follow-up). complexity: [high]
- [ ] T22.4 Specs: import-complete dispatches `show game` (identical events); `footage` snippet still works; `import` no longer triggers footage. complexity: [high]
- [ ] T22.5 Commit. complexity: [manual]

## Phase 23 — Cleanup: unify `/themes preview|apply`, drop `similar`, Pito::Copy 50-variant sweep

> `/themes preview|apply` (slash, `slash/handlers/theme.rb`) and the `theme_list`
> follow-up `preview`/`apply` both persist `AppSetting.theme` + broadcast — UNIFY
> onto one path. `similar` is DROPPED + cleaned. Every command's copy = a
> 50-variant `Pito::Copy` dictionary — audit + fill gaps.

- [ ] T23.1 Extract the theme preview/apply logic into one path; point both the `/themes` slash and the `theme_list` follow-up at it. complexity: [high]
- [ ] T23.2 Drop the `similar` follow-up action (`game_enhanced`) + its copy/specs; scrub references. complexity: [high]
- [ ] T23.3 Final copy check: the Phase Copy guard is green across ALL commands (every key 1-or-≥50); fill any remaining gaps. complexity: [low]
- [ ] T23.4 Specs: themes preview/apply identical via both entries; `similar` gone; copy audit green. complexity: [high]
- [ ] T23.5 Commit. complexity: [manual]

## Phase 24 — `sync` family (full refresh) + `import videos`; Confirmable, done-only broadcast

> `sync` does EVERYTHING for its target: refetch fields from IGDB (game) / YouTube
> (video, channel), then — IF indexable (embedded) fields changed — **dispatch the
> `reindex` op** for that entity (reuse it; do NOT re-embed inline), AND refresh
> `Pito::Stats` (views/likes/comments for videos; subscribers/views for channels).
> Message count follows from this: **indexable fields changed → ≥2 Standard
> messages** (one from `sync`, one from the dispatched `reindex`); **only
> `Pito::Stats` changed → 1 Standard message** now (possibly +1 Enhanced later);
> nothing changed → still 1 Standard message (the invariant). Every form is
> **Confirmable** and runs in the BACKGROUND, publishing its Standard **"done"**
> result on completion (no up-front ack, no page refresh — "everything produces and
> publishes"). Scope by the shift+tab channel
> (`@all`/none → all connected channels; `@<handle>` → that one). `import videos`
> is the YouTube import (vs `import game` = IGDB sidebar, Phase 22). 50-variant
> `Pito::Copy`. Forms:
> - `sync game <ref>` — IGDB fields + conditional Voyage re-embed.
> - `sync video <ref>` — YouTube fields + conditional Voyage re-embed + `Pito::Stats`.
> - `sync videos [scope]` — full sync of every video on the scoped channel(s).
> - `sync channel [scope]` — channel fields + `Pito::Stats` for the scoped channel(s).
> - `sync channel with videos [scope]` — the channel AND all its videos.
> - `import videos [scope]` — import only NEWER videos from YouTube for the scoped channel(s).

- [ ] T24.1 `sync game|video <ref>` verb → Confirmable; executor refetches fields, dispatches `reindex` IFF indexable fields changed (≥2 Standard msgs), + (video) `Pito::Stats` (stats-only → 1 Standard msg). complexity: [high]
- [ ] T24.2 `sync videos [scope]` → Confirmable; full sync of every video on the scoped channel(s). complexity: [high]
- [ ] T24.3 `sync channel [scope]` → Confirmable; channel fields + `Pito::Stats` for the scoped channel(s). complexity: [high]
- [ ] T24.4 `sync channel with videos [scope]` → Confirmable; channel + all its videos. complexity: [high]
- [ ] T24.5 `import videos [scope]` → Confirmable; import NEWER-only YouTube videos for the scoped channel(s). complexity: [high]
- [ ] T24.6 Resolve the shift+tab channel scope (`@all`/none → all connected; `@<handle>` → that one). complexity: [high]
- [ ] T24.7 Background execution publishes EXACTLY ONE Standard summary message on completion (via `Pito::Stream::Broadcaster`) with affected counts — per-entity messages SUPPRESSED in bulk (40 videos → 1 message); no up-front ack. complexity: [high]
- [ ] T24.8 50-variant `Pito::Copy` for each verb's confirm + done message. complexity: [low]
- [ ] T24.9 Specs: each verb confirms → enqueues the right job for the scope; the job broadcasts the done message; chat ≡ `#<handle>`. complexity: [high]
- [ ] T24.10 Commit. complexity: [manual]

---

## Help A — `/help` for commands (keep) — TO DISCUSS

> Placeholder. Flesh out when we reach this phase.

We keep the existing `/help` as the entry point for the **slash command**
surface — it should list/explain the available commands (including the new
Video + Game verbs from Phases 4–7). Scope, format, and per-command detail TBD.

- [ ] (tasks TBD after discussion)

## Help B — `#help` + `help` for hashtags & free messages — TO DISCUSS

> Placeholder. Flesh out when we reach this phase.

Two more help affordances beyond `/help`:

- `#help` — surfaces the **hashtag** possibilities (what `#<handle>` follow-ups
  and hashtag messages can do).
- `help` (bare, free message) — guidance for **free-text** messages (what a
  plain chat message does / how to get started).

Exact triggers, copy, and how these relate to `/help` are TBD.

- [ ] (tasks TBD after discussion)

---

## Follow-ups — re-evaluate at the end (after Phases 18–24)

- [ ] **`kind:` String → Symbol.** The follow-up handlers + `chat/handlers/delete.rb`
  self-heal via Phase 19 (rewritten as thin shims onto the symbol-using verb
  handlers). Re-evaluate the LEFTOVERS and either normalise to symbols in one
  focused commit or accept the split: `chat_controller` (8× `kind: "error"`), the
  slash handlers (`config`/`disconnect`/`games`/`help`/`theme`), `themes/switch`,
  `lib/pito/slash/{handler,help_renderer}`. (NOT `client_kind:`, the stats
  `kind: "views"`, search `error: { kind: }`, or `where(kind: "…")` queries —
  different `kind` concepts.) `Event` normalises `:kind` on save, so it's a style
  split, not a bug.
- [ ] **Help surface — `/help`, `#help`, bare `help`** (Help A / Help B above).
  Design the unified help once the verb + repliable-action matrix is final
  (Phases 18–24 done): what each entry lists, where the copy lives, how it stays in
  sync with the grammar/registry.
