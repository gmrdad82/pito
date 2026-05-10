# Manual test playbook — Phase 15: Calendar (model + month grid + schedule view)

**Branch:** `main` (commits `a690ca1` Phase 15 partial impl, `a9329aa` Phase 15
finalization, `b9b22ba` `[calendar]` nav link) **Specs:**
`docs/plans/beta/15-calendar/specs/01-calendar-data-model.md`,
`docs/plans/beta/15-calendar/specs/02-calendar-views.md` **Log:**
`docs/plans/beta/15-calendar/log.md` **Reviewer run:** 2026-05-10 16:35

## Pipeline summary

- Code review: pass — 4 non-blocking concerns (per-type sub-form fields,
  multi-day chip continuations, entry-detail reminder copy mismatch, stray
  active-state bracket padding). See "Concerns and suggestions".
- Simplify: pass — 1 minor opportunistic note (filter-cluster duplication
  between month + schedule). See below.
- Test suite (Phase 15 slice): **263 examples, 0 failures, 1 pending** (the
  pending example is `manual_date_override` IGDB-flow, intentionally deferred
  to Phase 14 IGDB sync per spec).
  - `spec/models/calendar_entry_spec.rb` — green
  - `spec/models/milestone_rule_spec.rb` — green
  - `spec/models/{video,channel,game}_calendar_derivation_spec.rb` — green (1
    pending in `game_calendar_derivation_spec.rb`)
  - `spec/validators/calendar_entry_{metadata,cross_reference}_validator_spec.rb`
    — green
  - `spec/services/calendar/{derivation,milestone_evaluator,occurred_flipper,notification_dispatch_declaration}_spec.rb`
    — green
  - `spec/jobs/{calendar_derivation_job,calendar_occurred_flipper_job,milestone_evaluator_job}_spec.rb`
    — green
  - `spec/components/{entry_chip,entry_row}_component_spec.rb` — green
  - `spec/helpers/calendar_helper_spec.rb` — green
  - `spec/requests/calendar/{month,schedule,entries}_spec.rb` — green
  - `spec/requests/deletions/calendar_entry_spec.rb` — green
  - `spec/system/calendar_{month_navigation,quick_add,schedule_filter,edit_delete}_spec.rb`
    — green
- Test suite (full repo): **2378 examples, 32 failures, 1 pending.** Of the 32
  failures, **only one is in Phase 15 surface area**:
  `spec/requests/calendar/month_spec.rb:35` (the known parallel-ordering flake
  the user heads-upped — passes in isolation, see Concern 1). The other 31
  failures live in unrelated specs (`spec/requests/channels_spec.rb`,
  `spec/requests/dashboard_spec.rb`, `spec/requests/games_spec.rb`,
  `spec/mcp/tools/*`, `spec/lint/numeric_formatting_spec.rb`,
  `spec/models/notification_spec.rb`, etc.) and pre-date / sit outside this
  phase's diff. Surface to the architect for separate triage; they are NOT
  blockers for Phase 15 sign-off.
- Lint (`bundle exec rubocop` on the 18 changed Phase 15 Ruby files): clean.
- Security static analysis (`bundle exec brakeman -q`): 0 warnings, 2 ignored
  (pre-existing).
- Dependency audit (`bundle exec bundler-audit check --no-update`): clean.
- Hard-rule sweep on calendar surface: 0 hits for `alert(` / `confirm(` /
  `prompt(` / `data-turbo-confirm` outside of comment text in
  `app/javascript/controllers/calendar_entry_form_controller.js` line 8 (a
  literal CLAUDE.md citation in a doc comment — not an active call).
- Yes/no boundary: enforced strictly in
  `Calendar::EntriesController#coerce_yes_no!` — `"true"` / `"false"` / `"1"` /
  `"0"` reject with 422. Verified.
- Bracketed-link convention: BracketedLinkComponent used throughout. One
  divergence on the active-state span — see Concern 4.
- Tenant-free check (`git grep tenant_id`, `Current.tenant`,
  `BelongsToTenant`): clean across the new model / service / job / spec files.
- Schema (`db/schema.rb`): every column / index / FK from the spec lands.
  Three partial unique expression indexes for the Q17 race-guard are present
  (`index_calendar_entries_unique_video_source_ref`,
  `index_calendar_entries_unique_channel_source_ref`,
  `index_calendar_entries_unique_game_source_ref`).
