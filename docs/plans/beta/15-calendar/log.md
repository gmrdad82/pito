# Phase 15 — Calendar Model + Views

> **Status:** specs landing 2026-05-10. Implementation pending.
>
> **Realignment work unit:** 7.
>
> **Cross-references:**
>
> - `docs/realignment-2026-05-09.md` — top-level direction map; work unit 7
>   ("Calendar model + views") plus Resolved ambiguity #5 (month grid + Schedule
>   view; day / week deferred).
> - `docs/notes/2026-05-09-19-14-10-calendar-and-notifications.md` — Mobile
>   note 5. Source of truth for the calendar entry shape, the eight `entry_type`
>   values, type-specific metadata jsonb, milestone rules, purchase-planned
>   entries, calendar views. The notifications half of the note is Phase 16
>   (next phase).
> - `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — single-
>   install posture; no `tenant_id` on any new table.
> - `docs/decisions/0004-mcp-scope-simplification-dev-app.md` — every new MCP
>   tool gates on the `app` scope. (Phase 15 does not ship MCP tools; the
>   coverage matrix is documented for Phase 16's sibling.)
> - `docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
>   — schema baseline this phase builds on.
> - `docs/plans/beta/12-video-schema-expansion/specs/01-video-schema-expansion-and-pre-publish-checklist.md`
>   — Phase 12. Establishes `videos.published_at`, `videos.publish_at`,
>   `videos.privacy_status`. Calendar's derived `video_published` /
>   `video_scheduled` entries depend on these columns existing.
> - `docs/plans/beta/14-game-model-igdb-sync/specs/01-data-model-and-igdb-client.md`
>   — Phase 14. Establishes `games.release_date`, `games.igdb_id`,
>   `games.igdb_slug`. Calendar's `game_release` derived entries depend on
>   `games.release_date` being populated.

## Specs in this phase

This phase ships as two feature specs to keep the data tier and the UI tier
self-contained and reviewable:

1. `specs/01-calendar-data-model.md` — `calendar_entries` table + the eight
   `entry_type` values + `milestone_rules` table + auto-derive jobs (from Video
   / Game / Channel) + manual entry CRUD model layer + idempotent firing
   semantics for milestone rules. Notification-firing hooks are declared here;
   delivery code is Phase 16.
2. `specs/02-calendar-views.md` — `/calendar/month/:year/:month` and
   `/calendar/schedule` routes + controllers + ERB views per `docs/design.md`
   - Stimulus navigation controller + quick-add manual entry form + edit /
     delete via the action confirmation page framework.

Each spec carries its own acceptance / test sweep / manual playbook.

## Cross-stack scope

| Surface           | Status                                                                                                                                                |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rails web app     | **In scope.** Primary lane.                                                                                                                           |
| MCP rack app      | **Skipped.** Realignment work unit 9. The calendar MCP tools (`calendar_list`, `calendar_create`, etc.) land alongside Phase 16's notification tools. |
| `pito` CLI (Rust) | **Skipped.** Realignment work unit 10. CLI parity for new domains is a separate dispatch.                                                             |
| Astro / website   | **Skipped.** N/A.                                                                                                                                     |

## Next

