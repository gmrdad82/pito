# Phase 7.5 — Follow-ups Sweep + Concept Foundations

> **Note:** This file is the original architect-written phase overview. The
> canonical Phase 7.5 plan lives at [`../plan.md`](../plan.md).

> **Status:** specs landed by architect-spec on 2026-05-07. The master agent
> hoists this overview into `plan.md` once the user resolves the open questions
> surfaced below; sub-specs may be refined before implementation dispatches kick
> off.

> **What this phase is:** a hybrid window between Phase 7 (Google OAuth +
> YouTube API foundation) and Phase 8 (Data Sync). Two halves:
>
> 1. **Hygiene sweep** — accumulated follow-ups from
>    `docs/orchestration/follow-ups.md` and the Phase 6+7+A2 reviewer playbook
>    get consolidated into a small number of focused dispatches.
> 2. **Concept foundations** — pre-specs for new feature concepts the user has
>    flagged (Games, Timelines, MCP sync, Terminal sync, Keyboard shortcuts,
>    Pito-managed assets volume, Footage thumbnails). Most of these are NOT yet
>    ready for implementation; this phase surfaces the open questions and parks
>    the answered ones into real specs in a follow-up architect dispatch.
>
> **What this phase is NOT:** Phase 8. Nothing in 7.5 reaches into the YouTube
> data-sync engine, the public-key API path for tracked content, or any rebuild
> of metadata the Path A2 retract removed. If a concept feels load-bearing for
> Phase 8, it is deferred with a note pointing at Phase 8.

---

## Goals

1. **Close out the hygiene backlog** so Phase 8 starts on a clean tree —
   `:unprocessable_entity` migration, OmniAuth scope-walk simplification,
   Channel-Revamp orphans cleanup, `Settings::SessionsController` `.unscoped`
   audit, the CLI rustfmt drift sweep, the CLI Dependabot advisory, and the CLI
   screen-layout parity pass.
2. **Validate Phase 6 + Phase 7 manually** against the user's real credentials.
   Cumulatively walk the existing reviewer playbook so the YouTube OAuth
   foundation is exercised before Phase 8 builds on top.
3. **Park concept work** behind clear pre-specs. Games, Timelines, MCP sync, and
   Terminal sync each get a doc that captures what is known, what is unknown,
   and what the user must answer before code-spec work can begin.
4. **Land the foundations the user has decided are concrete** — keyboard
   shortcuts (mirror the `pito` CLI schema), the `pito-assets` Docker volume,
   and the footage-thumbnails experiment that depends on it.
5. **Resolve the decorator-slim design question** so the post-Path-A2 wire shape
   is intentional, not accidental.

## Sequencing notes

The phase has three independent tracks that can run in parallel once the user
answers the open questions below:

- **Track A — Rails-side hygiene sweep.** One spec, one rails-impl dispatch,
  single commit. Bundles the `:unprocessable_entity` migration, the OmniAuth
  simplification, the Channel-Revamp orphans cleanup, the
  `Settings::SessionsController` audit. See `01-rails-hygiene-sweep.md`.
- **Track B — CLI-side hygiene sweep.** One spec, one cli-impl dispatch, single
  commit. Bundles the rustfmt drift sweep, the Dependabot advisory (ratatui 0.29
  → 0.30), and the screen-layout parity pass. See `02-cli-hygiene-sweep.md`.
- **Track C — Concept + foundation specs.** Multiple specs:
  - `03-decorator-slim-resolution.md` — design decision (most likely a no-op,
    captured as a note).
  - `04-keyboard-shortcuts.md` — Rails-side shortcuts mirroring the `pito` CLI
    keymap. Concrete, ready for implementation.
  - `05-pito-assets-volume.md` — Docker volume for Pito-managed assets;
    foundation for Game cover art, Footage thumbnails, future thumbnails
    surface. Concrete, ready for implementation. Pairs with 06.
  - `06-footage-thumbnails.md` — extract preview frames from imported footage,
    store under `pito-assets`, render in `_footage_pane`. Concrete, depends
    on 05.
  - `07-games-prespec.md` — pre-spec. Concept-stage; surfaces open questions for
    the user.
  - `08-timelines-resurrection-prespec.md` — pre-spec. Phase-4 deferral with
    surviving `timelines` table; surfaces what "resurrection" means.
  - `09-mcp-sync-prespec.md` — pre-spec. The phrase is ambiguous; surfaces the
    two possible interpretations.
  - `10-terminal-sync-prespec.md` — pre-spec. Same shape as 09 but for the
    `pito` CLI.

Tracks A and B are independent of each other AND of Track C. The
keyboard-shortcuts spec (04) reads `extras/cli/src/keys.rs` and
`extras/cli/src/ui/help.rs` as its source of truth, so it should be written /
dispatched AFTER Track B's CLI parity sweep lands (otherwise the shortcuts
mirror a pre-parity baseline). 05 must land before 06.

