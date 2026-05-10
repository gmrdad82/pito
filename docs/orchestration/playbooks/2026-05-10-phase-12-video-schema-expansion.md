# Manual test playbook — Phase 12 video schema expansion + edit surface + pre-publish checklist

**Branch:** `main` **Spec:**
`docs/plans/beta/12-video-schema-expansion/specs/01-video-schema-expansion-and-pre-publish-checklist.md`
**Reviewer run:** 2026-05-10 16:18

## Pipeline summary

- Code review: 2 blockers, 7 non-blocking concerns
- Simplify: 4 suggestions
- Test suite: 2527 examples, 4 failures, 1 pending — 1 failure is a Phase 12
  regression; 3 are unrelated / flaky (Phase 15 ordering + seeds env teardown)
- Rubocop: clean (547 files inspected, no offenses)
- Brakeman: 0 security warnings, 0 errors (2 obsolete ignore entries — minor
  cleanup item)
- Bundler-audit: clean (1078 advisories scanned, none match)

## Blockers

These break documented flows from the spec. The user should NOT run the User
Validation walkthrough until these are resolved.

### Blocker 1 — `[unpublish]` flow is doubly broken (functional + HTML)

**Severity:** HIGH

The spec's "Visibility" section (lines 737-741) calls for a direct
`public/unlisted → private` transition via an `[unpublish]` button on the edit
form, bypassing the pre-publish checklist (per Note 1: "going down is free").

Two compounding defects make the rendered button non-functional:

1. **Smuggle guard returns 422.** `VideosController#smuggled_publish_state?`
   (`app/controllers/videos_controller.rb:241-245`) flags any
   `params[:video][:privacy_status]` on the `update` action and returns 422 with
   "use [ publish ] or [ schedule ] to change privacy_status". The `[unpublish]`
   button in `app/views/videos/_form.html.erb:73-78` posts
   `{ video: { privacy_status: "private" } }` to that exact path. Result: the
   button always returns 422.

   `spec/requests/videos_spec.rb:335-338` explicitly asserts the 422 for
   `privacy_status` in update params, so the contract enforces the bug.

2. **Nested forms render invalid HTML.** The `button_to "[unpublish]", ...` call
   creates a `<form>` element nested inside the outer `<%= form_with %>`. HTML5
   forbids nested forms; the browser detaches the inner form on parse. Even with
   the controller fixed, the button may submit inconsistently across browsers.

The implementation log claims "Phase 12 finalization" but no spec exercises the
unpublish path end-to-end — the system spec only checks rendering
(`spec/system/video_pre_publish_checklist_spec.rb:42-47`).

**Suggested fix:** add an `unpublish` controller action (PATCH
`/videos/:id/unpublish`) that bypasses the smuggle guard and flips privacy to
private; render the CTA outside the parent form OR via a dedicated `link_to` +
`button_to` pair anchored elsewhere on the page. Add a request spec that
exercises the round-trip.

### Blocker 2 — `numeric_formatting_spec` fails on a Phase 12 regression

**Severity:** HIGH

`bundle exec rspec spec/lint/numeric_formatting_spec.rb` is RED:

```
app/views/projects/index.html.erb:122: <td class="num"><%= project.videos.count %></td>
```

The Phase 12 finalization commit (`76ba1d9`) added the "videos" column to the
projects index but rendered the count raw, violating `docs/design.md ## Numbers`
(every user-visible numeric must go through `number_with_delimiter`). The lint
also flags an unrelated `bundles/index.html.erb:28` regression that pre-dates
Phase 12.

**Suggested fix:** `<%= number_with_delimiter(project.videos.count) %>` on
line 122.

## Concerns and suggestions

Non-blocking, but worth folding into the next pass.

### A. Bracketed-link convention — implementation is consistent

The view layer uses no-inner-spaces `[publish]`, `[schedule]`, `[unpublish]`,
`[cancel]`, and `[<b>confirm publish</b>]` per project rule A. The
`BracketedLinkComponent` template renders `[<%= @label %>]` with no padding. No
regressions introduced.

