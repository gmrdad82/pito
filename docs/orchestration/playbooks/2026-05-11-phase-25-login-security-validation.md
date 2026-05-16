# Manual test playbook — Phase 25 Login Security + New-Location Approval

**Branch:** `main` **Phase:**
`docs/plans/beta/25-login-security-and-new-location-approval/` **Commit range:**
`e145122..2959a2f` **Reviewer run:** 2026-05-11 18:09

All seven sub-specs (01a through 01g) shipped and ticked. This playbook walks
the user through the full Phase 25 surface end-to-end across web, MCP-adjacent
checks, and the TUI overlay so the on-camera-ready login posture is exercised
before the architect pushes.

## Pipeline summary

- Code review (manual diff sweep across the 17 controllers, 13 services, 2
  models, 4 migrations, 6 MCP tools, rack-attack init, token-rotation concern,
  TUI overlay): pass — 6 non-blocking concerns (see Concerns).
- Simplify sweep: pass — 1 non-blocking observation (see Concerns).
- Phase 25 RSpec slice (`spec/services/auth/`, `spec/requests/login/`,
  `spec/requests/settings/security/`, both system specs, all 9 MCP tool specs,
  models, sessions rate-limit + token-rotation specs, sweeper job spec,
  rack-attack throttle spec): **683 examples, 0 failures**.
- Brakeman security scan: **0 warnings, 0 errors** across 64 controllers, 66
  models, 213 templates.
- bundler-audit: **0 vulnerabilities** (ruby-advisory-db 1,080 advisories
  current as of 2026-05-11).
- Rust `cargo test --workspace`: **770 passed, 0 failed, 0 ignored** across
  every CLI crate target (matches the log's claim).
- Rust `cargo fmt --check`: clean.
- Rust `cargo clippy --workspace --all-targets -- -D warnings`: clean.

## Blockers

None. Every gate is green and no blocker-class regression surfaced in the review
pass. The user can validate immediately.

## Concerns and suggestions

These are non-blocking. None gate the manual validation. Architect may decide to
fix-forward in a small Phase 25 polish lane after the user signs off, or fold
them into the docs sweep that already owes `docs/auth.md` + ADR-0007.

1. **Bracketed-link inner-padding regressions (6 violations).** Project rule per
   `docs/agents/reviewer.md` §A: `[label]` with no inner whitespace. Six new
   submit buttons in Phase 25 ERB carry `[ enable 2FA ]`, `[ confirm 2FA ]`,
   `[ disable 2FA ]`, `[ regenerate ]` (twice — one file is included in two
   places), `[ verify ]`:
   - `app/views/settings/security/totps/new.html.erb:35` — `[ enable 2FA ]`
   - `app/views/settings/security/totps/show.html.erb:49` — `[ confirm 2FA ]`
   - `app/views/settings/security/totps/destroy_screen.html.erb:23` —
     `[ disable 2FA ]`
   - `app/views/settings/security/totp_backup_codes/new.html.erb:23` —
     `[ regenerate ]`
   - `app/views/login/totp_challenges/show.html.erb:16` — `[ verify ]`

   These are plain `<button class="bracketed">` rather than the
   `BracketedLinkComponent`, which is why the inner-padding rule slipped past
   review. The bracketed-link components used elsewhere on the same pages
   (`[ manage 2FA ]`, `[ manage backup codes ]`, `[ disable ]`, `[ cancel ]`)
   render correctly via the component. Drop the inner spaces and switch to a
   form-wrapped `BracketedLinkComponent` submit if practical.

2. **`Login::TotpChallengesController#show` returns implicitly after an
   early-return redirect.** When `@pre_auth_user.totp_enabled?` is false, the
   `show` action calls `redirect_to login_challenge_path` without an explicit
   `return`. Today the action falls through and Rails treats the implicit
   double-render as a no-op because the redirect was already issued, but the
   pattern is brittle (any future addition after the redirect would
   double-render). The matching path in `create` correctly adds `return`. Add
   `return` to `show` for consistency.

3. **`disable 2FA` flow requires only the current TOTP code, not a fresh
   password + TOTP combo.** This matches `01e`'s spec (sole input: fresh 6-digit
   TOTP code), but the user's review brief asked for "re-enter password + TOTP".
   The playbook validates what the code actually does (TOTP only). If the brief
   reflects a tightening the user wants, it would need a short follow-up to add
   the password field to `settings/security/totps/destroy_screen.html.erb` and
   the matching check in `TotpsController#destroy_confirmed`. Same observation
   applies to regenerate-backup-codes (TOTP-only today, brief asked for
   password + TOTP).

