# Manual test playbook — Wave 1 + Wave 1.5 + Wave 2 polish bundle

**Branch:** `main` (uncommitted working tree) **Spec:**
`docs/plans/beta/04-project-workspace/specs/project-workspace.md` (Wave 2); Wave
1 / 1.5 are spec-less polish per the architect's bundle brief **Reviewer run:**
2026-05-06 01:31

## Pipeline summary

- Code review: 1 blocker, 4 non-blocking concerns — see below.
- Simplify: 2 minor suggestions — see below.
- Test suite (`bin/test spec/`, 8 workers): **1151 examples, 0 failures**.
- Rubocop: **clean** (285 files, 0 offenses).
- Brakeman (`bin/brakeman -q`): **0 errors, 0 security warnings**.
- Bundler-audit: **clean** (0 advisories, db updated to 2026-03-30).
- Cargo test (`extras/cli`): **323 tests passed** (120 unit + 192 unit-tests +
  11 integration; full output `0 failed`).
- Cargo clippy (`--all-targets -- -D warnings`): **clean**.
- Cargo fmt: pre-existing drift in `src/app.rs`, `src/commands/tui.rs`,
  `src/keys.rs`, `src/ui/*.rs`, `src/widgets/mod.rs`. **None of the files Lane E
  touched** appear in the drift list, so the gate is honoured per the reviewer
  brief.
- Hard-rules audit: no `data-turbo-confirm`, `window.confirm`, `alert(`, or
  `prompt(` anywhere in `app/`. Pass.
- Migrations reversibility: `db:rollback STEP=2` then `db:migrate` round-trip
  succeeds. Counter-cache backfill correctly seeds Project 1 with `4 / 1 / 0`.

## Blockers

### 1. CLI sends `filesize_bytes`, but Rails strong params silently drop it

**Files involved:**

- `app/controllers/api/footages_controller.rb:42-50` — `build_create_attrs`
  permit list does NOT include `:filesize_bytes`.
- `app/controllers/footages_controller.rb:78-87` — `build_update_attrs` JSON
  branch permit list does NOT include `:filesize_bytes`.
- `extras/cli/src/footage/api/client.rs:253` — CLI emits
  `footage[filesize_bytes]` on every POST and PATCH.
- `app/controllers/{api/,}footages_controller.rb` — `footage_json` correctly
  includes `filesize_bytes` on read (so GET/diff sees the value once it lands).

**Symptom the user will hit during the playbook:** Step 15 ("CLI filesize") will
report 4 rows as `[chg]`, the user confirms, the CLI gets HTTP 200 and prints "4
changed". On a second `--dry-run`, the SAME 4 rows STILL classify as `[chg]`
because the server's `filesize_bytes` column is still NULL: Rails' strong-params
filtering dropped the field on the PATCH, and the diff in
`extras/cli/src/footage/diff.rs:149` correctly compares
`record.filesize_bytes != probed.filesize_bytes` so the row is forever-dirty.

**Why the suite didn't catch it:** No request spec sends `filesize_bytes` on
POST or PATCH and asserts persistence. `spec/requests/footages_spec.rb` and
`spec/requests/api/footages_spec.rb` cover serialization on read paths only.

