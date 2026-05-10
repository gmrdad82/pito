# Manual test playbook — Phase 9: drop sign-in-with-Google + rename `GoogleIdentity` → `YoutubeConnection`

**Branch:** `main` (commit `9ea8896`) **Spec:**
`docs/plans/beta/09-login-with-google-drop/specs/01-google-identity-rename.md`
**ADR:** `docs/decisions/0006-drop-sign-in-with-google-channel-only-oauth.md`
**Reviewer run:** 2026-05-10 10:50

## Pipeline summary

- Code review: pass — 1 minor concern (pre-existing, not introduced by Phase 9)
- Simplify: pass — 0 suggestions (rename is mechanical; no new abstractions
  introduced)
- Test suite: 1673 examples, 0 failures, 0 pending
- Lint (`bundle exec rubocop`): 421 files inspected, 0 offenses
- Security static analysis (`bundle exec brakeman -q -w2`): 0 warnings
  (2 obsolete ignore-file entries flagged)
- Dependency audit (`bundle exec bundler-audit check --update`): clean (1078
  advisories scanned, none applicable)
- Reviewer-spec checkpoints (per spec §"Reviewer checkpoints"):
  - `git grep 'GoogleIdentity\|google_identity_id\|oauth_identity_id' app/ spec/ config/ lib/`
    — only intentional Phase-9 historical-rename comments. No live identifier
    survivors.
  - `git grep -i 'sign in with google\|sign-in with google\|login with google' app/ spec/`
    — only the assertion in `spec/requests/sessions_spec.rb` that guards
    against reintroduction. Clean.
  - `bin/rails routes | grep -i auth/google` — exactly the two expected lines
    (`/auth/google/callback` and `/auth/failure`); the dev-only `/auth/google`
    redirect is gone, the `:google_oauth_start` helper is gone.
  - Schema: `db/schema.rb` shows `create_table "youtube_connections"` and
    `youtube_connection_id` columns on `channels`, `videos`,
    `youtube_api_calls`. Zero `google_identities` / `oauth_identity_id` /
    `google_identity_id` survivors. FK lines reference `youtube_connections`.
  - Settings → YouTube view (`app/views/settings/youtube/show.html.erb`) uses
    `@youtube_connection` exclusively; no stray `@identity`.
  - Audit-log event keys are wired exactly per spec:
    `youtube_connection.callback.succeeded`, `youtube_connection.callback.failed`,
    `youtube_connection.callback.stale_intent` (see
    `app/controllers/youtube_connections/oauth_callbacks_controller.rb` lines
    46, 55, 63, 68).
  - Stale-intent flash copy matches spec verbatim:
    `"sign-in via google is not supported. log in with email and password."`
    (`STALE_INTENT_FLASH` constant at line 25).
  - Channel disconnect path: `dependent: :nullify` on
    `YoutubeConnection has_many :channels` (preserves Phase 7C decision);
    `dependent: :destroy` on `User has_many :youtube_connections` (per locked
    decision).

## Blockers

None.

## Concerns and suggestions

All flagged as **minor / nitpick** (non-blocking). The rename is mechanical and
the diff is exactly the spec-prescribed shape; the items below are
opportunistic notes, not corrections required before validation.

1. **(minor / pre-existing, NOT introduced by Phase 9) —
   `Settings::YoutubeController#connect` does not override the OAuth scope at
   the request phase.** The omniauth initializer comment at
   `config/initializers/omniauth.rb` line 30-32 promises that
   `Settings::YoutubeController#connect` will override the default
   `openid email profile` scope with the YouTube scopes via session-stashed
   params. The `connect` action at
   `app/controllers/settings/youtube_controller.rb:31-35` does NOT actually do
   this — it just `redirect_to "/auth/google_oauth2"` with no scope params.
   Result: the OAuth grant created at the callback only carries
   `openid email profile`; no `youtube.readonly`. This is a Phase 7-era gap
   that Phase 9 did not touch. Per the spec's "Phase 9 vs Phase 11 boundary"
   master decision (locked), expanding the connect surface to request the
   right scopes is Phase 11's job. **Practical impact for this manual test:**
   the OAuth flow completes and a `YoutubeConnection` row is created; the
   subsequent `Youtube::Client#channels_list(mine: true)` call from
   `/settings/youtube` will fail with a `Youtube::NeedsReauthError` or a
   401 from Google because the access token has no YouTube scope. The page
   renders the connected-state pane but the channel list shows the
   `youtube api unavailable right now ...` flash. This is expected; verify
   it does NOT block reaching step 7 below.