### B. Lead paragraph — acceptable

The pre-publish modal's lead paragraph (`_pre_publish_modal.html.erb:28-32`) is
one sentence per implicit visual line, as required for modal copy. The edit page
(`edit.html.erb`) uses `<h1>edit video</h1>` with no lead paragraph under it; a
lead paragraph would be welcome, but its absence is not a regression.

### C. Pane primitives — clean

`projects/show.html.erb:50` uses `.pane`. `videos/show.html.erb:44-82` uses
`.pane-strip` + `.pane` + `.pane--wide`. No `.framed-block` regressions.

### D. Spec pyramid — strong, with two gaps

Model, request, decorator, job, service, MCP-tool, and system specs all land per
the spec's "Test sweep" section. Two coverage gaps:

1. **No test for the `[unpublish]` round-trip.** Only the rendered button is
   asserted (system spec line 46). See Blocker 1.
2. **No test for project-page video listing ordering with `published_at NULL`.**
   The implementation uses `order(Arel.sql("published_at DESC NULLS LAST"))`,
   which differs from the spec's `published.order(published_at: :desc)`. Worth a
   spec covering a project with one published + one draft video to lock the
   rendering order.

### E. Yes / no boundary — consistent

External boolean params and decorator output use `"yes"` / `"no"` strings across
`VideoDecorator`, the three new MCP tools, and the pre-publish modal form. The
hidden-input pattern in `_pre_publish_modal.html.erb:44`
(`hidden_field_tag "...", "no"` + checkbox `value="yes"`) gives unchecked-
default-`no`, checked-`yes`. Internal storage stays Boolean. Clean.

### F. Tenant-free single-install — clean

No `tenant_id` columns, no `BelongsToTenant` mixins, no `Current.tenant` reads
in any new code. The migration is genuinely additive on the post- Phase-8 thin
schema.

### G. `star` editable in MCP but not in web edit form (parity gap)

`Mcp::Tools::UpdateVideo` (lines 5, 18, 39, 54) accepts `star: yes|no`. The web
`VideoPolicy::EDITABLE_ATTRS` (lines 20-23) does NOT include `star` — the edit
form has no toggle. The CLI / MCP can flip a video's star bit but the web user
cannot do the same on the edit page. The realignment doc (work unit 4) does not
call this out either way; flag for the next polish pass.

### H. `VideoPolicy.permit` is double-armored

`SMUGGLE_GUARDED_ATTRS` are explicitly deleted in `VideoPolicy.permit` after
being absent from the `EDITABLE_ATTRS` allowlist anyway. Strong-params would
have dropped them silently; the controller-level `smuggled_publish_state?`
returns 422 _before_ `permit` runs. The
`SMUGGLE_GUARDED_ATTRS.each { |k| attrs.delete(k) }` line in
`app/policies/video_policy.rb:54` is dead code. Defense-in-depth is defensible,
but the comment should call it out as deliberate redundancy (today it reads as
load-bearing).

### I. `connection&.update_columns(needs_reauth: true) if connection` (style)

`app/jobs/video_sync_back.rb:45` chains `&.` with `if connection` — redundant.
Pick one.

### J. Brakeman has 2 obsolete ignore entries

