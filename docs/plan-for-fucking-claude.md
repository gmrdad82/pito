# Smart, repeatable, multi-target `link`/`unlink` on follow-ups (lists + show cards)

> Status: Draft — execute on branch `followup-smart-link`.

## Sign-off

- [x] Drafted — 2026-06-10
- [x] Audited — 2026-06-10 (code audited: impl complete; 4 stale specs to fix)

## North star

`link`/`unlink` work reusably from any record context — `list videos`/`list games`
follow-ups AND the detail cards from `show video`/`show game` — inferring the entity
from context, accepting multiple `to`/`from` ids (HABTM), without consuming the handle.
`show` itself is unchanged.

## Locked decisions

| Topic                    | Decision                                                                                  |
| ------------------------ | ----------------------------------------------------------------------------------------- |
| Source side              | single id; entity inferred from `reply_target` (`video_*`→video, `game_*`→game)           |
| Target side              | one or more ids (`1,2,3` or space-separated); the opposite entity                         |
| Repeatable               | link/unlink return `Append` with `consume: false`, forced at the VerbDelegator chokepoint |
| Id resolution            | global `find_by(id:)` — not validated as list members                                     |
| `show` / `delete` / `rm` | unchanged (still consume)                                                                 |
| Branch                   | `followup-smart-link` (already created at user request)                                   |

## Complexity hints

| Hint       | Meaning                                              |
| ---------- | ---------------------------------------------------- |
| `[low]`    | mechanical / single-file / pattern-following edit    |
| `[high]`   | architectural / cross-cutting decision               |
| `[manual]` | operator: design choices, verification runs, commits |

## Phase index

- P0 — Non-consuming Append mechanism
- P1 — Link/Unlink follow-up: list source + multi-target
- P2 — Surface link/unlink on lists + suggestions + help
- P3 — Housekeeping + final verification

## P0 — Non-consuming Append mechanism

- [x] T0.1 Add a `consume:` keyword (default `true`) to `Pito::FollowUp::Result::Append` in `app/services/pito/follow_up/result.rb`. complexity: [low]
- [x] T0.2 Gate consume in `app/jobs/follow_up_dispatch_job.rb` — set `reply_consumed`/`replace_event` only when `result.consume`. complexity: [low]
- [x] T0.3 In `app/services/pito/follow_up/verb_delegator.rb`, rebuild the adapted `Append` with `consume: false` when the verb is `link`/`unlink`. complexity: [low]
- [x] T0.4 Add `spec/services/pito/follow_up/verb_delegator_spec.rb` cases: link/unlink → `Append.consume == false`; show/delete → `true`. complexity: [low]
- [x] T0.5 Add job spec: `consume: false` leaves `reply_consumed` unset; default `true` still consumes. complexity: [low]
- [x] T0.6 Run `bundle exec rspec` on the P0 specs + `bin/rubocop`; confirm green. complexity: [manual]
- [x] T0.7 Commit: `non-consuming Append; link/unlink repeatable via VerbDelegator`. complexity: [manual]

## P1 — Link/Unlink follow-up: list source + multi-target

- [x] T1.1 Add a shared target-id parser (split `/[\s,]+/`, strip a leading noun filler, numeric-only, dedup) used by `link.rb`/`unlink.rb`. complexity: [low]
- [x] T1.2 Add source resolution to `app/services/pito/chat/handlers/link.rb` follow-up branch — pick source class from `reply_target`; detail (payload `*_id`) vs list (id before the connector). complexity: [high]
- [x] T1.3 Implement the multi-target loop in `link.rb` — resolve each target, `VideoGameLink.find_or_create_by!`, collect linked + not-found. complexity: [low]
- [x] T1.4 Mirror source resolution + multi-target loop in `app/services/pito/chat/handlers/unlink.rb` (destroy each). complexity: [low]
- [x] T1.5 Add summary copy `games.linked_multi` / `games.unlinked_multi` (+ a not-found note) to `config/locales/pito/copy/en.yml`. complexity: [low]
- [x] T1.6 Add `spec/services/pito/chat/handlers/link_spec.rb` cases — list source, multi-target, not-found, detail source + multi. complexity: [low]
- [x] T1.7 Add the mirror cases to `spec/services/pito/chat/handlers/unlink_spec.rb`. complexity: [low]
- [x] T1.8 Run `bundle exec rspec` on link/unlink specs + `bin/rubocop`; confirm green. complexity: [manual]
- [x] T1.9 Commit: `link/unlink follow-up: list source + multi-target summary`. complexity: [manual]

## P2 — Surface link/unlink on lists + suggestions + help

- [x] T2.1 Add `"link", "unlink"` to `self.actions` in `app/services/pito/follow_up/handlers/video_list.rb`. complexity: [low]
- [x] T2.2 Add `"link", "unlink"` to `self.actions` in `app/services/pito/follow_up/handlers/game_list.rb`. complexity: [low]
- [x] T2.3 Make `filter_link_unlink` in `app/services/pito/suggestions/engine.rb` return both link & unlink for list and detail targets. complexity: [low]
- [x] T2.4 Add `actions.link` / `actions.unlink` copy under `list-videos` and `list-games` in `config/locales/pito/copy/en.yml`. complexity: [low]
- [x] T2.5 Update `show-video` / `show-game` link/unlink usage copy to the multi `to <id>[,id…]` form in `en.yml`. complexity: [low]
- [x] T2.6 Add engine ghost spec — list/detail handle palette includes both link & unlink. complexity: [low]
- [x] T2.7 Add `video_list`/`game_list` follow-up specs — `link`/`unlink` single + multi-target, and `reply_consumed` stays unset (repeatable). complexity: [low]
- [x] T2.8 Run `bundle exec rspec` + `bin/rubocop`; confirm green. complexity: [manual]
- [x] T2.9 Commit: `surface link/unlink on lists; show both in palette; help copy`. complexity: [manual]

## P3 — Housekeeping + final verification

- [x] T3.1 Fix the stale `Follow-up: NOT stamped` comment in `app/services/pito/chat/handlers/list.rb`. complexity: [low]
- [x] T3.2 Add detail follow-up specs (`game_detail`/`video_detail`) — link/unlink multi-target and the card is NOT consumed afterward. complexity: [low]
- [x] T3.3 Run full `bundle exec rspec` + `bin/rubocop` + `npx vitest run`; confirm green (ignore the lone known-flaky scrollback/games_search test). complexity: [manual]
- [x] T3.4 Commit: `link/unlink housekeeping + final verification`. complexity: [manual]
