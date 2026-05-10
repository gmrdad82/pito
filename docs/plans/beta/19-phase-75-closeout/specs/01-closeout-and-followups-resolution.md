# Phase 7.5 Close-out — Reconciliation + Follow-ups Resolution

> **Phase 19 (close-out).** This is a docs-only phase. No production code, no
> migrations, no new tests beyond an optional smoke spec. Its job is to
> reconcile what shipped during Phase 7.5 against the original plan, mark the
> dropped pre-specs as resolved per the 2026-05-09 realignment, dispose of
> follow-ups that Phase 7.5 either closed or carries forward, and produce a
> close-out playbook the user signs off before the docs-keeper finalizes the
> trailing per-phase tracking files.

## Goal

Phase 7.5 ("Follow-ups Sweep + Concept Foundations") shipped a substantial
hygiene + foundations body of work between Phase 7 and the 2026-05-09
realignment. The phase was never formally closed: the per-spec checkboxes in
`docs/plans/beta/7.5-followups-and-foundations/plan.md` are all flipped except
the four pre-specs (07–10), the `additions.md` and `dropped.md` files capture
mid-phase scope changes but never received a final reconciliation, and several
follow-up items in `docs/orchestration/follow-ups.md` remain "Open" even though
their work landed during Phase 7.5.

This spec produces:

1. A reconciliation table that enumerates every Phase 7.5 line item and pins its
   outcome (shipped + verified, shipped + needs verification, dropped per ADR /
   realignment, pending — moved to a later phase) with commit references where
   applicable.
2. A follow-ups disposition table that walks `docs/orchestration/follow-ups.md`
   end-to-end, marks each entry's status against Phase 7.5, and reassigns
   carry-forward entries to their post-realignment target phase.
3. A close-out playbook the user runs in dev to confirm Phase 7.5 is done.
4. A list of post-validation docs updates the docs-keeper makes (the `log.md`
   close-out entry, the `additions.md` / `dropped.md` reconciliations, the
   `follow-ups.md` cleanup, and the realignment-doc work-unit-11 marker).

The close-out is the gate that lets future architect dispatches stop treating
Phase 7.5 as "in flight" and start treating it as "complete and referenced from
git history".

## Files touched

The implementation agent for this spec is the **docs-keeper**. No application
code, no migrations, no new test files (with one optional exception below).

### Docs the docs-keeper updates after the user validates

- `docs/plans/beta/7.5-followups-and-foundations/log.md` — final close-out entry
  pinning the reconciliation summary and the close-out commit reference.
- `docs/plans/beta/7.5-followups-and-foundations/additions.md` — final
  reconciliation note (the realignment additions all landed downstream of 7.5
  per the realignment doc; nothing was added to the phase itself).
- `docs/plans/beta/7.5-followups-and-foundations/dropped.md` — final
  reconciliation note (the three pre-spec drops are confirmed; the historical
  recommendation prose stays).
- `docs/plans/beta/7.5-followups-and-foundations/plan.md` — leading status badge
  flipped from in-flight to "complete (closed by Phase 19)" with a one-line
  pointer to this spec.
- `docs/orchestration/follow-ups.md` — Open entries either move to ## Done with
  their resolving commit, or carry forward with their new target phase noted
  inline. Disposition driven by §"Follow-ups disposition table" below.
