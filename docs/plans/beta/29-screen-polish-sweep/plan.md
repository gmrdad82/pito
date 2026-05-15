# Phase 29 — Screen Polish Sweep — Lane A

> Read `docs/plans/beta/beta.md` first. Then read the beta-2 roadmap at
> `docs/plans/beta/29-screen-polish-sweep/roadmap.md`. Then read this `plan.md`.
> Per-screen specs land under `specs/` only after a `pito-reviewer` audit exists
> in `audits/` AND the user has triaged it.

---

## Goal

Step 1 of the beta-2 nine-step roadmap. Analyze, fix, and polish the web app
across the existing working screens — one screen at a time — using the
audit-first lifecycle declared in `roadmap.md`. The output is a denser, more
consistent, more accessible web app with no functional regressions and a
regression spec set that locks the polish in.

This phase is scoped to the **web** surface only. MCP / TUI / CLI parity work is
paused (per `CLAUDE.md` follow-ups + auto-memory). Any cross-surface consequence
of a polish change is deferred and noted in the per-screen spec.

---

## Scope statement

In scope:

- Per-screen polish across the existing working web surfaces (channels,
  projects, games, bundles, videos, notes / footage / timelines, settings
  sub-surfaces, security / sessions / tokens / oauth).
- Punch-list audits authored by `pito-reviewer` per screen.
- Polish specs authored by `pito-architect` per screen, including the regression
  spec mandate restated below.
- Regression specs landed in the same commit as each polish change.
- **Unit A0 — Channel read-only conversion** (see below) — runs first, ahead of
  the channel polish audit.

Out of scope:

- Net-new features (those belong in other lanes / phases).
- Cross-surface consequences (MCP / TUI / CLI). Deferred per pause.
- Design vocabulary consolidation across screens. That is Lane H
  (`35-design-consolidation/`) and runs after this lane closes.
- Cloudflare website (`extras/website/`).

---

## Unit A0 — Channel read-only conversion

> Placeholder at the plan level. The actual A0 spec is written by
> `pito-architect` only on per-lane greenlight — no implementation spec is
> authored here. See the roadmap's "Scope amendment — 2026-05-14: channel is a
> read-only mirror" section for the full Cut / Stays / Not-touched / Deferred
> lists.

Per the 2026-05-14 scope decision, the channel becomes a strictly one-way,
read-only mirror — YouTube to pito. pito never writes channel attributes back to
YouTube. Unit A0 removes the now-dead write-side machinery from the channel
surface. It runs **before** the channel polish audit (A-channels), so the
audit-first flow audits the post-cut surface.

**Scope — the cut (fat to remove from the channel surface):**

- `ChannelPreviewComponent` + `Channels::PreviewsController` + the
  `/channels/:id/preview` route — the entire live-preview machinery.
- Editable channel fields on `app/views/channels/edit.html.erb` and
  `app/views/channels/_form.html.erb` — title, handle, description, banner,
  avatar.
- `app/views/channels/_banner_upload.html.erb`,
  `app/views/channels/banner_updated.turbo_stream.erb`.
- The channel diff reconciliation surface: `app/views/channels/diff.html.erb`,
  `app/views/channels/_open_diff_banner.html.erb`, the `diff` action +
  `diff_channel_path` route, the `ChannelDiff` model + its table (a drop
  migration). `app/views/channels/_in_sync_banner.html.erb` is part of the same
  diff-banner family — flag it for review during A0 (likely also removed).

**Stays** (do not remove): the one-way sync pull, the `star` toggle,
URL-locked-after-create, per-channel analytics, the Google connection panel +
revoke flow, links display, the videos table, and **`ChannelChangeLog` / the
`/channels/:id/history` surface** — the read-only mirror's audit trail, kept
deliberately and distinct from the cut `ChannelDiff`.

**Not in scope:** the video thumbnail preview is a video-side surface — A0 does
not touch it.

**Deferred (MCP paused):** `channel_diff_show` / `channel_diff_apply` MCP tools
go dead and `update_channel` shrinks to star-only on a future MCP un-pause. A0
touches no MCP code.

**Lifecycle — NOT audit-first.** A0 is a straight `pito-architect` spec →
`pito-rails` impl. No `pito-reviewer` audit precedes it. On greenlight:

1. `pito-architect` writes the A0 cut spec under `specs/`.
2. `pito-rails` implements the cut and ships the regression specs in the same
   commit.

