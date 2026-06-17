# Pito chat-UI, jobs & cover-art consolidation

> Status: draft

## Sign-off

- [x] Drafted — 2026-06-16
- [x] Audited — 2026-06-17

## Context

A batch of independent improvements gathered in one session: make local
SolidQueue recurring jobs actually run under `bin/dev`; fix `sync` chat
autosuggest; tighten the `list channels` result item; move message timestamps
inline (more compact transcript); inline the game-card id with its title; and
shrink all game cover art to 75% with a clean regenerate. Each area is
self-contained and lands in its own phase so the branch stays green throughout.

## North star

After this plan: `bin/dev` runs the jobs worker so nightly recurring jobs fire
locally; typing `sy`/`sync` suggests the verb and its `channels`/`videos`
targets; `list channels` items show one-line `·`-separated stats with a yellow
linked `@handle` and no `[view]`; every timestamped message shows a 24H
`HH:MM ·` prefix on its first line; game cards read `#12 · Elden Ring`; and all
cover art is 75% size, regenerated, with no orphaned blobs.

## Locked decisions

| Topic | Decision |
| --- | --- |
| Local jobs runner | Add `jobs: bin/jobs` to `Procfile.dev` (separate process, not `SOLID_QUEUE_IN_PUMA`). |
| Timestamp scope | Only the 7 types already showing a timestamp (echo, system, enhanced, system_follow_up, enhanced_follow_up, confirmation, theme_diff). `thinking`/`error`/`confirmation_follow_up` unchanged. |
| Timestamp format | 24H `%H:%M` (zero-padded), rendered as a `HH:MM ·` prefix leading the first content line. Keep dim `text-fg-faded`; distinct from message color. |
| Timestamp structure | Extract timestamp out of `MetaLineComponent` into an inline prefix; `MetaLineComponent` keeps only handle/channel footer. |
| `sync` suggestions | Grammar `:sync` slot → `kind: :enum` over a `:sync_targets` vocab (`channels`, `videos`); add free-form verb prefix completion (server + client) mirroring slash mode. |
| `list channels` stats | Three stat rows → one flex line `subs · videos · views`, `text-fg-dim`, `·` separators. |
| `list channels` handle | `@handle` becomes a yellow `<a>` to the YouTube URL; remove the `[view]` link. Gated to list-channels via a new flag; `show game` enhanced item unchanged. |
| Game card id+title | `#id · title` on one inline line; id keeps `text-fg-faded`, title keeps `text-fg` + truncation. Applies to EnhancedComponent similar-game cards. |
| Cover art size | Master 600×800 → 450×600 (`normalizer.rb`); variant 240×320 → 180×240 (`game.rb`); CSS 240/320 → 180/240. Regenerate every game with a cover; purge orphaned blobs/variants. |
| `list` unknown noun | A leading `list <token>` where token isn't channels/videos/games or a games filter → unknown-target error/help, not a silent games list. |

## Complexity hints

| Hint | Meaning |
| --- | --- |
| `[manual]` | Operator by hand: smoke tests, data regeneration/purge, commits. |
| `[low]` | Mechanical / pattern-following single- or multi-file edits. |
| `[high]` | Grammar/DSL, shared-component variant design, typewriter interaction, irreversible data tooling. |

## Phase index

- P0 — Dev jobs runner
- P1 — `sync` chat autosuggest
- P2 — `list channels` item redesign
- P3 — Inline first-line timestamp
- P4 — Game card id·title inline
- P5 — Cover-art 75% resize + regenerate
- P6 — Reject unknown `list` nouns

## P0 — Dev jobs runner

- [x] T0.1 Add `jobs: bin/jobs` line to `Procfile.dev`. complexity: [low]
- [ ] T0.2 Run `bin/dev`; confirm the `jobs.1` process boots and `solid_queue_recurring_tasks` gets populated (`cleanup_notifications`, `game_igdb_nightly_refresh`). complexity: [manual]
- [ ] T0.3 Commit: `Run SolidQueue worker under bin/dev`. complexity: [manual]