Master agent dispatches `pito-rails-impl` against the two specs in order once
the user signs off. Spec 1 is the foundation (Spec 2 reads / writes through Spec
1's models). Phase 16 (notifications) starts after Phase 15 lands and the user
validates.

## Sessions

### 2026-05-10 — Spec 01 + 02 implementation (rails-impl agent)

Both Phase 15 specs implemented in a single dispatch.

**Migrations (4 new):**

- `20260510120000_add_calendar_timezone_to_app_settings.rb` — adds `timezone`
  (default `"UTC"`) column to `app_settings`.
- `20260510120001_add_manual_date_override_to_games.rb` — adds the per-spec
  `manual_date_override` boolean to `games`. Phase 14 shipped its own
  `release_date` / `igdb_id` / `igdb_slug` columns via separate migrations
  during this session (no conflict on this column).
- `20260510120002_create_milestone_rules.rb` — declarative rule table. Bigint
  primary key (NOT UUID — see "Spec drift" below).
- `20260510120003_create_calendar_entries.rb` — the central entry table. 25
  columns, 14 scalar/btree indexes, 2 GIN indexes on jsonb columns, 3 partial
  unique expression indexes for the Q17 race-guard, 1 check constraint, 7
  foreign keys.

**Models / concerns / validators:**

- `app/models/calendar_entry.rb` (new) — central model with four enums,
  validators, scopes, read-only enforcement.
- `app/models/milestone_rule.rb` (new) — `fire!` / `re_arm!` helpers, scope_id
  presence rules, IANA tz validation.
- `app/models/concerns/calendar_derivable.rb` (new) — host mixin.
- `app/validators/calendar_entry_metadata_validator.rb` (new) — per-type
  metadata key allowlist.
- `app/validators/calendar_entry_cross_reference_validator.rb` (new) — required
  / forbidden FK shape per entry_type.
- `app/models/video.rb` (edit) — `include CalendarDerivable`,
  `after_save_commit` derivation hook.
- `app/models/channel.rb` (edit) — same. Single `after_save_commit` declaration
  (registering the same filter via two `after_*_commit` lines merges them in
  Rails 8.1, which silently broke the after_create_commit pre-fix; surfaced +
  corrected during impl).
- `app/models/game.rb` (edit) — same, with `respond_to?`-guarded `release_date`
  / `igdb_id` / `release_precision` reads so the hook works regardless of Phase
  14 column shape.
- `app/models/app_setting.rb` (edit) — `timezone` accessor + IANA validation.

**Services:**

- `app/services/calendar/derivation.rb` — `sync!` upsert by
  `(entry_type, source_ref)`, preserves `metadata.user_overrides`, `revoke!`
  (single-source_ref) + `revoke_all_for_host!` (typed-FK), supersedes prior
  derivations on transition (eg video_scheduled → video_published).
- `app/services/calendar/notification_dispatch_declaration.rb` — Phase 16
  contract. Returns notification kind/offset hashes per entry; suppresses
  pre-release reminders when a child `purchase_planned` exists with
  `notify_anyway=false`.
- `app/services/calendar/milestone_evaluator.rb` — injectable metric reader
  (Phase 13 will replace the stub); per-rule rescue so a bad rule does not block
  others.
- `app/services/calendar/occurred_flipper.rb` — flips ripe scheduled entries to
  occurred.

**Jobs:**

- `app/jobs/calendar_derivation_job.rb`, `app/jobs/milestone_evaluator_job.rb`,
  `app/jobs/calendar_occurred_flipper_job.rb` — registered as Sidekiq cron
  (`02:00 UTC` daily for milestone evaluator, `5 * * * *` hourly for occurred
  flipper).

**Routes / controllers (spec 02):**

- `config/routes.rb` — `/calendar`, `/calendar/month/:year/:month`,
  `/calendar/schedule`,
  `/calendar/entries/{new,quick_add,:id, :id/edit,:id/note}`, plus
  `DELETE /deletions/calendar_entry/:ids` with
  `defaults: { type: "calendar_entry" }` so the Confirmable concern can
  dispatch.
- `app/controllers/calendar/month_controller.rb`, `schedule_controller.rb`,
  `entries_controller.rb` (new) — strong params, manual-only entry types, strict
  yes/no rejection per CLAUDE.md.
- `app/controllers/concerns/confirmable.rb` (edit) — adds `calendar_entry` to
  TYPES + per-type scope (filter to `source: :manual` only) + cancel_path →
  calendar_schedule_path.
- `app/controllers/deletions_controller.rb` (edit) — adds
  `cancel_calendar_entry` member, dispatches calendar_entry type-show partial.

**Views (ERB):**

- `app/views/calendar/month/{show,_grid,_cell,_navigation, _filter_cluster}.html.erb`,
  `app/views/calendar/schedule/{show,_pagination}.html.erb`,
  `app/views/calendar/entries/{new,edit,show,_form}.html.erb`,
  `app/views/deletions/{show_calendar_entry,_calendar_entry} .html.erb`.
  Lowercase per docs/design.md, bracketed-link convention, no JS
  confirm/alert/prompt.

**ViewComponents:**

- `app/components/entry_chip_component.{rb,html.erb}` — the month-grid chip.
  Glyph + truncated title + state class + cross-link target per Q6/Q13.
- `app/components/entry_row_component.{rb,html.erb}` — the schedule-view row.
  Date / time / glyph + title / state.
- `app/helpers/calendar_helper.rb` — month_grid_dates + the glyph/state/time
  helpers.

**Stimulus controllers:**

- `app/javascript/controllers/calendar_navigation_controller.js` — `[`, `]`, `t`
  keyboard shortcuts on month grid.
- `calendar_filter_controller.js`, `calendar_entry_form_controller .js` —
  per-type sub-form toggle (no confirm/alert/prompt).

**Sidekiq cron:**

- `config/sidekiq_cron.yml` — registered `milestone_evaluator` (daily 02:00 UTC)
  and `calendar_occurred_flipper` (hourly).

### Test sweep

| Surface                              | Count                                   |
| ------------------------------------ | --------------------------------------- |
| spec/models/calendar_entry_spec.rb   | 66                                      |
| spec/models/milestone_rule_spec.rb   | 21                                      |
| spec/models/video*calendar*\*        | 5                                       |
| spec/models/channel*calendar*\*      | 3                                       |
| spec/models/game*calendar*\*         | 6 (1 pending)                           |
| spec/validators (2 files)            | 25                                      |
| spec/services/calendar (4 files)     | 39                                      |
| spec/jobs (3 files)                  | 7                                       |
| spec/components (2 files)            | 21                                      |
| spec/helpers/calendar_helper_spec.rb | 14                                      |
| spec/requests/calendar (3 files)     | 37                                      |
| spec/requests/deletions/calendar\_\* | 5                                       |
| spec/system (4 files)                | 13                                      |
| **Total**                            | **262 examples, 0 failures, 1 pending** |

Pending: `spec/models/game_calendar_derivation_spec.rb` — `manual_date_override`
IGDB-flow expectations live in Phase 14's IGDB sync flow, not in Phase 15.

### Quality gates

- `bundle exec rspec` (calendar suite + sanity sweep) — green.
- `bundle exec rubocop` (full repo, 534 files) — clean.
- `bundle exec brakeman -q -w2` — 0 security warnings.

### Spec drift / surfaced contract notes

- **UUID vs bigint.** The architect's spec calls for UUID primary keys per ADR
  0003; the existing schema (channels, videos, games, users, projects) uses
  bigint everywhere. New tables adopt bigint for FK referential consistency. ADR
  0003 may need a separate ADR-or-amendment for the URL-vs-PK distinction;
  surfaced for master-agent review.
- **`metric_window` enum.** Master decision said use short-form `7d` / `28d` /
  `90d` / `lifetime`. Implemented as Rails enum with the short-form names as
  keys (Ruby symbols quoted because `7d` isn't a valid bareword:
  `enum :metric_window, { lifetime: 0, "7d": 1, "28d": 2, "90d": 3 }`).
- **Phase 12 + Phase 14 parallel-run.** Both phases shipped migrations during
  this session, slightly ahead of Phase 15's bring-up. The Phase 12 migration
  `20260510135730_expand_videos_for_data_api_v3.rb` has a redundant
  `ALTER INDEX ... RENAME TO ...` block that Rails 8.1's `rename_table` already
  handles automatically; the migration succeeded on the second attempt (after
  the first attempt's transaction was discarded). Surfaced to master agent for
  Phase 12's review — may need a follow-up cleanup.
- **`after_create_commit` + `after_update_commit` callback merge.** Rails 8.1
  merges multiple `after_*_commit` declarations sharing the same filter symbol.
  The first hook on Channel was silently dropped when a second declaration with
  `if:` was added. Fixed by collapsing to a single `after_save_commit` per host
  model; surfaced as an implementation guardrail.

### Manual playbook (handed to user)

Both specs ship full manual playbooks. Spec 01 §1-§11 covers the data tier
(auto-derive, milestone rule fire, occurred flipper, cascade). Spec 02 §1-§19
covers the UI tier (month grid render, schedule, quick-add, edit, cancel,
navigation, filters, cross-links, edge cases).

### Blockers / next steps

- Phase 14's `release_precision` column is NOT yet on `games` (only
  `release_date`, `release_year`, `igdb_id`, `igdb_slug` shipped). Game-host
  derivation reads `release_precision` via `respond_to?` guard; once Phase 14
  ships the column, the Game re-derivation will start populating
  `calendar_entries.release_precision`. The current behavior leaves the column
  nil for all auto-derived game_release entries. One spec is `pending` waiting
  for Phase 14 IGDB-sync flow.
- MCP tools (`calendar_*`, `purchase_*`, `milestone_rule_*`) and Rust CLI parity
  are realignment work units 9 + 10 — deferred per spec scope.

---

## 2026-05-10 — Security audit follow-up (rails-impl)

Phase 15 reviewer / security audit produced two Medium findings (F1, F2) plus
three minor concerns (3, 4, 6). Bundled the cheap-win fixes in this session.

**Findings closed**

- **F1 — `bypass_readonly` whole-record bypass.** Replaced
  `attr_accessor :bypass_readonly` (Boolean short-circuit) on `CalendarEntry`
  with `attr_accessor :bypass_readonly_for` — an Array of attribute names. The
  `before_save` check now computes
  `forbidden_changes = changes.keys - %w[updated_at metadata] - allowlist` and
  treats `metadata` as fully bypassed only when `metadata` is explicitly in the
  allowlist (otherwise the existing `metadata_changes_only_user_overrides?`
  check still applies). Three call sites updated:
  - `Calendar::Derivation#upsert_existing!` — allowlist is the explicit
    `UPSERT_ALLOWED_ATTRIBUTES` constant:
    `%i[title description starts_at ends_at state metadata source_ref release_precision manual_date_override]`.
    Anything outside that set (e.g., a typed FK like `video_id`) is rejected
    even on the service code path.
  - `Calendar::EntriesController#note` — `bypass_readonly_for = [:metadata]`.
    The endpoint already only writes `user_overrides`, but the explicit scope
    keeps the bypass surface auditable.
  - `DeletionsController#cancel_calendar_entry` —
    `bypass_readonly_for = [:state]`. Soft-cancel only flips `state`; nothing
    else.
- **F2 — milestone-firing race window.** Added migration
  `20260510183815_add_unique_index_calendar_entries_milestone_rule.rb` — a
  partial unique index on `calendar_entries(milestone_rule_id)` scoped
  `WHERE entry_type = 6 AND source = 2`. Updated `MilestoneRule#fire!` to rescue
  `ActiveRecord::RecordNotUnique` and re-read `fired_at`: if the sibling caller
  already committed, the rescue returns the rule cleanly (the firing is
  idempotent). If `fired_at` is somehow still nil after reload (defensive branch
  — the surrounding transaction rolled back without a sibling commit landing),
  the exception is re-raised so the caller can decide.

**Reviewer concerns closed**

- **Concern 3** — `app/views/calendar/entries/show.html.erb` reminder copy is
  now the literal `[remind: t-7 t-1 t-0]`, not derived from
  `@declarations.map { |d| d[:kind] }`. Visibility is gated on
  `@declarations.any? { |d| d[:kind] == "game_release_upcoming" }` so the
  literal still only appears for entries that genuinely have pre-release
  reminders.
- **Concern 4** — Bracketed-link active-state divergence in the reminder copy:
  removed the inner padding (`[ remind: ... ]` → `[remind: ...]`) in both
  `show.html.erb` and `entry_row_component.html.erb`, matching the canonical
  `[label]` form rendered by `BracketedLinkComponent`.
- **Concern 6** — Removed the `[note]` link from the read-only branch of
  `show.html.erb`. The link pointed at a `modal-trigger` whose target
  (`note-modal`) was never rendered on the page, so clicks were no-ops. The
  PATCH `/calendar/entries/:id/note` endpoint is preserved (programmatic callers
  — MCP / future Rust client — and a future UI revival).

**Files touched**

- Models: `app/models/calendar_entry.rb`, `app/models/milestone_rule.rb`
- Services: `app/services/calendar/derivation.rb`
- Controllers: `app/controllers/calendar/entries_controller.rb`,
  `app/controllers/deletions_controller.rb`
- Views / components: `app/views/calendar/entries/show.html.erb`,
  `app/components/entry_row_component.html.erb`
- Migration:
  `db/migrate/20260510183815_add_unique_index_calendar_entries_milestone_rule.rb`
- Schema: `db/schema.rb` (regenerated)
- Specs: `spec/models/calendar_entry_spec.rb` (added 4 cases for the scoped
  allowlist), `spec/models/milestone_rule_spec.rb` (added 4 cases for the F2
  race-condition guard), `spec/services/calendar/derivation_spec.rb` (no-bypass
  on user_overrides metadata write),
  `spec/components/entry_row_component_spec.rb` (literal-form assertion),
  `spec/requests/calendar/entries_spec.rb` (canonical literal + no-modal
  assertions), `spec/models/channel_calendar_derivation_spec.rb` (comment
  refresh)

**Quality gates**

- `bundle exec rspec spec/models spec/services spec/components spec/requests spec/jobs spec/validators spec/helpers`
  — 3048 examples, 0 failures, 1 pending (pre-existing Phase 14 IGDB pending).
- `bundle exec rubocop` — 795 files, no offenses.
- `bundle exec brakeman -q -w2` — 0 security warnings, 0 errors. Two stale
  ignore entries flagged as "Obsolete Ignore Entries" (`4d586370...ba5`,
  `050af471...317`); pre-existing, unrelated to this session, surfaced to master
  agent for cleanup.

**Open issues**

- The `[note]` modal markup for derived/auto entries remains unbuilt. The PATCH
  endpoint stays in the controller; pick this up when the modal is designed (use
  `ConfirmModalComponent` or a sibling `note-modal` partial).
- `Calendar::Derivation::UPSERT_ALLOWED_ATTRIBUTES` is the source of truth for
  which derived-entry attributes the service overwrites. If a future spec adds a
  new column the service should write (e.g., a derived-entry `priority`), update
  the constant alongside the schema change.

## 2026-05-10 — Default-create entry flow (rails-impl, Projects pattern)

**Spec slug:** ad-hoc — no formal feature spec; user request to mirror the
`/projects` `[+]` default-create UX onto the calendar breadcrumb `[+]`.

**Why**

The previous flow forced the user to fill out a multi-field form (type / title /
description / starts_at / ends_at / all_day / timezone) before any row existed.
The Projects index already takes the opposite stance — `[+]` POSTs immediately
and lands the user on the edit page where real values are filled in. This
session ports that pattern to calendar entries so the breadcrumb `[+]` is a
one-click action that always succeeds.

**Files touched (high level)**

- `app/controllers/calendar/entries_controller.rb` — `create` short-circuits
  when `params[:calendar_entry]` is blank: builds a `milestone_manual` entry
  with `title="Untitled event"`, `starts_at=Time.current`, `ends_at=nil`,
  `all_day=false`, `timezone=AppSetting.first&.timezone || "UTC"`, saves, and
  redirects to `edit_calendar_entry_path`. Original payload-bearing flow (form
  POST, deep links, `quick_add`) is preserved verbatim.
- `app/views/calendar/month/_navigation.html.erb` — `[+]` swapped from a
  `BracketedLinkComponent` (GET to `new_calendar_entry_path`) to a `button_to`
  POST against `calendar_entries_path` with `data-turbo: false` so the redirect
  lands on the edit page. Markup mirrors the `/projects` index `[+]` exactly.
- `app/views/calendar/schedule/show.html.erb` — same swap as the month nav.
- `app/views/calendar/entries/_form.html.erb` — submit button copy tightened
  from `[ create ]` / `[ save ]` to `[create]` / `[save]` per
  `docs/agents/rails.md` rule A. The cancel link already uses
  `BracketedLinkComponent` (no inner spaces) and was untouched.
- `app/views/calendar/entries/new.html.erb` — left in place. The form still
  works for deep-link / programmatic access; `[+]` just streamlines past it.

**Specs added / updated**

- `spec/requests/calendar/entries_spec.rb` — new
  `describe "POST /calendar/entries (default-create — no params)"` block: 4
  examples covering (1) row shape after no-params POST, (2) redirect to `/edit`,
  (3) `AppSetting.first.timezone` honored, (4) edit page pre-populates with the
  placeholder values.
- `spec/requests/calendar/month_spec.rb` —
  `[+] link points at the new calendar entry path` rewritten to
  `[+] is a POST button_to to /calendar/entries (default-create per Projects pattern)`.
  Asserts `<form action="/calendar/entries" method="post" data-turbo="false">`
  wrapping a `[<span class="bl">+</span>]` `<button class="bracketed">`.
- `spec/system/calendar_quick_add_spec.rb` — `click_button "[ create ]"` →
  `click_button "[create]"`.
- `spec/system/calendar_edit_delete_spec.rb` — `click_button "[ save ]"` →
  `click_button "[save]"`.

**Quality gates**

- `bundle exec rspec spec/requests/calendar/ spec/system/calendar_quick_add_spec.rb`:
  75 examples, 0 failures.
- `bundle exec rspec spec/requests/calendar/ spec/requests/projects_spec.rb`:
  213 examples, 0 failures.
- `bundle exec brakeman -q -w2`: 0 security warnings.
- `spec/system/calendar_edit_delete_spec.rb`: pre-existing failure on the
  `[note]` link assertion (already documented in this log under "Phase 15
  reviewer concern 6 — read-only entries no longer expose a `[note]` link until
  the modal markup is built"). Untouched by this session.

**Open issues**

- None new. The `[note]` modal markup for read-only entries remains the
  pre-existing follow-up; not in scope for this session.

---

## 2026-05-10 — `[month]` toggle dead-click regression fix (rails-impl)

**User report.** Visiting `/calendar/schedule` and clicking `[month]` did
nothing.

**Spec slug:** ad-hoc — no formal feature spec; targeted regression fix
delegated by the master agent.

**Root cause.** The schedule view's `[month]` link targeted `calendar_root_path`
(`/calendar`). `/calendar` is the `Calendar::RouterController#show` page that
reads the `pito-calendar-view` localStorage key on connect and
`window.location.replace`s back to either the schedule or the month grid. Once
the user had any state where the router decided to land them back on schedule,
the toggle bounced the user right back — so the click looked dead.

**Fix.**

- `app/views/calendar/schedule/show.html.erb` — `[month]` now targets the
  canonical month URL directly (`/calendar/month/<year>/<month>` for the current
  month), bypassing the router. It also carries
  `data-action="click->calendar-view-router#persistMonth"` so the preference
  flips to `"month"` for subsequent fresh visits to `/calendar`.
- `app/views/calendar/month/_navigation.html.erb` — `[schedule]` already
  targeted `calendar_schedule_path` correctly; added the symmetric
  `data-action="click->calendar-view-router#persistSchedule"` so the preference
  flips to `"schedule"`.
- Both toggles are wrapped in `<span data-controller="calendar-view-router">` so
  the action descriptor finds an ancestor controller (the breadcrumb-actions
  slot lives in the layout's `<nav>`, outside any view-level controller mount).
- `app/javascript/controllers/calendar_view_router_controller.js` — extended
  with `persistMonth` / `persistSchedule` action methods (best-effort writes;
  localStorage failure does not block navigation). `connect()` clarified: only
  redirects when a corresponding `*PathValue` is wired, so mounting the
  controller on a regular calendar view (without `month-path-value` /
  `schedule-path-value`) is a safe no-op.

**Files touched**

- Views: `app/views/calendar/schedule/show.html.erb`,
  `app/views/calendar/month/_navigation.html.erb`
- Stimulus: `app/javascript/controllers/calendar_view_router_controller.js`
- Specs: `spec/requests/calendar/schedule_spec.rb` (3 new cases: canonical
  href + persist action, span wrapper, NOT routed through `/calendar`),
  `spec/requests/calendar/month_spec.rb` (2 new cases: canonical href + persist
  action, span wrapper), `spec/system/calendar_schedule_filter_spec.rb`
  (existing `[month]` click-through case retargeted to assert the canonical
  month URL)

**Quality gates**

- `bundle exec rspec spec/requests/calendar/` — 72 examples, 0 failures.
- `bundle exec rspec spec/system/calendar_schedule_filter_spec.rb:32 spec/system/calendar_month_navigation_spec.rb:40`
  — 2 examples, 0 failures (the two toggle-link click-through system cases).
- `bin/brakeman -q -w2` — 0 security warnings, 0 errors.

**Open issues**

- The pre-existing `[+] in the breadcrumb actions links to the new entry form`
  system specs (in both `calendar_schedule_filter_spec.rb` and
  `calendar_month_navigation_spec.rb`) fail because the sibling default-create
  change flipped the breadcrumb `[+]` from a link to a `button_to`; the system
  specs still call `click_link "+"`. Out of this lane's scope — already surfaced
  as a follow-up to the agent that owns the `[+]` migration.

**Manual playbook**

1. Open `/calendar/schedule` in a browser. Confirm `[month]` click lands on
   `/calendar/month/<current-year>/<current-month>` and the page renders the
   month grid.
2. Open DevTools → Application → Local Storage → site origin. Confirm
   `pito-calendar-view = "month"` after the click.
3. Click `[schedule]` from the month view. Confirm it lands on
   `/calendar/schedule` and `pito-calendar-view = "schedule"`.
4. Visit `/calendar` directly. Confirm it now resolves to the
   most-recently-toggled view (schedule) without flicker.
5. Wipe `pito-calendar-view` from localStorage and visit `/calendar` again.
   Confirm it falls through to the current month grid.

### 2026-05-10 — Calendar UX restructure (rails-impl agent)

Per master-agent dispatch (no architect-written spec; the dispatch prompt was
the contract). Restructured the calendar chrome to:

1. **Move `[schedule]` / `[month]` toggle + `[+]` quick-add into the layout's
   `:breadcrumb_actions` slot.** Each calendar page emits a
   `content_for :breadcrumb_actions` block that the global
   `application.html.erb` already yields trailing the breadcrumb crumbs (no
   layout edit required — the slot was already wired). The dedicated shared
   partial `app/views/shared/_dot_separator.html.erb` renders the muted `·`
   glyph between the breadcrumb and the action cluster.

2. **Persist the active calendar view in `localStorage`
   (`pito-calendar-view`).** `/calendar` switched from a server-side redirect to
   a thin `Calendar::RouterController#show` shell that mounts the
   `calendar-view-router` Stimulus controller; the controller `replace`s the URL
   with the saved view (schedule or the current month grid) and falls through a
   `<meta http-equiv="refresh">` to the month grid for non-JS clients. The
   `[schedule]` / `[month]` toggle links target the canonical view URLs directly
   (NOT `/calendar`, which would let a stale preference swallow the click) and
   carry a `persistMonth` / `persistSchedule` Stimulus action that writes the
   new preference on click.

3. **Rebuild the kind filter as a multi-value csv contract (`?types=`).** The
   previous single-value `?type=video` contract is gone. The new shape:
   - No `types` param → all 5 kinds rendered (default = "all checked").
   - `?types=a,b,c` → only those kinds rendered (union of mapped `entry_type`
     values).
   - `?types=` (empty) → no kinds rendered ("all unchecked"). Validation drops
     unknown labels silently. A `[ ] all` synthetic master toggle is checked
     when the param is absent OR every individual kind label is in the csv;
     clicking it sets the URL to the "everything unchecked" / "default = all
     checked" extreme. The 5 individual chips toggle their own label in/out of
     the csv. URL is the single source of truth; clicking a chip navigates
     rather than mutating client-side state.

4. **Convert `[+]` to a `button_to` default-create (Projects pattern).** POSTs
   to `/calendar/entries` with no payload; the controller's `create` action
   already supported the default-create branch (seeds an "Untitled event"
   milestone_manual entry, redirects to `/edit`).

5. **Drop the inline `prev month` / `next month` labels** in favor of `[prev]` /
   `[next]` (no-inner-space bracketed-link rule) aligned via
   `justify-content: space-between` flex so prev anchors left, next anchors
   right, `[today]` sits in the middle when not on the current month.

6. **Tighten the schedule's "include cancelled" affordance** into a
   `[ ] include cancelled` filter-chip-style checkbox (matching the type
   filters' visual rhythm).

**Files touched**

- Controllers: `app/controllers/calendar/month_controller.rb`,
  `app/controllers/calendar/schedule_controller.rb`,
  `app/controllers/calendar/router_controller.rb` (new)
- Helpers: `app/helpers/calendar_helper.rb` (new `calendar_active_kinds` /
  `calendar_kind_checked?` / `calendar_all_kinds_checked?` /
  `calendar_kind_chip_href` / `calendar_all_kinds_chip_href`,
  `CALENDAR_KIND_LABELS` constant)
- Components: `app/components/filter_chip_component.rb` (new opt-in `csv:`
  multi-value mode; existing single-value contract preserved)
- Views: `app/views/calendar/month/show.html.erb`,
  `app/views/calendar/month/_navigation.html.erb`,
  `app/views/calendar/month/_filter_cluster.html.erb`,
  `app/views/calendar/schedule/show.html.erb`,
  `app/views/calendar/router/show.html.erb` (new),
  `app/views/shared/_dot_separator.html.erb` (new)
- JS: `app/javascript/controllers/calendar_navigation_controller.js`,
  `app/javascript/controllers/calendar_filter_controller.js`,
  `app/javascript/controllers/calendar_view_router_controller.js` (new)
- Routes: `config/routes.rb` (replaced the `/calendar` redirect with the
  `calendar/router#show` mount; canonical URLs unchanged)
- Specs: `spec/requests/calendar/month_spec.rb` (rebuilt around `?types=`
  contract, breadcrumb_actions assertions, default-create `[+]` form),
  `spec/requests/calendar/schedule_spec.rb` (same),
  `spec/requests/calendar/router_spec.rb` (new — router shell),
  `spec/system/calendar_month_navigation_spec.rb`,
  `spec/system/calendar_schedule_filter_spec.rb`,
  `spec/components/filter_chip_component_spec.rb` (new csv-mode cases),
  `spec/helpers/calendar_helper_spec.rb` (new helper cases)

**Quality gates**

- `bundle exec rspec spec/requests/calendar/ spec/system/calendar_* spec/components/filter_chip_component_spec.rb spec/components/bracketed_link_component_spec.rb spec/helpers/calendar_helper_spec.rb`
  — 152 examples, 0 failures.
- `bundle exec rubocop` on the changed Ruby files — 15 files, 0 offenses.
- `bundle exec brakeman -q -w2` — 0 security warnings, 0 errors. Two stale
  ignore entries flagged (`4d586370…ba5`, `050af471…317`) — pre-existing,
  unrelated to this session.
- Broader sweep (`spec/components spec/helpers spec/requests`) — 7 pre-existing
  failures unrelated to this session (notes editor / dashboard five-count /
  bundle / channels / projects). Spot-confirmed via stash: the same set fails
  without my changes.

**Open issues**

- The schedule view's `?source=<source>` filter is still a redirect-on-invalid
  flash. Future polish: convert it to csv too (`?sources=manual,igdb`) for
  consistency with `?types=`.
- The keyboard `f <kind>` shortcuts (mirror of `[ ] all` / `[ ] video` etc.) are
  not yet wired in the global keyboard controller. Follow-up if the rails-app
  keyboard shortcut work-stream resumes.
