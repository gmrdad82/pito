# Manual test playbook — Phase 8: Tenant Drop + Email-Only Login

**Branch:** `main` **Spec:**
`docs/plans/beta/08-tenant-drop/specs/01-tenant-drop-and-email-only-login.md`
**Reviewer run:** 2026-05-10 04:28

## Pipeline summary

- Code review: pass — 5 minor / nitpick concerns; no blockers
- Simplify: pass — 2 light-touch suggestions (no waste, no duplication that
  warrants action this round)
- Test suite: **1662 examples, 0 failures, 0 pending**
- Rubocop: 420 files inspected, no offenses
- Security static analysis (brakeman -q -w2): **0 security warnings** (2
  obsolete-ignore entries — see Concern N4)
- Dependency audit (bundler-audit): no advisories (1078-advisory DB, last
  updated 2026-03-30)
- Cross-stack gates: skipped per spec (Phase 8 explicitly Rails-only — no
  `extras/cli/`, no `extras/website/` changes)

## Reviewer checkpoint sweep (per spec §"Reviewer checkpoints")

The spec defines a `git grep` checkpoint that should return zero matches in
`app/`, `lib/`, `spec/`, `db/`, `config/` for
`Tenant|tenant_id|Current\.tenant|BelongsToTenant|find_by_username_or_email|username`,
modulo the migration body, schema version comment, and intentional
historical-context comments.

Findings:

| Surface                                                        | Result                                                                                                                                                                                                                                                                                                                                                                                                    |
| -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `app/`                                                         | All `Tenant` / `tenant_id` / `BelongsToTenant` matches are explanatory `# Phase 8 — tenant drop.` comments documenting WHY the column / concern is gone, plus the intentional `_legacy_tenant_id` ignored-arg in `NoteSyncJob#perform` (cron-compat shim, called out in the spec). No live references.                                                                                                    |
| `app/models/user.rb`                                           | One mention of `username` in a doc comment ("No `username`, no `tenant`...") — explanatory, not a live ref.                                                                                                                                                                                                                                                                                               |
| `app/models/concerns/`                                         | `belongs_to_tenant.rb` deleted. Confirmed.                                                                                                                                                                                                                                                                                                                                                                |
| `app/models/tenant.rb`                                         | Deleted. Confirmed.                                                                                                                                                                                                                                                                                                                                                                                       |
| `config/initializers/console_tenant.rb`                        | Deleted. Confirmed.                                                                                                                                                                                                                                                                                                                                                                                       |
| `db/schema.rb`                                                 | Zero matches for `tenant_id`, `"tenants"`, or `index_users_on_username`. `users` table = `id, created_at, email (citext), password_digest, updated_at` only. Schema version `2026_05_10_021811` matches the new migration.                                                                                                                                                                                |
| `db/seeds.rb`                                                  | One match (`# is no Tenant model, no username...`) — explanatory.                                                                                                                                                                                                                                                                                                                                         |
| `db/migrate/`                                                  | Historical migrations carry `tenant_id` references (immutable history, expected). The new `20260510021811_drop_tenant_and_username.rb` is the dropper.                                                                                                                                                                                                                                                    |
| `config/database.yml`, `config/routes.rb`, `config/deploy.yml` | `username` mentions are unrelated identifiers (Postgres user, Sidekiq basic-auth `username` block param). Acceptable.                                                                                                                                                                                                                                                                                     |
| `config/sidekiq_cron.yml`                                      | Stale comment "Walks the notes volume per tenant" + "Tenant-wide lock auto-clears" — see Concern N1.                                                                                                                                                                                                                                                                                                      |
| `app/controllers/footages_controller.rb:112`                   | Comment says "with the tenant drop the default scope is gone" — explanatory; line 112 is mid-comment, not code. The grep hit is the word `BelongsToTenant` inside the comment.                                                                                                                                                                                                                            |
| `spec/`                                                        | Every match is an intentional Phase-8 assertion (`expect(...).not_to have_key(:tenant_id)`, `expect(User).not_to respond_to(:find_by_username_or_email)`, the rack-app stray-`tenant_id`-param flaw test, etc.) or a comment. `tenant_context.rb` deleted; `cross_tenant_leak_spec.rb` deleted; `tenant_spec.rb` deleted; `belongs_to_tenant_spec.rb` deleted; `factories/tenants.rb` deleted. Confirmed. |