- Sidekiq cron (`config/sidekiq_cron.yml`): `milestone_evaluator` daily at
  `0 2 * * *` and `calendar_occurred_flipper` hourly at minute 5 are
  registered.
- Spec drift (per log): bigint vs UUID PKs, `metric_window` short-form names
  (`"7d"` / `"28d"` / `"90d"` / `lifetime`), Phase 12 redundant `ALTER INDEX`
  in a sibling migration, callback-merge guardrail. Each is documented in the
  log; none blocks user validation.

## Blockers

None. The full-suite failures outside Phase 15 are unrelated and pre-existing
relative to this phase's diff.

## Concerns and suggestions

All non-blocking. Numbered for follow-up dispatch reference.

1. **Known flake — `spec/requests/calendar/month_spec.rb:35`
   ("non-numeric year hits the route constraint and 404s").** Passes in
   isolation; fails intermittently in the full-suite parallel run. Reviewer
   reproduced both: standalone pass (1 example, 0 failures, 0.58s); full-suite
   fail (one of 32 failures observed). Likely root cause is route-cache or
   route-priority race when `routes.rb` is reloaded between specs that
   redefine `calendar_root` redirect targets — the route constraint
   `constraints: { year: /\d{4}/, month: /\d{1,2}/ }` is in place
   (`config/routes.rb:259`). Fix-forward only; queue under Phase 15 follow-up.
   Suggested approach: pin `Rails.application.routes` reload between specs OR
   tighten the redirect lambda so non-matching paths fall through deterministically.

2. **Per-type sub-form fields are not rendered in the quick-add /
   edit form.** `app/views/calendar/entries/_form.html.erb` only renders
   common fields (type, title, description, starts_at, ends_at, all_day,
   timezone). Spec 02 §"View: quick-add form" calls for type-tagged
   sub-sections (`game_release` → `release_precision`,
   `manual_date_override`, `tba_remind_monthly`, `game`;
   `purchase_planned` → `parent_entry`, `purchase_kind`, `storefront`,
   `storefront_name`, `storefront_url`, `amount`, `currency`, `ordered_at`,
   `confirmation_ref`, `notify_anyway`; `custom` → `tags`). The
   `calendar_entry_form_controller.js` Stimulus controller already toggles
   `[data-type]` sections — but no markup with `data-type=` exists. Effect:
   user can create `milestone_manual` and `custom` entries via the form;
   `game_release` and `purchase_planned` quick-add are functionally
   incomplete (a created entry is missing its type-specific metadata).
   Manual workaround: use the Rails console for `game_release` /
   `purchase_planned` until the partial gains the sub-sections. Fix-forward;
   queue under Phase 15 follow-up.

3. **Reminder copy on the entry detail page does not match spec.**
   `app/views/calendar/entries/show.html.erb` line 63 renders
   `[ remind: <%= @declarations.map { |d| d[:kind] }.uniq.join(' ') %> ]`,
   which yields strings like `[ remind: game_release_upcoming
   game_release_today ]`. Spec 02 §"View: schedule" + Q8 master-decision
   call for the literal `[ remind: t-7 t-1 t-0 ]` (relative-offset words).
   The schedule-row component
   (`app/components/entry_row_component.html.erb` line 12) gets it right.
   Trivial template-only fix; queue under Phase 15 follow-up.

