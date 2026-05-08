# Manual test playbook — Phase 6 + Phase 7 + Path A2 retract + console hook + chart sweep + cross-stack alignment

**Branch:** `main` **Diff baseline:** working tree vs. last commit `21c44ea`
(the prior Phase 5+5.5 playbook is `playbook-2026-05-07-phase-5-and-5.5.md`).
**Specs covered:**
`docs/plans/beta/12-auth-ui-multi-user-readiness/specs/{6a,6b,6c}-*.md`,
`docs/plans/beta/07-google-oauth-youtube-foundation/specs/{7a,7b,7c}-*.md`, plus
the Path A2 retract that lives across `app/decorators/`, `app/mcp/tools/`,
`app/views/{channels,videos}/`, `app/models/{channel,video}.rb`,
`app/controllers/{channels,videos}_controller.rb`,
`config/initializers/console_tenant.rb`, the dashboard sweep
(`app/controllers/dashboard_controller.rb`,
`app/views/dashboard/index.html.erb`), and the cross-stack alignment in
`extras/cli/src/{api/models.rs,ui/dashboard.rs}`. **Reviewer run:** 2026-05-07.

## Pipeline run summary

- `bundle exec rspec`: **1671 examples, 0 failures, 0 pending** — matches the
  expected target of 1671/0/0.
- `bundle exec rubocop`: **clean** (410 files inspected, 0 offenses).
- `bundle exec brakeman -q -A -w1`: **3 warnings** (1 ForceSSL high + 1
  VerbConfusion weak + 1 UnscopedFind weak). **Down from the 7-warning
  pre-Path-A2 baseline** the dispatch cited — Path A2 retired the unscoped Find
  Video controller actions and the count fell to 3. The remaining three:
  - `config/environments/production.rb:1` — ForceSSL is the long-standing
    accepted finding (production HTTPS is terminated upstream by the Cloudflare
    tunnel; documented baseline).
  - `app/controllers/concerns/sessions/auth_concern.rb:73` — VerbConfusion on
    `request.get?` inside `stash_intended_url`. Intentional: `HEAD` requests are
    not navigations and we explicitly do not want them to overwrite the stash.
    Benign; would be cleared by an explicit `request.get? || request.head?`
    no-op guard if the warning becomes noise.
  - `app/controllers/notes_controller.rb:122` — pre-existing `Note.find` that is
    tenant-safe via `BelongsToTenant`'s default scope. Carried over from the
    Phase 5+5.5 playbook (was 5 hits there; 4 of them retired with Path A2's
    Video controller cleanup, only this one remains).
- `bundle exec bundler-audit check --update`: **clean** (1078 advisories
  scanned, ruby-advisory-db at b1e3c15 / 2026-03-30, no vulnerabilities).
- `cd extras/cli && cargo build --release`: **clean** (release profile, 12.5s).
- `cd extras/cli && cargo clippy --all-targets --all-features -- -D warnings`:
  **clean** (0 warnings under `-D warnings`).
- `cd extras/cli && cargo test`: **green** — 199 unit tests + 20 footage
  integration tests + 0 doc-tests, 0 failures.
- `cargo audit` (repo root): **2 known deferred warnings, both ride through
  ratatui 0.29 per follow-ups #4** —
  - `paste 1.0.15` unmaintained (RUSTSEC-2024-0436)
  - `lru 0.12.5` unsound (RUSTSEC-2026-0002) Anything else → STOP. Confirmed
    nothing else.
- Hard-rule grep:
  - `rg 'data-turbo-confirm' app/ extras/`: 2 hits, both doc-comment references
    (`bracketed_link_component.rb:3`,
    `settings/oauth_applications_controller.rb:9`). No live attribute. Clean.
  - `rg 'window\.confirm|alert\(|prompt\(' app/`: 2 hits, both doc-comments
    (`bracketed_link_component.rb:3`, `unsaved_form_controller.js:12`). Clean.
  - `rg 'target="_blank"' app/ -A 1`: 2 hits, both carry
    `rel="noopener noreferrer"` (`videos/_pane.html.erb:18`,
    `channels/_pane.html.erb:15`). Clean.
- Yes/no boundary on new external surfaces:
  - **Login form** — `remember_me` posts the literal string `"yes"` (see
    `sessions/new.html.erb:31`); the controller compares with `== "yes"`.
  - **Settings → OAuth applications form** — `confidential` is read with
    `.to_s == "yes"`. Clean.
  - **Doorkeeper authorization screen** — Doorkeeper's own internals run OAuth's
    native parameter shapes (`response_type`, `code_challenge_method`, etc.)
    which are OAuth standard strings, not yes/no booleans. No boundary-crossing
    yes/no surface.
  - **Google identity callback** — the auth hash from OmniAuth carries
    `expires_at` (epoch seconds) and `scope` (string) — no yes/no in the wire
    shape, no boundary violation.
  - **`/dashboard.json`** — five integer counts only, no booleans, clean.
  - **MCP `get_dashboard`** — same five integer counts.
  - **MCP `update_channel`, `update_video`, `list_channels`, `sync_records`** —
    all retracted to `star`/`connected`/`confirm` enum-of-`yes|no` strings.
