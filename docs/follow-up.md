# Follow-up / re-check list

Durable pin of things deferred during development, so they aren't silently lost.
(Permanent reference — unlike the gitignored `docs/claude/` working plans.)

## 0.8.0 analytics — ViewComponent session (next analyze session)

The `analyze` verb groundwork shipped (verb + scope resolution + per-video/channel
primitives store with completed-period freeze + aggregation + two messages
`:system`/`:enhanced` + fan-out job + per-message thinking duration). The two
messages currently render the **interim scalar kv-table**. Still to do:

- **`:system` vs `:enhanced` content split** — decide what each message shows.
  Interim: both render the scalars kv-table with their own copy. Plan: `:system`
  gains Devices · Subscribed-status · Geography (country); `:enhanced` gains
  Day-of-week heatmap (derive from `daily`) · Retention curve (single-video) ·
  Demographics (age × gender). The `AnalyticsClient` methods already exist.
- **Extract each kv-table scalar into its own ViewComponent** (owner's plan).
- **fx "pop" wiring** — the new per-dimension components must behave like the
  score-bar / ttb components: appear at once (add their selectors to
  `ALWAYS_POP_PATTERNS` in the reveal engine) while the message prose obeys the
  fx style.
- **Payload extensibility** — the `"analyze"` marker is jsonb (extensible by
  design); no speculative empty slots added (YAGNI). Add dimension data to the
  marker + `ready_payload` when the components land.

## 0.8.0 analytics — Phase 4 repliability (BLOCKED on a decision)

`analyze` messages + the `show vid`/`show game` analytics `:enhanced` should be
repliable via `#<handle>`. **Blocked on the `with` / `without` option vocabulary**
(owner-deferred) — that's the primary reply use case. The base "reply → re-analyze
this entity" path is buildable on top of `FollowUp` + `VerbDelegator` (delegate
the `analyze` verb to the handler with the replied-to entity as context; the
handler gets a `follow_up?` branch that resolves the scope from the source event
instead of `ScopeResolver`). Build once the `with`/`without` vocab is defined so
the FollowUp action set is settled.

## YouTube Analytics API re-checks (carried from the 0.8.0 brief)

- **Demographics (age × gender)** — plumbing exists but **data-starved** on this
  channel (Studio: "Not enough demographic data"). Re-check as `@gmrdad82` grows.
- **Hour-of-day heatmap** — NOT in the public API (`hourOfDay` absent). Day-of-week
  IS derivable. Re-check only if Google exposes an hour dimension.
- **Thumbnail impressions / CTR / end-screen click rate** — confirmed NOT in the
  Analytics API (Studio-only). Re-check only if Google adds them.
- **Channel-level primitive granularity** — channel metrics are fetched per-channel
  (`videos: nil`), NOT summed from per-video primitives (subs aren't all
  video-attributable; channel-wide covers unsynced/deleted videos). Re-check if a
  per-video channel breakdown is ever needed.
- **Nightly cache pre-warm** — add only if first-load latency annoys.
- **Higher Analytics API quota** — only if usage approaches the limit (won't at
  current scale).

## Side backlog deferrals (need owner input — from the 2026-06-25 overnight run)

- **SB1–SB3 — ASCII alignment** in the channel "welcome aboard" dictionary
  (`config/locales/pito/copy/en.yml` ~L6150–6243). Font-dependent **visual** fixes
  (the `▰` glyph appears wider than `─` in the app font, so bars overhang the
  borders). Needs visual verification — fix with the owner watching the render.
- **SB4 / SB5 — recommendation sorting.** `similar_games` + `channels_for` already
  return "ranked best-first" by their recommendation/fit score and the enhanced
  builder renders in that order. Confirm whether a real ordering bug was seen, or
  whether the owner wants a _different_ score (the game's review `score` vs the
  similarity/fit blend).

## Done in the overnight run (accumulated, await GPG PIN)

- **SB8** — `CompactCount` rounds DOWN (floor), never up (`2,259 → 2.2K`).
- **SB7** — free-chat `link` accepts a multi-id list per side
  (`link game 1 with vid 15,14`).
- **SB6** — IGDB import sidebar renders search rows + step rows at the single 14px
  base size (removed `text-sm`/`text-xs` utilities).

## Pre-existing (not from this work)

- `spec/javascript/suggestions_controller.test.js` — 2 failing tests
  (`_computeLocalGhost("sync ", …)` returns null) that fail at HEAD, unrelated to
  analyze. Decide whether to fix the `sync ` ghost or update the tests.