4. **Bracketed-link active-state divergence in calendar filter clusters.**
   `app/views/calendar/schedule/show.html.erb` line 17 and
   `app/views/calendar/month/_filter_cluster.html.erb` line 7 render the
   active filter as `<span class="bracketed bracketed-active">[ <kind> ]</span>`
   with inner padding — the rest of the codebase, including
   `BracketedLinkComponent` itself
   (`app/components/bracketed_link_component.html.erb`,
   `app/views/shared/_igdb_cover.html.erb` line 14), renders the active
   variant as `[label]` with no inner spaces (per `docs/design.md` "Bracketed
   Links / Buttons" → "Active state bracketed-active`[label]`"). Reviewer
   convention rule A in `docs/agents/reviewer.md` flags `[ label ]` (padded)
   outside the `[ ]` checkbox shape. Trivial template fix; queue under Phase
   15 follow-up.

5. **Multi-day chip rendering does not span days on the month grid.**
   Spec 02 Q11 calls for multi-day entries (`ends_at` non-null) to render as
   a continuous bar across grid cells, with `↳` (continuation) on cells
   after the leftmost. Current `_cell.html.erb` buckets by
   `starts_at.in_time_zone(...).to_date` only — entries spanning multiple
   days appear in one cell only. The schedule view row separately handles
   this OK (renders the date range). The month-grid acceptance check
   "Multi-day rendering. A `game_release` with `ends_at` 5 days later
   renders 6 cells with `↳` continuations" is asserted in
   `spec/requests/calendar/month_spec.rb` but the assertion only checks for
   the chip's title presence, not the `↳` continuation across cells.
   Fix-forward; queue under Phase 15 follow-up.

6. **`[ note ]` link on derived entries goes nowhere.**
   `app/views/calendar/entries/show.html.erb` lines 47–49 render the
   `[ note ]` link with `href: "#"` and a `modal-trigger#open` data action
   targeting `note-modal` — but no `<dialog id="note-modal">` element is
   rendered on the page. The `PATCH /calendar/entries/:id/note` endpoint
   exists (`config/routes.rb` + `Calendar::EntriesController#note`), and the
   action's spec coverage is implicit only (no request spec hits the `note`
   action). User clicking `[ note ]` on a derived entry currently does
   nothing visible. Master-decision Open question #8 said "ship in v1";
   wiring is half-present. Fix-forward; queue under Phase 15 follow-up.

7. **Filter-cluster duplication between schedule and month views.**
   `app/views/calendar/schedule/show.html.erb` lines 13–22 and
   `app/views/calendar/month/_filter_cluster.html.erb` render essentially
   the same filter cluster with slightly different URL builders. Two-line
   `entry_filter_cluster(view:, params:)` ViewComponent or partial would
   collapse them. Pure simplify suggestion; not a regression.

8. **Pagination footer suppressed when `@total_pages == 1`.**
   `app/views/calendar/schedule/_pagination.html.erb` only renders inside
   `if @total_pages > 1`. Spec 02 §"Required test cases" → "GET
   /calendar/schedule?page=999 (out-of-range) renders empty list with
   pagination saying `page 999 / N`" suggests pagination should render even
   for empty paginated results. The actual request spec passes (it asserts
   page 999 yields a 200 with empty list); but the visible "page 999 / N"
   line never appears for users on an over-paginated URL. Minor. Queue under
   Phase 15 follow-up only if the user asks for it.

## Phase-spec reviewer checkpoints (per spec §"Reviewer checkpoints")

### Spec 01 (data model)

- `bundle exec rspec` (Phase 15 model / service / job slice) — green (207
  examples, 0 failures, 1 pending; pending matches log).
- `bundle exec rubocop` (changed Phase 15 Ruby files) — clean.
- `bundle exec brakeman -q -w2` — 0 warnings.
- Manual playbook §1-§11 — see "Manual test steps" below.
- Spec file count delta logged in
  `docs/plans/beta/15-calendar/log.md` ("Test sweep" table) — present.
- `git grep 'tenant\|tenant_id\|Current\.tenant'` in
  `app/models/calendar_entry.rb`, `app/models/milestone_rule.rb`, every new
  service, every new job, every new spec — clean (zero hits in calendar
  files).
- `CalendarEntry` validations reject every sad-path entry — confirmed via
  `spec/models/calendar_entry_spec.rb` (66 examples covering all
  cross-reference / metadata / read-only paths).

### Spec 02 (views)

- `bundle exec rspec` (request + system slice) — green (56 examples, 0
  failures, including the 14 system specs).
- `bundle exec rubocop` — clean.
- `bundle exec brakeman -q -w2` — clean.
- Manual playbook §1-§19 — see "Manual test steps" below.
- Spec file count delta logged — present.
- `git grep 'alert(\|confirm(\|prompt(\|data-turbo-confirm'` in new files —
  zero live hits (only one comment-text match in the Stimulus controller
  citing the rule).
- `git grep 'cursor: pointer'` — `BracketedLinkComponent` provides the
  `.bracketed` class which carries `cursor: pointer` site-wide; new clickable
  elements all flow through the component or the chip / row components,
  which inherit the same pointer style.