- Tenant scoping check on new models:
  - `Session` → `include BelongsToTenant` ✓.
  - `GoogleIdentity` → `include BelongsToTenant` ✓.
  - `YoutubeApiCall` → `include BelongsToTenant` ✓.
  - `OauthApplication`, `OauthAccessToken`, `OauthAccessGrant` → explicitly NOT
    in the default scope (deviation #2 from Phase 6 dispatch). All three carry
    `belongs_to :tenant`; `OauthAccessToken` and `OauthAccessGrant` denormalize
    `tenant_id` from the owning application via
    `before_validation :denormalize_tenant_from_application`. Confirmed in
    place.
  - 17 tenanted data models include `BelongsToTenant`; 6 documented exceptions
    (`Tenant`, `User`, `ApiToken`, `AppSetting`, `ApplicationRecord`, `Current`)
    plus the three Doorkeeper-owned models above.

## Findings

### Blocker

1. **Cross-stack regression: `pito` CLI's `Channel` and `Video` Rust structs no
   longer deserialize the slimmed JSON Rails emits.**
   - File / line:
     - Rust: `extras/cli/src/api/models.rs:3-18` (`Channel`),
       `extras/cli/src/api/models.rs:20-35` (`Video`).
     - Rails: `app/decorators/channel_decorator.rb:8-19` (`as_summary_json`),
       `app/decorators/video_decorator.rb:7-21` (`as_summary_json`).
   - The Rust `Channel` struct still has a required `syncing: bool` field (with
     the `crate::api::yes_no` adapter) — the Rails decorator no longer emits
     `syncing` after Path A2. `serde_json::from_str` will fail with a
     `missing field "syncing"` error against the post-retract Rails server.
   - The Rust `Video` struct still has required `title: String`,
     `privacy_status: String`, `views: u64`, `likes: u64`, `comments: u64`,
     `watch_time_minutes: f64`, `published_at: Option<String>` fields. The Rails
     decorator emits `views/likes/comments/watch_time_minutes` (good) but no
     longer emits `title`, `privacy_status`, or `published_at`.
   - **Why this is a Blocker, not Should-Fix:** the dispatch's "cross-stack
     dashboard alignment" item shipped (DashboardData is in sync), but the same
     audit step did not extend to `Channel` and `Video`. The CLI's TUI calls
     `client.get_channels()` and `client.get_videos()` on startup
     (`extras/cli/src/app.rs:254` and `:284`) — both will fail to deserialize
     against `bin/dev`-served `/channels.json` and `/videos.json`, and the TUI's
     channels and videos panels will show empty. Cargo tests pass because the
     Rust structs round-trip against themselves; Rails specs pass because they
     don't exercise the Rust deserializer.
   - Two ways to land the fix (master agent's call which one to dispatch — this
     is not the reviewer's call):
     - **Trim Rust** — delete the four removed fields from `Channel`/`Video` and
       their `syncing/title/privacy_status/published_at` references in the TUI.
       Symmetric with what Path A2 did to the Rails surface.
     - **Soften Rust** — wrap the four fields in `Option<…>` plus
       `#[serde(default)]` so the CLI tolerates either pre-A2 or post-A2 servers
       during the transition. Slightly more code, but lets older Rails-side
       commits cohabit during dev.
   - Verification once fixed: from the repo root after `bin/dev` is up,
     `curl -s http://localhost:3000/channels.json | head -200` should round-
     trip through `serde_json::from_str::<Vec<Channel>>` in a `cargo test`
     scratch case, AND launching `pito` (TUI) should populate the channels and
     videos panels from the seed.

### Should-Fix

1. **`SessionsController::DUMMY_BCRYPT_HASH` is a class constant computed at
   class-load time** (`app/controllers/sessions_controller.rb:114`). That means
   a `bcrypt` round runs on every Rails reload in development (every code change
   in dev rebuilds the controller class). Cost is `MIN_COST` so it's cheap, but
   moving it to a memoized class method
   (`def self.dummy_bcrypt_hash; @dummy_bcrypt_hash ||= …; end`) would only pay
   the cost on first failed-login, which is the real timing path anyway.
   Optional polish.
2. **`Settings::OauthApplicationsController#create` still uses
   `:unprocessable_entity`**
   (`app/controllers/settings/oauth_applications_controller.rb:44,61`). The
   Phase 5+5.5 review flagged the same drift in `Settings::TokensController` and
   recommended converging on `:unprocessable_content`. Same drift here; bundle
   the fix into the same pass.
3. **`Settings::SessionsController#index` re-applies
   `where(user_id: Current.user.id)` on top of
   `Current.user.sessions.unscoped`**
   (`app/controllers/settings/sessions_controller.rb:11`). The `unscoped` call
   drops `BelongsToTenant`'s default scope (intentional — needed to include
   revoked rows that may sit outside the tenant default scope) but then the
   explicit `where(user_id: …)` is exactly what `Current.user.sessions` already
   implies. Net behavior is correct (and defensive); reads as overly
   belt-and-suspenders. Optional simplify.
4. **`Auth::GoogleCallbacksController#parse_granted_scopes` walks both
   `extra.raw_info.scope` and `credentials.scope`** with a manual nil-walk
   (`app/controllers/auth/google_callbacks_controller.rb:113-121`). OmniAuth's
   `auth_hash.credentials.scope` is the canonical surface; the fallback walks
   exist because OmniAuth versions vary. The code is correct but the fallback
   chain is hard to follow at a glance. Worth a comment pinning which
   `omniauth-google-oauth2` minor versions surface which key. Cosmetic.
5. **`OauthApplication`'s `tenant_id` validation is duplicated**: the migration
   declares `null: false` on the column AND the model carries
   `validates :tenant_id, presence: true`
   (`app/models/oauth_application.rb:19`). Either is sufficient; both is
   harmless but reads as redundant. Cosmetic.

### Informational

1. **Dashboard HTML view does not show all five counts.** The HTML branch
   (`app/views/dashboard/index.html.erb:7-10`) only shows
   `<videos> videos across <channels> channels` plus the "[ dashboard reset —
   charts return with intentional metrics in a later phase. ]" placeholder
   sentence. The five-count payload is JSON-only. The dispatch's wording
   "dashboard shows the placeholder line with five counts" appears to refer to
   the JSON contract that the CLI consumes (`/dashboard.json`), not the HTML
   view; this matches the JSON-only contract the
   `extras/cli/src/ui/dashboard.rs` test asserts
   ("dashboard_renders_all_five_counts" walks the rendered TUI buffer for all
   five labels). Calling out so the user is not surprised when `/dashboard` in
   the browser shows two counts, not five.

   **Resolution:** intentional and accepted. The dashboard HTML view is in a
   post-chart-sweep transitional state — the placeholder line plus the two-count
   summary stand in until intentional metrics are designed in a later phase. The
   JSON branch (`/dashboard.json` and the MCP `get_dashboard` tool) must satisfy
   the CLI's five-count `DashboardData` contract because the `pito` TUI's
   dashboard panel is the only consumer that needs the broader shape today. The
   two surfaces serve different consumers and the asymmetry is by design; no
   code change required.