4. **TUI overlay parses notification fields out of the rendered markdown body.**
   `extras/cli/src/notifications/login_pending.rs` extracts browser / OS / IP /
   fingerprint / attempt id by string-matching the body the Rails
   `NotificationFormatter::Templates::LoginPendingApproval` template emits.
   Already flagged in the `01c` TUI log under "Open follow-ups" — the structured
   `Notification#event_payload` JSON exists server-side but the decorator does
   not surface it. Brittle to template-copy edits. Not a blocker.

5. **`Auth::BackupCodeConsumer` iterates `find_each` over every backup-code row
   to find a match, then re-locks the matched row.** The first pass uses
   `find_each` for BCrypt comparison; with 10 codes per user this is fine (max
   10 BCrypt compares per login), but the comment claims "10 BCrypt compares at
   human login rate is cheap" while `find_each` defaults to batches of 1000 —
   it's the right shape, just over-engineered for a collection that maxes at 10.
   Optional cleanup: swap to `user.totp_backup_codes.each` since the collection
   is small and bounded. Not a perf concern.

6. **Two purges (`Settings::Security::Blocks::PurgesController` and
   `Settings::Security::Attempts::PurgesController`) write an audit row with
   `target_type` referring to the _purged_ model and `target_id: 0`.** That
   shape is consistent (per the 01g log it resolves the open
   `TODO(phase-25/01d)` marker), and matches the MCP-side purge that uses
   `target_type: "User"` for the actor. Worth double-checking the future
   audit-log filter UI knows how to display `target_id: 0` (it should render as
   "collection scope" not a broken link). Minor UI concern, not a defect.

7. **(Simplify) Two near-identical action-screen controllers under
   `/login/approvals/:id` and `/login/blocks/:id`.** `ApprovalsController` and
   `BlocksController` are 89 + 81 lines with identical `load_attempt` /
   `expired_state?` / `redirect_expired` private methods and the same
   `confirm == "yes"` gate. A `Login::AttemptActionsController` base with the
   service-class swap (`Approver` vs `Blocker`) as a class-level constant would
   save ~60 lines and keep behaviour identical. Optional refactor for a future
   polish lane.

## Manual test steps

Preamble — code-level prerequisites the user runs once before working through
the validation walkthrough below.

1. `git status` — confirm clean tree on `main` at `2959a2f`.
2. `bin/dev` running (Web Puma + Sidekiq + Tailwind watcher). Restart it after
   pulling if it was running before the migrations landed — Phase 25 added three
   migrations and `db/structure.sql` was re-dumped.