2. **(minor / housekeeping) — Two obsolete entries in
   `config/brakeman.ignore`** (fingerprints
   `4d586370565ad858623ed4e34fae39e1c97703ae2505563f20e37f124f373ba5` and
   `050af47121b0c4251d18c5b722e529807edb8a9852128f6fa384c768d47e0317`).
   Brakeman flagged them as obsolete on this run because the underlying
   warnings no longer fire under Brakeman 8.0.4 + Rails 8.1.3. Already noted
   by rails-impl as a non-blocking follow-up for a future hygiene sweep.

3. **(minor / pre-existing) —
   `Google::RevokeToken.call` is invoked from inside an
   `ActiveRecord::Base.transaction` block in `Youtube::DisconnectChannel.call`
   (`app/services/youtube/disconnect_channel.rb:29-52`). The revoke makes a
   synchronous outbound HTTP POST to `oauth2.googleapis.com/revoke` while the
   DB transaction is held open, AND `RevokeToken#write_audit_row` tries to
   `INSERT` a `YoutubeApiCall` row on the same connection. Network latency
   inflates the transaction window; if the audit insert raised, the entire
   disconnect would roll back even though the upstream Google revoke
   succeeded. This is a Phase 7C-era pattern; Phase 9 only renamed the
   parameter. Not a Phase 9 regression; flagging for the architect's
   architectural-debt list.

4. **(nitpick) — `db/migrate/20260510081047_rename_google_identity_to_youtube_connection.rb`
   `down` method exists but is documented as "bookkeeping only".** No spec
   exercises it. Acceptable per the spec's "Migration posture" section. No
   action.

## Manual test steps

The user works through this set on a `bin/dev`-running stack with Postgres
seeded fresh. If the master agent has already reseeded in parallel, jump
straight to step 2.

> **Setup preamble.** Reseed the database to verify the migration runs cleanly
> on a fresh schema, and confirm the seed prints the expected banner. Run from
> the repo root:
>
> ```bash
> bin/rails db:drop db:create db:migrate db:seed
> ```
>
> **Expected:** the seed output prints `user: <email> (id=...)`, prints the
> dev-token banner once, prints `100 channels seeded` and `200 videos with
> stats`, ends with `done!`. No migration error. No SQL warning about a
> missing index or stale FK.

1. **Verify schema invariants** (one-shot, no UI yet). Connect to the dev DB:

   ```bash
   bin/rails dbconsole
   ```

   Then run:

   ```sql
   \dt
   ```

   **Expected:** `youtube_connections` is in the list; `google_identities` is
   NOT. Then:

   ```sql
   \d youtube_connections
   ```

   **Expected:** the column list matches the schema dump
   (`access_token`, `email`, `expires_at`, `google_subject_id`,
   `last_authorized_at`, `last_refreshed_at`, `needs_reauth`, `refresh_token`,
   `scopes`, `user_id`); two indexes:
   `index_youtube_connections_on_google_subject_id` (unique) and
   `index_youtube_connections_on_user_id`. Then:

   ```sql
   \d channels
   ```

   **Expected:** `youtube_connection_id bigint` column;
   `index_channels_on_youtube_connection_id`; FK to `youtube_connections`. NO
   `oauth_identity_id` column.

   ```sql
   \d videos
   \d youtube_api_calls
   ```

   **Expected (videos):** `youtube_connection_id` column; FK to
   `youtube_connections`. **Expected (youtube_api_calls):**
   `youtube_connection_id` column; two indexes
   (`index_youtube_api_calls_on_youtube_connection_id` and
   `index_youtube_api_calls_on_connection_time`). Quit with `\q`.

