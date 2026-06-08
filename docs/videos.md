# Videos domain: commands, sync, reindex, recommendations

> Status: Signed off 2026-06-08 — executing on `beta-videos`. Phases 1/10/2/3/4/5/6/7/8/9 DONE. Phase 11 SUPERSEDED. **Recommendation v2 (Phases 12–16) is the active workstream** — channel-personality model; validated by reporting recomputed numbers on the 7-game fixtures. D2 resolved → 3×/day.

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
- Phase 17 — Polish: `list videos` UI (column alignment, optional `add` columns, follow-up `show video`)
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

- [ ] T15.1 Add the graded-K link helper `K = 100·d/(d+α+β·o)` (α=5, β=1; published videos; d=this game, o=other games). complexity: [high]
- [ ] T15.2 Rebuild `Game::ChannelRecommendation` = profile-fit blend (game facets vs channel profile) + graded-K bonus. complexity: [high]
- [ ] T15.3 Rebuild `Channel::GameRecommendation` symmetrically (game facets vs channel profile + graded-K). complexity: [high]
- [ ] T15.4 Recompute game→channel over the fixtures; REPORT numbers for user confirmation. complexity: [manual]
- [ ] T15.5 Spec dilute/reinforce + the "same game, two channels, two scores" behavior on the fixtures. complexity: [high]
- [ ] T15.6 Commit: "Recommendation v2: channel scoring as personality-profile fit + graded-K". complexity: [manual]

## Phase 16 — Golden scenario matrix + harden the flaky pool

- [ ] T16.1 Build the exhaustive golden matrix (game↔game + game→channel) over the fixtures, locked to confirmed numbers. complexity: [high]
- [ ] T16.2 Harden the order-dependent `GameSimilarity` pool/limit spec (deterministic clean slate). complexity: [high]
- [ ] T16.3 Run the FULL suite to completion green (no abort, deterministic count); commit. complexity: [manual]

## Phase 17 — Polish: `list videos` UI (AFTER Recommendation v2)

> Deferred until Phases 12–16 ship. Bring the `list videos` message to `list
> games` parity and make it interactive.

Requirements (from the user, with screenshot):
- **Column alignment** — render rows in an aligned grid / KV-table like the games
  list (today they're a ragged `#id title @handle privacy` line). The KV-table
  must be able to **expand to more columns** when extra ones are requested.
- **`@handle` cyan** — the channel handle renders in cyan (matches the meta-line
  channel colour), not the default fg.
- **Follow-up-able** — stamp the list message follow-up-able (`reply_target:
  "video_list"`) and add a `Pito::FollowUp::Handlers::VideoList` with a `show`
  action so `#<handle> show video <id|title>` opens the video detail (mirrors the
  game list's `#<handle> show <id>`).
- **Optional columns via `add`** — `list videos … add <col> [<col> …]` appends
  columns to the table, chosen from: **game** (linked game title), **duration**,
  **views**, **likes**, **comments** (the last three from `Pito::Stats`). One or
  more columns; order as typed.
- **Autosuggestions** — the `add` keyword offers the column names
  (game/duration/views/likes/comments) as tab-completable suggestions (wire a
  column vocabulary into the suggestions catalog).
- **Duration format** — `H:MM:SS` / `M:SS` (e.g. `9:34`, `1:02:22`, `43:23`,
  `1:00:32`). Reuse / extract the existing `Pito::Video::DetailComponent`
  duration formatter into a shared helper.

- [ ] T17.1 Extract the duration formatter (`H:MM:SS`/`M:SS`) from `Video::DetailComponent` into a shared helper. complexity: [low]
- [ ] T17.2 Rebuild the videos-list component as an aligned, expandable KV-table grid (parity with the games list). complexity: [high]
- [ ] T17.3 Render the `@handle` in cyan. complexity: [low]
- [ ] T17.4 Stamp the list message follow-up-able (`reply_target: "video_list"`). complexity: [low]
- [ ] T17.5 Add `Pito::FollowUp::Handlers::VideoList` with a `show` action → `#<handle> show video <id|title>` opens the video detail. complexity: [high]
- [ ] T17.6 Parse `list videos … add <columns>` (game/duration/views/likes/comments, one+; order preserved). complexity: [high]
- [ ] T17.7 Render the requested extra columns in the expanded KV-table (counts via `Pito::Stats`). complexity: [high]
- [ ] T17.8 Add a column vocabulary to the suggestions catalog so `add ` tab-completes the column names. complexity: [high]
- [ ] T17.9 Add specs: alignment/columns, `@handle` cyan, follow-up `show video`, duration format, `add` parsing + autosuggest. complexity: [high]
- [ ] T17.10 Run the new specs; make green. complexity: [low]
- [ ] T17.11 Commit: "Polish list videos: aligned KV-table, add-columns, show-video follow-up". complexity: [manual]

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