**Per-section acceptance from the spec:**

- Schema acceptance (7 items): all pass.
- Models / Concerns / Current acceptance (10 items): all pass — `Current`
  declares `:user, :token, :session` only; `belongs_to :tenant` zero hits;
  `Current.tenant` zero hits in `app/`; `User`, `Session`, `ApiToken`,
  `GoogleIdentity` all show the specified shapes.
- Controllers / Auth acceptance (4 items): all pass — concerns drop the pin;
  `SessionsController#create` reads `params[:email]`; view has no
  `name="identifier"`.
- MCP / Doorkeeper acceptance (4 items): three pass; the fourth (OAuth flow
  smoke against `bin/dev`) is a manual step in this playbook.
  - `git grep 'tenant' app/mcp/` returns ZERO matches. Confirmed.
- Storage acceptance (4 items): three pass via grep; the fourth (on-disk note
  files land at `<PITO_NOTES_PATH>/projects/<id>/<file>.md`) is a manual step.
- Seed / Credentials acceptance (5 items): four pass via grep / spec; the fifth
  (`bin/rails db:seed` runs idempotently with the new owner block) is a manual
  step (the seeds_spec.rb file already covers the idempotency programmatically;
  the manual step is to run it on the real dev DB and confirm).
- Tests acceptance (3 items): all pass. RSpec green; spec sweep clean.

**IDOR sweep:** zero `*idor*` files; zero `IDOR` text in `app/` or `spec/`.
Confirmed.

## Blockers

**None.** No blockers — proceed to validation.

## Concerns and suggestions (non-blocking)

### Code review

- **N1 (minor — config doc drift).** `config/sidekiq_cron.yml:14-16` still
  describes the lock as "Tenant-wide lock auto-clears" / "Walks the notes volume
  per tenant". The lock semantics are now install-wide (`AppSetting` key, not
  `Tenant#notes_syncing_at`) and the walk is install-wide. Suggested rewrite:
  "Walks the notes volume install-wide" / "install-wide lock auto-clears".
  Comment-only; no behavior impact. Defer to a docs-keeper or next-touch sweep.