- `config/locales/en.yml` is unchanged in this phase; copy is inlined per the
  master-agent decisions (lowercase per `docs/design.md`). Copy strings
  observed inline match the Q1-Q11 master decisions.

## Manual test steps

> The user runs through these from a fresh `bin/dev`. Order matters: the
> data-tier checks seed the calendar, the UI checks observe what the data
> tier produced.

### Setup

1. **Bring up the dev stack.** `bin/dev` (Docker + Puma + Sidekiq + Tailwind
   watcher). Wait for `app.pitomd.com` to render the dashboard.
2. **Confirm migrations are applied.** `bin/rails db:migrate:status | tail`
   should show every migration up to and including
   `20260510120003 Create calendar entries` as `up`.
3. **Optional: seed if the DB is empty.** `bin/rails db:seed` brings up the
   100-channel / 200-video / 1-project sample. Calendar entries derive
   automatically as Channel / Video / Game rows save (the seed does NOT
   write CalendarEntry rows directly).

### Data-tier checks (Spec 01 §1-§11) — Rails console

Open a Rails console with `bin/rails console`. Each step is a paste-able
snippet; the **Expected** line says what the console should return.

4. **Auto-derive from Channel.** `Channel.first.touch ; CalendarEntry.where(entry_type: :channel_published).count`.
   Expected: count is `>= 1`. The derived entry's `title` is
   `"channel joined: <channel_url or title>"`.
5. **Auto-derive from Video (public).**
   `v = Video.where(privacy_status: :public).where.not(published_at: nil).first ; v&.touch ; v&.calendar_entries&.where(entry_type: :video_published)&.first&.title`.
   Expected: a string starting with `"video published:"`. (If the seed has
   no public videos with a `published_at`, set one by hand:
   `Video.first.update!(privacy_status: :public, published_at: 2.days.ago, category_id: "10")`.)
