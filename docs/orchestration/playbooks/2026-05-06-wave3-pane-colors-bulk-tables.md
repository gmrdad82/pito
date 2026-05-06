# Manual test playbook — Wave 3 (pane colors, notes always-on bulk, list-table polish)

**Branch:** `main` (uncommitted working tree, sits on `5ea1c7a`) **Bundle
brief:** architect dispatch on 2026-05-06 — three lanes folded into Wave 3 plus
diagnostic of a pre-existing meilisearch flake **Reviewer run:** 2026-05-06
02:10

## Pipeline summary

- Code review: 4 non-blocking concerns, 0 blockers — see below.
- Simplify: 3 minor suggestions — see below.
- Test suite (`bin/test spec/`, 8 workers): **1179 examples, 0 failures**.
  Re-ran serially (`bundle exec rspec spec/`) for the meilisearch-flake
  diagnosis: also **1179 / 0**. The pollution the architect warned about did NOT
  surface in this run.
- Rubocop: **clean** (285 files inspected, 0 offenses).
- Brakeman (`bin/brakeman -q`): **0 errors, 0 security warnings**.
- Bundler-audit (`bin/bundler-audit check --update`): **clean** (0 advisories,
  db updated to 2026-03-30).
- Cargo test (`extras/cli`): **green** (sanity — Wave 3 made no Rust changes).
- Cargo clippy (`--all-targets -- -D warnings`): **clean**.
- Hard-rules audit: no `data-turbo-confirm`, `window.confirm`, `alert(`, or
  `prompt(` introduced. Pass.

## Blockers

None. Diff is ready for the user's manual validation walkthrough.

## Concerns and suggestions

### Code review — non-blocking

1. **`/channels/:id` and `/videos/:id` show pages are now constrained to a
   454px-wide pane.** Wrapping the single-pane content in
   `pane-container > pane-wrapper` triggers the global `.pane-wrapper` rule at
   `app/assets/tailwind/application.css:238-242`
   (`width: 454px; flex: 0 0 454px`). Previously these show pages rendered
   `_pane.html.erb` directly and occupied full content width. The wide-tone
   color paints correctly via `:only-child`, but the visible width regression on
   a 1920px viewport is significant (~3x narrower). Confirm the architect
   intended this — eyeballing in step 4 of User Validation below covers it.
2. **Single-pane workspace view (`/channels/panes?ids=42`) also resolves to
   `:only-child`** so the wide tone applies there too. That's semantically
   consistent with "single pane = wide tone", but means the user opens a 1-id
   workspace and sees the SAME bg as a `/channels/:id` show — whereas adding a
   second id flips both panes to A | B alternation. Worth noting in the
   playbook.
3. **`VideosController::ALLOWED_DIRS = %w[asc desc].freeze` is dead code
   today.** The `index` action doesn't read sort params and there's no
   `sanitized_dir` helper in this controller. The architect's brief said to
   leave server-side `ALLOWED_SORTS` as forward-looking; the `ALLOWED_DIRS`
   mirror is the same shape but worth flagging since nothing consumes either
   today. Drop or wire when the JSON sort surface lands. Not urgent.
