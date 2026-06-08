# Videos domain: commands, sync, reindex, recommendations

> Status: Drafting — not signed off. Implementation waits for explicit go-ahead.

## Sign-off

- [x] Drafted
- [ ] Audited

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

- **D1 — Video columns to drop (Phase 2).** "Keep only title, description, tags,
  thumbnail" is read as: keep those 4 **content** fields plus the **operational**
  columns the new features require (`channel_id`, `youtube_video_id`,
  `privacy_status`, `publish_at`, `published_at`, `last_synced_at`,
  `summary_embedding`, `embedded_digest`, `search_vector`). **Drop:** `category_id`,
  `comment_count`, `like_count`, `duration_seconds`, `etag`. Views/likes/comments
  live in `Pito::Stats`, not on the row. Confirm the drop set.
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
- Phase 2 — Slim the Video model (task 4)
- Phase 3 — Reindex messages + follow-up for channel & game (tasks 1, 2)
- Phase 4 — Video verbs: show / delete / publish / schedule / unlist (task 5)
- Phase 5 — Game↔Video link both directions (tasks 5 link, 6)
- Phase 6 — `list games upcoming [genres] [platforms]` (task 9)
- Phase 7 — `list videos published|unlisted` scoped by shift+tab channel (task 10)
- Phase 8 — Nightly: Video stats sync + Game upcoming-only refresh (tasks 7, 8)
- Phase 9 — Intraday Video stats cadence (task 11) [decision D2]
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

## Phase 2 — Slim the Video model (task 4) [decision D1]

- [ ] T2.1 Write a reversible migration dropping `category_id`, `comment_count`, `like_count`, `duration_seconds`, `etag` from `videos`. complexity: [low]
- [ ] T2.2 Remove dropped attributes from `app/models/video.rb` (validations, scopes, methods). complexity: [high]
- [ ] T2.3 Remove dropped fields from `Video::Sync` / `ImportVideosJob` YouTube mapping. complexity: [high]
- [ ] T2.4 Remove dropped fields from `app/services/video/embed_text.rb` if referenced. complexity: [low]
- [ ] T2.5 Confirm `Video::EmbedText` uses only title + description + tags. complexity: [low]
- [ ] T2.6 Remove dropped fields from any video view/component. complexity: [low]
- [ ] T2.7 Update video factory + specs to the slim column set. complexity: [high]
- [ ] T2.8 Reindex one video locally to confirm the embed text is unchanged. complexity: [low]
- [ ] T2.9 Run `bundle exec rspec` for video model/job/component specs; make green. complexity: [low]
- [ ] T2.10 Commit: "Slim Video to title/description/tags/thumbnail + operational fields". complexity: [manual]

## Phase 3 — Reindex messages + follow-up (tasks 1, 2)

- [ ] T3.1 Add a `reindex channel <ref>` grammar spec entry mirroring game reindex. complexity: [high]
- [ ] T3.2 Add a `reindex video <ref>` grammar spec entry. complexity: [high]
- [ ] T3.3 Add reindex copy keys for channel + video to `config/locales/pito/copy/en.yml`. complexity: [low]
- [ ] T3.4 Add a `confirm_channel_reindex` branch to `Pito::Confirmation::Executor`. complexity: [high]
- [ ] T3.5 Add a `confirm_video_reindex` branch to `Pito::Confirmation::Executor`. complexity: [high]
- [ ] T3.6 Broadcast a reindex result message for channel via `Pito::Stream::Broadcaster`. complexity: [high]
- [ ] T3.7 Broadcast a reindex result message for video. complexity: [high]
- [ ] T3.8 Add a reindex follow-up handler entry for channel messages. complexity: [high]
- [ ] T3.9 Add a reindex follow-up handler entry for video messages. complexity: [high]
- [ ] T3.10 Add specs for channel + video reindex confirm + follow-up. complexity: [high]
- [ ] T3.11 Run the new specs; make green. complexity: [low]
- [ ] T3.12 Commit: "Add reindex messages + follow-up for channel and video". complexity: [manual]

## Phase 4 — Video verbs: show / delete / publish / schedule / unlist (task 5)

- [ ] T4.1 Add `show video <ref>` grammar spec entry. complexity: [high]
- [ ] T4.2 Implement `show video` in `app/services/pito/chat/handlers/show.rb`. complexity: [high]
- [ ] T4.3 Build a `Pito::MessageBuilder::Video::Detail` payload. complexity: [high]
- [ ] T4.4 Build a `Pito::Video::DetailComponent` (title/description/tags/thumbnail + stats). complexity: [high]
- [ ] T4.5 Add `delete|rm video <ref>` grammar + confirm branch. complexity: [high]
- [ ] T4.6 Implement `delete video` in `handlers/delete.rb` with confirmation. complexity: [high]
- [ ] T4.7 Add `publish video <ref>` grammar entry. complexity: [low]
- [ ] T4.8 Implement `publish video` (set `privacy_status: public`, clear `publish_at`). complexity: [high]
- [ ] T4.9 Add `unlist video <ref>` grammar entry. complexity: [low]
- [ ] T4.10 Implement `unlist video` (set `privacy_status: unlisted`). complexity: [high]
- [ ] T4.11 Add `schedule video <ref> <when>` grammar entry with a time vocabulary. complexity: [high]
- [ ] T4.12 Implement `schedule video` (set `privacy_status: private` + `publish_at`). complexity: [high]
- [ ] T4.13 Decide write-through: confirm whether publish/schedule/unlist call YouTube or local-only. complexity: [manual]
- [ ] T4.14 Add copy keys for each video verb result. complexity: [low]
- [ ] T4.15 Add specs for show/delete/publish/schedule/unlist. complexity: [high]
- [ ] T4.16 Run the new specs; make green. complexity: [low]
- [ ] T4.17 Commit: "Add Video verbs: show, delete, publish, schedule, unlist". complexity: [manual]