2. **`Mcp::RackApp#call` still resets `Current` in `ensure`.** The Phase 5+5.5
   review flagged this as redundant given Rails `CurrentAttributes` reset
   per-request. Phase 6/7 did not touch this; carrying the note forward.
3. **`config/initializers/doorkeeper.rb:8` requires `app/lib/scopes.rb`
   explicitly.** The comment in the initializer explains why (initializer load
   order vs. Zeitwerk autoload). This is the right shape for a first-class
   initializer; flagging only so the user knows the explicit require is
   intentional, not a leftover.
4. **`config/initializers/console_tenant.rb` mutates `Current.tenant` /
   `Current.user` at console boot** but does NOT call `Current.reset` on exit.
   Console sessions are short-lived and the `Current` attributes are fiber-local
   — when the console process exits, the state goes with it. No leak. Worth
   knowing if the user ever wires `Rails.application.console` into a persistent
   process; that's not the current shape.
5. **Brakeman delta vs. f4b8c68 baseline**: the Phase 5+5.5 playbook reported "1
   ForceSSL + 5 weak UnscopedFind" (6 total). Phase 6/7+A2 collapses to "1
   ForceSSL + 1 weak VerbConfusion (newly introduced by Phase 6A's
   `auth_concern.rb`) + 1 weak UnscopedFind" (3 total). Net improvement of 3
   warnings. The new VerbConfusion is the only net-new warning; it's intentional
   per the inline justification in `auth_concern.rb:73-75`.

## Phase 6 manual test plan

> Setup preamble — run BEFORE the User Validation walkthrough.

1. **Verify the Rails credentials block carries everything Phase 6 needs.** Run:

   ```bash
   bin/rails runner '
     ok_pep   = Rails.application.credentials.dig(:tokens, :pepper).present?
     ok_owner = Rails.application.credentials.dig(:owner).present?
     ok_goog  = Rails.application.credentials.dig(:google_oauth, :client_id).present?
     puts({tokens_pepper: ok_pep, owner: ok_owner, google_oauth: ok_goog}.inspect)
   '
   ```

   Expected: all three keys `true`. If any are `false`,
   `bin/rails credentials:edit` and add the missing block.

2. **Reset and reseed the database.** Run: `bin/rails db:reset`. Expected: the
   seed output enumerates `Tenant`, `User`, `ApiToken` (dev token plain- text
   shown once — copy it), and the project workspace sample. Capture the
   seed-time login email and password from the `:owner` credentials block —
   `bin/rails credentials:show | grep -A 4 owner` will print them. The playbook
   below assumes you can sign in with that email + password.

3. **Start the app + MCP HTTP server.** Run `bin/dev` in one terminal and
   `bin/mcp-web` in a second. Expected: web Puma binds `:3000`, MCP Puma binds
   `:3001`, no stack traces.

4. **Sanity: tail the audit log.** In a third terminal:
   `tail -f log/auth_audit.log`. You should see fresh JSON lines for every login
   / logout / OAuth event you trigger below.

### Phase 6A — sessions + login UI

5. **Browser: sign-in happy path.** Open `http://localhost:3000` → expect the
   app to redirect to `/login`. Submit the seeded email + password with the
   `remember me` checkbox unticked. Expected: redirect to `/` (dashboard). The
   audit log gets one `{"event":"session.login.success", …}` line.

6. **Browser: dashboard renders the placeholder line.** On `/`, expect the
   header `dashboard`, the line `<N> videos across <M> channels.`, and
   immediately below
   `[ dashboard reset — charts return with intentional metrics in a later phase. ]`.
   NO chart canvases, NO chart toolbar. (See the chart sweep validation below.)

7. **Browser: `[ logout ]` button is present and works.** Top-right of the
   header chrome shows `[ logout ]`. Click it. Expected: redirect to `/login`
   with flash `signed out.`. Audit log: one `{"event":"session.logout"}` line.