- `docs/realignment-2026-05-09.md` — work unit 11 ("Phase 7.5 pre-specs 08 / 09
  / 10 resolution") gets a Resolution line pointing at this spec and the
  close-out commit.

### Docs this spec creates

- `docs/plans/beta/19-phase-75-closeout/specs/01-closeout-and-followups-resolution.md`
  — this file (architect-spec output).
- `docs/plans/beta/19-phase-75-closeout/log.md` — created as a stub by
  architect-spec; the docs-keeper appends the close-out session entry after the
  user validates.

### Optional smoke spec (architect's recommendation: skip)

A "Phase 7.5 smoke" integration spec under
`spec/integration/phase_7_5_smoke_spec.rb` would touch each shipped Phase 7.5
surface in a single example run (keyboard shortcuts modal renders, footage
thumbnail URL responds, `Pito::AssetsRoot.root` resolves, etc.). Architect's
recommendation: **skip**. Each shipped surface already has dedicated coverage
(see §"Test coverage already in place"); a smoke spec adds churn without adding
signal. If the docs-keeper or reviewer decides otherwise post-validation,
escalate to a follow-up architect dispatch — do not expand this spec's scope to
write the smoke file.

## Acceptance

- [ ] Reconciliation table in §"Reconciliation table" below names every Phase
      7.5 line item from `plan.md` (10 numbered specs + the deferred
      workstreams) with status, commit refs where applicable, and notes.
- [ ] Follow-ups disposition table in §"Follow-ups disposition table" below
      walks every entry currently under `## Open` in
      `docs/orchestration/follow-ups.md`. Each is marked Closed (with resolving
      commit) or Carry-forward (with target phase or new trigger).
- [ ] Manual close-out playbook in §"Manual close-out playbook" below has
      explicit step-by-step verification instructions a user can run in
      `bin/dev` without assistance.
- [ ] §"Tenant-drop interaction" lists which Phase 7.5 modules touch `tenant_id`
      paths and confirms each survives the Phase 8 tenant-drop work unit (or
      notes which require subsequent docs touch-up).
- [ ] §"Open questions" enumerates every decision the master agent must answer
      before dispatching the docs-keeper.
- [ ] No application code is modified. No migrations are added. No new RSpec
      files are added (the optional smoke spec is explicitly out of scope per
      architect's recommendation; if reviewer flips that call it becomes a
      separate follow-up dispatch).
- [ ] Phase 19 log stub is created at
      `docs/plans/beta/19-phase-75-closeout/log.md`. It carries only the spec
      reference + a placeholder for the close-out session entry the docs-keeper
      appends after user validation.
- [ ] After user signs the playbook off, docs-keeper appends the close-out entry
      to `docs/plans/beta/7.5-followups-and-foundations/log.md`, updates
      `additions.md` + `dropped.md` + `follow-ups.md` +
      `realignment-2026-05-09.md` per §"Documentation impact (post-validation)".

## Reconciliation table

Each row pins a Phase 7.5 line item against its outcome. Architect cross-checked
against `docs/plans/beta/7.5-followups-and-foundations/plan.md`, `additions.md`,
`dropped.md`, the phase log, and the realignment doc.

Commit references are TBD — the docs-keeper resolves each `<commit>` placeholder
to the actual hash by walking `git log --oneline -- <path>` for the listed files
at close-out time. Architect-spec does not have a session shell, so hashes can't
be embedded here; the disposition (which spec / which commit range) is the
load-bearing piece.

| #   | Item from original plan                                  | Status                                   | Commit refs (placeholder) | Notes                                                                                                                                                                                                                                                                                                                                          |
| --- | -------------------------------------------------------- | ---------------------------------------- | ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 01  | Rails hygiene sweep — Settings sessions audit            | Shipped + verified                       | `<commit>`                | Q1 resolved (b): removed `.unscoped` workaround. 3 cross-tenant regression specs added. Log entry 2026-05-07 Track A step 01.                                                                                                                                                                                                                  |
| 01  | `:unprocessable_entity` → `:unprocessable_content` sweep | Shipped + verified                       | `<commit>`                | Q2 resolved (a): broad sweep across `app/` + `spec/`. Same dispatch as above. 49 callsites migrated.                                                                                                                                                                                                                                           |
| 01  | OmniAuth initializer simplification                      | Shipped + verified                       | `<commit>`                | Single credentials lookup + early-fail. Same dispatch.                                                                                                                                                                                                                                                                                         |
| 01  | Channel Revamp orphan cleanup                            | Shipped + verified                       | `<commit>`                | `_confirm_dialog` partial + Stimulus controller deleted; `confirm:` kwarg dropped from `BracketedLinkComponent`. Same dispatch.                                                                                                                                                                                                                |
| 02  | CLI hygiene — `cargo fmt` drift sweep                    | Shipped + verified                       | `<commit>`                | Track B step 02. `cargo fmt --check` clean post-sweep.                                                                                                                                                                                                                                                                                         |
| 02  | CLI hygiene — ratatui 0.29 → 0.30                        | Shipped + verified                       | `<commit>`                | Q3 resolved (accept render side effects). Zero callsite breakage. `lru` + `paste` advisories cleared. Same dispatch.                                                                                                                                                                                                                           |
| 02  | CLI screen-layout parity sweep                           | Shipped + verified                       | `<commit>`                | Q4 resolved (full walk). Three discrepancies fixed: channel-detail action legend, help screen `f y` row removal, dashboard placeholder copy. Eight cross-stack gaps surfaced and explicitly out-of-scope (column reconciliation between channels list / videos list / settings panes / search results).                                        |
| 03  | Decorator slim resolution                                | Shipped (closed no-op)                   | n/a (decision-only)       | Q5 resolved: keep decorators as-is. Recorded in `follow-ups.md` ## Done section dated 2026-05-07. No code change.                                                                                                                                                                                                                              |
| 04  | Rails keyboard shortcuts                                 | Shipped + verified                       | `<commit>`                | Q6 resolved (strict mirror of CLI). 33 new specs. Five cross-stack gaps documented (browser-back `q`, `:q` / Ctrl+C, `e` for channel-edit, `c` for connected toggle, list-row `enter`). Independent of tenant model.                                                                                                                           |
| 05  | `pito-assets` Docker volume + `Pito::AssetsRoot`         | Shipped + verified                       | `<commit>`                | Q7 resolved (env-var-driven). `bin/setup` mkdir-p on first install. 29 unit tests in `spec/lib/pito/assets_root_spec.rb`. **Tenant-touch:** `tenant_root` method assumes `tenant.id`; survives the tenant drop only if the helper is updated (see §"Tenant-drop interaction").                                                                 |
| 06  | Footage thumbnails — Rails endpoints                     | Shipped + verified                       | `<commit>`                | `GET /footages/:id/frames.json` + `m/t` JPEG streamers + bearer-authed `PATCH /api/footages/:id/frames`. 19 new specs. Schema migration `20260507400003`. **Tenant-touch:** uses `Footage.unscoped.find` for public-read endpoints.                                                                                                            |
| 06  | Footage thumbnails — CLI rendering                       | Shipped + verified                       | `<commit>`                | ratatui-image v10 + StatefulImage. Capability detection at boot. LRU cache at `~/.cache/pito/thumbnails/`. 96 new tests across 7 modules. Live image rendering on Kitty / Sixel / iTerm2 / Halfblocks paths.                                                                                                                                   |
| 06  | Footage thumbnails — importer-side ffmpeg extraction     | Pending — moved to Phase 8+              | n/a                       | Originally scoped for 7.5; deferred. The `PATCH /api/footages/:id/frames` endpoint exists and is bearer-authed; the importer half is the only blocker. Carry-forward target: bundled with the per-domain CLI parity work unit (work unit 10) when footage import gets revisited, OR a dedicated dispatch if the user wants real frames sooner. |
| 07  | Games — concept pre-spec                                 | Pending — moved to work unit 6           | n/a                       | Pre-spec stayed open through 7.5; superseded by realignment work unit 6 (Game model expansion + IGDB sync). The `07-games-prespec.md` file's open questions are absorbed into the implementation spec the architect dispatches for work unit 6. Pre-spec stays in place as historical reference.                                               |
| 08  | Timelines resurrection — concept pre-spec                | Dropped per realignment                  | n/a (file deleted)        | 2026-05-10 deletion. Resolved ambiguity #1: replaced by direct `Video.project_id` (nullable) in work unit 4. Pre-spec file deleted; durable record in `realignment-2026-05-09.md` + `dropped.md`.                                                                                                                                              |
| 09  | MCP sync — concept pre-spec                              | Dropped per realignment                  | n/a (file deleted)        | 2026-05-10 deletion. Resolved ambiguity #2: superseded by per-domain MCP coverage matrices declared inline in each downstream domain spec. Web is canonical; MCP is best-effort parity.                                                                                                                                                        |
| 10  | Terminal sync — concept pre-spec                         | Dropped per realignment                  | n/a (file deleted)        | 2026-05-10 deletion. Resolved ambiguity #3: same posture as 09 but for the Rust CLI. Superseded by per-domain CLI coverage matrix.                                                                                                                                                                                                             |
| -   | Cassette-recording session (deferred)                    | Deferred — Phase 7.6 trigger unfulfilled | n/a                       | Trigger ("user has manually walked the Phase 7 playbook end-to-end") is itself the close-out playbook below. After the playbook signs off, the cassette session becomes a queued dispatch; track in `follow-ups.md`.                                                                                                                           |
| -   | YouTube data sync engine                                 | Pending — work unit 5                    | n/a                       | Phase 8 / realignment work unit 5 (Analytics sync engine + tables + dashboard). Always was Phase 8; included here for completeness of the original deferral list.                                                                                                                                                                              |
| -   | Real `top videos` chart rebuild                          | Pending — work unit 4/5                  | n/a                       | Depends on Video schema expansion (work unit 4) + Analytics tables (work unit 5).                                                                                                                                                                                                                                                              |
| -   | `/channels` + `/videos` URL-hash → query-param           | Carry-forward                            | n/a                       | Trigger ("list grows past a few dozen entries") still unmet. Stays in `follow-ups.md`. Tenant-drop unaffected.                                                                                                                                                                                                                                 |
| -   | Filter chip group component                              | Carry-forward                            | n/a                       | UI-component-DRY pass. No phase target. Stays in `follow-ups.md`.                                                                                                                                                                                                                                                                              |
| -   | Meilisearch indexing per-target flag parity              | Carry-forward                            | n/a                       | Pairs with Voyage AppSetting revamp. Realignment defers to "after Channel + Video schema expansion lands" (post-work-unit-4). Stays in `follow-ups.md` with the new trigger condition noted.                                                                                                                                                   |
| -   | Wider `follow-ups.md` backlog                            | Carry-forward                            | n/a                       | Each entry handled individually below.                                                                                                                                                                                                                                                                                                         |

### In-flow work outside the original plan

Several dispatches landed during the Phase 7.5 window that were never numbered
specs. The reconciliation table acknowledges them so the close-out doesn't
silently drop them.

| Dispatch                                                               | Status             | Commit refs | Notes                                                                                                                                                                                |
| ---------------------------------------------------------------------- | ------------------ | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| MCP OAuth discovery (RFC 8414 + RFC 9728) + Doorkeeper bearer dispatch | Shipped + verified | `<commit>`  | 2026-05-07 log entry. Closes Phase 6B deviation #2. New `well_known_controller`, bearer dispatch in `Api::TokenAuthenticator`, `WWW-Authenticate` header on every 401. 14 new specs. |
| Doorkeeper scope soft-clip + OAuth-app UX polish                       | Shipped + verified | `<commit>`  | 2026-05-07 log entry. Initializer monkey-patches `Doorkeeper::OAuth::PreAuthorization` for clip-on-mismatch. `[copy]` affordance on credentials. 13 new specs.                       |
| Doorkeeper consent + error pages restyled to Pito                      | Shipped + verified | `<commit>`  | 2026-05-09 log entry. `:hide_chrome` + 480px container + bracketed-link convention.                                                                                                  |
| OAuth applications UI polish (5 fixes)                                 | Shipped + verified | `<commit>`  | 2026-05-07 log entry. `client_id` middle-truncate, framed-block credentials, `[i have saved them]` lowercase, `.framed-block` class documented in `docs/design.md`.                  |
| MCP custom-connector icon discovery (shotgun)                          | Shipped + verified | `<commit>`  | 2026-05-07 log entry. `apple-touch-icon`, `manifest.json`, `og:*` tags, `logo_uri` in `.well-known` metadata, `/favicon.ico` redirect to `/Pito.png`. 4 new specs.                   |

These in-flow dispatches close out cleanly with Phase 7.5. They are listed for
audit completeness; their commit refs anchor in the same `git log` walk.

### Items the architect could not classify from docs alone

None. Every plan checkbox + every additions.md / dropped.md entry has a clear
disposition above. If the docs-keeper finds an ambiguity at close-out time
(e.g., a log entry references a sub-task that doesn't appear in either the plan
or the realignment doc), they pause and escalate to the master agent rather than
pick a status unilaterally.

## Follow-ups disposition table

This table walks every entry currently under `## Open` in
`docs/orchestration/follow-ups.md` (as of the architect-spec session date) and
pins disposition. Order matches the file's order so the docs-keeper can sweep
top-to-bottom.

| Follow-up entry (heading)                                                            | Phase 7.5 status                                             | Action at close-out                                                                                                                                                                                                                                                                                                                                            |
| ------------------------------------------------------------------------------------ | ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Phase 6 deviation acknowledgment — DB-backed sessions vs cookie_store (decision 6.1) | Closed by Phase 7.5 (informational)                          | Move to ## Done. Cited inline in the close-out log entry as "informational, intentionally preserved as a paragraph in the file even after move (the warning to future readers stays useful)". Architect's recommendation: leave under ## Open as a permanent informational notice, NOT moved. Treat as a permanent fixture; flag in the close-out log instead. |
| Channel Revamp post-commit cleanup                                                   | Closed by Phase 7.5                                          | Move to ## Done with Track A step 01 commit ref.                                                                                                                                                                                                                                                                                                               |
| Rails-app keyboard shortcuts                                                         | Closed by Phase 7.5                                          | Move to ## Done with Track C step 04 commit ref.                                                                                                                                                                                                                                                                                                               |
| `pito` CLI screen layout parity with Rails app                                       | Closed by Phase 7.5                                          | Move to ## Done with Track B step 02 commit ref. Note that 8 cross-stack gaps surfaced (channel/video columns, settings panes, search disabled-stub) and were explicitly out of scope; those stay queued under a NEW carry-forward entry "CLI feature-parity sweep" with target = post-realignment per-domain CLI parity (work unit 10).                       |
| `pito` CLI Dependabot alert #1 (low severity) — `lru` + `paste` advisories           | Closed by Phase 7.5                                          | Move to ## Done with Track B step 02 commit ref. ratatui 0.30 bump cleared both advisories.                                                                                                                                                                                                                                                                    |
| CI cli job working-directory                                                         | Carry-forward                                                | Stays under ## Open. Not addressed in 7.5. Trigger unchanged ("any future CI sweep").                                                                                                                                                                                                                                                                          |
| Procfile.dev / bin/dev / Rails controller wiring for the `pito` binary               | Carry-forward                                                | Stays under ## Open. Not addressed in 7.5.                                                                                                                                                                                                                                                                                                                     |
| Stale `pito-sh` comments in Rails app                                                | Carry-forward                                                | Stays under ## Open. Not addressed in 7.5.                                                                                                                                                                                                                                                                                                                     |
| Footage API surface symmetry — namespace member actions under `/api/`                | Carry-forward                                                | Stays under ## Open. Not addressed in 7.5.                                                                                                                                                                                                                                                                                                                     |
| CodeMirror 6 importmap pinning                                                       | Carry-forward                                                | Stays under ## Open. Not addressed in 7.5.                                                                                                                                                                                                                                                                                                                     |
| Agent definition sync — install monolith renames into `~/.claude/`                   | Likely closed (verify)                                       | Architect cannot confirm from docs alone — the `install-claude-config.sh` script is at the user's discretion. Docs-keeper checks `ls ~/.claude/agents/` parity at close-out time; if synced, move to ## Done; else stays.                                                                                                                                      |
| Meilisearch indexing parity with Voyage per-target flags                             | Carry-forward                                                | Stays under ## Open. Realignment doc adjusts the trigger to "after Channel + Video schema expansion lands"; docs-keeper updates the trigger language inline.                                                                                                                                                                                                   |
| Re-prefix pito agents with `pito-*` for multi-project clarity                        | Closed (per the user's note about Phase 4 closeout sequence) | Per the user's auto-memory ("Phase 4 closeout sequence — bundle agent re-prefix + --prune into Phase B's final commit"), this should already be done. Docs-keeper greps `~/.claude/agents/` and `.claude-config/agents/` at close-out time to confirm; if so, move to ## Done; else stays.                                                                     |
| Implement `--prune` flag on `install-claude-config.sh`                               | Same as above                                                | Same disposition as the re-prefix entry above; pair them.                                                                                                                                                                                                                                                                                                      |
| `pito footage import` runtime validation against live `app.pitomd.com`               | Carry-forward                                                | Stays under ## Open. Phase 7.5 didn't ship a fresh CLI build to production.                                                                                                                                                                                                                                                                                    |
| Validate and commit Phase B-2 (note revamp + bulk + inline-delete)                   | Closed (Phase 4 work)                                        | Should already be in ## Done from Phase 4 closeout. Docs-keeper confirms; if still under ## Open, move it.                                                                                                                                                                                                                                                     |
| `pito` CLI footage handling end-to-end review                                        | Carry-forward                                                | Stays under ## Open.                                                                                                                                                                                                                                                                                                                                           |
| `fps` BigDecimal → string serialization in non-API FootagesController                | Carry-forward                                                | Stays under ## Open.                                                                                                                                                                                                                                                                                                                                           |
| `pito footage import` reports "X failed" when server actually succeeded              | Carry-forward                                                | Stays under ## Open.                                                                                                                                                                                                                                                                                                                                           |
| Wire footage bulk-mode (`Confirmable::TYPES` + delete behavior)                      | Carry-forward                                                | Stays under ## Open.                                                                                                                                                                                                                                                                                                                                           |
| Footage source column sorts by enum integer, not alphabetical                        | Carry-forward                                                | Stays under ## Open.                                                                                                                                                                                                                                                                                                                                           |
| Pre-existing rustfmt drift in extras/cli/                                            | Closed by Phase 7.5                                          | Move to ## Done with Track B step 02 commit ref.                                                                                                                                                                                                                                                                                                               |
| Videos new form `[add]` rebadge mirror                                               | Carry-forward                                                | Stays under ## Open.                                                                                                                                                                                                                                                                                                                                           |
| projects_controller.rb sort allowlist patterns repeat                                | Carry-forward                                                | Stays under ## Open.                                                                                                                                                                                                                                                                                                                                           |
| Filter chip group component — share between channels and footage                     | Carry-forward                                                | Stays under ## Open.                                                                                                                                                                                                                                                                                                                                           |
| `request.query_parameters.merge(sort:, dir:)` mixes string + symbol keys             | Carry-forward                                                | Stays under ## Open.                                                                                                                                                                                                                                                                                                                                           |
| `.filename-cell display: flex` on `<td>` — narrow viewport eyeball                   | Carry-forward                                                | Stays under ## Open.                                                                                                                                                                                                                                                                                                                                           |
| `bulk_select_controller.js` legacy comments mislead                                  | Carry-forward                                                | Stays under ## Open.                                                                                                                                                                                                                                                                                                                                           |
| Migrate /channels + /videos sort from URL hash to query params                       | Carry-forward                                                | Stays under ## Open. Realignment-doc tenant-drop work shouldn't touch these controllers' sort logic.                                                                                                                                                                                                                                                           |
| Meilisearch test isolation — `wait_for_tasks` race condition                         | Carry-forward                                                | Stays under ## Open.                                                                                                                                                                                                                                                                                                                                           |
| `docs/design.md:463` still references `--color-bg-alt` for the zebra rule            | Carry-forward                                                | Stays under ## Open. Trivial; docs-keeper MAY fix in the close-out commit since the docs surface is in scope this session, but architect's recommendation is to KEEP IT SEPARATE — close-out commits stay tightly scoped. Reassign target = next docs sweep.                                                                                                   |
| `--color-pane-bg` single-token alias has no consumers post-Wave-3                    | Carry-forward                                                | Stays under ## Open.                                                                                                                                                                                                                                                                                                                                           |
| `bulk_select_controller.js` comments mislead post-notes-always-on                    | Carry-forward                                                | Stays under ## Open.                                                                                                                                                                                                                                                                                                                                           |
| Wave 3 `:only-child` rule expands single-pane mobile from 88vw to 100vw              | Carry-forward                                                | Stays under ## Open.                                                                                                                                                                                                                                                                                                                                           |
| OmniAuth scope-walk fallback simplification in `config/initializers/omniauth.rb`     | Closed by Phase 7.5                                          | Move to ## Done with Track A step 01 commit ref. The Phase 7.5 hygiene sweep landed exactly the early-fail simplification this entry called for.                                                                                                                                                                                                               |
| 2026-05-09 realignment — top-level direction map                                     | Informational                                                | Architect's recommendation: leave under ## Open permanently as a "read first" notice for any session that touches the realignment work units. Same posture as the Phase 6 deviation entry.                                                                                                                                                                     |
| Phase 7.5 pre-specs 08 / 09 / 10 close-out                                           | **Closed by THIS spec**                                      | Move to ## Done with the Phase 19 close-out commit ref. The entry's own Resolution paragraph (2026-05-10) already records the per-spec dispositions; the close-out commit is the artifact.                                                                                                                                                                     |
| 2026-05-10: Realignment paperwork landed. Tenant-drop spec dispatch pending          | Carry-forward                                                | Stays under ## Open. Tenant drop dispatch is downstream of this close-out (Phase 8). The line should be updated to point at the close-out commit so the trail is complete.                                                                                                                                                                                     |

### New carry-forward entries this close-out CREATES

The disposition above promotes a small number of items that were "out of scope"
in earlier dispatches into formally-tracked carry-forwards. The docs-keeper adds
these as new entries under `## Open` in `docs/orchestration/follow-ups.md`:

1. **CLI feature-parity sweep — channels list / videos list / settings panes /
   search results.** Trigger: post-realignment per-domain CLI parity work unit
   (work unit 10). Source: Phase 7.5 Track B parity sweep surfaced eight
   cross-stack gaps that were explicitly out of scope. Listed in the Phase 7.5
   log entry for Track B step 02.

2. **Footage importer-side ffmpeg frame extraction + bulk PATCH upload.**
   Trigger: paired with the next dispatch that touches the footage importer, OR
   a dedicated "fill in real footage thumbnails" pass. Source: Phase 7.5 spec 06
   explicitly carved this out as a future dispatch. The Rails endpoint exists
   and is bearer-authed; the CLI half exists and is wired against wiremock
   fixtures. Only the importer's ffmpeg + multipart upload remains.

3. **Phase 7.5 smoke integration spec (optional).** Trigger: if the close-out
   playbook surfaces any regression that a wider integration test would have
   caught. Architect's recommendation: skip. Tracked here so it's not lost.

## Manual close-out playbook

The user runs this end-to-end against a fresh `bin/dev` boot. Each step is a
verification gate; any failure stops the close-out and routes the issue back to
the master agent for triage.

### 0. Pre-flight

```bash
git status                  # Working tree clean OR carrying only this spec.
git log --oneline -50       # Visible: Phase 7.5 dispatches landed in commit history.
bin/setup                   # Idempotent re-run; confirms pito-assets volume mkdir step works.
bin/dev                     # All services boot cleanly. No "missing google_oauth credentials".
```

### 1. Hygiene sweep (Track A)

1. **`Settings::SessionsController` `.unscoped` removal verified.** Sign in,
   visit `/settings/sessions`. The active sessions list renders with the
   `(this session)` annotation. Open `[revoke]` on a non-current row, confirm
   via the action screen, return to the index — the row is marked revoked.
2. **`:unprocessable_content` migration verified.** Submit the create-channel
   form with an invalid URL. The form returns with errors and the response
   status is 422. (The status code is the same in either token; the verification
   is that the controller's `render status: :unprocessable_content` lookup
   resolves cleanly and the form re-renders without raising.)
3. **OmniAuth simplification verified.** Visit `/settings/youtube`. If a Google
   account is connected, the connect-channel UI renders. If not, the connect
   button is visible. (The early-fail path was tested in the Track A log entry's
   manual recipe; the user need only confirm OmniAuth boots clean.)
4. **Channel Revamp orphan cleanup verified.**
   `grep -rn "_confirm_dialog\|confirm_dialog_controller" app/` returns zero
   matches.

### 2. Hygiene sweep (Track B)

1. **CLI rustfmt + clippy clean.**
   `cargo fmt --check --manifest-path extras/cli/Cargo.toml` exits 0.
   `cargo clippy --all-targets --all-features --manifest-path extras/cli/Cargo.toml -- -D warnings`
   exits 0.
2. **CLI tests pass.** `cargo test --manifest-path extras/cli/Cargo.toml`
   reports the post-Phase-7.5 baseline (448+ passing per the log).
3. **Dependabot advisory cleared.**
   `cargo audit --manifest-path extras/cli/Cargo.toml` reports zero advisories
   OR only advisories that postdate Phase 7.5.
4. **Channel-detail action legend verified.** Run `pito` (TUI default), navigate
   to a channel detail screen. Top action legend shows
   `[view] [sync] [delete]   (v) view  (Y) sync  (D) delete` — no `(s) star`
   keystroke hint. Star/unstar lives inline on the Starred KV row.

### 3. Concept + foundation specs (Track C)

1. **Decorator slim resolution closed.** No verification needed — the resolution
   was a documented no-op decision. Confirm the entry exists in the
   `follow-ups.md` ## Done section dated 2026-05-07.
2. **Keyboard shortcuts (spec 04).**
   - Visit `/`. Press `?` → help modal opens with five sections (general,
     navigation, list pages, detail pages, confirmation prompts).
   - Press `Esc` → modal closes.
   - Press `g` then `c` within ~1 second → URL navigates to `/channels`.
   - On `/channels`, press `f` then `s` → starred filter chip toggles (URL gains
     `?star=yes`).
   - On `/channels`, press `j` three times → third row gets the
     `keyboard-highlight` background.
   - Click the `[ ? ]` link in the top-right header → same modal.
   - Click into the search input, type `j` → letter `j` lands in the input (no
     row movement; focus guard).
   - Press `Ctrl+F` → browser-native find bar opens (no in-app override).
   - Open a channel detail page, press `v` → channel URL opens in a new tab.
   - From the channel-detail breadcrumb, click `[-]` (delete) → land on
     `/deletions/channel/:id`. Press `y` → form submits.
3. **`pito-assets` volume (spec 05).**
   - In `bin/rails console`:
     ```ruby
     Pito::AssetsRoot.root
     # => Pathname expected; in dev resolves under tmp/pito-assets unless PITO_ASSETS_PATH set.
     Pito::AssetsRoot.tenant_root(Tenant.first)
     # => Pathname under <root>/<tenant_id>/.
     ```
   - The directory exists on disk after `bin/setup`.
4. **Footage thumbnails (spec 06).**
   - Visit `/projects/:id` for a project that has at least one footage row. The
     footage table renders a leading thumb column. Cells will be broken-image
     glyphs (404) until the importer dispatch lands — that is expected.
   - Click into a footage row's filename → land on `/footages/:id`. The scrub
     layout renders above the metadata table: big preview area, `+` playhead
     glyph, scrolling strip below.
   - Until frames are seeded, the placeholder reads "no frames extracted yet."
   - Optionally seed via the §"Manual test plan" recipe in the log entry (drop
     JPEGs under `<assets_root>/footage_thumbs/<id>/{m,t}/...`) and reload — the
     scrub UI shows the masters, hover walks the timestamp, and the project-page
     row thumb fills in.
   - Test the wire shape:
     ```bash
     curl -s http://localhost:3027/footages/<id>/frames.json | jq .
     # => {"duration_seconds": <float>, "timestamps": [...]}
     curl -s -o /dev/null -w '%{http_code}\n' \
       "http://localhost:3027/footages/<id>/frames/m/..%2Fetc%2Fpasswd.jpg"
     # => 404 (path-traversal rejected by route constraint).
     ```
   - In `pito` (TUI), navigate to the same footage detail (programmatic for now;
     the nav surface is a follow-up). The preview renders via the terminal's
     graphics protocol if available; halfblocks otherwise.

### 4. Pre-spec dispositions (08 / 09 / 10)

1. `ls docs/plans/beta/7.5-followups-and-foundations/specs/` does NOT contain
   `08-timelines-resurrection-prespec.md`, `09-mcp-sync-prespec.md`, or
   `10-terminal-sync-prespec.md`.
2. `grep -r "08-timelines-resurrection-prespec\|09-mcp-sync-prespec\|10-terminal-sync-prespec" app/ extras/ docs/plans/beta/`
   returns zero matches outside `dropped.md`, `realignment-2026-05-09.md`, and
   the phase log.
3. No TBD comments referencing Timelines / MCP sync / Terminal sync exist in
   `app/` or `extras/`. (Architect cannot anchor this with a grep here; the
   docs-keeper or user runs the grep at close-out time. If matches surface,
   they're either historical context that's fine, or stragglers that should
   route into a new follow-up entry.)

### 5. Follow-ups posture

1. `docs/orchestration/follow-ups.md`'s `## Open` section reads cleanly. Each
   entry the close-out closed has been moved to `## Done` with its commit ref.
   Each carry-forward entry's trigger is current and points at a real future
   phase or a real condition.

### 6. Final sign-off

1. The user reads the close-out summary inline (the docs-keeper drafts this as
   the top of the new `log.md` entry; user reviews before the docs-keeper
   appends).
2. User commits the close-out as a single commit. Suggested message:
   `Phase 7.5 close-out — reconciliation, follow-ups disposition, plan complete`.
3. After commit, the user reads `docs/realignment-2026-05-09.md` work unit 11
   and sees the Resolution line pointing at the close-out commit.
4. **"Phase 7.5 is complete."** The next architect dispatch is the Phase 8
   tenant-drop spec (work unit 1).

## Tenant-drop interaction

Phase 7.5 shipped against the tenant-scoped data model. The realignment locks
the tenant drop as the very next work unit (work unit 1 in
`docs/realignment-2026-05-09.md`). Architect verified that every Phase 7.5
module survives the drop — but flags the modules that need docs-keeper attention
so the tenant-drop dispatch has a clean baseline.

| Phase 7.5 module                      | Tenant-touch                                                                                                          | Survives tenant drop                                                                                                                                                                                                                                                                                                                                                                  |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Track A — Sessions audit              | The `BelongsToTenant` concern was confirmed correct; `.unscoped` workaround was removed.                              | Yes. Tenant-drop removes `BelongsToTenant` entirely; `Current.user.sessions` association stays.                                                                                                                                                                                                                                                                                       |
| Track A — `:unprocessable_content`    | None.                                                                                                                 | Yes. Independent of tenant model.                                                                                                                                                                                                                                                                                                                                                     |
| Track A — OmniAuth init               | None.                                                                                                                 | Yes.                                                                                                                                                                                                                                                                                                                                                                                  |
| Track A — Channel Revamp orphans      | None (deletion only).                                                                                                 | Yes.                                                                                                                                                                                                                                                                                                                                                                                  |
| Track B — CLI hygiene sweep           | None.                                                                                                                 | Yes.                                                                                                                                                                                                                                                                                                                                                                                  |
| Track C — Decorator slim (no-op)      | None.                                                                                                                 | Yes.                                                                                                                                                                                                                                                                                                                                                                                  |
| Track C — Keyboard shortcuts          | None. Pure UI.                                                                                                        | Yes.                                                                                                                                                                                                                                                                                                                                                                                  |
| Track C — `pito-assets` volume        | `Pito::AssetsRoot.tenant_root(tenant)` accepts a tenant and builds `<root>/<tenant_id>/`. Tenant-drop removes Tenant. | **Needs touch.** `Pito::AssetsRoot.tenant_root` must collapse to `Pito::AssetsRoot.user_root(user)` OR retire entirely (single-install assumes `<root>/` is the tenant prefix). The tenant-drop spec covers this directly. Architect flags it here so the tenant-drop spec doesn't miss the helper.                                                                                   |
| Track C — Footage thumbnails (Rails)  | `Footage.unscoped.find` was used in public-read endpoints to bypass `BelongsToTenant::TenantContextMissing`.          | **Needs touch.** Tenant-drop removes `BelongsToTenant`; `Footage.unscoped.find(id)` collapses to `Footage.find(id)`. Tenant-drop spec must rewrite the `lookup_footage` helper. The path-traversal defense is unaffected. Tenant-namespaced paths (`<root>/<tenant_id>/footage_thumbs/...`) lose the tenant segment per the realignment doc's "Tenant-namespaced storage paths" drop. |
| Track C — Footage thumbnails (CLI)    | None. The CLI doesn't know about tenants.                                                                             | Yes.                                                                                                                                                                                                                                                                                                                                                                                  |
| In-flow — MCP OAuth + bearer dispatch | The bearer dispatch added a defense-in-depth `user.tenant_id == token.tenant_id` check.                               | **Needs touch.** Tenant-drop removes the column; the check disappears. Tenant-drop spec covers it.                                                                                                                                                                                                                                                                                    |
| In-flow — Doorkeeper polish + icons   | None.                                                                                                                 | Yes.                                                                                                                                                                                                                                                                                                                                                                                  |

The three "needs touch" items are NOT this close-out's responsibility. They are
flagged so the Phase 8 tenant-drop spec writer can pick them up cleanly without
re-deriving the list.

## Test coverage already in place

Architect cross-referenced shipped Phase 7.5 surfaces against existing test
files. No new specs needed for close-out. Coverage:

- Sessions audit: `spec/requests/settings/sessions_spec.rb` (3 cross-tenant
  regression specs added in Track A step 01).
- `:unprocessable_content` sweep: 26 callsites in `app/` already exercised by
  the existing request specs that posted invalid input.
- OmniAuth init simplification: covered by `bin/rails runner` boot test in the
  manual recipe; spec coverage via `config/initializers/omniauth.rb` boot
  through `spec/rails_helper.rb`.
- BracketedLinkComponent kwarg drop:
  `spec/components/bracketed_link_component_spec.rb`.
- CLI hygiene: `cargo test` (354 → 448 passing across the phase).
- Keyboard shortcuts:
  `spec/components/keyboard_shortcuts_modal_component_spec.rb` (9),
  `spec/requests/keyboard_shortcuts_layout_spec.rb` (22),
  `spec/components/filter_chip_component_spec.rb` (+2).
- `Pito::AssetsRoot`: `spec/lib/pito/assets_root_spec.rb` (29).
- Footage thumbnails Rails: `spec/requests/footages/frames_spec.rb` (11),
  `spec/requests/api/footages/frames_spec.rb` (8),
  `spec/requests/footages_spec.rb` (+1).
- Footage thumbnails CLI: 96 unit + 5 integration tests.
- MCP OAuth + bearer: `spec/requests/well_known_spec.rb` (6),
  `spec/requests/mcp/oauth_token_acceptance_spec.rb` (8).
- Doorkeeper polish: `spec/requests/oauth_scope_clip_spec.rb` (10),
  `spec/requests/settings/oauth_applications_spec.rb` (+3).
- Icon discovery: `spec/requests/manifest_spec.rb` (2),
  `spec/requests/favicon_spec.rb` (2), `spec/requests/well_known_spec.rb` (+2
  asserts on `logo_uri`).

Total Phase 7.5 spec delta (estimated from log entries): RSpec 1671 → 1795+
(roughly +124 specs); CLI tests 349 → 448+ (roughly +99 tests). The full test
suite gates the close-out: `bundle exec rspec` and
`cargo test --manifest-path extras/cli/Cargo.toml` must both be green.

## Documentation impact (post-validation)

The docs-keeper performs the following updates after the user signs off the
close-out playbook. None of these touch application code.

1. **`docs/plans/beta/7.5-followups-and-foundations/log.md`** — append a "##
   YYYY-MM-DD — Phase 7.5 close-out" entry containing:
   - Reconciliation summary (one-paragraph).
   - Reference to this spec at
     `docs/plans/beta/19-phase-75-closeout/specs/01-closeout-and-followups-resolution.md`.
   - Final RSpec + cargo test counts.
   - Commit ref of the close-out commit.
   - Sign-off line: "Phase 7.5 is complete; next dispatch is the Phase 8
     tenant-drop spec."

2. **`docs/plans/beta/7.5-followups-and-foundations/additions.md`** — append a
   "## YYYY-MM-DD — Final reconciliation" section noting that no items were
   added to Phase 7.5 itself by the realignment; all realignment work units are
   downstream phases. Add a one-line pointer to this close-out spec.

3. **`docs/plans/beta/7.5-followups-and-foundations/dropped.md`** — append a "##
   YYYY-MM-DD — Final reconciliation" section confirming the three pre-spec
   drops (08 / 09 / 10) are pinned. Add a one-line pointer to this close-out
   spec.

4. **`docs/plans/beta/7.5-followups-and-foundations/plan.md`** — flip the
   leading status line / tracker checkbox to "complete" and add a top-of-file
   pointer:
   `> **Status:** complete (closed by Phase 19; see docs/plans/beta/19-phase-75-closeout/).`
   Do NOT rewrite the historical workstream tracker — those checkboxes record
   what landed; they remain frozen.

5. **`docs/orchestration/follow-ups.md`** — execute the §"Follow-ups disposition
   table" above. Move closed entries to ## Done with their resolving commit
   refs. Update carry-forward entries' triggers where the realignment shifted
   the timing language. Add the three NEW carry-forward entries listed in §"New
   carry-forward entries this close-out CREATES".

6. **`docs/realignment-2026-05-09.md`** — work unit 11 ("Phase 7.5 pre-specs 08
   / 09 / 10 resolution") gets a Resolution line:
   `**Resolution:** closed by Phase 19 close-out commit <commit_hash>; see docs/plans/beta/19-phase-75-closeout/.`
   Same line added to the matching follow-up entry "Phase 7.5 pre-specs 08 / 09
   / 10 close-out" (already present at the bottom of that entry; just fill in
   the commit hash placeholder).

7. **`docs/plans/beta/19-phase-75-closeout/log.md`** — append the Phase 19
   close-out session entry: which user-validated steps in the playbook passed,
   which docs-keeper updates landed, and the final commit ref.

The close-out commit MUST land in a single commit (per the user's workflow rule
"commit directly to main with one-line meaningful messages"). Suggested message:
`Phase 7.5 close-out — reconciliation, follow-ups disposition, plan complete`.

## Cross-stack scope

| Surface               | In scope                      | Notes                                                                                                                                                      |
| --------------------- | ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rails web app         | No                            | Docs-only close-out. No application code, no migrations, no new specs.                                                                                     |
| MCP server            | No                            | Same.                                                                                                                                                      |
| `pito` CLI            | No                            | Same.                                                                                                                                                      |
| Cloudflare Pages site | No                            | Same.                                                                                                                                                      |
| Docs / orchestration  | Yes                           | The bulk of the work. Five files in `docs/plans/beta/7.5-followups-and-foundations/`, two files under `docs/orchestration/`, and one realignment-doc edit. |
| Tests                 | No (skip optional smoke spec) | Architect's recommendation: skip. If reviewer disagrees, escalate as a separate dispatch.                                                                  |

## Open questions

These are decisions the master agent answers before dispatching the docs-keeper.
None require user input — all have an architect's lean noted; the master can
override.

1. **Optional smoke spec — skip or land?** Architect's recommendation: **skip**.
   Each surface has dedicated coverage; a smoke spec adds maintenance burden
   without surfacing new signal. If overridden, the smoke spec becomes a
   separate `pito-rails-impl` dispatch under this same close-out phase, NOT
   folded into the docs-keeper's commit.

2. **Phase 6 deviation entry disposition — informational fixture or move to
   Done?** Architect's recommendation: \*\*leave as a permanent fixture under

   ## Open\*\*. The entry's value is its deterring future "fixers" from breaking

   `/settings/sessions` revocation by reverting to `cookie_store`. Moving it to

   ## Done loses that deterrent for casual readers. The 2026-05-09 realignment

   entry has the same shape and the same posture is recommended.

3. **`docs/design.md:463` `--color-bg-alt` zebra-rule fix.** Architect's
   recommendation: **keep separate**. The fix is trivial but the close-out
   commit should stay tightly scoped to phase reconciliation. Reassign the
   follow-up to "next docs sweep" rather than landing it inline. If the master
   prefers in-flow, route to a separate `pito-docs-keeper` dispatch and chain
   commits.

4. **Phase-complete status badging in the docs tree.** Architect's
   recommendation: **adopt a lightweight convention**. Each phase's `plan.md`
   gains a top-of-file `> **Status:** ...` line — values: `in flight`,
   `complete (closed by Phase NN)`, `superseded by ...`. This close-out is the
   first phase to use the convention; its `plan.md` flip is the precedent. Any
   prior phase that wants the badge gets it via a separate docs-keeper dispatch.
   If the master prefers to skip the convention, the close-out skips the
   `plan.md` status flip and just adds the pointer to this spec inline.

5. **Hidden carry-forward items in `docs/orchestration/follow-ups.md`.**
   Architect walked the file end-to-end. No item appears to lack a clean target
   phase post-realignment. If the docs-keeper finds an entry whose trigger
   condition is now structurally impossible (e.g., references a model that the
   tenant-drop will remove), they pause and escalate rather than silently
   retiring it.

6. **Reconciliation table commit-ref placeholders.** Architect cannot resolve
   `<commit>` placeholders without a session shell. The docs-keeper resolves
   each placeholder by walking `git log --oneline -- <file>` for the listed
   files at close-out time. Master agent: confirm this is the docs-keeper's
   responsibility, not architect's.

7. **In-flow dispatches reconciliation.** The dispatches under §"In-flow work
   outside the original plan" landed during the Phase 7.5 window but were never
   numbered specs. Architect classified them all as "Shipped + verified" and
   pinned them in the reconciliation table. Master agent: confirm this is the
   right disposition (vs. relegating them to a separate "Phase 7.5 sidebar"
   document). Architect's lean: keep them in the reconciliation table — they
   shipped in flow, they belong in the close-out trail.

## Master agent decisions (2026-05-10)

Master agent has resolved every open question per the autonomy rule, concurring
with all architect recommendations. Implementation agent (the close-out
docs-keeper) treats these as the contract.

1. **Optional smoke spec — skip.** No additional integration spec lands as part
   of this close-out. Each shipped Phase 7.5 surface already has dedicated
   coverage; a smoke spec adds maintenance burden without surfacing new signal.
   If a future reviewer flips this call, the smoke spec becomes a separate
   `pito-rails-impl` dispatch — never folded into the docs-keeper's commit.

2. **Phase 6 deviation entry disposition — leave as permanent fixture under
   `## Open` in `docs/orchestration/follow-ups.md`.** The entry's value is its
   deterring future "fixers" from breaking `/settings/sessions` revocation by
   reverting to `cookie_store`. Same posture for the 2026-05-09 realignment
   entry — both stay under `## Open` permanently as "read first" notices.

3. **`docs/design.md:463` `--color-bg-alt` zebra-rule fix — keep separate.** The
   fix is trivial but the close-out commit stays tightly scoped to phase
   reconciliation. Reassign the follow-up to "next docs sweep"; do not fold into
   the close-out commit.

4. **Phase-complete status badging convention — adopt.** Each phase's `plan.md`
   gains a top-of-file `> **Status:** ...` line. Permitted values: `in flight`,
   `complete (closed by Phase NN)`, `superseded by ...`. Phase 7.5 close-out is
   the first phase to use the convention; its `plan.md` flip is the precedent.
   Prior phases get the badge via separate docs-keeper dispatches if needed —
   the close-out does NOT retroactively backfill other phases.

5. **Hidden carry-forward items in `docs/orchestration/follow-ups.md` —
   architect's posture confirmed.** If the close-out docs-keeper finds an entry
   whose trigger condition is now structurally impossible (e.g., references a
   model the tenant-drop will remove), they pause and escalate rather than
   silently retiring it.

6. **Reconciliation table commit-ref placeholders — docs-keeper resolves at
   close-out time.** The docs-keeper walks `git log --oneline -- <file>` per the
   listed entries to substitute each `<commit>` placeholder with its actual
   hash.

7. **In-flow dispatches reconciliation — keep in the reconciliation table as
   architect classified.** The dispatches under §"In-flow work outside the
   original plan" shipped during the Phase 7.5 window; they belong in the
   close-out trail. They stay in the reconciliation table — no separate "Phase
   7.5 sidebar" document.

## Non-goals

- **No new Phase 7.5 production work.** The phase is closing, not expanding.
- **No new RSpec or cargo tests** (smoke spec is explicitly out of scope).
- **No changes to Phase 7.5 production code.**
- **No changes to other phase plans / specs / logs** beyond what is listed in
  §"Documentation impact (post-validation)".
- **No commit by the architect or docs-keeper.** The user commits after the
  playbook signs off (per the workflow rule "do NOT commit until the user has
  tested and validated the changes"). The docs-keeper writes the file changes;
  the user inspects + commits.
- **No changes to the `pito` CLI's binary distribution** — that is realignment
  work unit 12 (deferred ~6 months).