When the A0 spec is authored, an ADR under `docs/decisions/` should also be
authored — the one-way channel model is a structural commitment per
`CLAUDE.md`'s ADR criteria.

**Regression-spec requirement specific to A0** (in addition to the lane mandate
below):

- **System specs** asserting the channel edit form is gone, the preview routes
  are gone or return 404, and the diff routes are gone or return 404.
- A **model spec / migration spec** covering the `ChannelDiff` table drop — the
  table no longer exists, the model is removed.
- **Request specs** for every removed route (`/channels/:id/preview`, the `diff`
  action, the banner-upload / banner-updated endpoints) asserting they no longer
  resolve.

The channel polish audit (A-channels, audit-first flow) is **gated on A0 landing
first**. Every other Lane A audit screen is day-1 parallel.

---

## Unit A1 — AppSetting to credentials consolidation

> Spec authored: `specs/appsetting-credentials-consolidation.md`. A straight
> `pito-architect` spec → `pito-rails` impl unit — NOT audit-first.

Restores the project's stated configuration strategy: secrets live exclusively
in `Rails.application.credentials`; `AppSetting` is for runtime-mutable,
non-secret config only. During alpha / beta-1 three secret-bearing surfaces
drifted onto the `AppSetting` singleton — the YouTube OAuth + API credentials,
the Voyage AI embedding key, and the Google console credentials (the same
`:google_oauth` block). A1 drops all three from `AppSetting`, points every
consumer at credentials, removes the Settings UI panels that edit them, and
closes follow-up 3 (the omniauth hot-rotation gap) by accepting the tradeoff —
Google / YouTube config becomes deploy-time config.

Slack + Discord webhook config **stays** DB-backed and Settings-UI-managed.
Inventory confirmed it already lives on `NotificationDeliveryChannel` (not
`AppSetting`) and `webhook_url` is already encrypted with the same Active Record
Encryption mechanism the Voyage key used. The Slack / Discord settings panes
render and save **exactly as today** — storage is already correct; only an
orphaned `AppSetting.*_enabled` gate behind them changes.

**Lifecycle — NOT audit-first.** Straight `pito-architect` spec → `pito-rails`
impl:

1. `pito-architect` writes the A1 spec under `specs/`. **Done** —
   `specs/appsetting-credentials-consolidation.md`. The spec carries open
   questions the master agent resolves before dispatch.
2. `pito-rails` implements the consolidation and ships the regression specs in
   the same commit.

When A1 is implemented, a `docs/decisions/` ADR should record the reversal of
ADR 0007 (`youtube-credentials-moved-to-appsetting`) — moving credentials onto
`AppSetting` was a configuration-strategy violation; A1 restores the strategy.

**Regression-spec requirement specific to A1** (in addition to the lane mandate
below) — full enumeration lives in the spec; summary by layer:

- **Model specs** — `AppSetting` no longer carries the dropped columns /
  accessors; `NotificationDeliveryChannel#webhook_url` encryption round-trip.
- **Migration specs** — the column-drop migration (reversibility) and the
  defensive webhook re-encrypt migration.
- **Request specs** — Settings UI no longer exposes the YouTube / Voyage key
  panels; Slack / Discord panes still render and save.
- **System specs** — the Slack / Discord settings screen renders + saves
  exactly as before; the removed panels are gone.
- **Initializer / boot spec** — omniauth still configures the `google_oauth2`
  strategy from credentials.

A1 is independent of A0 and of the audit-first screens — it can run in parallel.

---

## Unit A2 — User auth refactor (username login + mandatory 2FA)

> Spec authored: `specs/user-auth-refactor.md`. A straight `pito-architect` spec
> → `pito-rails` impl unit — NOT audit-first.

Drops `email` from `User` and moves browser login to **username + password**.
The operator does not run SMTP or any email service, so email backs nothing —
it only carries account-existence risk and an unused format contract. Three
changes land in lockstep:

1. **email → username** — `users.email` (citext) is dropped and replaced by
   `users.username` (citext, NOT NULL, unique). The login form, sessions
   controller, account self-edit, and the `:owner` credentials block all swap
   from email to username. Destructive-and-reseed migration posture (ADR 0003 /
   `docs/setup.md`) — no production data, straight column swap.
2. **2FA mandatory from first login** — the Phase 25 TOTP infrastructure
   (already built as an optional second factor) becomes mandatory. A
   `before_action` in `Sessions::AuthConcern` gates every non-allowlisted route
   behind `totp_configured?`; an authenticated-but-unconfigured user is
   redirected into the TOTP setup flow until they finish. On a fresh seed the
   owner has no TOTP, so their first login is forced straight into enrollment.
