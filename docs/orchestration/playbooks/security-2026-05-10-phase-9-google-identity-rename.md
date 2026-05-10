# Security review — Phase 9: Login-with-Google drop + GoogleIdentity → YoutubeConnection rename

**Branch:** `main` (commits `9ea8896` + `fc894fb`) **Spec:**
`docs/plans/beta/09-login-with-google-drop/specs/01-google-identity-rename.md`
**Reviewer playbook:**
`docs/orchestration/playbooks/2026-05-10-phase-9-google-identity-rename.md`
**ADR:** `docs/decisions/0006-drop-sign-in-with-google-channel-only-oauth.md`
**Audit run:** 2026-05-10

## Verdict

**CLEAR TO MERGE.** No Critical or High findings introduced by Phase 9. One
Medium pre-existing concern (cross-user token overwrite) and one Informational
note on playbook step 9. Phase 9's rename is mechanically clean; the sign-in
branch is fully removed; audit-log keys, session-intent rename, and stale-intent
flash copy all match the spec verbatim.

## Findings by severity

- Critical: 0
- High: 0
- Medium: 1 (pre-existing — F1)
- Low: 1 (pre-existing — F4)
- Informational: 4 (F2, F3, F5, F6, F7, F8)
- Phase-9-introduced findings: **0**

## F1. Cross-user token overwrite when two pito users share a Google account (MEDIUM, pre-existing)

- **Location:**
  `app/controllers/youtube_connections/oauth_callbacks_controller.rb:88-113`
  (`upsert_youtube_connection_for_current_user`); schema unique index
  `index_youtube_connections_on_google_subject_id` at `db/schema.rb:397`
- **Description:** The upsert keys solely on `google_subject_id`, ignoring
  `Current.user.id`. If pito user A connects Google account `12345`, then pito
  user B (a different `User`) runs the YouTube connect flow against the same
  Google account, the existing `YoutubeConnection` row owned by user A has its
  `access_token`, `refresh_token`, `expires_at`, `scopes`, and
  `last_authorized_at` overwritten with B's grant. The `user_id` is preserved
  (`connection.user ||= Current.user`), so the row's owner stays as A — but A's
  stored tokens are now B's. Subsequent API calls misattribute. Threat
  scenarios: family Google account; insider attack with second pito User row;
  compromise of A's session and intentional re-bind.
- **Impact:** Silent token swap; misattributed API calls; audit trail keyed
  against tokens A never granted.
- **Recommendation (preferred):** Change the unique index and upsert key to
  `(user_id, google_subject_id)`. Each (pito user, Google account) pair gets its
  own row.
- **Recommendation (fallback):** Keep install-wide unique on `google_subject_id`
  but the upsert MUST detect a `user_id` mismatch and abort: if
  `connection.user_id.present? && connection.user_id != Current.user.id`, raise
  / redirect to failure with a "this Google account is connected to a different
  pito user" alert.
- **References:** OWASP Cryptographic Storage; CWE-863 (Incorrect
  Authorization).
- **Pre-existing:** Yes — design landed in Phase 8 when the unique index dropped
  tenant scoping. Phase 9 only renamed; logic unchanged. Tracked as Phase 11+
  follow-up.

## F2. Manual-playbook step 9 expectation may diverge from production behavior (INFORMATIONAL)

- **Location:**
  `docs/orchestration/playbooks/2026-05-10-phase-9-google-identity-rename.md`
  step 9;
  `app/controllers/youtube_connections/oauth_callbacks_controller.rb:33-41` and
  `app/controllers/concerns/sessions/auth_concern.rb:47-68`
- **Description:** Step 9 says hitting `/auth/google/callback` directly with no
  session intent should land on `/auth/failure` with the stale-intent flash.
  But: `:create` is NOT `allow_anonymous`. An unauthenticated browser hitting
  the callback gets redirected to `/login` BEFORE reaching the stale-intent
  branch. Only authenticated users without the intent in session see the
  stale-intent flash; bare `curl` triggers `session.cookie.invalid` instead.
- **Impact:** None on security. Documentation alignment only.
- **Recommendation:** Tighten step 9 to specify "while logged in, hit the bare
  callback".

## F3. `params[:message]` echoed in `/auth/failure` plain-text body (INFORMATIONAL)

- **Location:**
  `app/controllers/youtube_connections/oauth_callbacks_controller.rb:75-80`
- **Description:** `failure` reads `params[:message]` (attacker-controllable)
  and renders via `render plain:`. `text/plain` content-type-locked, so no XSS.
  No length cap on the parameter — slight DoS surface if the attacker can
  convince a user to follow the URL.
- **Impact:** Not a security finding.
- **Recommendation (optional):** Clamp `@reason` to 200 chars:
  `params[:message].to_s.first(200).presence`.

