# Manual test playbook — Channel read-only conversion (Unit A0)

**Branch:** `main` (uncommitted working tree) **Spec:**
`docs/plans/beta/29-screen-polish-sweep/specs/channel-read-only-conversion.md`
**Reviewer run:** 2026-05-14 16:50

> **Restart `bin/dev` before you start.** This change touches `config/routes.rb`
> (routes added/removed), autoloaded classes (controllers + model + helper
> deleted/added), and applies a DB migration (`drop_channel_diffs`). A running
> server will 500 or misroute until restarted. The migration was already applied
> to the dev DB by the implementer — if you reset the DB, re-run
> `bin/rails db:migrate`.

## Pipeline summary

- Code review: pass — 0 blocking concerns, 1 minor note (see Concerns)
- Simplify: pass — 0 suggestions; the diff is overwhelmingly deletion (-7881
  lines), no new redundancy introduced
- Test suite: 8614 examples, 25 failures, 1 pending — all 25 failures are
  pre-existing and unrelated to A0 (none of the failing files are in the A0
  diff; all 427 A0-touched specs pass in isolation)
- Security static analysis (brakeman -q): 0 new warnings — 3 weak-confidence
  findings, all pre-existing (notifications `link_to` href, TOTP QR svg,
  composites `send_file`), none in A0-touched files
- Dependency audit (bundler-audit): clean — no vulnerabilities
- Rubocop: clean — 14 A0-touched files inspected, 0 offenses

## Blockers

None. This is a GO for user validation.

## Concerns and suggestions

- **Minor (no action needed):** the spec's `StarsController` sketch referenced
  `params[:channel_id]`, but a singular nested `resource :star` exposes the
  parent id as `params[:id]`. The implementer correctly used `params[:id]` and
  documented the deviation in the controller comment. Behaviourally correct;
  flagged only so the spec/code divergence is on record.
- **Tracked follow-up — `db/structure.sql`:** still lists `channel_diffs`.
  Verdict: **acceptable as a tracked follow-up, not A0's concern.** The repo has
  no `config.active_record.schema_format = :sql` setting, so Rails uses the
  default `:ruby` format — `db:migrate` regenerates `db/schema.rb` only and
  never touches `structure.sql`. The file is genuinely orphaned (prior
  migrations like `drop_deprecated_notification_kinds` left it equally stale).
  Forcing A0 to hand-edit an un-maintained file would be wrong. Recommend a
  dedicated cleanup unit that either deletes `structure.sql` or wires the dump.
- **Tracked follow-up — orphaned watermark/channel-preview CSS:** ~45 dead
  `.watermark-*` / `.preview-watermark` / `channel-preview` rules remain in
  `app/assets/tailwind/application.css`. Verdict: **acceptable as a tracked
  follow-up.** Dead CSS does not 500 and does not affect behaviour; removing it
  is pure tidy-up. Matches the posture the spec itself took with
  `youtube/client.rb`'s now-dead write methods. Should be swept in the same
  later tidy-up pass.
- **Docs drift (already flagged in the log):** `docs/architecture.md` channel
  section and `docs/mcp.md` (`channel_diff_*` tools) still describe the cut
  surface. Out of `pito-rails` scope by design — for the docs pass.

## Manual test steps

Setup preamble (terminal):

1. Stop any running `bin/dev`, then start it fresh: `bin/dev`. Wait for Puma +
   Tailwind to come up.
2. Confirm the migration is applied:
   `bin/rails runner 'puts ActiveRecord::Base.connection.table_exists?(:channel_diffs)'`
   → prints `false`.
3. Confirm the cron entry is gone:
   `grep -c channel_diff_check config/sidekiq_cron.yml` → prints `0`;
   `grep -c video_diff_check_bulk config/sidekiq_cron.yml` → prints `1` (video
   diff-check survives).
4. Log in at `http://localhost:3000` with your dev owner credentials.
5. Have at least one channel in the DB (ideally one with a connected Google
   account, so the connection panel and sync are exercisable). Note its slug and
   integer id.

Happy path:

6. **Channel index renders.** Open `http://localhost:3000/channels` → the
   channel list renders, sort/filter controls work, no error.
7. **Channel show renders read-only.** Click a channel → `/channels/:slug`
   loads. The heading-actions row shows only `[changes]`, `[sync]`, `[revoke]`,
   `[-]` — **no `[e]` / `[edit]`** affordance. Page body has the banner, links,
   videos table, analytics, Google panel — no editable form, no diff banner.
8. **No diff-banner frame in source.** View-source on the show page, search for
   `channel_diff_banner` → **absent**.