## P1 — `sync` chat autosuggest

- [x] T1.1 Add a `:sync_targets` vocabulary (`channels`, `videos`) in `lib/pito/grammar/vocabularies.rb`. complexity: [low]
- [x] T1.2 Change the `:sync` spec slot in `lib/pito/grammar/specs.rb` (~109-114) from `kind: :free` to `kind: :enum, source: :sync_targets`. complexity: [high]
- [x] T1.3 Add free-form verb prefix completion in `app/services/pito/suggestions/engine.rb` (mirror slash `verb_stage_completions` ~115-125 inside `free_completions` ~556-572). complexity: [high]
- [x] T1.4 Add the client-side free-form verb prefix fallback in `app/javascript/controllers/pito/suggestions_controller.js` (`_computeLocalGhost`/`_findChatSpec`, ~583-663). complexity: [high]
- [x] T1.5 Add suggestion specs: `sy` → `sync`; after `sync ` → `channels`/`videos`. complexity: [low]
- [x] T1.6 Run `node --check` on `suggestions_controller.js`. complexity: [low]
- [ ] T1.7 Commit: `Autosuggest sync verb and its channel/video targets`. complexity: [manual]

## P2 — `list channels` item redesign

- [x] T2.1 Add a list-channels mode flag (e.g. `handle_link:`/`stats_inline:`) to `Pito::Channel::ItemComponent` (`item_component.rb`), defaulting to current behavior. complexity: [high]
- [x] T2.2 Collapse the three stat rows (`item_component.html.erb` ~45-57) into one flex line `subs · videos · views`, `text-fg-dim`, `·` separators. complexity: [low]
- [x] T2.3 Render `@handle` (`item_component.html.erb` ~15) as a yellow `<a>` to `youtube_url` when in list-channels mode; plain text otherwise. complexity: [low]
- [x] T2.4 Remove the `[view]` link (`item_component.html.erb` ~21-26) in list-channels mode. complexity: [low]
- [x] T2.5 Pass the new flag from `list_component.html.erb`; verify `enhanced_component.html.erb` (show game) renders unchanged. complexity: [low]
- [x] T2.6 Update `.pito-channel-item__*` CSS in `application.css` for the one-line stats and linked handle. complexity: [low]
- [x] T2.7 Update `ItemComponent` specs/previews for both modes. complexity: [low]
- [ ] T2.8 Commit: `Compact list-channels item: one-line stats, linked handle`. complexity: [manual]

## P3 — Inline first-line timestamp

- [x] T3.1 Switch the time format in `meta_line_component.rb` (~16-18) to 24H `%H:%M`. complexity: [low]
- [x] T3.2 Create `Pito::Event::TimestampPrefixComponent` — inline span `HH:MM ·`, `text-fg-faded`. complexity: [low]
- [x] T3.3 Remove the timestamp from `MetaLineComponent` (keep handle/channel only) so it is not double-rendered. complexity: [low]
- [x] T3.4 Prefix the timestamp inline on the first content line of `echo_component.html.erb` in a flex wrapper (avoids monospace whitespace gap). complexity: [low]
- [x] T3.5 Prefix the timestamp inline on `system_component.html.erb` first-line body. complexity: [low]
- [x] T3.6 Prefix the timestamp inline on `enhanced_component.html.erb` body without breaking the typewriter target. complexity: [high]
- [x] T3.7 Prefix the timestamp inline on `confirmation_component.html.erb` first line. complexity: [low]
- [x] T3.8 Prefix the timestamp inline on `theme_diff_component.html.erb` first line. complexity: [low]
- [x] T3.9 Update CSS for the inline timestamp prefix; confirm the handle/channel footer still renders. complexity: [low]
- [x] T3.10 Update event-component specs for 24H format and inline placement across the 7 types. complexity: [low]
- [ ] T3.11 Commit: `Move message timestamp inline to first line, 24H`. complexity: [manual]