3. **Reset-password via 2FA** — with no email there is no forgot-password
   email. A new `/password/reset` surface verifies username + a live TOTP code
   (or a backup code), then lets the user set a new password. Treated as a
   credential-recovery surface: throttled, no account-existence oracle, generic
   failure copy, session-invalidating on success.

`db/seeds.rb` also loses the project-workspace sample (Collection / Game /
Project / Note / Timeline) and the `now playing` Collection — see the spec's
"db/seeds.rb coordination" section, which enumerates the exact line ranges this
unit touches so it can be sequenced with the parallel A1 unit (A1 owns the
AppSettings block; A2 owns the owner seed + sample removal — disjoint ranges).

**Lifecycle — NOT audit-first.** Straight `pito-architect` spec → `pito-rails`
impl:

1. `pito-architect` writes the A2 spec under `specs/`. **Done** —
   `specs/user-auth-refactor.md`. The spec carries blocking open questions
   (backup-code acceptance in the reset flow, the lockout escape hatch, the
   first-login bootstrap path) the master agent resolves before dispatch.
2. `pito-rails` implements the refactor and ships the regression specs in the
   same commit.

This is a security-sensitive change: a `pito-security` `/security-review` pass
runs against the implemented diff after `pito-rails` finishes and before the
master agent commits.

**Regression-spec requirement specific to A2** (in addition to the lane mandate
below) — full enumeration lives in the spec; summary by layer:

- **Model specs** — `username` validations (presence, length, format,
  case-insensitive uniqueness, normalization); `email` column / validation
  gone; `totp_configured?` truth table; `totp_uri` provisions against username.
- **Migration spec** — `email` + its index dropped, `username` + unique index
  added.
- **Request specs** — login by username (happy / wrong-password / unknown /
  blank, no oracle); the mandatory-2FA gate blocks every non-allowlisted route
  and unblocks on enrollment; the full `/password/reset` flow (happy with TOTP
  code, happy with backup code, every sad path, throttling, no
  account-existence oracle, no session established on success); account-edit
  form swaps to username.
- **System specs** — fresh-seed first-login journey (seed → login → forced TOTP
  setup → unblocked); password-reset-via-2FA end to end.
- **Seed spec** — owner seeded from `credentials.owner.{username, password}`;
  no Channel / Video / Project / Game / Collection / Note / Timeline rows
  seeded; idempotent.

A2 is independent of A0 and the audit-first screens — it can run in parallel.
It touches `db/seeds.rb` alongside A1; the master agent sequences the two
`pito-rails` dispatches (one commits before the other starts) to keep the diff
legible.

**Docs impact (flagged for a `pito-docs` pass — A2 does NOT edit docs):**
`CLAUDE.md` (the `User` architecture note + the `:owner` block in
"Configuration strategy"), `docs/auth.md` (§1 login flow, §1a recovery snippet
+ the new reset-via-2FA flow, §8b audit payloads, §9 throttles), `docs/setup.md`
(§3 `:owner` block, §5 seed description).

---

## Dependencies (which lanes block this)

None. Lane A is greenlit-first per `roadmap.md`. It runs in parallel with Lanes
B, C, E, F, G when they greenlight. Internal to Lane A: the A-channels audit is
gated on unit A0 landing.

---

## Entry conditions

- User greenlight on Lane A in conversation (master agent does not self-open).
- Roadmap at `roadmap.md` exists and matches the current direction.
- `pito-reviewer` is available; `pito-architect` and `pito-rails` are available
  for sequential dispatch.

---

## Exit conditions

- Unit A0 has landed: the channel is a read-only mirror, its cut surface
  removed, A0 regression specs green in CI.
- Every targeted screen has:
  - An audit in `audits/<screen>.md` triaged by the user.
  - A polish spec in `specs/<screen>.md` referencing the audit.
  - A landed implementation with regression specs green in CI.
- Lane log (`log.md`) carries a session entry per screen close.
- No remaining open audit items the user wants addressed in this lane.

---

## Expected agents

- `pito-reviewer` — per-screen audit author. Read-only against the codebase;
  writes punch lists to `audits/`. Does **not** audit unit A0 (A0 is not
  audit-first).
- `pito-architect` — per-screen polish spec author, and the A0 cut spec author.
  Writes to `specs/` only.