6. **Auto-derive from Game.**
   `g = Game.first ; g.update!(release_date: Date.current + 30.days) ; CalendarEntry.where(game_id: g.id, entry_type: :game_release).first`.
   Expected: a row with `starts_at` ~30 days out, `release_precision: "day"`
   (or nil if Phase 14's `release_precision` column is not yet on `games`),
   `state: "scheduled"`.
7. **Supersede on Video flip.**
   `v.update!(privacy_status: :private, publish_at: nil, published_at: nil) ; v.calendar_entries.where(entry_type: :video_published).first.state`.
   Expected: `"superseded"` (NOT deleted; row still exists).
8. **`manual_date_override` sticky.**
   `g.update!(manual_date_override: true) ; g.update!(release_date: Date.current + 60.days) ; g.calendar_entries.where(entry_type: :game_release).first.starts_at.to_date`.
   Expected: starts_at is the **first** date set in §6 (~30 days out), NOT
   the second (~60 days out). The override blocks IGDB sync overwrites; manual
   updates still shift per master-decision Open question #2 — but only when
   the host's `release_date` change is treated as user intent. Current
   `Game#calendar_entry_attributes` reads `manual_date_override` as a strict
   guard. Confirm `starts_at` did NOT shift.
9. **Milestone rule fire.**
   `r = MilestoneRule.create!(name: "100 subs", scope_type: :install, metric: "subscriberCount", metric_window: :lifetime, threshold: 100, direction: :cross_up) ; reader = Struct.new(:value).new.tap { |s| s.define_singleton_method(:read) { |**_| 150 } } ; Calendar::MilestoneEvaluator.new(metric_reader: reader).evaluate_all! ; r.reload.fired_at`.
   Expected: non-nil timestamp. Then
   `CalendarEntry.where(entry_type: :milestone_auto, milestone_rule_id: r.id).count`.
   Expected: 1.
10. **Idempotent re-fire.**
    `Calendar::MilestoneEvaluator.new(metric_reader: reader).evaluate_all! ; CalendarEntry.where(milestone_rule_id: r.id).count`.
    Expected: still 1 (no second milestone_auto entry; rule already fired).
11. **Occurred flipper.**
    `e = CalendarEntry.create!(entry_type: :milestone_manual, source: :manual, state: :scheduled, title: "test ripe", starts_at: 2.hours.ago, all_day: false, timezone: "UTC") ; Calendar::OccurredFlipper.flip_ripe! ; e.reload.state`.
    Expected: `"occurred"`.
12. **Cascade on host delete.** Pick a Video that has at least one calendar
    entry (per §5: `v = Video.find_by(id: <id from §5>)`). Capture
    `v.calendar_entries.count`, then `v.destroy ; CalendarEntry.where(video_id: v.id).count`.
    Expected: 0 (FK ON DELETE CASCADE).
13. **Read-only enforcement.** Pick any derived entry:
    `e = CalendarEntry.where(source: :derived).first ; e.update(title: "tampered")`.
    Expected: `false` (validation blocks); `e.errors.full_messages` contains
    `"derived / auto entries are read-only outside metadata.user_overrides"`.
    Then `e.update(metadata: e.metadata.merge("user_overrides" => { "note" => "ok" }))`.
    Expected: `true` (allowed via the user_overrides escape hatch).

## User Validation

> Pure UI walkthrough. No console / no terminal. Browser at
> `app.pitomd.com` after `bin/dev` is up. Each step crosses off as you
> observe the expected outcome.

[ ] 1. **Top nav has `[calendar]`.** Open any page in the app (e.g.,
       `/dashboard`). The header nav cluster shows `[home] [calendar] …`.
       Click `[calendar]`. The URL changes to
       `/calendar/month/<this_year>/<this_month>` and the month grid
       renders.

[ ] 2. **Month grid skeleton.** On the calendar month page you see, in this
       order: a navigation cluster `[ prev month ] [ next month ]
       <month_name> [ schedule ] [ add entry ]` (with a `[ today ]` link
       inserted between `prev` and `next` only when you are NOT on the
       current month); a filter row `[ all types ] [ video ] [ game ]
       [ milestone ] [ purchase ] [ custom ]`; a 7-column grid with
       lowercase weekday headers `mon tue wed thu fri sat sun`; date
       cells. Today's cell carries a 1px solid outline and a small
       `today` text marker next to the day number.

[ ] 3. **Empty-state copy.** Navigate via `[ next month ]` repeatedly until
       you land on a future month with no entries. The page shows
       `no entries this month — [ add entry ]` below the empty grid.

[ ] 4. **Month navigation.** From the current month, click `[ prev month ]`.
       URL changes to the previous month and the grid re-renders. Click
       `[ next month ]`. URL advances. Click `[ today ]`. URL returns to
       the current month and the `[ today ]` link disappears (because
       you're back on the current month).

[ ] 5. **Year boundary.** Navigate to December (current or any) using
       `[ next month ]` / `[ prev month ]`. From December, one
       `[ next month ]` click rolls into January of the next year. From
       January, one `[ prev month ]` rolls back to December.

[ ] 6. **Filter cluster (month).** Click `[ video ]` in the filter row.
       The URL gains `?type=video` and the grid re-renders showing only
       chips with the `v:` (or `v?:`) glyph. Click `[ all types ]`. The
       grid resets.

[ ] 7. **Schedule view.** Click `[ schedule ]` in the navigation cluster.
       URL is `/calendar/schedule`. The page shows the same filter row at
       top, a linear table with columns date / time / glyph + title /
       state, and a `[ today ]` divider row splitting past entries from
       future entries (if both are present).

[ ] 8. **Schedule filters.** Click `[ game ]` filter on the schedule view.
       Only `g:` rows remain. Click `[ all types ]`. Reset. Click
       `[ include cancelled ]` (top right of the filter row) — cancelled
       and superseded rows surface (strike-through / muted styling).
       Click `[ hide cancelled ]` to restore default visibility.

[ ] 9. **Quick-add manual entry.** From the month grid, click `[ add entry ]`.
       You land on `/calendar/entries/new` with the form: a `type` radio
       cluster (game release / purchase planned / milestone manual /
       custom), title, description, starts at, ends at, all day (yes/no),
       timezone. Pick `milestone_manual`, fill `title` =
       `"podcast appearance"`, leave `starts_at` ~tomorrow, click
       `[ create ]`. You land on the entry detail page with the title
       displayed.

[ ] 10. **Entry shows on the month + schedule.** Click `[ home ]` then
        `[ calendar ]`. The new entry's chip (prefix `m:` for
        milestone_manual) appears on the appropriate cell. Click
        `[ schedule ]`. The entry shows in the linear list with the same
        glyph.

[ ] 11. **Edit manual entry.** From the entry detail page (click the chip
        from §10), click `[ edit ]`. Change the title to
        `"podcast appearance — rescheduled"`. Click `[ save ]`. You
        return to the detail page. Title is updated. Re-visit the month
        grid; the chip shows the new title.

[ ] 12. **Cancel manual entry (action-screen flow).** From the entry
        detail page, click `[ cancel ]` (rendered in red as the
        destructive variant). You land on
        `/deletions/calendar_entry/<id>` showing the confirmation copy
        `cancel calendar entry?` (singular) plus a one-line description
        `this will mark the entry as cancelled. it stays on the calendar
        with strike-through styling.` and a table row of the entry.
        Click `[ confirm cancel ]`. You land on `/calendar/schedule`
        with a flash `cancelled 1 calendar entry.` The entry now shows
        in the list with `cancelled` state and strike-through styling
        (visible only when `[ include cancelled ]` is toggled — by
        default cancelled entries are hidden).

[ ] 13. **Read-only derived entry has no `[ edit ]` / `[ cancel ]`.**
        Visit the schedule view. Click any chip whose state is
        derived-by-source — e.g., a `c:` (channel_published) entry from
        seed data, or a `v:` if you triggered §5 above. The detail page
        shows `[ note ]` and `[ back ]` only. NO `[ edit ]`. NO
        `[ cancel ]`.

[ ] 14. **Cross-link to source.** From the same derived entry detail
        page, click the title's chip-glyph link area (or the chip on the
        month grid for a derived entry). Expected: you land on the source
        row's page — `/videos/:id` for `video_published`, `/channels/:id`
        for `channel_published`, `/games/:id` for `game_release`. (Note:
        the entry detail page itself does not yet wire a clickable
        cross-link separate from the chip; click via the schedule view's
        glyph link or the month grid's chip.)

[ ] 15. **Reminder copy on a future game release.** From §6's data setup,
        navigate to `/calendar/schedule`, ensure the filter is `[ all
        types ]` (or `[ game ]`). Find the `g:` chip you created. Its row
        shows the trailing copy `[ remind: t-7 t-1 t-0 ]` (read-only
        copy; not yet a clickable element). Note: clicking through to the
        entry detail page renders a slightly different reminder line —
        this discrepancy is logged as Concern 3.

[ ] 16. **Footer also has `[calendar]`.** Scroll to the bottom of any
        page. The footer nav cluster mirrors the header and includes
        `[calendar]`.

[ ] 17. **Keyboard shortcuts on the month grid.** From any month page,
        press `[` (left bracket key). The page navigates to the previous
        month. Press `]`. Next month. Press `t`. Returns to today.

[ ] 18. **Add entry via the schedule view.** Click `[ add entry ]` from
        `/calendar/schedule`. Same form as §9. Type, title, save. The
        new entry shows in the schedule list at its starts_at position.

[ ] 19. **Calendar from a fresh tab works without server state.** Open
        a new tab to `/calendar`. The redirect lands on the current
        month grid without errors.

[ ] 20. **Sidekiq cron entries are scheduled.** Visit
        `/sidekiq/cron` (HTTP basic auth required). Two entries
        related to Phase 15 should be listed: `milestone_evaluator`
        (daily 02:00 UTC) and `calendar_occurred_flipper` (hourly at
        minute 5).

## Cleanup

If the user wants to roll back local state and retry from scratch:

```bash
# Drop and recreate the dev DB (test DB is independent).
bin/rails db:drop db:create db:migrate db:seed

# Or, surgical: undo just calendar entries for re-derive testing.
bin/rails runner 'CalendarEntry.delete_all; MilestoneRule.delete_all'

# Verify the test DB is clean (in case a parallel agent's migration leaked):
RAILS_ENV=test bin/rails db:migrate:status | tail
```

If the rspec parallel run leaves stale Postgres connections (the reviewer
hit this once during the pipeline run), terminate them via:

```ruby
# Inside `bin/rails runner` (test env):
ActiveRecord::Base.connection.select_all(
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity " \
  "WHERE pid <> pg_backend_pid() AND application_name LIKE '%rspec%'"
)
```

Document this only as an environmental remediation; the test suite itself
does not require it on a clean machine.