8. **Browser: bad password path.** From `/login`, submit the seeded email with a
   wrong password. Expected: `/login` re-renders with the generic alert "invalid
   email or password.", status 422, NO information about whether the email
   exists. Repeat 9 times in fast succession. The 10th attempt should still
   render the same generic alert; the 11th should hit the rack-attack `/login`
   blocklist and render the plain-text 429 body. Wait 5 minutes (or
   `bin/rails runner 'Rack::Attack.cache.store.clear'`) to clear the bucket.
   Audit log: 10 `{"event":"session.login.failed", …}` lines plus 1
   `{"event":"session.login.throttled", …}` line.

9. **Browser: `/settings/sessions` lists active rows.** Sign in fresh, then
   visit `/settings/sessions`. Expected: a table with one row, your user-agent,
   IP, last activity, `remember = no`, status `active`, `(this session)`
   annotation in the user-agent column, `[ revoke ]` action.

10. **Browser: revoking the current session.** Click `[ revoke ]` on the
    `(this session)` row. Expected: action confirmation page with a red
    `[ revoke ]` submit button, NOT a JS confirm. Submit. Expected: redirect to
    `/login` with flash "current session revoked. please sign in again.". Audit
    log: `{"event":"session.revoked", …}`.

11. **Browser: revoking a non-current session.** Sign in, then in a
    private/incognito window sign in again with the same credentials. Two rows
    appear at `/settings/sessions`. Revoke the OTHER row (not `(this session)`).
    Expected: redirect to `/settings/sessions` with flash `session revoked.`,
    the revoked row stays in the table at opacity 0.6 with status
    `revoked YYYY-MM-DD`. The current session is untouched.

### Phase 6B — Doorkeeper OAuth server

12. **Register an OAuth application.** Visit `/settings/oauth_applications` →
    `[ new application ]`. Fill in `name = playbook-cli`,
    `redirect_uri = http://localhost:8000/callback`, untick `confidential`, and
    tick at least `dev:read`. Submit. Expected: the create page renders with the
    `client_id` and `client_secret` shown once, monospace, selectable. Copy both
    values to a scratch file — save them as `CLIENT_ID` and `CLIENT_SECRET`.