## F4. `Google::RevokeToken` synchronous HTTP + audit INSERT inside `ActiveRecord::Base.transaction` (LOW, pre-existing)

- **Location:** `app/services/youtube/disconnect_channel.rb:29-52` invokes
  `Google::RevokeToken.call` inside the AR transaction at line 48;
  `Google::RevokeToken.write_audit_row` runs an INSERT on the same connection
  while the transaction is held open.
- **Description:** Network latency holds the DB transaction open. The
  `rescue StandardError` catches audit-row failure and only logs, but the
  network call to Google is still inside the transaction.
- **Impact:** Defense-in-depth concern. No data leakage. On single-user dev,
  negligible.
- **Recommendation:** Move `Google::RevokeToken.call` outside the transaction;
  two-phase pattern. Architect's call.
- **Pre-existing:** Phase 7C-era. Not introduced by Phase 9.

## F5. Migration audit — clean (INFORMATIONAL — positive finding)

- **Location:**
  `db/migrate/20260510081047_rename_google_identity_to_youtube_connection.rb`
- **Verification:** Reviewed `up`/`down` shape; index renames cover all five
  expected sites; `rename_index_if_exists` makes the migration idempotent.
  Active Record Encryption columns (`access_token`, `refresh_token`) survive the
  rename because metadata is keyed on attribute name. `db/schema.rb` shows the
  rename completed. Cascade chain: delete User → destroys YoutubeConnections →
  nullifies channels/videos/audit-rows. Clean.

## F6. Sign-in branch removal — clean (INFORMATIONAL — positive finding)

- **Verification:**
  - `git grep 'GoogleIdentity|google_identity_id|oauth_identity_id' app/ spec/ config/`
    — only Phase-9 historical-rename comments and the migration body. No live
    identifier survivors.
  - `git grep -i 'sign in with google'` — only the guarding spec at
    `spec/requests/sessions_spec.rb:43`.
  - `:google_oauth_intent` session key fully replaced by
    `:youtube_connection_oauth_intent`.
  - Audit-log keys
    (`youtube_connection.callback.{succeeded,failed,stale_intent}`) match spec
    verbatim.
  - Stale-intent flash copy match:
    `sign-in via google is not supported. log in with email and password.`
  - `/auth/google` dev-only redirect retired; `:google_oauth_start` helper
    removed.
  - `app/controllers/auth/google_callbacks_controller.rb` deleted;
    `app/controllers/concerns/google_oauth_redirect.rb` deleted.
  - Login form carries no Google button; spec guards against reintroduction.
  - Smuggled `google_id_token` / `google_access_token` parameters to
    `POST /login` are ignored.

## F7. Reviewer's flagged Concern #1 (OAuth scope gap) — security verdict (INFORMATIONAL)

- **Location:** `app/controllers/settings/youtube_controller.rb:31-35`
  (`#connect`); `config/initializers/omniauth.rb:55`
- **Description:** The `connect` action does not override the OmniAuth scope at
  the request phase. The grant carries only `openid email profile` — no YouTube
  scopes. Subsequent API calls 401.
- **Security analysis:** No token elevation path (Google validates scope at
  grant time). No credential leak. Posture is over-restrictive, not
  under-restrictive — the user authorizes less than the page advertises, not
  more.
- **Verdict:** Phase 11's job to expand. NOT a security regression.

## F8. Reviewer's flagged Concern #3 — same as F4 above

## Quality gate evidence

- **Brakeman (`bundle exec brakeman -q -A -w1`)**: 4 warnings, 2 ignored, 0
  errors. **None of the 4 warnings are introduced by Phase 9.**
- **Bundler-audit**: 1078 advisories scanned, no vulnerabilities found.
- **Reviewer playbook gates**: tests green (1673 examples, 0 failures), rubocop
  clean, brakeman -w2 clean.

## Out-of-scope but noted

- **OAuth scope gap (F7)** — Phase 11's lock means the user-facing "we'll
  request `youtube.readonly`" copy at
  `app/views/settings/youtube/show.html.erb:19-23` is currently dishonest.
  Either drop the copy until Phase 11 lands, or leave a TODO. Pure UX/copy
  concern.
- **No rate limit on `/auth/google/callback`** — endpoint is gated by Sessions
  auth + OmniAuth state validation. Adding Rack::Attack throttle would be
  defense-in-depth but not required.
- **F1's institutional fix** — if pito stays multi-user-on-single-install, the
  unique-by-`google_subject_id` constraint should evolve to
  `(user_id, google_subject_id)`. Worth a separate Phase 11+ spec.

## Blockers

None. **CLEAR TO MERGE.**