## P4 — Game card id·title inline

- [x] T4.1 Combine id + title into one inline line in `enhanced_component.html.erb` (~50-55): `#id · title`, flex row, id `text-fg-faded`, title `text-fg`. complexity: [low]
- [x] T4.2 Move truncation/ellipsis onto the title child only (id stays fixed-width) in `application.css` (`__similar-game-title`). complexity: [low]
- [x] T4.3 Confirm `detail_component` is out of scope (or mirror if it shows the id the same way). complexity: [low]
- [x] T4.4 Update `enhanced_component` spec/preview. complexity: [low]
- [ ] T4.5 Commit: `Inline game card id with title`. complexity: [manual]

## P5 — Cover-art 75% resize + regenerate

- [x] T5.1 Change `MASTER_W`/`MASTER_H` in `app/services/game/cover_art/normalizer.rb` (~20-21) to 450/600. complexity: [low]
- [x] T5.2 Change `COVER_VARIANT` in `app/models/game.rb` (~21-25) to `resize_to_limit: [180, 240]`. complexity: [low]
- [x] T5.3 Update cover CSS in `application.css` (detail + enhanced cover classes) 240×320 → 180×240. complexity: [low]
- [x] T5.4 Add a one-off `cover_art:regenerate` rake task that force re-normalizes every `Game.where.not(cover_image_id: nil)` (bypassing the freshness skip). complexity: [high]
- [x] T5.5 Run `cover_art:regenerate` against dev data; verify covers re-attach at the new size. complexity: [manual]
- [x] T5.6 Purge orphaned blobs/variants (`ActiveStorage::Blob.unattached`); verify before/after counts so no dead files remain. complexity: [manual]
- [x] T5.7 Update cover-art normalizer specs for the new dimensions. complexity: [low]
- [ ] T5.8 Commit: `Resize game cover art to 75% and regenerate`. complexity: [manual]

## P6 — Reject unknown `list` nouns

- [x] T6.1 In `Pito::Chat::Handlers::List#call`, detect a leading token after `list` that is neither a recognized noun (channels/videos/games) nor a recognized games filter term, and return an unknown-target error/help instead of defaulting to the games list. complexity: [high]
- [x] T6.2 Add the "unknown list target" copy (`Pito::Copy`/locale) the error renders, naming the valid nouns. complexity: [low]
- [x] T6.3 Add specs: `list asd` → unknown-target error; `list`, `list games`, `list upcoming RPG` still list games; `list channels`/`list videos` unchanged. complexity: [low]
- [ ] T6.4 Commit: `Reject unknown list nouns instead of defaulting to games`. complexity: [manual]

## Open follow-ups (not in scope — need a decision)

- **Channel/video stats are not scheduled at all.** `SyncChannelStatsJob` and
  `VideoStatsSnapshotJob` exist and are tested but are never in `recurring.yml`
  nor enqueued by the chat `sync` verb (which uses `SyncChannelJob` /
  `SyncVideosJob`). P0 only makes the two *already-scheduled* dev jobs run
  (`cleanup_notifications`, `game_igdb_nightly_refresh` = upcoming games). If
  you want channel/video `Pito::Stats` to auto-refresh on a schedule, that's a
  separate decision (schedule the existing jobs, or delete the dead ones).
- `recurring.yml` header comments mislabel several jobs as "triggered via chat
  `sync` verb" — stale; worth correcting alongside the above.

## How to use this plan

Execute phase by phase on the current branch. One Sonnet sub-agent per atomic
task; verify `bundle exec rspec` green and `bin/rubocop` clean (and `node
--check` for JS) before the next task. Stage this plan file with each phase
commit. UI phases (P2–P4) need a manual smoke in the running app; P5's
regenerate/purge (T5.5–T5.6) are manual data operations — never drop the DB,
only re-attach/purge attachments.