**How to fix (architect's call, not mine):** add `:filesize_bytes` to both
controllers' permit lists, and add a request spec that POSTs / PATCHes the
column and asserts it survives the round-trip (mirrors how the `fps to_f` fix
shipped on 2026-05-05).

The diff is **not ready for the user's manual validation** until this is
addressed. If shipped as-is, the user's "is the column populated?" check
silently fails and the bug looks like a CLI regression.

## Concerns and suggestions

### Code review — non-blocking

1. **`ProjectsController#sort_clause` rebuilds what
   `sanitized_sort_key`/`sanitized_dir` already produced**
   (`app/controllers/projects_controller.rb:114-131`). The pattern is mirrored
   from `ChannelsController` (the comment explains the Brakeman trick), so the
   duplication is intentional. Worth a follow-up if Brakeman ever loosens — the
   four lines could collapse into one helper.
2. **`ordered_footages` repeats the same sanitization shape inline**
   (`projects_controller.rb:206-221`) instead of calling
   `sanitized_footage_dir`. Same Brakeman reasoning applies; flag for
   simplification once the flow analysis can resolve through the helper.
3. **`request.query_parameters.merge(sort:..., dir:...)` in
   `_footage_pane.html.erb:59`** — preserves filters when re-sorting (correct),
   but `request.query_parameters` returns a string-keyed hash and the merge uses
   symbol keys. Rails URL helpers stringify both, so this works in practice.
   Just calling it out so the next reader doesn't get spooked.
4. **`.filename-cell` uses `display: flex` on a `<td>`**
   (`app/assets/tailwind/application.css:354`). Modern browsers handle
   flex-on-table-cell gracefully, but historically this has surfaced edge cases
   at very narrow widths. Worth eyeballing on a 320px viewport in step 7 of the
   user-validation walkthrough. Not a blocker.

### Simplify — non-blocking

1. **Footage filter chips and channels filter chips are conceptually the same
   pattern** (chip group + `[clear]` link, render only when ≥2 distinct values).
   They diverge in a couple of places (`request.query_parameters` vs inline
   `@filters`). A shared `FilterChipGroupComponent` could absorb both. Defer
   until after Wave 3 unless the architect wants it in this bundle.
2. **`bulk_select_controller.js` keeps legacy `enterBulk` / `exitBulk` /
   `bulkToggle`** (lines 36-58) "for any view still wiring `[bulk]` /
   `[cancel]`". Notes pane (`projects/_notes_pane.html.erb`) and the `/projects`
   index still wire it; if Lane G is the last hop and notes / projects
   deliberately stay on the toggle pattern, the legacy hooks are permanent and
   that comment is misleading. Tighten the comment OR migrate notes / projects
   to always-on too.

## Manual test steps

> Pre-flight (not part of "User Validation" — this is for getting the dev stack
> running before you start clicking):

```bash
# 1. Confirm app dev stack is running
bin/dev   # or check existing tmuxinator / overmind session

# 2. Confirm the CLI release binary the user spec referenced is fresh
ls -la /home/catalin/Dev/pito/target/release/pito

# 3. Sanity-check that the 4 footage rows are present on Project 1
bin/rails runner 'p Project.first&.attributes&.slice("id","name","footages_count","notes_count","timelines_count")'
# Expected: {"id"=>1, "name"=>"Ghost 'n Goblins Resurrection",
#            "footages_count"=>4, "notes_count"=>1, "timelines_count"=>0}
```

If the strong-params blocker (#1) has been fixed, repeat:

```bash
bundle exec rspec spec/requests/api/footages_spec.rb spec/requests/footages_spec.rb
# Expected: green; new spec asserts filesize_bytes round-trips on POST / PATCH.
```

## Cleanup

To re-run the playbook from scratch:

```bash
# Roll back the working tree, keeping uncommitted CLI binary intact
git stash push --keep-index --include-untracked

# Reset the DB to a known shape
bin/rails db:reset    # WARNING — destroys local data; only run in dev

# Re-stash the working tree
git stash pop
```

If the CLI run leaves bad rows behind:

```bash
bin/rails runner 'Footage.where(project_id: 1).update_all(filesize_bytes: nil)'
# Then re-run pito footage import --project 1 --path ... --dry-run
```

## User Validation

[ ] 1. **Tab title apostrophe.** Open `http://127.0.0.1:3027/projects/1` in a
browser. The browser tab reads `Ghost 'n Goblins Resurrection ~ pito` with a
literal apostrophe — NOT `Ghost &#39;n Goblins Resurrection ~ pito`.

[ ] 2. **Bracket labels site-wide.** Click around: `/channels`, `/videos`,
`/projects`, `/projects/1`, `/games`, `/collections`, `/settings`. Every
`[edit]` reads `[e]`, every `[delete]` reads `[-]`, every `[open]` reads `[o]`,
every `[view]` reads `[v]`. `[bulk]`, `[cancel]`, `[download cli]` are
unchanged. No leftover `[ + add channel ]` style verbose labels.

[ ] 3. **Settings page layout.** Visit `/settings`. The page shows three rows:
appearance | workspaces (50/50), YouTube OAuth | Voyage AI (50/50), search (full
width). Every form's submit button reads `[update]`, never `[save]`.

[ ] 4. **URL casing.** On `/settings`, the YouTube section shows "client ID"
(uppercase ID), "client secret", "redirect URI" (uppercase URI). Voyage section
shows "API key" (uppercase API). Open `/channels/1` — the channel detail page
heading and the address row read "URL https://..." with URL uppercase.

[ ] 5. **Channels new form button copy.** Visit `/channels/new`. Breadcrumb
reads `[ channels ] / [ add ]`. The submit button reads `[add]` (NOT
`[update]`). Click it with the URL field empty — the browser native validity
hint mentions "must match" the pattern, the page does not navigate, the button
still reads `[add]`. Now visit `/channels/1/edit` — the submit button reads
`[update]` (NOT `[add]`).

[ ] 6. **Saved-view buttons.** On `/channels` open one or more channels in panes
(`/channels/panes?ids=1`). Above the pane row, the save-this-view button reads
`[save]` (NOT `[update]`, not `[+]`). Same on `/videos/panes`.

[ ] 7. **Channels list always-on bulk.** Visit `/channels` (with at least 3
channels). Every row already shows a checkbox in the leading column. The header
row shows a checkbox. No `[bulk]` toggle anywhere on the page. No "select items
to act on · [cancel]" copy. Click the header checkbox once — all rows tick,
header reads `[x]`-equivalent (checked state). Click again — all untick. Tick
exactly two row checkboxes manually — the bulk toolbar appears with
`[open 2] · [sync 2] · [delete 2]`. Header checkbox shows the indeterminate
state.

[ ] 8. **Channels URL column behaviour.** On `/channels`, the table header
column for URL is plain text `URL` (NOT a `[ URL ]` sortable link, NOT
`[ URL ▲ ]`). Click any URL cell — opens YouTube in a NEW tab (target=\_blank).
No YouTube column.

[ ] 9. **Channels add-pane modal `[/]`.** On `/channels` open a single channel
pane (`/channels/panes?ids=1`). The heading reads `channels (1) · [/]`. Click
`[/]` — a modal opens. The modal does NOT extend to the bottom of the viewport
(it caps at 80vh). The channel list inside the modal scrolls internally if it
overflows. At the bottom inside a `.modal-footer` (hairline above), `[close]` is
visible. Click outside or `[close]` — the modal closes.

[ ] 10. **Videos parity.** Repeat steps 7, 8, 9 against `/videos` and
`/videos/panes`. Always-on checkboxes, `URL` not sortable as a column header
(channel column links externally to YouTube), `[/]` add-pane button,
height-capped modal with `[close]` in `.modal-footer`.

[ ] 11. **Projects index sortable columns.** Visit `/projects`. Five columns
show: name (clickable to project show), created (`~Xh ago`-style), footages,
notes, timelines. Project 1 reads `4 / 1 / 0`. Click the `name` header — URL
becomes `?sort=name&dir=asc`, header shows ` ▲`. Click again — URL becomes
`?sort=name&dir=desc`, header shows ` ▼`. Click `footages` header twice to get
`?sort=footages_count&dir=desc` — Project 1 sits at the top. Click the project's
name link — lands on `/projects/1`.

[ ] 12. **Project show 2-row layout.** On `/projects/1`, below the H1 the page
shows: row 1 = timelines pane (left, "no timelines yet") | notes pane (right,
existing notes table). Row 2 = footage table full-width with 8 columns —
filename, game, resolution, fps, bit depth, duration, filesize, source. The
`kind` column is gone. Filter chip rows render only for dimensions where the
project's footage varies (Project 1 may show no chips because its 4 footages all
share the same fps / resolution / bit-depth / source — that's expected).

[ ] 13. **Footage table sort + filter.** On `/projects/1`, click any footage
column header — the URL acquires `?sort=...&dir=...` and the header shows ▲ / ▼.
Click a filter chip if any rendered — the table narrows. Click `[clear]` (only
visible when a filter is active) — sort and filter clear.

[ ] 14. **Footage filename links to edit.** On `/projects/1`, click any footage
filename. Lands on `/footages/<id>/edit`, the full edit form (kind, source,
game, platform, description, NAS path, recorded at).

[ ] 15. **Notes title links to show.** On `/projects/1`, in the notes pane,
click any note title. Lands on `/notes/<id>`, the note show page.

[ ] 16. **CLI filesize import (BLOCKED on concern #1 above).** This step exposes
the strong-params bug. Do NOT skip it — it's the smoking gun if the fix didn't
ship.

```bash
~/Dev/pito/target/release/pito footage import \
  --project 1 \
  --path "/home/catalin/FootageExtra/Projects/Ghost 'n Goblins Resurrection/" \
  --dry-run
```

Expected (after blocker fix): 4 rows classify as `[chg]` (filesize was nil, now
populated). Re-run without `--dry-run`. Re-run a third time with `--dry-run`
again — this time **0 rows** show as `[chg]`. If 4 rows STILL show as `[chg]` on
the third run, the strong-params fix did NOT land — file a bug back to
architect.

[ ] 17. **Counter caches unchanged after import.** Reload `/projects`. The
counts column for Project 1 still reads `4 / 1 / 0`. The CLI import was a
"Change" (filesize backfill), not an "Add", so counts must be stable.

## Sign-off

Step ✓-marked → diff ready to commit. Any ✗ → reopen with the architect.