4. **`docs/design.md` zebra rule still references `--color-bg-alt`.**
   `docs/design.md:463` documents
   `.pane-container > .pane-wrapper:nth-child(even) { background-color: var(--color-bg-alt); }`
   but the new CSS uses `var(--color-pane-bg-b)`. The CSS comments were updated
   in this Wave; the design doc was not (it's outside reviewer's write scope and
   outside Wave 3's brief). Doc-keeper follow-up after commit.

### Simplify — non-blocking

1. **`--color-pane-bg` (singular alias) has zero callers in `app/`.** Comment on
   `app/assets/tailwind/application.css:14` says it's "kept as alias for `-a`
   for back-compat with any inline-styled cell that hasn't migrated." A grep
   confirms zero remaining callers — the alias is currently dead. Safe to keep
   for safety; safe to drop once the codebase shape stabilizes.
2. **`docs/orchestration/follow-ups.md` "bulk_select_controller.js legacy
   comments mislead" entry is now partly out of date.** That follow-up was filed
   when `notes pane` and `/projects index` still wired `enterBulk` / `exitBulk`
   / `bulkToggle`. Wave 3 Lane J just migrated notes pane to always-on; only the
   projects index still uses the toggle pattern. Trim the follow-up text on the
   next docs sweep.
3. **`pane-cell-{a,b,wide}` utility classes could replace inline-style
   repetition in `projects/show.html.erb` and `settings/index.html.erb`.** Both
   templates carry duplicated
   `style="background: var(--color-pane-bg-X); padding: 12px;"` patterns.
   Architect explicitly chose "no per-page CSS class" for these revamps; defer
   until a broader CSS pass.

## Pre-existing meilisearch test pollution — diagnosis

Per the architect's brief: 2 failures expected in
`spec/services/search/meilisearch_engine_spec.rb` (`#remove`, `#reindex_all`)
when running the full suite, polluted by some other spec indexing into
Meilisearch.

**This reviewer run did NOT reproduce the failures.** Both `bin/test spec/` (8
workers parallel) and `bundle exec rspec spec/` (serial) returned 1179 examples,
0 failures. The meilisearch spec passes in isolation (14/14) AND inside the full
suite.

**Root-cause investigation, even though I couldn't reproduce:**

- Models including `Searchable` (only `Video`) have
  `after_commit :search_index, on: [:create, :update]` and
  `after_commit :search_remove, on: :destroy`
  (`app/models/concerns/searchable.rb:25-26`).
- The hooks enqueue `SearchIndexJob.perform_later(...)` /
  `SearchRemoveJob.perform_later(...)`, which the `:test` queue adapter enqueues
  but does NOT execute (`config/environments/test.rb:43`).
- All `*Search*` job specs (`spec/jobs/search_index_job_spec.rb`,
  `spec/jobs/search_remove_job_spec.rb`, `spec/jobs/reindex_all_job_spec.rb`)
  stub `Search.engine` with an `instance_double`, so they cannot reach
  Meilisearch even with `perform_now`.
- `spec/services/search_spec.rb` and `spec/services/search/engine_spec.rb` only
  exercise `Search.engine` resolution; they don't index.
- The meilisearch_engine_spec's own `before` block at lines 8-16 deletes the
  `videos_test` index docs at the start of every example — so cross-example
  pollution within the file is bounded.

The most plausible remaining trigger: **`wait_for_tasks` (line 137-146) reads
`client.tasks["results"]` (the GLOBAL Meilisearch tasks list). Under load it may
report `pending.empty?` prematurely if Meilisearch hasn't yet enqueued the
index-deletion task triggered by `before`'s `delete_all_documents` call.** That
would manifest as a race condition, not a deterministic spec-ordering bug. If it
reproduces again on the architect's machine, narrow `wait_for_tasks` to scope to
`videos_test` tasks only (filter by `indexUid`) and add a small ceiling timeout
to fail loud rather than spin.

**Recommendation:** track this as a follow-up entry under
`docs/orchestration/follow-ups.md` ("Meilisearch test isolation hardening")
rather than blocking the Wave 3 commit. The flake is pre-existing and the green
run on my machine suggests it's environmental.

## Manual test steps

> Pre-flight (run BEFORE the User Validation walkthrough):

```bash
# 1. Start the dev stack (Docker + Puma + Sidekiq + Tailwind watcher).
bin/dev   # or check existing tmuxinator / overmind session

# 2. Confirm at least 3 channels and 3 videos exist for the table-polish steps.
bin/rails runner 'puts Channel.count, Video.count'

# 3. If counts are <3, seed:
bin/rails db:seed   # respects existing data; safe re-run
```

If all green, jump to User Validation.

## Cleanup

To re-run the playbook from scratch:

```bash
# Roll back the working tree, but keep this playbook file
git stash push --keep-index --include-untracked -- \
  app/ spec/

# Reset the DB to a known shape
bin/rails db:reset    # WARNING — destroys local data; only run in dev

# Re-stash the working tree
git stash pop
```

## User Validation

[ ] 1. **Project show — three pane tones.** Open
`http://127.0.0.1:3027/projects/1` (or any project that has at least one note +
one footage row). Below the H1, the page shows row 1 (timelines | notes)
followed by row 2 (footage, full width). The three cells should read as three
subtly distinct background colors — timelines (left of row 1), notes (right of
row 1), and footage (row 2) all visually separated. At default theme:

- Light mode: timelines = pale gray-blue (`#f4f6f8`), notes = slightly darker
  pale gray (`#eef0f3`), footage = cooler pale blue-gray (`#eef2f7`).
- Dark mode: timelines = dark blue-gray (`#2f3142`), notes = lighter dark gray
  (`#353748`), footage = cooler dark blue (`#2d3344`).

There should be a small (12px) vertical gap between row 1 and row 2.

[ ] 2. **Settings — alternating tones + wide row.** Visit
`http://127.0.0.1:3027/settings`. The three rows alternate:

- Row 1 left (appearance) = A tone, row 1 right (workspaces) = B tone.
- Row 2 left (YouTube OAuth) = A tone, row 2 right (Voyage AI) = B tone.
- Row 3 (search, full width) = wide tone — distinct from A and B.

The whole settings stack is centered on the page with whitespace on both sides —
at a 1920px viewport, expect roughly ~520px of margin on each side (880px
content cap). At 1280px, expect ~200px each side. At 1440px, expect ~280px each
side. Vertical 12px gap between rows.

[ ] 3. **Theme toggle — tones still distinguishable.** Click the theme switcher
(toggles light↔dark). On the Settings page AND on the Project show, the three
tones (A / B / wide) should still read as visually distinct in BOTH themes. None
of the three should be visually identical to another at any theme.

[ ] 4. **Channels show — single-pane wide tone (and width regression check).**
Click any channel link to land on `/channels/:id`. The detail content (URL row,
starred / connected / syncing / last sync KV table, videos list) should render
on the **wide** pane tone (cooler than A or B). **Note:** the pane is
constrained to ~454px wide — it will look noticeably narrower on a wide monitor
than it did before this Wave. If that feels wrong, flag back to the architect
before committing.

[ ] 5. **Channels workspace — single id = wide, multiple ids = A/B.** From
`/channels`, tick exactly one channel checkbox + click `[open 1]` (or visit
`/channels/panes?ids=<one-id>` directly). The single pane shows the **wide**
tone. Now click `[/]` to add another channel — pane count goes to 2, both panes
flip to **A | B alternation** (left = A, right = B). Adding a third pane gives A
| B | A. Adding a fourth gives A | B | A | B.

[ ] 6. **Videos show + workspace — same as channels.** Repeat steps 4 and 5 on
`/videos/:id` and `/videos/panes`. Single-id = wide, multi-id = A/B alternation.

[ ] 7. **Project show — notes pane always-on bulk shape.** Back on
`/projects/1`, look at the notes pane (right side of row 1). The heading reads
`notes (N) · [+] · [scan]` — there is **no `[bulk]` link** in the heading row,
**no `[cancel]` link** anywhere in the pane.

The notes table has a checkbox column always visible:

- Header row: empty header cell holding a `[ ]` select-all checkbox.
- Each row: leading `[ ]` checkbox.

Click the header checkbox once → all row checkboxes tick, header reads as
checked, a `[delete N]` action appears in the bulk toolbar above the table.
Click it again → all untick, `[delete N]` hides. Tick exactly one row checkbox →
`[delete 1]` appears.

[ ] 8. **/channels list — Name column at position 2.** Visit `/channels`. The
table columns are now: `[ ]` checkbox, **Name**, `[o]` open-action, URL,
starred, last sync (6 columns total). The Name cell shows the channel id (e.g.
`38`) as a clickable link. Click `38` → lands on `/channels/38`.

[ ] 9. **/channels Name column sortable.** Click the "Name" column header. The
browser URL gains a `#0=name_asc` hash fragment (NOT a `?sort=...&dir=...` query
string — this is client-side sort persisted in the URL hash). Rows reorder by id
ascending. Click again — fragment flips to `#0=name_desc`, rows reverse. Refresh
the page with the hash present — the sort state persists.

[ ] 10. **/videos list — same shape as channels.** Visit `/videos`. Name column
at position 2 with `video.id` as a clickable link. Header sortable the same way.
Clicking a Name cell goes to `/videos/:id`.

[ ] 11. **/projects list — `[o]` column gone, name still clickable.** Visit
`/projects`. The table no longer has an `[o]` action column header or per-row
`[o]` cell. The Project's name cell is still a link to its show page — clicking
it lands on `/projects/<id>`.

[ ] 12. **Hard-rules sanity (no destructive JS confirms anywhere).** While
walking through steps 1-11, click any `[-]` (delete) link or destructive button.
Each one MUST go through the in-app confirmation modal / page — never the
browser's native `confirm()` dialog. (This is a sanity check; Wave 3 didn't
touch the destructive flows, but the hard-rule audit verifies it stays clean.)

## Sign-off

Step ✓-marked → diff ready to commit. Any ✗ → reopen with the architect.

> Note for the user: the pre-existing meilisearch test pollution flagged in the
> architect's brief did NOT reproduce in this reviewer run. If it resurfaces on
> your machine after `bin/dev` is up, file as a separate follow-up — do NOT
> block the Wave 3 commit on it.
