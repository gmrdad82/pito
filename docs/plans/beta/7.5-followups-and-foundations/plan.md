# Phase 7.5 — Follow-ups Sweep + Concept Foundations

> **Status:** complete (closed by Phase 19; see
> [`docs/plans/beta/19-phase-75-closeout/`](../19-phase-75-closeout/)). The
> historical workstream tracker below remains frozen as a record of what landed.

> **Goal:** Close the hygiene backlog accumulated through Phase 6 + 7 + Path A2,
> land the concept foundations the user has decided are concrete (keyboard
> shortcuts, `pito-assets` volume, footage thumbnails), and park the remaining
> concept work behind pre-specs so Phase 8 starts from a clean tree.

**Depends on:** Phase 7 (Google OAuth + YouTube API foundation) committed; Path
A2 retract committed.

**Unblocks:** Phase 8 (YouTube data sync engine).

> **Not Phase 8.** Nothing in 7.5 reaches into the YouTube data-sync engine, the
> public-key API path, or any rebuild of metadata that Path A2 retired.

The full design rationale, open questions, and per-spec detail live in
[`specs/00-phase-overview.md`](specs/00-phase-overview.md) and the per-track
specs `01`–`10`. This file is the at-a-glance progress tracker.

---

## In-scope workstreams

### Track A — Rails hygiene sweep

Spec: [`specs/01-rails-hygiene-sweep.md`](specs/01-rails-hygiene-sweep.md)

- [x] `Settings::SessionsController` `.unscoped` audit and fix (Q1 = b: remove
      the over-defensive workaround; underlying `BelongsToTenant` scope is
      correct)
- [x] `:unprocessable_entity` → `:unprocessable_content` broad sweep (Q2 = a:
      every callsite across `app/` and `spec/`)
- [x] OmniAuth initializer simplification (single credentials lookup, explicit
      early-fail on missing keys)
- [x] Channel Revamp orphan cleanup (delete `_confirm_dialog` partial + Stimulus
      controller; drop unused `BracketedLinkComponent#confirm:` kwarg)

### Track B — CLI hygiene sweep

Spec: [`specs/02-cli-hygiene-sweep.md`](specs/02-cli-hygiene-sweep.md)

- [x] `cargo fmt` drift sweep
- [x] Dependabot advisory: ratatui 0.29 → 0.30 (Q3 = accept TUI breakage and fix
      in-dispatch)
- [x] Screen-layout parity pass with the Rails app (Q4 = walk every screen,
      surface and fix discrepancies as a list)

### Track C — Concept + foundation specs

#### 03 · Decorator slim resolution

Spec:
[`specs/03-decorator-slim-resolution.md`](specs/03-decorator-slim-resolution.md)

- [x] Confirm decorators stay as-is post-Path-A2 (Q5 = keep derived/joined
      fields; documented as a no-op note, not a code spec)

#### 04 · Rails keyboard shortcuts

Spec: [`specs/04-keyboard-shortcuts.md`](specs/04-keyboard-shortcuts.md)

- [x] Mirror the `pito` CLI keymap on the Rails web surface (Q6 = strict mirror;
      no web-only additions)

#### 05 · `pito-assets` Docker volume

Spec: [`specs/05-pito-assets-volume.md`](specs/05-pito-assets-volume.md)

- [x] Provision the `pito-assets` Docker volume mounted at
      `/var/lib/pito-assets`
- [x] `PITO_ASSETS_PATH` env var (Q7 = mirror `PITO_NOTES_PATH` shape)

#### 06 · Footage thumbnails experiment

Spec: [`specs/06-footage-thumbnails.md`](specs/06-footage-thumbnails.md)

- [x] Rails-side thumbnail render in `_footage_pane` (path resolution,
      placeholder fallback)
- [x] CLI-side thumbnail render scaffolding in the `pito` footage panes
- [ ] Importer-side ffmpeg extraction (Q8 = one frame at 50% of duration; Q9 =
      post-import Sidekiq job)
- [x] CLI image-rendering integration (terminal image protocol selection + pane
      composition)

#### 07–10 · Concept pre-specs (no implementation in 7.5)

These specs surface open questions for the user. Each upgrades into a real
implementation spec (or explicit deferral) in a follow-up architect dispatch
once the user has answered the embedded questions.