9. **Star toggles via the new path.** Back on `/channels`, select two or more
   rows and `[open N]` to get split-view panes. In a pane, click `[star]` → the
   label flips to `[unstar]`, the page redirects to the channel show with a
   "channel updated." notice. Click `[unstar]` to flip back. Reload → state
   persisted.
10. **Star via JSON (curl).** With integer id `N`:
    ```
    curl -X PATCH http://localhost:3000/channels/N/star.json \
      -H "Content-Type: application/json" \
      -d '{"channel":{"star":"yes"}}'
    ```
    Expect `200` with the channel detail JSON, `"star"` reflecting the toggle.
11. **Bad boundary value is rejected.**
    `curl -X PATCH http://localhost:3000/channels/N/star.json -H "Content-Type: application/json" -d '{"channel":{"star":"bad"}}'`
    → expect `422` with an `errors` array; `star` unchanged.
12. **Read-only mirror proof — extra fields ignored.**
    `curl -X PATCH http://localhost:3000/channels/N/star.json -H "Content-Type: application/json" -d '{"channel":{"star":"yes","title":"HACKED"}}'`
    → expect `200`; then open the channel show page and confirm the title is
    **unchanged** (the removed attribute was silently ignored, not assigned).
13. **Sync still pulls.** On a channel show page click `[sync]` → routes to the
    sync confirmation screen at `/syncs/channel/:id` (no `?intent=diff_check` in
    the URL). Confirm it → the one-way `ChannelSync` enqueues (check `/sidekiq`
    or watch `last_synced_at` update on reload). No diff banner appears
    afterward.
14. **History survives.** On a channel show page click `[changes]` →
    `/channels/:slug/history` renders the read-only change-history table (or the
    "no changes yet." empty state).
15. **Google connection panel survives.** On a channel with a connected Google
    account, confirm the connection panel still renders email / scopes /
    last-authorized state, and the `[connect]` / reauth affordances behave.

Edge cases — removed routes are gone:

16. **Edit route is gone.** Visit `http://localhost:3000/channels/<slug>/edit` →
    routing error / 404, not an edit form.
17. **Diff route is gone.** Visit `http://localhost:3000/channels/<slug>/diff` →
    routing error / 404.
18. **Preview route is gone.** Visit
    `http://localhost:3000/channels/<slug>/preview` → routing error / 404.
19. **General update is gone.**
    `curl -i -X PATCH http://localhost:3000/channels/N.json -H "Content-Type: application/json" -d '{"channel":{"star":"yes"}}'`
    → expect `404` (the old `channels#update` JSON path no longer exists; the
    CLI star toggle break is a known, deferred consequence per spec Q1).

## Cleanup

- The star toggles and the sync are idempotent — re-star / re-sync to restore
  prior state.
- To roll back the migration locally: `bin/rails db:rollback` (the
  `drop_channel_diffs` migration has a faithful reversible `down`).
- To discard the whole change and retry: `git stash` (or `git checkout -- .`
  plus removing the untracked new files), then restart `bin/dev`.

## User Validation

[ ] 1. **Read-only show page.** Open a channel from `/channels` → the
heading-actions row shows `[changes]`, `[sync]`, `[revoke]`, `[-]` and **no
`[e]` / `[edit]`** link; the page body has no editable form. [ ] 2. **No diff
banner.** On the same channel show page → there is no "youtube has N newer
values" banner anywhere on the page. [ ] 3. **Star toggles and persists.** Open
two channels in split-view panes, click `[star]` in a pane → label flips to
`[unstar]`, you land back on the channel show with a "channel updated." notice;
reload → the new star state is still there. [ ] 4. **Star toggles back.** Click
`[unstar]` → label flips back to `[star]` and persists across a reload. [ ] 5.
**Edit URL 404s.** Type `/channels/<slug>/edit` into the address bar → you get a
routing-error / 404 page, not an edit form. [ ] 6. **Diff URL 404s.** Type
`/channels/<slug>/diff` into the address bar → routing-error / 404 page. [ ] 7.
**Preview URL 404s.** Type `/channels/<slug>/preview` into the address bar →
routing-error / 404 page. [ ] 8. **History still works.** Click `[changes]` on a
channel show page → the read-only change-history table (or "no changes yet."
empty state) renders. [ ] 9. **Sync still works.** Click `[sync]` on a channel
show page → you land on the sync confirmation screen; confirm it → it returns
you to the channel with no error and no diff banner. [ ] 10. **Google panel
still works.** On a channel with a connected Google account, the connection
panel renders the account email / scopes / last-authorized state as before.