- `pito-rails` — per-screen implementation and the A0 implementation, including
  the regression specs.

Master agent coordinates dispatch, reviews report-backs, and commits after user
validation.

---

## Regression spec mandate (restated for this lane)

Every polish unit ships its regression specs in the same commit. The per-screen
architect spec MUST enumerate the regression spec list before any `pito-rails`
impl runs.

| Layer of change               | Required regression spec type                                                                                  |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------- |
| View / page change            | RSpec **system spec** (Capybara) exercising the polished interaction                                           |
| ViewComponent change          | RSpec **component spec** rendering the component in isolation, asserting structure / classes / a11y attributes |
| Helper / partial logic        | RSpec **request spec** or focused **view spec**                                                                |
| Routing / controller behavior | RSpec **request spec**                                                                                         |
| Stimulus controller behavior  | RSpec **system spec** that exercises the JS path (Capybara + JS driver)                                        |

A change crossing layers carries the specs for **every** layer touched.
Additive, never substitutive. The impl agent reports back with green specs
before the master agent commits.

---

## Audit-first flow (restated for this lane)

> Applies to every Lane A unit **except A0, A1, and A2**. A0, A1, and A2 are
> straight architect-spec → rails-impl units — see their sections above.

1. **Audit** — `pito-reviewer` writes `audits/<screen>.md`. Covers alignment,
   density, copy, empty states, dead code, ViewComponent extraction candidates,
   a11y issues, naming inconsistencies, missing regression coverage.
2. **Triage** — user reviews the punch list, decides what moves into the spec.
3. **Spec** — `pito-architect` writes `specs/<screen>.md` with the regression
   spec list.
4. **Implement** — `pito-rails` implements the polish AND writes the regression
   specs in the same commit.

---

## Checkboxes

> Per-screen audits and specs land here as they are produced. None pre-written
> per the scaffold rule.

- [x] A0 — Channel read-only conversion (architect-spec → rails impl, NOT
      audit-first; runs before the A-channels audit). Spec written on
      greenlight. Rails impl landed 2026-05-14: channel is a read-only
      mirror, the edit/preview/banner/watermark/diff surface removed, the
      `channel_diffs` table dropped, star rides a dedicated
      `channel_star` path, A0 regression specs green.
- [x] A1 — AppSetting to credentials consolidation (architect-spec → rails
      impl, NOT audit-first). Spec authored:
      `specs/appsetting-credentials-consolidation.md`. Rails impl landed
      2026-05-14: the seven secret-bearing / orphaned columns dropped from
      `app_settings` (Voyage + YouTube credentials + the orphaned
      Slack/Discord `*_enabled` gate columns), every consumer re-sourced from
      `Rails.application.credentials`, the YouTube credentials Settings pane
      removed and the Voyage pane slimmed to the non-secret indexing toggle,
      the Slack/Discord delivery gate rewired to derive from the
      `NotificationDeliveryChannel` row (fixing the silently-dead delivery
      bug), and the `youtube_credentials_backfill` rake task deleted. A1
      regression specs green; full suite at the pre-existing 24-failure
      baseline.
- [ ] A2 — User auth refactor: username login + mandatory 2FA (architect-spec →
      rails impl, NOT audit-first). Spec authored:
      `specs/user-auth-refactor.md`. Drops `users.email` for `users.username`,
      makes TOTP 2FA mandatory from first login, adds a reset-password-via-2FA
      surface, and trims `db/seeds.rb` (no sample channels / videos / projects /
      games). Queued for `pito-rails` dispatch once the master agent resolves
      the spec's blocking open questions; a `pito-security` `/security-review`
      pass runs post-impl, pre-commit. Sequenced with A1 over the shared
      `db/seeds.rb` edit.
- [ ] A-channels polish audit + spec (audit-first; gated on A0 landing).
- [ ] Remaining per-screen audits and polish specs land here once the user
      greenlights the lane and triages each audit.

---

## References

- `docs/plans/beta/29-screen-polish-sweep/roadmap.md` — beta-2 umbrella,
  including the 2026-05-14 channel read-only scope amendment.
- `docs/notes/2026-05-11-21-58-29-beta-phase-roadmap.md` — source user note.
- `CLAUDE.md` — project rules, hard rules, surface pause directives.
- `docs/agents/architect.md` — spec pyramid rule D, bracketed-link rule A.
- `docs/design.md` — design vocabulary referenced by audits.