- [ ] `07-games-prespec.md` — Games concept (Q10)
- [ ] `08-timelines-resurrection-prespec.md` — Timelines resurrection (Q11)
- [ ] `09-mcp-sync-prespec.md` — MCP sync (Q12)
- [ ] `10-terminal-sync-prespec.md` — Terminal sync (Q13)

---

## Deferred workstreams

Each item below was considered for 7.5 and explicitly punted. Trigger / target
phase noted inline.

- [ ] **Cassette-recording session.** Replace WebMock stubs in `YouTube::Client`
      specs with VCR cassettes recorded against the user's real Google account.
      Deferred to Phase 7.6 (or whatever the gate-before-Phase-8 dispatch is
      named). Trigger: user has manually walked the Phase 7 playbook end-to-end
      at least once.
- [ ] **YouTube data sync engine.** Phase 8.
- [ ] **Real `top videos` chart rebuild.** Phase 8+ (depends on the sync engine
      populating Video metadata first).
- [ ] **`/channels` and `/videos` URL-hash → query-param sort migration.**
      Trigger: list grows past a few dozen entries.
- [ ] **Filter chip group component.** Deferred to a UI-component-DRY pass.
- [ ] **Meilisearch indexing per-target flag parity with Voyage.** Pairs with
      the Voyage AppSetting revamp; not in 7.5 to keep the phase tight.
- [ ] **Wider `follow-ups.md` backlog.** Anything not pulled into the four
      hygiene-sweep specs above stays queued.

---

## Sequencing notes

Three independent tracks. Tracks A and B are independent of each other AND of
Track C. Track C has internal ordering: 04 (keyboard shortcuts) reads
`extras/cli/src/keys.rs` and `extras/cli/src/ui/help.rs` as its source of truth,
so it dispatches AFTER Track B's parity sweep lands. 05 (pito-assets volume)
lands before 06 (footage thumbnails).

**Wave 1 (parallel):** Track A spec 01 · Track B spec 02 · Track C specs 03 + 05
· Track C pre-specs 07–10 (doc-only).

**Wave 2 (after Track B and 05 land):** Track C spec 04 (keyboard shortcuts) ·
Track C spec 06 (footage thumbnails — the Rails-side and CLI-side scaffolding
shipped here; the importer-side ffmpeg extraction and the CLI image-rendering
integration remain open).

**Manual gate (user-driven, in flow with the sweeps):**

- Phase 6 manual walk — login UI, sessions revocation, OAuth client CRUD, OAuth
  authorization grant flow with PKCE, refresh, revoke, rate limit.
- Phase 7 manual walk — Google OAuth connect with the user's real account,
  `/settings/youtube` connect-channel, channel placeholders, disconnect,
  `needs_reauth` banner.

Both walks reference
`docs/orchestration/playbooks/playbook-2026-05-07-phase-6-and-7-and-pathA2.md`.
Implementation agents do NOT run the playbook; the user does, then the master
commits each track.

**Big consolidated playbook (post-waves, pre-Phase-8):** the master assembles a
combined Phase 6 + 7 + 7.5 walkthrough so the user signs off the entire
foundation in one pass. After that gate is green, Phase 8 begins.

---

## Cross-references

- [`specs/00-phase-overview.md`](specs/00-phase-overview.md) — full design
  rationale, open questions Q1–Q13, deferral triggers, and out-of-scope
  guardrails.
- [`specs/01-rails-hygiene-sweep.md`](specs/01-rails-hygiene-sweep.md) through
  [`specs/10-terminal-sync-prespec.md`](specs/10-terminal-sync-prespec.md) —
  per-track / per-concept detail.
- `docs/orchestration/follow-ups.md` — canonical backlog this phase draws from.
- `docs/orchestration/playbooks/playbook-2026-05-07-phase-6-and-7-and-pathA2.md`
  — the user-driven validation gate.
- `docs/plans/beta/07-google-oauth-youtube-foundation/` — the Phase 7 plan + log
  this phase builds on top of.
- `docs/plans/beta/7.5-followups-and-foundations/log.md` — session log for this
  phase (append-only, written by docs-keeper after each track lands).