`config/brakeman.ignore` lists two warning hashes that no longer match any real
warning (they're under "Obsolete Ignore Entries" in the Brakeman output).
Cleanup item; not a security finding.

### K. `app/jobs/video_publish.rb` is a Sidekiq job that's never enqueued

The class is defined and tested but the spec says "the controller `#publish` /
`#schedule` actions perform this synchronously (no enqueue)". Verified — the
controllers do their own attribute-assignment + save inline. The `VideoPublish`
job has no caller in the codebase. The header comment claims it's "reserved for
MCP-driven flows" but the MCP `publish_video` tool does the same inline
assignment as the controller and never enqueues `VideoPublish`. This is dead
code today; either wire it into MCP or remove to keep the codebase honest.

## Manual test steps

These are the command-line / setup prerequisites the user runs once to prepare
for the User Validation walkthrough. Stop here if any step fails.

1. **Pull and migrate.**

   ```
   git pull --rebase
   bin/rails db:migrate
   ```

   Expected: `db/migrate/20260510135730_expand_videos_for_data_api_v3.rb`
   applies cleanly. The `videos` table gains 19 columns; `playlist_items`
   becomes `playlist_videos`.

2. **Re-confirm `db/schema.rb` reflects the migration.**

   ```
   git diff db/schema.rb
   ```

   Expected: no diff — the schema was committed alongside the migration.

3. **Start the dev stack.**

   ```
   bin/dev
   ```

   Expected: Puma on `http://localhost:3000`, Sidekiq running, Tailwind
   watching. No errors from `Video` model load.

4. **Run the test suite once locally.**

   ```
   bundle exec rspec
   ```

   Expected: 4 failures matching this playbook's "Pipeline summary":
   - 1 Phase 12 regression (Blocker 2 — `projects/index.html.erb:122`)
   - 1 Phase 15 ordering flake (`calendar/month_spec.rb:35`, passes in isolation
     per the implementation log)
   - 2 seeds-spec env failures (Postgres connection terminated mid-run — not
     Phase 12, environmental)

   If the failure count or shape differs, stop and surface to the architect.

5. **Run rubocop and brakeman.**

   ```
   bundle exec rubocop
   bundle exec brakeman -q -w2
   bundle exec bundler-audit check --update
   ```

   Expected: rubocop clean, brakeman 0 warnings, bundler-audit no advisories.

## Cleanup

If the user wants to roll back local state:

```
bin/rails db:rollback STEP=1   # reverts the Phase 12 migration
git stash                       # discard any local changes
git checkout main && git pull --rebase
```

The migration is mechanically reversible (the `down` block is explicit). Sidekiq
queues drain on `bin/dev` shutdown; in-flight `VideoSyncBack` jobs will retry on
next boot if they had failed mid-run.

## User Validation

The user steps through the rendered surfaces in the browser. No terminal needed
past this point. Each step is observable from the UI alone.

[ ] 1. **Connect a YouTube channel.** Visit `/settings/youtube` and connect a
Google account that owns at least one private draft video AND at least one
published video. Expected: the connection appears with "active" status and the
channel rows populate.

[ ] 2. **Open the videos index.** Visit `/videos`. Expected: each row shows a
`privacy` column with `private` / `public` / `unlisted` text; imported videos
(public / unlisted with `pre_publish_checked_at` = NULL) show a small muted
"imported" indicator next to the privacy text; every row ends with an `[edit]`
bracketed link.

[ ] 3. **Open the edit page for a private draft.** Click `[edit]` on a row whose
privacy is `private`. Expected: a form with section legends `basics`,
`visibility`, `audience`, `disclosures`, `studio-only`, `project`. The
visibility section shows `privacy: private` and two CTAs — `[publish]` and
`[schedule]`. No `[unpublish]` here.

[ ] 4. **Edit metadata and save.** Change the title (keep ≤100 chars and no `<`
or `>`), change the description, save. Expected: redirect to `/videos/:id` with
flash "video updated."; the title now shows on the show page; if a YouTube
connection is live, a `VideoSyncBack` Sidekiq job runs in the background — visit
`/sidekiq` to confirm the job processed and YouTube Studio reflects the change.

[ ] 5. **Open the pre-publish modal — publish flow.** From the same draft's edit
page, click `[publish]`. Expected: a Turbo-Frame modal opens with heading
"pre-publish checklist", four checkboxes labelled "Game set correctly (if
category = Gaming)", "Age restriction (18+) reviewed", "Paid promotion declared
if applicable", "End screen reviewed", each with a `[check in studio]`
deep-link. The submit button reads `[confirm publish]` and is disabled.

[ ] 6. **Tick boxes incrementally.** Tick three of the four boxes. Expected: the
`[confirm publish]` button stays disabled. Tick the fourth. Expected: the button
becomes enabled.