## Phase 5 — Game↔Video link both directions (tasks 5 link, 6)

- [ ] T5.1 Add `link video <ref> <game-ref>` grammar entry. complexity: [high]
- [ ] T5.2 Add `link game <ref> <video-ref>` grammar entry. complexity: [high]
- [ ] T5.3 Implement video→game linking in `handlers/link.rb` (find-or-create `VideoGameLink`). complexity: [high]
- [ ] T5.4 Implement game→video linking in `handlers/link.rb` (same row, reversed args). complexity: [high]
- [ ] T5.5 Add `unlink` support for both directions in `handlers/unlink.rb`. complexity: [high]
- [ ] T5.6 Register video + game actions in `config/initializers/pito_actions.rb` (scopes `:videos`/`:games`). complexity: [high]
- [ ] T5.7 Add link/unlink result copy keys. complexity: [low]
- [ ] T5.8 Add specs for link/unlink both directions + idempotency. complexity: [high]
- [ ] T5.9 Run the new specs; make green. complexity: [low]
- [ ] T5.10 Commit: "Add bidirectional game↔video link verb + actions". complexity: [manual]

## Phase 6 — `list games upcoming [genres] [platforms]` (task 9)

- [ ] T6.1 Widen the PLATFORMS vocabulary so `ps` maps to ALL PlayStation tokens (PS5 + PS4). complexity: [high]
- [ ] T6.2 Add a genre vocabulary alias set if missing (rpg/action/etc → canonical). complexity: [low]
- [ ] T6.3 Add a `list games [upcoming] [genres…] [platforms…]` grammar entry (order-independent, `upcoming` optional). complexity: [high]
- [ ] T6.4 Add an `upcoming?` scope to `Game` (release date in the future / unreleased). complexity: [high]
- [ ] T6.5 Implement `list games` filtering in `handlers/list.rb` (genre AND platform AND optional upcoming). complexity: [high]
- [ ] T6.6 Resolve platform filter tokens through the widened mapping (match any synonym). complexity: [high]
- [ ] T6.7 Build a games-list message/component (no pagination, list all). complexity: [high]
- [ ] T6.8 Add copy keys for the games list + empty state. complexity: [low]
- [ ] T6.9 Add specs: upcoming-only, genre filter, platform mapping (ps matches PS5 + PS4), combined, order-independent. complexity: [high]
- [ ] T6.10 Run the new specs; make green. complexity: [low]
- [ ] T6.11 Commit: "Add list games upcoming with genre + platform mapping". complexity: [manual]

## Phase 7 — `list videos published|unlisted` by shift+tab channel (task 10)

- [ ] T7.1 Add a `list videos [published|unlisted]` grammar entry. complexity: [high]
- [ ] T7.2 Read the shift+tab channel from the request `channel` param in `ChatController`. complexity: [high]
- [ ] T7.3 Resolve `@all` → all channels; `@handle` → that channel only. complexity: [high]
- [ ] T7.4 Implement `list videos` filtering in `handlers/list.rb` by privacy_status + channel scope (local only). complexity: [high]
- [ ] T7.5 Build a videos-list message/component (no pagination, list all). complexity: [high]
- [ ] T7.6 Add copy keys for the videos list + empty state. complexity: [low]
- [ ] T7.7 Add specs: @all lists all, @handle scopes to one channel, published vs unlisted filter. complexity: [high]
- [ ] T7.8 Run the new specs; make green. complexity: [low]
- [ ] T7.9 Commit: "Add list videos published/unlisted scoped by channel". complexity: [manual]

## Phase 8 — Nightly: Video stats sync + Game upcoming-only (tasks 7, 8)

- [ ] T8.1 Add a `Pito::Stats` views snapshot step to `NightlyVideoSyncJob` (per video). complexity: [high]
- [ ] T8.2 Confirm the nightly stats snapshot runs under the 01:00 UTC fan-out (`NightlySyncJob`). complexity: [low]
- [ ] T8.3 Add an `upcoming` (unreleased) filter to `GameIgdbNightlyRefresh`. complexity: [high]
- [ ] T8.4 Limit the nightly Game refresh to upcoming/unreleased games only. complexity: [high]
- [ ] T8.5 Add specs for the nightly video stats snapshot + game upcoming-only filter. complexity: [high]
- [ ] T8.6 Run the new specs; make green. complexity: [low]
- [ ] T8.7 Commit: "Nightly: snapshot video stats + refresh only upcoming games". complexity: [manual]

## Phase 9 — Intraday Video stats cadence (task 11) [decision D2]

- [ ] T9.1 Add recurring entries for video stats at 09:00 and 17:00 UTC in `config/recurring.yml`. complexity: [low]
- [ ] T9.2 Extract the video-stats snapshot into a job callable by all three slots. complexity: [high]
- [ ] T9.3 Add a YouTube quota guard / batch (≤50 ids per `videos.list` call). complexity: [high]
- [ ] T9.4 Add specs for the intraday stats job + batching. complexity: [high]
- [ ] T9.5 Run the new specs; make green. complexity: [low]
- [ ] T9.6 Commit: "Add 3×/day video stats snapshot (01:00 / 09:00 / 17:00 UTC)". complexity: [manual]

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