- **N2 (minor — comment cleanup).** `db/seeds.rb` calls `Current.user = owner`
  immediately before `ApiToken.generate!` (line 64). The `generate!` signature
  no longer needs the pin — the explicit `user: owner` keyword is what carries
  the ownership. The `Current.user =` line is dead. Recommendation: drop the
  line. Not strictly required (it's a no-op); cleanup-only. Defer to follow-ups.
- **N3 (nitpick — dead arg).** `NoteSyncJob#perform(_legacy_tenant_id = nil)`
  keeps the positional arg for cron compatibility per the spec. Once the cron
  config is touched again (paired with N1's rewrite), drop the arg outright.
- **N4 (minor — brakeman ignore drift).** `config/brakeman.ignore` carries two
  fingerprints (the `SendFile` false-positive on
  `footages_controller#serve_frame` and the `VerbConfusion` carve-out on
  `Sessions::AuthConcern#stash_intended_url`) that brakeman now reports as
  "Obsolete Ignore Entries." The underlying defenses still apply (route
  constraint + regex re-check + cleanpath containment for `serve_frame`; the
  `request.get?` guard at line 75 of `auth_concern.rb` still exists). Most
  likely the rewrite of `Api::AuthConcern` shifted brakeman's fingerprint
  inputs. Refresh the ignore file by re-running brakeman with `-I` to
  interactively re-add the same warnings — only when they actually resurface.
  Track in follow-ups; don't block.
- **N5 (nitpick — non-canonical brakeman flag).** This project's reviewer-doc
  declares `bundle exec brakeman -q`; the dispatch description specifies `-w2`.
  Both are consistent with project conventions for security-sensitive changes
  (warning level 2 surfaces the medium/high band). Not a finding; noted for
  record-keeping.

### Simplify

- **S1 (suggestion).** `NotesLockGuard.locked_tenant_for(controller)` is now an
  alias for `locked_project_for`. The shim exists because callers in the
  controllers still call the old name. Recommendation: rename the call sites and
  drop the shim in a follow-up. Not urgent — the shim is one line and
  well-commented. (The implementation log mentions this.)
- **S2 (suggestion).** `intended_url_target` in `SessionsController` deletes the
  cookie before validating it — fine, but `cookies.delete(...)` with a blank
  target is a wasted write. Move `cookies.delete` to AFTER the blank check.
  Negligible; nitpick only.

### Out-of-scope items rails-impl flagged (carried forward, not actioned by

this review)

1. `pito-docs-keeper` dispatch needed for prose rewrites
   (`docs/architecture.md`, `docs/auth.md`, `docs/setup.md`, `docs/mcp.md`,
   "Architecture notes" paragraph in `CLAUDE.md`). Not blocked by this review.
2. `pito-security-auditor` dispatch — auth-sensitive change. Trigger AFTER this
   playbook is signed off. Not blocked by this review.
3. **User must run `bin/rails credentials:edit`** for the `:owner` block shape
   change. The rails-impl agent cannot edit `config/credentials.yml.enc`. Step 1
   below covers it.

## Manual test steps

The user runs these in order. Each step has an action and an expected outcome.
The user's job is to confirm the expected outcome matches reality.

### Setup

1. **Update credentials (development).**
   - **Action:** `bin/rails credentials:edit --environment development`. In the
     editor, locate the existing `:owner` block (which previously had
     `tenant_name`, `tenant_slug`, `username`, `email`, `password`) and replace
     it with the new shape:
     ```yaml
     owner:
       email: <your-email>
       password: <your-password>
     ```
     Save and exit.
   - **Expected:** the editor closes without error; `config/credentials.yml.enc`
     is rewritten. No error printed by the `credentials:edit` command.

2. **Update credentials (test).**
   - **Action:** `bin/rails credentials:edit --environment test`. Repeat the
     `:owner` block shape from step 1. The values can be different from
     development (suggested: `owner@example.test` / `change-me-please`); the
     test seed only cares that the keys exist.
   - **Expected:** same as step 1.

3. **Optional — wipe legacy on-disk state.**
   - **Action:** if you have a populated `<PITO_NOTES_PATH>` or
     `<PITO_ASSETS_PATH>` from before this phase (the layouts had `tenant-1/`
     segments), wipe them so the flat-layout reseed lands cleanly:
     ```bash
     rm -rf "${PITO_NOTES_PATH:-/var/lib/pito-notes}"/*
     rm -rf "${PITO_ASSETS_PATH:-/var/lib/pito-assets}"/*
     ```
     If `PITO_NOTES_PATH` / `PITO_ASSETS_PATH` are unset in your shell, check
     `.env.development` for their actual locations (likely `tmp/pito-notes` /
     `tmp/pito-assets` under the repo).
   - **Expected:** the directories are empty (or absent — the importer/seed
     creates them on demand).

4. **Destructive reseed.**
   - **Action:** `bin/rails db:drop db:create db:migrate db:seed`
   - **Expected:**
     - Migration `DropTenantAndUsername (20260510021811)` runs without raising.
     - Seed prints `seeding owner user...` followed by
       `user: <your-email> (id=<n>)`.
     - The Voyage AppSetting bootstrap line appears if a key is configured.
     - The dev token banner prints exactly once between `=` rules. Save the
       plaintext now — you cannot recover it.
     - 100 channels, 200 videos with stats, 1 collection / game / project / note
       / timeline. `done!` at the end.
     - No `WARNING: credentials :owner block missing` line if you populated step
       1 correctly.

### Quality gates (run from repo root)

5. **Run the full RSpec suite.**
   - **Action:** `bundle exec rspec`
   - **Expected:** `1662 examples, 0 failures, 0 pending`. (The reviewer's run
     matched.) If your local count differs, expect it to be `1662` modulo any
     local sandbox / fixture variance.

6. **Run rubocop.**
   - **Action:** `bundle exec rubocop`
   - **Expected:** `420 files inspected, no offenses detected`.

7. **Run brakeman.**
   - **Action:** `bundle exec brakeman -q -w2`
   - **Expected:** `0 security warnings`. The `Obsolete Ignore Entries` section
     MAY list 1-2 fingerprints — that's Concern N4, not a blocker.

8. **Run the dependency audit.**
   - **Action:** `bundle exec bundler-audit check --update`
   - **Expected:** `No vulnerabilities found`.

### Web smoke (start `bin/dev` and exercise the surface)

9. **Start the app.**
   - **Action:** `bin/dev`. Wait until Puma binds (you see "Listening on
     http://127.0.0.1:3027" or similar — the project's pito-specific port).
   - **Expected:** Puma + Sidekiq + Tailwind watcher come up cleanly. No boot
     error referencing `Tenant`, `BelongsToTenant`, `Current.tenant`, or missing
     `:owner` credentials.

10. **Login surface — happy path.**
    - **Action:** open `http://127.0.0.1:3027/login` in a browser. Confirm a
      single field labeled `email` (no "or username" text) with placeholder
      `you@example.com`. Type your seeded `:owner.email`, your password, leave
      `remember me` unchecked, click `[log in]`.
    - **Expected:** redirect to `/` (or whatever `intended_url` redirects to
      from a fresh login). Flash banner reads `signed in.` (lowercase). The
      `pito_session` cookie is set.

11. **Login surface — wrong password.**
    - **Action:** logout (`[log out]` or DELETE /session). Re-open `/login`.
      Submit your email with a deliberately wrong password.
    - **Expected:** the form re-renders with status 422 and a SINGLE inline
      message reading `invalid email or password.` (no duplicate copies, no
      "user not found" or "invalid email" wording that would distinguish missing
      vs. wrong-password).

12. **Login surface — unknown email.**
    - **Action:** submit `nobody@nowhere.test` with any password.
    - **Expected:** identical message to step 11 (`invalid email or password.`).
      The constant-time bcrypt dummy compare runs on the backend so the response
      timing should match a wrong-password attempt within ~50ms (you don't
      measure this — it's covered by spec; the manual check is just that the
      COPY is identical).

13. **Login surface — malformed email.**
    - **Action:** submit `garbage-without-an-at` as the email, any password.
    - **Expected:** form re-renders with the SAME generic error. The browser may
      also block the submit via the `type="email"` HTML5 validation (depending
      on browser); if it does, blank the email and try again with a missing-`@`
      value (e.g., paste `garbage` directly into the field via DevTools after
      disabling required, then submit). The server-side path should yield the
      same generic message.

14. **Login surface — blank email.**
    - **Action:** submit a blank email (use DevTools to clear the `required`
      attribute first if the browser blocks it).
    - **Expected:** same generic message; status 422.

15. **Login surface — stray-param flaw smoke.**
    - **Action:** in DevTools, open the login form's network tab. Submit a valid
      login with extra hidden inputs `tenant_id=999`, `username=hax`,
      `admin=yes` (use DevTools to inject them into the form before submission).
    - **Expected:** login succeeds normally. The new `Session` row in the DB has
      `user_id` matching your owner; nothing else changes. There is no
      `tenant_id` column on `sessions` to even attempt to set.

### Settings pages

16. **Settings index renders.**
    - **Action:** visit `/settings`.
    - **Expected:** the page renders without a 500. The header MAY show
      `Current.user.email` instead of the prior `username` — confirm the
      identity displayed is your seeded email.

17. **`/settings/oauth_applications` renders.**
    - **Action:** visit `/settings/oauth_applications`. Confirm the list page
      renders and any seeded applications are present.
    - **Expected:** no error; the index lists applications install-wide (no
      tenant filter applied, none visible). Click `[ new application ]`, fill
      the form, submit. The plaintext-once page shows `uid` + `secret`. Visit
      the index again and the new application appears.

18. **`/settings/tokens` renders.**
    - **Action:** visit `/settings/tokens`. Confirm the dev token from the seed
      appears in the active list with its 4-character preview.
    - **Expected:** the index renders, the dev token is listed, the token's
      `user` (if displayed) is your seeded owner.

19. **`/settings/sessions` renders.**
    - **Action:** visit `/settings/sessions`. Confirm your current session is
      listed (the IP, user-agent, last-activity timestamp).
    - **Expected:** the page renders. You can click `[ revoke ]` on a different
      session (if any) to test that surface; do NOT revoke your current session
      unless you are testing the redirect-to-login path.

20. **`/settings/youtube` renders.**
    - **Action:** visit `/settings/youtube`. Confirm the page renders.
    - **Expected:** no error. The page may say "no Google identity connected" or
      list one if you completed the OAuth dance previously (Phase 7).

### Storage path verification

21. **Note file lands flat.**
    - **Action:** in `bin/dev`, navigate to a project (you have a `Demo Project`
      from the seed). Open its Notes pane. Edit the `Demo note` and save a body
      line. (The seed creates the row but not the file — the editor's first save
      creates the on-disk file.)
    - **Expected:** the file lands at
      `<PITO_NOTES_PATH>/projects/<project_id>/demo-note.md`. Run
      `find "${PITO_NOTES_PATH:-/var/lib/pito-notes}" -name '*.md'` and confirm
      NO `tenant-1/` segment in any path. Path shape is exactly
      `.../projects/<id>/<file>.md`.

22. **Game cover lands flat.**
    - **Action:** the seeded `Demo Game` has a `cover_art.jpg` attachment. View
      the project's show page; the cover art renders inline.
    - **Expected:** the on-disk file lives under
      `<PITO_ASSETS_PATH>/ active_storage/...` (Active Storage manages its own
      internal hashing layout). Confirm NO `tenant-1/` directory exists anywhere
      under `<PITO_ASSETS_PATH>`. Run
      `find "${PITO_ASSETS_PATH:-/var/lib/pito-assets}" -maxdepth 2 -type d` and
      confirm only `active_storage/` and (if the importer ran) its sub-trees are
      present — no `tenant-X` segments.

### MCP re-pair

23. **Re-pair Claude Mobile and/or Desktop.**
    - **Action:** the prior MCP authorization may carry tokens whose `user`
      reader still resolves correctly (no schema change to the OAuth tables
      beyond the `tenant_id` drop), but token rotation is good hygiene. In
      Claude Desktop / Mobile, disconnect the existing pito MCP connection and
      re-pair via OAuth. The flow goes `/oauth/authorize` (with `scope=dev`) →
      consent → callback → token.
    - **Expected:** the flow completes without the consent screen throwing. The
      new token works.

24. **`dev:save_note` lands a file.**
    - **Action:** from Claude Mobile or Desktop, invoke the `dev:save_note` tool
      with body `phase 8 playbook smoke`.
    - **Expected:** a new file appears at
      `docs/notes/<YYYY-MM-DD-HH-MM-SS>-<slug>.md` (relative to repo root). Open
      the file and confirm it contains the body you sent. NO `tenant-X/` segment
      in the path. The file system layout for notes under `docs/notes/` is
      install-wide (always was — verify it stayed that way).

25. **`list_docs` returns.**
    - **Action:** invoke `dev:list_docs` with
      `prefix: plans/beta/08-tenant-drop/`.
    - **Expected:** the spec and the log are listed; sorted by mtime.

### Doorkeeper smoke (post re-pair)

26. **OAuth dance against bin/dev.**
    - **Action:** if you didn't already do this in step 23, drive an
      Authorization Code + PKCE flow with the curl recipe from `docs/auth.md`
      (or use a Doorkeeper test client). The endpoints are `/oauth/authorize`
      then `/oauth/token`.
    - **Expected:** the access token comes back with the requested scope. A
      subsequent `Authorization: Bearer <token>` request to a tenant-free API
      endpoint (e.g., `/api/projects/1/footages.json`) returns the resource
      without any tenant pinning chatter in the Rails log.

### Sidekiq web

27. **Sidekiq web at /sidekiq.**
    - **Action:** visit `/sidekiq`. The browser prompts for HTTP basic auth;
      enter the credentials from `:sidekiq.<env>.username` /
      `:sidekiq.<env>.password`.
    - **Expected:** the Sidekiq UI loads. Confirm the queues page renders
      ("default" + "search" should be visible). No tenant-related boot error in
      the Sidekiq process logs.

### Cleanup

28. **(Optional) Reset to a fresh DB.**
    - **Action:** if you want to redo the validation from scratch:
      ```bash
      bin/rails db:drop db:create db:migrate db:seed
      ```
    - **Expected:** same as step 4. The dev token banner re-prints (a new token;
      the old one is gone forever — that's the design).

29. **(Optional) Rollback test.**
    - **Action:** `bin/rails db:rollback STEP=1` against the new migration.
    - **Expected:** the migration's `down` runs (re-creates `tenants` empty +
      re-adds `tenant_id` columns nullable). NOTE: the docstring and ADR 0003
      explicitly say rollback is NOT supported. The `down` method exists for
      Rails bookkeeping; the resulting state is NOT a working application —
      every model expects no `tenant_id`. Do not use this in any environment
      with data. The reviewer ran this only as a "does it raise?" check; the
      user can skip this step entirely.

## User Validation

[ ] 1. **Login form looks right.** Visit `/login`. The page shows ONE field
labeled `email` with placeholder `you@example.com`, a password field, a
`remember me on this device (30 days)` checkbox, and a `[log in]` button. There
is NO field labeled `username`, no copy reading `email or username`, and no
other identifier field.

[ ] 2. **Happy login.** Type your seeded email + password, leave remember-me
unchecked, click `[log in]`. The page redirects to `/`. The flash banner at the
top reads `signed in.` exactly once.

[ ] 3. **Wrong password is generic.** Log out (`[log out]` link). Re-open
`/login`, submit your email with a wrong password. The page reloads with one
inline error reading `invalid email or password.` — exactly that text, no other
"no such user" or "wrong password" hints.

[ ] 4. **Unknown email is identical.** Submit `nobody@nowhere.test` with any
password. The error text is identical to step 3 —
`invalid email        or password.` — and renders in the same place.

[ ] 5. **Settings header shows email.** After logging in successfully, visit
`/settings`. The page header / top-right user indicator shows your email (or its
local part) — never `username` or any tenant name.

[ ] 6. **OAuth applications list renders.** Visit
`/settings/oauth_applications`. The page lists every OAuth application
install-wide. No "your tenant's applications" copy.

[ ] 7. **Tokens list renders.** Visit `/settings/tokens`. Your dev token (from
the seed) appears in the active list. The 4-character preview (e.g., `…p88` for
the run captured during this review) matches the last 4 chars of the plaintext
you saved during reseed.

[ ] 8. **Sessions list renders.** Visit `/settings/sessions`. Your current
session appears with IP and last-activity time. The page describes sessions
install-wide, not tenant-scoped.

[ ] 9. **YouTube settings page renders.** Visit `/settings/youtube`. The page
either shows "no Google identity connected" or lists your previously-connected
identity (if you completed the OAuth dance in Phase 7). No tenant-scoped copy
anywhere.

[ ] 10. **Project workspace works.** Visit the seeded `Demo Project`. Open its
Notes pane. Click into `Demo note`, type a line of body, save. The status bar at
the bottom updates the word / char count. No tenant-related error in the flash
or in the Rails server log.

[ ] 11. **MCP from Claude Mobile / Desktop.** Re-pair the MCP connection. From
Mobile or Desktop, invoke `dev:save_note` with any body. A new file appears
under `docs/notes/<timestamp>-<slug>.md`. Open the file in your editor; confirm
the body matches what you sent.

[ ] 12. **Doorkeeper still gates.** Visit `/oauth/applications/<your-app>` from
step 17 above. Confirm the application detail page renders with `[ revoke ]`
buttons on tokens. The OAuth dance from step 23 / 26 above completes without any
tenant-pin error.

[ ] 13. **Sidekiq web renders.** Visit `/sidekiq`, authenticate via the HTTP
basic prompt. The dashboard loads.

## Cleanup

To roll back local state and retry from scratch:

```bash
bin/rails db:drop db:create db:migrate db:seed
rm -rf "${PITO_NOTES_PATH:-tmp/pito-notes}"/*
rm -rf "${PITO_ASSETS_PATH:-tmp/pito-assets}"/*
```

To recover the dev token plaintext (it is shown ONCE; if you lost it, delete the
row and re-seed):

```bash
bin/rails runner 'ApiToken.find_by(name: "dev")&.destroy'
bin/rails db:seed
```