The four pre-specs (07–10) do NOT spawn implementation agents in this phase.
They surface questions; the user answers; a follow-up architect dispatch
upgrades each into a real spec OR explicitly defers to a later phase. The
pre-spec docs are written this round so the user's answers have a place to land.

Manual validation (Phase 6 + Phase 7 walk) happens in flow with the hygiene
sweeps — the playbook is at
`docs/orchestration/playbooks/playbook-2026-05-07-phase-6-and-7-and-pathA2.md`
and is the user's gate. Implementation agents do NOT run that playbook; the user
does, then the master commits.

## In-scope workstreams

| #   | Workstream                        | Spec                                   | Track | Status                 |
| --- | --------------------------------- | -------------------------------------- | ----- | ---------------------- |
| 1   | Rails hygiene sweep               | `01-rails-hygiene-sweep.md`            | A     | Implementation-ready   |
| 2   | CLI hygiene sweep                 | `02-cli-hygiene-sweep.md`              | B     | Implementation-ready   |
| 3   | Decorator slim resolution         | `03-decorator-slim-resolution.md`      | C     | Decision pending       |
| 4   | Rails keyboard shortcuts          | `04-keyboard-shortcuts.md`             | C     | Implementation-ready   |
| 5   | `pito-assets` Docker volume       | `05-pito-assets-volume.md`             | C     | Implementation-ready   |
| 6   | Footage thumbnails experiment     | `06-footage-thumbnails.md`             | C     | Implementation-ready   |
| 7   | Games — concept pre-spec          | `07-games-prespec.md`                  | C     | Pre-spec; user answers |
| 8   | Timelines — resurrection pre-spec | `08-timelines-resurrection-prespec.md` | C     | Pre-spec; user answers |
| 9   | MCP sync — concept pre-spec       | `09-mcp-sync-prespec.md`               | C     | Pre-spec; user answers |
| 10  | Terminal sync — concept pre-spec  | `10-terminal-sync-prespec.md`          | C     | Pre-spec; user answers |

## Deferred workstreams

The following items were considered for 7.5 and explicitly deferred. Each notes
its target phase / trigger.