[ ] 7. **Confirm the publish.** Click `[confirm publish]`. Expected: redirect to
the video's show page with flash "video published."; the show page now reflects
`privacy: public`; the show page's "starred" / "connected" detail rows survive;
YouTube Studio shows the video as Public within ~30s (sync-back is async).

[ ] 8. **Edit a public video — no checklist re-fires.** Visit the edit page for
a video that's now `public`. Expected: the visibility section shows
`[unpublish]` instead of `[publish]` / `[schedule]`. Edit the description (no
privacy change), save. Expected: redirect with "video updated." flash; no modal
appears; the privacy stays `public`.

[ ] 9. **Try `[unpublish]`.** Click `[unpublish]` on the edit page. **EXPECTED
OUTCOME (TODAY):** the action returns 422 with an error page showing "use [
publish ] or [ schedule ] to change privacy_status". This is the documented
Blocker 1 and indicates the bug surfaces as designed in the playbook. (When
Blocker 1 is fixed, the expected outcome flips to: privacy returns to `private`;
no checklist fires; flash confirms the unpublish.)

[ ] 10. **Schedule a future publish.** Visit a private draft's edit page, click
`[schedule]`. Expected: the modal opens with a `publish at` datetime input below
the four checkboxes. Pick a timestamp at least one hour in the future. Tick all
four boxes. Click `[confirm schedule]`. Expected: redirect with "video
scheduled." flash; the show page reflects `privacy: private` AND a `publish_at`
timestamp; YouTube Studio shows the video as "Scheduled".

[ ] 11. **Schedule rejects past timestamps.** From a different private draft,
click `[schedule]`. Set `publish at` to one minute in the past. Tick all four
boxes. Submit. Expected: the modal re-renders with a flash error "publish_at
must be in the future" (or equivalent).

[ ] 12. **Schedule rejects untouched checklist.** From a private draft, click
`[schedule]`, leave all checkboxes unchecked, set a future `publish at`. Notice
the submit button stays disabled. (If you bypass the JS via DevTools and POST
anyway, the server still rejects with "must be 'yes'".)

[ ] 13. **Link a video to a project.** Visit the edit page for any video. In the
`project` section, pick a project from the select. Save. Expected: redirect with
success flash; the show page now shows "part of project: [project name]" near
the title.

[ ] 14. **Project page lists linked videos.** Visit
`/projects/:linked_project_id`. Expected: a "linked videos" section lists the
video(s) you linked, ordered with most-recent `published_at` first; draft videos
render with `—` in the published column.

[ ] 15. **Unlink survives project deletion.** Delete the project from
`/projects` (via the deletions confirmation flow). Expected: the project
disappears from `/projects`; the previously-linked video still exists at
`/videos/:id` with no project line on the show page.

[ ] 16. **Imported video edit doesn't trigger the modal.** Identify a `public`
or `unlisted` video that has never gone through the publish flow (the small
"imported" indicator shows on the index and show pages). Click `[edit]`.
Expected: the visibility section shows `[unpublish]` (no `[publish]`). Edit the
description and save. Expected: the modal does not fire; the update succeeds.

[ ] 17. **Validation surfaces inline error copy.** Edit a video, set the title
to a 101-character string, save. Expected: form re-renders at the same URL with
a 422; the error block at the top reads "couldn't update — check the fields
below." with the message "Title is too long (maximum is 100 characters)" listed.

[ ] 18. **Last-sync-error surfaces inline.** (Optional, requires breaking the
sync-back deliberately.) If a sync-back run lands a non-empty `last_sync_error`
on a video, visit the show page. Expected: a flash-error block reading "youtube
sync failed: <error>".

[ ] 19. **Studio deep-links open in a new tab.** On the edit page, `studio-only`
section, click any `[open in studio]` link. Expected: a new tab opens at
`https://studio.youtube.com/video/<youtube_video_id>/edit`.

[ ] 20. **Smuggle guard surfaces a clear error.** (Optional, manual.) Use
DevTools to inject `privacy_status=public` into the edit form's POST and submit.
Expected: 422 with an error message instructing to use `[publish]` or
`[schedule]`. Today this is also what the `[unpublish]` button hits — see
Blocker 1.