2. **Run the full test suite** (architect already ran; user re-runs to confirm
   on their machine):

   ```bash
   bundle exec rspec
   ```

   **Expected:** `1673 examples, 0 failures` (give or take the architect's
   delta — within ±5 examples is fine if seeding fixtures shift the count).

3. **Run rubocop:**

   ```bash
   bundle exec rubocop
   ```

   **Expected:** `421 files inspected, no offenses detected`.

4. **Run brakeman:**

   ```bash
   bundle exec brakeman -q -w2
   ```

   **Expected:** `No warnings found`. The "Obsolete Ignore Entries" block is
   informational only; not a security regression.

5. **Smoke the routes table:**

   ```bash
   bin/rails routes | grep -iE 'auth/google|youtube_connection_oauth'
   ```

   **Expected:** exactly three lines:

   - `youtube_connection_oauth_callback GET|POST /auth/google/callback ... youtube_connections/oauth_callbacks#create`
   - `youtube_connection_oauth_failure  GET     /auth/failure(.:format)   ... youtube_connections/oauth_callbacks#failure`
   - (no third — confirm absence of `/auth/google` redirect AND
     `:google_oauth_start`)

6. **Confirm `/auth/google` (the dropped dev-only redirect) is GONE.** With
   `bin/dev` running, hit it directly:

   ```bash
   curl -sS -o /dev/null -w '%{http_code}\n' https://app.pitomd.com/auth/google
   ```

   **Expected:** `404` (the route was removed; no shortcut entry-point exists
   anymore).

7. **Confirm the stale-callback path.** Hit the callback URL directly with no
   session intent:

   ```bash
   curl -sS -o /dev/null -w '%{http_code}\n' https://app.pitomd.com/auth/google/callback
   ```

   **Expected:** redirect (302) to `/auth/failure?...`. The first redirect
   target should NOT be `/` (root) — that was the dropped sign-in branch.
   Then read the audit log:

   ```bash
   tail -3 log/auth_audit.log
   ```

   **Expected:** the most recent entry has
   `"event":"youtube_connection.callback.stale_intent"` AND/OR
   `"event":"youtube_connection.callback.failed"` with
   `"reason":"missing_auth_hash"` (depending on whether OmniAuth supplied an
   auth hash on the bare GET — both are acceptable shapes; the stale-intent
   key is the spec-locked one for the dropped-sign-in case).

## User Validation

The browser-only walkthrough. Each step is observable from the URL bar / page
render alone.

[ ] 1. **Login form is email-only.** Visit `https://app.pitomd.com/login`. The
       page renders an `email` field, a `password` field, a "remember me on
       this device (30 days)" checkbox, and a `[log in]` button. There is NO
       "Sign in with Google" button, NO `<hr>` divider, NO third-party-
       identity copy. (This was already true post-Phase-8; Phase 9 only adds a
       guarding spec. Visual confirmation.)

[ ] 2. **Sign in with the seeded email + password.** Use the credentials
       printed during reseed (or in `bin/rails credentials:edit` under the
       `:owner` block). The post-login redirect lands on `/` or the channels
       workspace. Confirm the page chrome ("settings", "channels", "videos")
       renders normally.

[ ] 3. **Settings → YouTube renders the empty state.** Visit
       `https://app.pitomd.com/settings/youtube`. The page heading reads
       `settings → YouTube`. The body shows `no google account connected.`
       and a single `[ connect ]` button. The text below mentions
       `youtube.readonly` and `yt-analytics.readonly` — read-only assurance.

[ ] 4. **Click `[ connect ]`.** The browser bounces through Google's consent
       screen. Approve. The post-callback redirect lands on `/settings/youtube`
       with a green-bracketed `google account connected.` notice. The page now
       shows `connected as: <your-google-email>` and a `[ reconnect ]` button.
       (Per concern §1 above, the channel list area below probably shows
       `youtube api unavailable right now ...` because the OAuth grant only
       carries `openid email profile`. This is expected for Phase 9; Phase 11
       expands the connect surface.)