13. **Authorize an access token via PKCE.** From a separate terminal, generate a
    PKCE pair:

    ```bash
    CODE_VERIFIER=$(openssl rand -base64 64 | tr -d '=+/' | tr -d '\n' | head -c 64)
    CODE_CHALLENGE=$(printf '%s' "$CODE_VERIFIER" | openssl dgst -sha256 -binary | openssl base64 -A | tr -d '=' | tr '+/' '-_')
    echo "verifier:  $CODE_VERIFIER"
    echo "challenge: $CODE_CHALLENGE"
    ```

    Open in the browser:

    ```
    http://localhost:3000/oauth/authorize?client_id=<CLIENT_ID>&response_type=code&redirect_uri=http://localhost:8000/callback&scope=dev:read&code_challenge=<CODE_CHALLENGE>&code_challenge_method=S256&state=playbook
    ```

    Expected: the consent screen renders, listing `dev:read` with its
    description. Click `[authorize]`. The browser bounces to
    `http://localhost:8000/callback?code=<CODE>&state=playbook` (which will fail
    to load — that's fine; copy the `code` param value as `AUTH_CODE`).

14. **Exchange the code for an access token.** From the terminal:

    ```bash
    curl -s -i -X POST http://localhost:3000/oauth/token \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "grant_type=authorization_code" \
      -d "code=<AUTH_CODE>" \
      -d "client_id=<CLIENT_ID>" \
      -d "client_secret=<CLIENT_SECRET>" \
      -d "redirect_uri=http://localhost:8000/callback" \
      -d "code_verifier=<CODE_VERIFIER>"
    ```

    Expected: HTTP 200 with a JSON body containing `access_token`,
    `refresh_token`, `expires_in: 7200`, `scope: "dev:read"`. Save the
    `access_token` as `OAUTH_AT` and the `refresh_token` as `OAUTH_RT`. Audit
    log: one `{"event":"oauth.token.created", …}` line.

15. **Refresh the access token.** Run:

    ```bash
    curl -s -i -X POST http://localhost:3000/oauth/token \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "grant_type=refresh_token" \
      -d "refresh_token=<OAUTH_RT>" \
      -d "client_id=<CLIENT_ID>" \
      -d "client_secret=<CLIENT_SECRET>"
    ```

    Expected: HTTP 200 with a NEW `access_token` AND a NEW `refresh_token`
    (refresh-token rotation enabled). The previous `OAUTH_RT` is now invalid —
    re-running the same curl with the OLD refresh token returns 401
    `invalid_grant`. Audit log: one `{"event":"oauth.token.refreshed", …}` line.

16. **Revoke the OAuth application.** Visit `/settings/oauth_applications`,
    click the row for `playbook-cli` to see its detail, then `[ revoke ]`.
    Action confirmation page renders. Submit. Expected: redirect to
    `/settings/oauth_applications` with flash "application revoked and all its
    tokens were revoked.". Re-using the now-issued access token against
    `/oauth/token` (or any future Doorkeeper-protected surface) should 401.
    Audit log: `{"event":"oauth.application.destroyed", …}` plus revoke entries
    for each previously-issued token.

17. **Rate-limit `/oauth/token`.** Fire 32 bad refresh requests:

    ```bash
    for i in $(seq 1 32); do
      curl -s -o /dev/null -w "%{http_code}\n" -X POST http://localhost:3000/oauth/token \
        -d "grant_type=refresh_token&refresh_token=junk-$i&client_id=junk&client_secret=junk"
    done
    ```

    Expected: the first ~30 return 401. After the 30th the rack-attack bucket
    flips and subsequent requests return 429 with body
    `{"error":"rate_limited","retry_after":300}`. Clear with
    `bin/rails runner 'Rack::Attack.cache.store.clear'`.

## Phase 7 manual test plan

This section uses your real Google account. The Cloud Console redirect URI must
already be set to `https://app.pitomd.com/auth/google/callback` AND
`http://localhost:3000/auth/google/callback` (Cloud Console's "Authorized
redirect URIs" list accepts multiple entries). If only the `app.pitomd.com` URI
is registered, run the localhost path through your Cloudflare tunnel (the URL
bar reads `https://app.pitomd.com` while the Rails server runs locally). The
`:google_oauth.client_id`, `client_secret`, `project_id`, and (optionally)
`redirect_uri` credentials are populated.

18. **Browser: sign in to Pito.** From a clean session, sign in via the standard
    email/password login. Expected: dashboard loads. (Phase 7 does NOT add a
    "sign in with google" button; that's deferred to a later phase.)

19. **Browser: connect a Google account from `/settings/youtube`.** Visit
    `/settings/youtube`. Expected: the empty-state pane "no google account
    connected." plus the `[ connect google account ]` button and the
    read-only-scopes paragraph. Click `[ connect google account ]`. Expected: a
    server-side redirect kicks you out to Google's `accounts.google.com` consent
    screen with the scopes `youtube.readonly` + `yt-analytics.readonly`.
    Approve. Google redirects you back to `/auth/google/callback?...`, which
    redirects to `/settings/youtube` with flash `google account connected.`. The
    page now shows the connected-state pane: `connected as: <your-gmail>`,
    `last authorized: <timestamp>`, `scopes: …`, and the `[ reconnect ]` button.

20. **Browser: see your YouTube channels.** On the same `/settings/youtube`
    page, scroll to "your youtube channels". Expected: a table with one row per
    channel under your Google account. Columns: `channel id`, `title`,
    `subscribers`, `state`. The `state` column shows `[ connect ]` for each row.

21. **Browser: connect a single channel into Pito.** Click `[ connect ]` on any
    channel row. Expected: redirect to `/settings/youtube` with flash
    `connected.`. The same row's `state` column now shows `connected` followed
    by `[ disconnect ]`. Behind the scenes, a `Channel` row was created (or
    updated, if the URL existed) with `oauth_identity_id` pinned to your
    `GoogleIdentity`.

22. **Browser: verify the channel appears in `/channels` with URL placeholder.**
    Visit `/channels`. Expected: the index table shows the newly-connected
    channel. The `name` column shows the row's `id` (a placeholder until
    channel-title sync lands; this is part of Path A2's intentional retract).
    The URL column is middle-truncated. The `last sync` column shows a recent
    timestamp. The `[ + ]` add-channel button in the header is still present
    (channel manual-add is NOT retired).

23. **Browser: disconnect (idempotent).** Back on `/settings/youtube`, click
    `[ disconnect ]` on a connected channel row. Expected: action confirmation
    page (NOT a JS confirm) titled "disconnect 1 youtube channel?", listing the
    channel URL, `[ confirm disconnect ]` red button + cancel link. Submit.
    Expected: redirect to `/settings/youtube` with flash
    `disconnected 1 channel.`. The `Channel` row's `oauth_identity_id` is now
    NULL but the row itself survives. If this was the LAST channel using that
    `GoogleIdentity`, the identity row is destroyed AND `Google::RevokeToken`
    POSTs to `https://oauth2.googleapis.com/revoke` to revoke the grant
    server-side. Verify by visiting `https://myaccount.google.com/permissions` —
    `pito` should no longer appear under "third-party apps with account access".

24. **Browser: idempotent disconnect when grant was already revoked.**
    Re-connect the same channel (step 19 + 21 again). Then go to
    `https://myaccount.google.com/permissions` and revoke pito's access there
    manually. Now click `[ disconnect ]` in pito's `/settings/youtube`.
    Expected: same green-path UX (confirm screen + success flash); the
    `Google::RevokeToken` call sees a `400 invalid_token` from Google and audits
    it as `client_error: token already invalid` rather than failing the
    user-facing flow. Verify by grepping `log/auth_audit.log` (or
    `bin/rails runner 'puts YoutubeApiCall.last.attributes'`) for the
    `oauth2.revoke` audit row with `outcome: "client_error"`,
    `error_message: "token already invalid: …"`.

25. **Browser: needs_reauth banner appears after revoke-then-reload.**
    Re-connect again. From `/settings/youtube` (in pito) revoke the grant at
    `myaccount.google.com` while leaving the `GoogleIdentity` row in place.
    Force the `needs_reauth: true` flag manually (since pito only learns about
    revocation when it makes a YouTube API call — triggering one is the natural
    way):

    ```bash
    bin/rails runner '
      id = GoogleIdentity.last
      Youtube::Client.new(id).channels_list(mine: true)
    rescue Youtube::NeedsReauthError => e
      puts "got: #{e.message}"
    '
    ```

    Visit `/settings/youtube`. Expected: a red-bordered banner reading "your
    google grant was revoked. pito can no longer fetch youtube data for this
    account." with a `[ reconnect google account ]` button. The banner uses
    `border: 1px solid #cc0000` — this is the documented carve-out for
    failure-state UI per the design.md exemption.

## Path A2 retract validation plan

26. **`/channels` shows URL placeholders, not titles.** Visit `/channels` after
    seeding. Expected: the `name` column displays each channel's integer `id`
    (linked to the show page) — NOT a YouTube channel title. The URL column
    shows the middle-truncated channel URL. The `[ + ]` add-channel button is
    still in the header.

27. **`/channels/:id` show pane omits inline `[ connect ]` / `[ disconnect ]`.**
    Visit `/channels/<seeded id>`. Expected: the pane shows URL + star/unstar
    toggle + `connected: yes/no` (with google email if connected) + last sync.
    NO inline `[connect]` or `[disconnect]` button on the pane — that flow lives
    at `/settings/youtube` only.

28. **`/videos` index has no `[ + ]` add button and no `[ e ]` edit column.**
    Visit `/videos`. Expected: header reads `videos` with saved-views chip — NO
    `[ + ]` link. The columns are
    `name | youtube id | channel | views | likes | chats | watch | star | last sync`.
    No `[ e ]` (edit) action column. The picker check-boxes work for bulk
    delete.

29. **`/videos/:id/edit` and `/videos/new` 404.** Run:

    ```bash
    curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/videos/new
    curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3000/videos/$(bin/rails runner 'puts Video.first.id')/edit"
    ```

    Both expected: 404 (route not defined per the comment in
    `config/routes.rb:47-50`).

30. **Search is intact but returns no results.** Visit `/search?q=any`.
    Expected: the search page renders with the search box and the "0 results"
    message — Video's `searchable :*` and `filterable :*` declarations were
    dropped (Path A2). The Searchable concern hooks still fire (re-indexing is a
    no-op since `searchable_fields` is empty), the Meilisearch service is still
    up, but no records are indexed.

31. **MCP `get_dashboard` returns five integer counts.** With `bin/mcp-web`
    running and a `dev:read`-scoped token in `$DEV_TOKEN`:

    ```bash
    curl -s -X POST http://localhost:3001/mcp \
      -H "Authorization: Bearer $DEV_TOKEN" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json, text/event-stream" \
      -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_dashboard","arguments":{}}}'
    ```

    Expected: a JSON envelope; the `text` field contains a JSON object with
    exactly these five keys: `video_count`, `channel_count`, `project_count`,
    `footage_count`, `note_count`. No daily-views, views-by-channel, or
    daily-engagement payloads.

32. **MCP `list_videos` retracted output.** Same curl shape, swap the arguments
    to `{"name":"list_videos","arguments":{"limit":3}}`. Expected: each item has
    `id`, `youtube_video_id`, `channel_id`, `channel_url`, `star` (yes/no
    string), `views`, `likes`, `comments`, `watch_time_minutes`,
    `last_synced_at`, `trend: null`. NO `title`, `description`,
    `privacy_status`, `tags`, `category`, `language`.

33. **MCP `list_channels` retracted output.** Swap to
    `{"name":"list_channels","arguments":{"limit":3}}`. Expected: each item has
    `id`, `tenant_id`, `channel_url`, `star` (yes/no), `connected` (yes/no),
    `last_synced_at`, `created_at`, `updated_at`. NO `syncing` field. The
    `connected: "yes"|"no"` string is derived from `oauth_identity_id.present?`.

34. **MCP `update_channel` rejects anything but `id` + `star`.** Try setting
    `connected`:

    ```bash
    curl -s -X POST http://localhost:3001/mcp \
      -H "Authorization: Bearer $DEV_TOKEN" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json, text/event-stream" \
      -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"update_channel","arguments":{"id":1,"connected":"yes"}}}'
    ```

    Expected: error response (the input schema declares
    `additionalProperties: false`, so `connected` is rejected before reaching
    the controller).

35. **MCP `sync_records` no longer partitions for "already syncing".** Run
    `{"name":"sync_records","arguments":{"type":"channel","ids":[1,2,3], "confirm":"no"}}`.
    Expected: the response body lists all three under `syncable` (or
    `not_found_ids` if a row is missing) — there is no `skipped` partition for
    "already syncing". The Path A2 retract dropped the `syncing` boolean.

36. **MCP `create_video` is gone.** Run
    `{"name":"create_video","arguments":{}}`. Expected: an error response
    `unknown tool: create_video`.

## Console tenant hook validation

37. **Console boot prints the confirmation line.** Run:

    ```bash
    bin/rails console
    ```

    Expected: somewhere during boot, the line:

    ```
    [pito] Current.tenant=<id> Current.user=<id>
    ```

    (where `<id>` is a non-nil integer). `Channel.new`, `Channel.first`,
    `Video.new`, `Video.first` should all succeed without raising
    `BelongsToTenant::TenantContextMissing`. Try:

    ```ruby
    Channel.first
    Video.first
    Note.count
    Project.count
    exit
    ```

    All four should return values without an error. Without the console hook
    (rename the initializer file to disable it), the same calls raise
    `BelongsToTenant::TenantContextMissing` — that's the regression the hook
    prevents.

38. **Hook does NOT fire in tests.** From a separate terminal:

    ```bash
    grep -c '\[pito\] Current\.tenant=' log/test.log || echo "0 hits"
    ```

    Expected: `0 hits`. The `Rails.application.console do … end` block only runs
    on `bin/rails console`, never under RSpec or Sidekiq.

## Chart sweep validation

39. **`/dashboard` HTML shows the placeholder, no charts.** Visit
    `http://localhost:3000/dashboard`. Expected: heading `dashboard`, the line
    `<N> videos across <M> channels.`, and the placeholder line
    `[ dashboard reset — charts return with intentional metrics in a later phase. ]`.
    NO chart canvases (no `<canvas>` elements), NO chart toolbar, NO range
    keybindings hint. View source with
    `view-source:http://localhost:3000/dashboard` and confirm there are zero
    `<canvas>` tags and no references to `chart_toolbar_component` or
    `chart_sync_controller`.

40. **`/dashboard.json` returns five integer counts.** Run:

    ```bash
    curl -s http://localhost:3000/dashboard.json | python3 -m json.tool
    ```

    Expected:

    ```json
    {
      "video_count": <int>,
      "channel_count": <int>,
      "project_count": <int>,
      "footage_count": <int>,
      "note_count": <int>
    }
    ```

    Exactly five keys. Any other key (especially `daily_views`,
    `views_by_channel`, `daily_engagement`) → STOP.

41. **`ChartToolbarComponent` and `chart_sync_controller.js` are gone.** From
    the repo root:

    ```bash
    rg -l 'ChartToolbarComponent|chart_toolbar_component|chart_sync_controller' app/ 2>/dev/null
    ```

    Expected: no output. (The plumbing helpers `chart_palette` and `htmlLegend`
    survive — those are unrelated to the toolbar / sync pieces.)

## Cross-stack dashboard alignment validation

42. **Build the CLI binary fresh.**

    ```bash
    cd extras/cli
    cargo build --release
    ```

    Expected: clean build, exit 0.

43. **Run the CLI against the live local server.** With `bin/dev` up on `:3000`:

    ```bash
    cd extras/cli
    PITO_HOST=http://localhost:3000 PITO_API_TOKEN=$DEV_TOKEN ./target/release/pito
    ```

    The TUI launches. Press `?` for the help dialog if needed.

44. **Dashboard pane shows the five-row block.** The default landing pane is the
    dashboard. Expected: a bordered box titled `dashboard` with five rows, two
    columns each:

    ```
      videos     <int>
      channels   <int>
      projects   <int>
      footage    <int>
      notes      <int>
    ```

    Counts must equal the JSON values from step 40 exactly. Any mismatch → STOP
    and check whether `bin/dev` and the CLI are pointing at the same database.

45. **Range keybindings are gone.** Press the keys that used to switch chart
    range (`1`, `7`, `30`, `90` per the prior shape). Expected: no keybinding
    response. Press `?` to confirm the help dialog does NOT list any range keys
    — only the surviving navigation + theme + footage keys.

46. **Channels and Videos panels — KNOWN ISSUE per Blocker #1.** Press the
    navigation key for channels (or videos). Expected once the Blocker is fixed:
    a populated panel listing seed channels (or videos). **Until the blocker is
    fixed,** expect either an empty panel with an error in the CLI's status line
    ("startup get_channels: …") or a deserialization error. Confirm the failure
    mode matches the Blocker's stated symptom; do NOT sign off on cross-stack
    alignment until Blocker #1 lands.

## Cleanup

If you want a clean slate to retry from scratch:

```bash
# Stop bin/dev and bin/mcp-web (Ctrl-C in each terminal).

# Drop, recreate, reseed.
bin/rails db:reset

# Clear rack-attack throttle buckets between runs.
bin/rails runner 'Rack::Attack.cache.store.clear'

# Restart.
bin/dev    # one terminal
bin/mcp-web # second terminal

# Roll back the working tree if you tried something destructive (DON'T run
# without confirming there are no other uncommitted changes you want to keep).
git status
git diff
# Only if you're sure:
# git restore .

# Revoke any stale Google grants you no longer want connected.
# Visit https://myaccount.google.com/permissions and remove pito.
```

## User Validation

[ ] 1. **Login form renders.** Visit `/` → expect a redirect to `/login` with a
heading `log in`, a muted paragraph about credentials, an email field, a
password field, a `remember me on this device (30 days)` checkbox, and a
`[log in]` button. The browser tab title reads `log in ~ pito`.

[ ] 2. **Successful sign-in.** Submit your seeded credentials → expect to land
on `/` (dashboard). The header bar's right side now shows `[ logout ]` followed
by the theme toggle key. No JS errors in the browser console.

[ ] 3. **Dashboard placeholder.** On `/`, expect the heading `dashboard` plus
the line `<N> videos across <M> channels.` plus the placeholder sentence
`[ dashboard reset — charts return with intentional metrics in a later phase. ]`.
NO chart canvases anywhere on the page.

[ ] 4. **Logout.** Click `[ logout ]` → expect to land on `/login` with a green
flash `signed out.`.

[ ] 5. **Bad password generic alert.** From `/login`, submit any seeded email
with a wrong password → expect the page to re-render with the generic flash
`invalid email or password.`. The flash MUST NOT reveal whether the email
exists.

[ ] 6. **Active sessions index.** Sign in fresh, visit `/settings/sessions` →
expect a single-row table with your user-agent, IP, last-activity, the
`(this session)` annotation, status `active`, and a `[ revoke ]` link. Above the
table: heading `sessions` and a muted paragraph about revocation.

[ ] 7. **Revoke confirmation page.** Click `[ revoke ]` on the `(this session)`
row → expect a full-page confirmation screen (NOT a JS modal). The page shows
the session metadata + a red `[ revoke ]` button

- a `[ cancel ]` link.

[ ] 8. **Revoke current session bounces to /login.** Submit `[ revoke ]` on the
confirmation page → expect to land on `/login` with the alert "current session
revoked. please sign in again." The `pito_session` cookie is gone.

[ ] 9. **OAuth applications index.** Sign in, visit
`/settings/oauth_applications` → expect heading `oauth applications`, a muted
explanatory paragraph about authorization code + PKCE, and a
`[ new application ]` link. If the table is empty, the muted line "no
applications yet." renders.

[ ] 10. **OAuth application create-once secrets.** Click `[ new application ]`,
fill in name `validation-app`, redirect_uri `http://localhost:8000/callback`,
untick `confidential`, tick at least one scope, submit → expect the next page to
show `client_id` and `client_secret` once, monospace and selectable, with a
warning that they cannot be shown again.

[ ] 11. **OAuth consent screen.** Build the
`/oauth/authorize?…&code_challenge=…` URL from the CLIENT_ID minted in step 10
(use the curl recipe in step 13 of the Manual test plan above) → expect the
consent screen to render with the application name in the heading, a list of
requested scopes with descriptions, the redirect URI and client_id in a small
table, and `[authorize]` + `[ cancel ]` buttons. Authorize → expect the browser
to bounce to your registered redirect_uri with `?code=…&state=…` in the query.

[ ] 12. **OAuth application revoke confirmation.** From the index, click the
application row, then `[ revoke ]` → expect a full-page action confirmation page
(NOT a JS modal). Submit → flash "application revoked and all its tokens were
revoked." renders.

[ ] 13. **Settings → YouTube empty state.** Visit `/settings/youtube` with no
`GoogleIdentity` connected → expect a pane reading "no google account
connected." plus the `[ connect google account ]` button plus the muted
read-only-scopes paragraph.

[ ] 14. **Google OAuth happy path.** Click `[ connect google account ]` → expect
Google's consent screen (browser leaves localhost). Approve. Expected: bounce
back to `/settings/youtube` with green flash `google account connected.` and the
connected-state pane (your gmail address, `last authorized` timestamp, scopes
string, `[ reconnect ]` button).

[ ] 15. **YouTube channels list.** Same page, scroll down → expect a table
titled "your youtube channels" with one row per channel under the connected
Google account. Columns: channel id, title, subscribers, state. State column
shows `[ connect ]` on every row.

[ ] 16. **Connect a YouTube channel.** Click `[ connect ]` on any row → expect
the page to reload with flash `connected.`; that row's state column now reads
`connected` followed by `[ disconnect ]`.

[ ] 17. **Disconnect confirmation page.** Click `[ disconnect ]` → expect a
full-page action confirmation page (NOT a JS modal) titled "disconnect 1 youtube
channel?", listing the channel URL, with red `[ confirm disconnect ]` and
`[ cancel ]` buttons.

[ ] 18. **Disconnect commits.** Submit → flash `disconnected 1 channel.`
renders. The row's state column flips back to `[ connect ]`. The Google grant
entry at `myaccount.google.com/permissions` disappears (verify in a separate
browser tab).

[ ] 19. **needs_reauth banner.** Re-connect, then revoke pito's grant manually
at `myaccount.google.com/permissions`. Trigger a YouTube call from the Rails
console (see Manual test step 25) so pito learns about the revocation and flips
`needs_reauth: true`. Reload `/settings/youtube` → expect a red-bordered banner
reading "your google grant was revoked. pito can no longer fetch youtube data
for this account." with a `[ reconnect google account ]` button. The red border
is the documented design.md exemption for failure-state UI.

[ ] 20. **Channels index URL placeholder.** Visit `/channels` → expect the
`name` column to show numeric IDs linked to show pages, NOT YouTube channel
titles. The URL column is middle-truncated.

[ ] 21. **Channels show pane omits inline connect/disconnect.** Click into any
channel → expect the pane to show URL + star/unstar + `connected: yes/no` + last
sync — but NO inline `[ connect ]` or `[ disconnect ]` button.
Connect/disconnect lives at `/settings/youtube`.

[ ] 22. **Videos index has no add or edit affordances.** Visit `/videos` →
expect the heading `videos` with no `[ + ]` link, and the rows have no `[ e ]`
edit action. The columns are name, youtube id, channel, views, likes, chats,
watch, star, last sync.

[ ] 23. **Videos edit/new return 404.** In the URL bar, navigate to
`/videos/new` and to `/videos/<an existing id>/edit` → expect both to render the
plain-text "Not found" 404 page (or browser-default 404 chrome).

[ ] 24. **Search returns no results.** Visit `/search?q=test` → expect the
search input pre-filled with `test` and a "0 results" message. NO results table.

[ ] 25. **No JS confirm dialogs anywhere in the walkthrough.** During all of the
above, you NEVER see a browser-native `confirm()` / `alert()` modal. Destructive
flows (revoke session, revoke OAuth app, disconnect YouTube) all use full-page
confirmation screens.

[ ] 26. **Beforeunload guard untouched.** Open any footage edit page
(`/footages/:id/edit`), change a field, click a navigation link → expect the
browser-native "Leave site?" dialog (which is NOT `window.confirm` — the browser
renders it itself). Cancel → stay on the form. Save and try again → no dialog.