- **Cassette-recording session** (replace WebMock stubs with VCR cassettes
  recorded against the user's real Google account). Deferred to **Phase 7.6**
  (or whatever the gate-before-Phase-8 dispatch ends up named). Trigger: user
  has manually walked the Phase 7 playbook end-to-end at least once. Why not
  7.5: cassette recording is a flow-style activity the user runs themselves, not
  an implementation dispatch.
- **YouTube data sync engine.** Phase 8.
- **Real `top videos` chart rebuild.** Phase 8+ (depends on the sync engine
  populating Video metadata first).
- **`/channels` and `/videos` URL-hash → query-param sort migration.** Deferred
  to its own follow-up pass once channels / videos lists grow past a few dozen
  entries (the trigger noted in `follow-ups.md`).
- **Filter chip group component.** Deferred to a UI-component-DRY pass.
- **Meilisearch indexing per-target flag parity with Voyage.** Captured in
  `follow-ups.md`; pairs with the Voyage AppSetting revamp; not in 7.5 to keep
  this phase tight.
- **Wider follow-ups list** — every entry in `follow-ups.md` not bundled into
  7.5 stays in the backlog. The four hygiene-sweep specs above pull the items
  the user named in the dispatch. Anything else stays queued.

## Open questions for the user

These must be answered before implementation dispatches kick off. Numbered
globally so the user can answer "Q1 = …" inline; sub-specs reference the same
numbers.

### Track A — Rails hygiene sweep (spec 01)

**Q1 — `Settings::SessionsController .unscoped` resolution.** Does the audit
conclude (a) "the `.unscoped` is load-bearing for a Phase 12+ multi-tenant user
surfacing sessions across tenants — keep it and add an inline comment", or (b)
"it's a workaround for a `BelongsToTenant` default-scope nuance that should be
fixed at the concern level"? Reviewer's lean is (a) — the `.unscoped` plus the
explicit `where(user_id:)` is defensive and correct; the audit closes with a
documenting comment. Confirm or flip.

**Q2 — `:unprocessable_entity` migration spread.** The reviewer flagged Phase 6
hits in `Settings::OauthApplicationsController`, `Settings::TokensController`.
Should the sweep also cover any other controllers in the codebase that still use
the deprecated value (broad sweep), or just the ones the reviewer surfaced
(narrow sweep)? Reviewer's lean: broad sweep — easier to audit, smaller
follow-up later.

### Track B — CLI hygiene sweep (spec 02)

**Q3 — ratatui 0.30 upgrade tolerance.** The bump unblocks the Dependabot
advisory but is documented as TUI-API-breaking. Is the user prepared to accept
"the CLI looks slightly different after this bump" and have the cli-impl agent
fix breakage as it surfaces? Or does the user want a screenshots-before /
screenshots-after gate that the master agent assembles before the commit?
Default: accept the breakage and let the cli-impl agent solve.

**Q4 — Screen-layout parity scope.** The follow-up entry lists the
channel-detail "(s) star" hint and the sync-link placement explicitly. Does the
user want the parity sweep scoped to those two items only, or should the
cli-impl agent walk every screen and surface every discrepancy as part of the
same dispatch? Default: walk every screen, surface as a list, fix in the same
dispatch.

### Track C — Concepts + foundations

**Q5 — Decorator slim resolution.** The follow-up entry's master-agent lean is
"keep decorators as-is — derived/joined fields stay". Confirm or flip. (If
flipped, this becomes a real spec instead of a doc-only resolution.)

**Q6 — Keyboard shortcuts: any divergence from the CLI?** The 7.5 spec mirrors
the `pito` CLI's keymap exactly (after Track B parity lands). Does the user want
any web-only addition (e.g. `Ctrl+/` to focus search), or strict mirroring?
Default: strict mirror.

**Q7 — `pito-assets` volume mount point + permissions.** The volume name and
Docker mount are decided (`pito-assets` → `/var/lib/pito-assets`). Does the user
want a Rails-side `PITO_ASSETS_PATH` env var (mirroring `PITO_NOTES_PATH`), or
should the path be hard-coded? Default: env var, to mirror notes.

**Q8 — Footage thumbnails: which timestamp(s) to extract?** The simplest answer
is "one frame at 50% of duration". Other options: "three frames at 25/50/75%",
"one frame from each chapter marker if the file has them", "user-pickable
thumbnail in a future iteration". Default: one frame at 50%.

**Q9 — Footage thumbnails: extract job timing?** During import (slow import,
faster show page), or as a post-import Sidekiq job (faster import, thumbnails
appear shortly after)? Default: post-import Sidekiq job, queued by the importer
once the row is saved.

**Q10 — Games concept (pre-spec 07).** Several sub-questions, listed in the
pre-spec. Master agent has no lean; these are open.

**Q11 — Timelines resurrection (pre-spec 08).** Sub-questions in the pre-spec.
Master agent's lean: continue deferring until Phase 9 / 10.

**Q12 — MCP sync (pre-spec 09).** What does "MCP sync" mean? Two plausible
interpretations. Master agent has no lean — depends on the user's intent.

**Q13 — Terminal sync (pre-spec 10).** Same shape as Q12 but for the `pito` CLI.
Master agent has no lean.

## Manual testing gates

Two playbook walks happen DURING 7.5, in flow with the user, NOT after:

- **Phase 6 manual walk** — login UI, sessions revocation, OAuth client CRUD,
  OAuth authorization grant flow with PKCE, refresh, revoke, rate limit. Steps
  in
  `docs/orchestration/playbooks/playbook-2026-05-07-phase-6-and-7-and-pathA2.md`,
  Phase 6 manual test plan + Phase 6 user-validation checkboxes.
- **Phase 7 manual walk** — Google OAuth connect with the user's real account,
  `/settings/youtube` connect-channel, channel placeholders, disconnect
  (idempotent, including the already-revoked-at-Google path), needs_reauth
  banner. Steps in the same playbook, Phase 7 manual test plan + Phase 7
  user-validation checkboxes.

Both walks are user-driven. No implementation agent runs them. The master
commits each track only after the affected playbook section is green.

## Out of scope (explicit guardrails)

- **No Path A2 reversal.** Path A2 is settled. No spec in this phase
  reintroduces the dropped Channel/Video metadata columns, no spec re-enables
  Video search beyond the current stub, no spec rebuilds the retired charts. The
  path forward is Phase 8's "build up intentionally".
- **No Phase 8 surface area.** No spec touches the YouTube sync engine, the
  `Youtube::PublicClient` rebuild, or the public-key data path.
- **No `plan.md` write.** The master agent + docs-keeper hoist this overview
  into `plan.md` afterward. The architect-spec dispatch only writes under
  `specs/`.
- **No app code or tests.** Implementation agents run only after the user
  resolves the open questions.

## Cross-references

- `docs/orchestration/follow-ups.md` — the canonical backlog this phase draws
  from. Items not pulled into a 7.5 spec stay in `## Open` until a later phase /
  sweep.
- `docs/orchestration/playbooks/playbook-2026-05-07-phase-6-and-7-and-pathA2.md`
  — the user-driven validation gate this phase satisfies.
- `docs/plans/beta/07-google-oauth-youtube-foundation/log.md` — Phase 7 and Path
  A2 history. Phase 8 builds on the schema this log describes.