[ ] 5. **Confirm a `YoutubeConnection` row exists.** Open `bin/rails
       dbconsole` (in a separate terminal) and run
       `SELECT id, user_id, email, google_subject_id, needs_reauth FROM
       youtube_connections;`. Expected: exactly one row;
       `needs_reauth = false`; `email` matches the Google account you
       approved. Then `SELECT access_token FROM youtube_connections;` —
       confirm the value starts with `{"p":"`...` (encrypted ciphertext blob,
       NOT plaintext `ya29....`).

[ ] 6. **Connect a channel.** From `/settings/youtube`, if the channel list
       rendered (concern §1 may suppress it — if the list is empty, skip to
       step 8), pick a channel and click its `[ connect ]` button. The post-
       redirect lands back on `/settings/youtube` with a `connected.` notice.
       In `dbconsole`:
       `SELECT id, channel_url, youtube_connection_id FROM channels WHERE
       youtube_connection_id IS NOT NULL;` — confirm at least one row with
       `youtube_connection_id` populated.

[ ] 7. **Disconnect the channel via the action-confirmation page.** From
       `/settings/youtube`, click the `[ disconnect ]` link on a connected
       channel row. The browser navigates to a confirmation page with the
       heading `disconnect 1 YouTube channel?`, a single-row table showing
       the channel URL, and `[ confirm disconnect ]` / `[ cancel ]` buttons.
       Click `[ confirm disconnect ]`. The post-redirect lands on
       `/settings/youtube` with a `disconnected 1 channel.` notice. In
       `dbconsole`: `SELECT id, channel_url, youtube_connection_id FROM
       channels WHERE id = <the_id>;` — `youtube_connection_id IS NULL`. Then
       `SELECT count(*) FROM youtube_connections;` — expect `0` if no other
       channel referenced the connection (per locked Phase 7C disconnect-
       lifecycle decision: when no channels remain, the connection row is
       destroyed and the Google grant is revoked).

[ ] 8. **Walking unauthenticated `/auth/google` lands on a 404.** Open a
       private/incognito window. Visit `https://app.pitomd.com/auth/google`
       directly. The browser renders a 404 page (the dropped dev-only
       redirect). The login page does NOT redirect from this URL — there is
       no shortcut entry-point.

[ ] 9. **Walking the bare callback path lands on the failure page with the
       locked flash copy.** In the same incognito window, visit
       `https://app.pitomd.com/auth/google/callback` directly (no session
       intent). The browser ends on `/auth/failure` (or shows the "google
       sign-in failed" plain-text page). The flash copy on the redirect
       chain — visible if you flip on the redirect chain in DevTools or check
       the cookie-stored flash — reads `sign-in via google is not supported.
       log in with email and password.` (This is the locked stale-intent
       flash from spec §"Master agent decisions → Copy decisions §1".)

[ ] 10. **Re-pair MCP / Claude Mobile (sanity).** Phase 8 issued a fresh dev
        token and the auth tokens carry over. Open Claude Mobile (or the
        Web MCP UI), confirm the existing pairing still resolves
        `list_docs` / `read_doc` against the current docs tree. (No Phase 9
        change to MCP; this is a smoke verification that Phase 9 did not
        accidentally touch the MCP surface — `git grep 'GoogleIdentity'
        app/mcp/` returned zero.)

[ ] 11. **Sidekiq web is reachable.** Visit `https://app.pitomd.com/sidekiq`,
        sign in with the basic-auth user from
        `Rails.application.credentials.sidekiq.username` /
        `:password`. Confirm the dashboard renders (no Phase 9 regression on
        the Sidekiq mount).

## Cleanup

If you want to roll back local state to the seeded baseline:

```bash
bin/rails db:drop db:create db:migrate db:seed
```

The seed reprints the dev-token banner; copy it into your MCP / API token
manager. No `git checkout` needed — Phase 9 already landed in `main`.

If a Google grant was revoked during step 7, you may want to revisit
`https://myaccount.google.com/permissions` and confirm the pito grant is gone
(idempotent check — the spec's locked `7C-already-revoked` decision means
re-running disconnect is a no-op).