3. `bundle exec rspec spec/system/login_security_journeys_spec.rb spec/system/totp_2fa_journey_spec.rb`
   — confirms green locally before running interactively (already verified by
   reviewer, but a 4-second re-run is cheap insurance for the user's machine).
4. Open a browser profile A (your trusted browser — call it "home") and profile
   B (a second profile / incognito with a different UA, call it "field").
   Profile B simulates a new-location login.

## User Validation

Walk through these steps in profile A (home) and profile B (field). Both
profiles are pointed at the same `bin/dev`. Pass / fail is observable from the
browser alone unless a step explicitly tells you to open a separate terminal.

[ ] 1. **Trusted-location happy path.** In profile A, log out if signed in.
Visit `/login`, enter your email + the correct password, submit. You see the
regular signed-in landing page (no challenge, no pending screen). Open
`/settings/security` — the "recent activity" table shows one fresh `success` row
with your geo (or `location unknown` if MaxMind isn't seeded) and a 12-char
fingerprint. "trusted locations: 1, pending: 0".

[ ] 2. **New-location detection — choose approval path.** In profile B
(incognito + different UA), visit `/login`, enter the same email + correct
password, submit. You are redirected to `/login/challenge`, which shows two
bracketed-link choices: `[enter 2FA code]` and `[ask for approval]`. Click
`[ask for approval]`. You land on `/login/pending` with a 10:00 countdown and a
card showing browser / OS / IP / fingerprint.

[ ] 3. **Approve via web notification.** Switch back to profile A. Open
`/notifications` (or click the bell in the top nav). You see an `urgent`
notification titled "new-location login pending approval" with the same browser
/ OS / IP shown in step 2 and two bracketed links: `[yeah, it's me]` and
`[block the intruder]`. Click `[yeah, it's me]`. The action-screen shows the
attempt detail and a `[yeah, it's me]` submit button. Click it. You are
redirected back to `/notifications` with "approved." flash.

[ ] 4. **Pending session activates after approval.** Switch to profile B. The
`/login/pending` page should auto-redirect (the countdown Stimulus controller
reloads on a state flip) to the signed-in landing page. If it does not
auto-redirect within ~15 seconds, refresh — you should be signed in.

[ ] 5. **Block flow — different new-location attempt.** In profile B, log out.
Visit `/login`, enter the correct password again, choose `[ask for approval]` on
`/login/challenge`. New `/login/pending` row appears. Switch to profile A. Open
the new notification, click `[block the intruder]`. Action-screen confirms the
block; click the submit button. Switch back to profile B — `/login/pending`
reloads to `/login` with the generic `login failed.` flash. Re-attempt from
profile B with correct password — you immediately see `login failed.` without
even a challenge prompt (the pair is now auto-blocked).

[ ] 6. **Auto-block list visible.** In profile A, visit `/settings/security` —
"active blocks on the auto-block list" counter is 1 (or higher if step 5 was
repeated). Click `[auto-block list]`. The `/settings/security/blocks` index
shows the just-blocked row with the short fingerprint, ip prefix, source badge
"WEB", attempt counter, and a `[view]` action.

[ ] 7. **Unblock action-screen.** Click `[view]` on the blocked row. On the
detail page, click `[unblock]`. The action-screen describes what unblocking
does. Submit the unblock. You are redirected back with "block unblocked."
notice. Switch the index filter `active=no` — the unblocked row appears.

[ ] 8. **Purge expired blocks.** Visit
`/settings/security/blocks?source_surface=web` so a filter is applied (purge
requires at least one filter). Click `[purge by filter]`. The action-screen
previews the row count. Confirm. Rows matching the filter disappear; the audit
log records the purge.

[ ] 9. **Failed-login rate limit (per-IP).** In a fresh profile C (incognito,
fresh UA), visit `/login` and submit the **wrong** password 5 times in quick
succession. The 6th submit returns the generic `login failed.` page (a plain
HTML body, no Tailwind layout) with a `Retry-After` response header — DevTools →
Network → click the `/login` POST → Response headers → confirm
`Retry-After: 60`. Wait 60s before the next attempt or you stay throttled.

[ ] 10. **TOTP enrollment from `/settings/security/totp`.** In profile A, visit
`/settings/security/totp`. Status reads `2FA: off`. Click the enroll button. The
one-shot page shows a QR code, the seed underneath, and 10 backup codes. **Save
the backup codes now** — they will not be shown again. Scan the QR with
1Password (or any TOTP app). Enter a fresh 6-digit code into the confirm field,
submit. Status flips to `2FA: on since <timestamp>` with
`backup codes: 10         unused`.

[ ] 11. **Login with TOTP enabled — 2FA gate appears.** Log out of profile A.
Visit `/login`, submit the correct password. You are bounced to `/login/totp`
(NOT to `/login/challenge` — TOTP gates every login once enrolled, even from a
trusted location). Enter a fresh 6-digit code. You land on the signed-in landing
page. Check `/settings/security/attempts` — the most recent success row has
reason `new_location_2fa_passed`.

[ ] 12. **Backup code consumption.** Log out of profile A. Log in again with the
correct password. On `/login/totp`, instead of a 6-digit code, paste one of the
8-char backup codes you saved in step 10. You are signed in. Visit
`/settings/security/totp_backup_codes` — the unused count is now 9. Log out,
repeat with the **same** backup code — it is rejected with the generic
`login failed.` flash (single-use enforced).

[ ] 13. **TOTP disable flow.** Log in to profile A. Visit
`/settings/security/totp/disable`. The action-screen asks for a fresh 6-digit
code. Enter one, submit. The page redirects to `/settings/security/totp` with
status `2FA: off`. Verify `/settings/security/attempts` does NOT show a new
attempt row for the disable itself (disable is a Settings action, not a login),
but `/settings/security` mentions one fewer trusted action surface. (Note per
Concern 3: this flow uses TOTP-only, not password+TOTP.)

[ ] 14. **Regenerate backup codes.** Re-enroll TOTP via steps 10. Visit
`/settings/security/totp_backup_codes`. Click `[regenerate]`. The action-screen
asks for a fresh 6-digit code. Submit. A new one-shot page displays 10 fresh
codes. Save them. Try one of the OLD codes on a fresh login attempt — it is
rejected.

[ ] 15. **Blocked-locations list and unblock-via-action-screen.** Re-block one
location (repeat the new-location + block flow from step 5 if needed). Visit
`/settings/security/blocks` — row visible. Click `[view]` then `[unblock]` —
action-screen confirms. Submit. The row flips to soft-unblocked (stays for
audit, doesn't auto-block any more).

[ ] 16. **Session hardening — cookie inspection.** In profile A, after signing
in, open DevTools → Application → Cookies → `http://localhost:3027` (or
whichever host you're on). The `pito_session` cookie has `HttpOnly` checked and
`SameSite=Lax`. In production these would also be `Secure`; in `bin/dev` the
flag is off because the dev server is plain HTTP (this is by design — see
`Sessions::TokenRotation#rotate_session_token!` and
`Login::TotpChallengesController#write_session_cookie`).

[ ] 17. **Audit log has rows for every transition.** After running steps 2
through 14, the `auth_audit_logs` table should carry: one `approve` row (step
3), one `block` row (step 5), one `unblock` row (step 7), one `purge` row (step
8), one `totp_enroll` row (step 10), one `totp_disable` row (step 13), one
`backup_code_regenerate` row (step 14). Open a Rails console
(`bin/rails console`):
`AuthAuditLog.order(created_at: :desc).limit(10).pluck(:action, :source_surface, :created_at)`.
Confirm each action above appears with `source_surface: "web"`. **Note: there is
no UI surface for the audit log; it is verified only via the console and
`auth_audit_log_list` MCP tool.**

[ ] 18. **TUI overlay — pending notification appears.** Open a second terminal
and run `extras/cli/target/release/pito` (or `cargo run` from `extras/cli/`).
The TUI lands on the Dashboard. Bearer token must be configured in
`~/.config/pito/config.toml` (or via env) — if not, the TUI runs but does not
poll for notifications. Re-trigger the new-location pending flow from profile B
(steps 2 here). Wait up to 30 s for the TUI poll. The status-line footer should
show `pending approval — [a]pprove [b]lock [l]ater`.

[ ] 19. **TUI overlay — approve via `a`.** Press `a` in the TUI while the
pending-approval prompt is visible in the footer. The pending- approval card
opens as a centered overlay. The footer hint reads `approve   block  `. Press
`a` again to enter ConfirmApprove stage (footer ` confirm approve   cancel`).
Press `y` to fire. The overlay transitions to a `working...` state, then
`approved.`. Press any key to close. Profile B's `/login/pending` should
redirect to the signed-in landing page within ~15 s (next status poll).

[ ] 20. **TUI overlay — block via `b`.** Trigger another pending flow from
profile B. Wait for the TUI prompt. Press `b`, then on the ConfirmBlock stage
press `y`. Overlay shows `blocked.`. Profile B again bounces to `/login` with
generic `login failed.`. Confirm via `/settings/security/blocks` that a new
auto-block row appeared with `source_surface: tui`.

[ ] 21. **TUI overlay — cancel via `l` or Esc.** Trigger one more pending flow.
In the TUI status-line, press `l` to dismiss the prompt for this poll cycle. The
prompt clears. It returns on the next 30 s poll if the pending row is still
in-window. Alternatively, open the overlay (`a`), then press Esc on the Card
stage — overlay closes without firing a POST.

[ ] 22. **Smoke: no JS confirm / alert / prompt anywhere.** Repeat any
destructive action — approve / block / unblock / purge / TOTP disable /
backup-code regenerate. Watch DevTools → Console for any `confirm()` / `alert()`
/ `prompt()` call. There should be none. Every destructive action goes through
the server-rendered action-screen (per LD-16 / project hard rule).

[ ] 23. **Final sign-off — phase 25 plan boxes.** Visit
`docs/plans/beta/25-login-security-and-new-location-approval/plan.md` in your
editor. All seven sub-spec checkboxes (01a through 01g) should be `[x]`. Phase
log (`docs/plans/beta/25-login-security-and-new-location-approval/log.md`) has
seven session entries dated 2026-05-11. No `additions.md` / `dropped.md` files
(none required — every sub-spec landed as scoped).

## Cleanup

Reset state if you want to retry the walkthrough from scratch:

```ruby
# bin/rails console
LoginAttempt.delete_all
BlockedLocation.delete_all
TrustedLocation.delete_all
Session.where(state: %i[pending_approval expired revoked]).delete_all
AuthAuditLog.delete_all
User.first.update!(totp_seed_encrypted: nil, totp_enabled_at: nil,
                   totp_disabled_at: nil)
User.first.totp_backup_codes.delete_all
Notification.where(kind: "login_pending_approval").delete_all
```

Then in a terminal:

```bash
# Restart Sidekiq to clear any in-flight pending sweepers
# (only needed if you ran the validation steps multiple times)
docker compose restart redis   # only if redis-backed Rack::Attack buckets stick
```

Note: the `docker compose restart redis` is optional — it only matters if rate-
limit buckets from step 9 are still tripping. Restart only the named `redis`
service; do not run `docker compose down` or any prune commands.
