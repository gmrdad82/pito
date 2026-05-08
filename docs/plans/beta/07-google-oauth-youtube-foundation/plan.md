# Phase 7 — Google OAuth + YouTube API Foundation

> **Goal:** Wire up Google OAuth so the user can connect their Google account,
> link YouTube channels, and have Pito hold encrypted access/refresh tokens.
> Build a rate-limit-aware YouTube API client that handles the 10,000-unit daily
> quota gracefully. **No actual data sync in this phase** — that's Phase 8. This
> phase establishes the foundation; Phase 8 industrializes it.

**Depends on:** Phase 3 (`User` and `Tenant` models exist; OAuth tokens link to
a User).

**Unblocks:** Phase 8 (data sync), Phase 11 (video workflow features touch real
videos), Phase 12 (login UI can include "Sign in with Google").

---

## Why Phase 7 is now

By Phase 7, the application has:

- Real auth (Phase 3): tokens, scopes, multi-tenant-ready schema
- A locked design language (Phase 4): the YouTube settings page slots into
  existing patterns
- A first-class JSON API on Web Puma (Phase 4): proven good enough for the
  terminal app and Slack
- Postgres with encrypted columns (Phase 2): OAuth tokens can be stored at rest
  with Active Record Encryption

This is the moment Pito stops being fake-data-driven and starts being real. The
phase is intentionally narrow: prove the user can connect their Google account,
that we can fetch a single channel's metadata, and that quota tracking works
end-to-end. The actual sync engine (which fetches lots of data continuously, on
schedule, with error recovery) is Phase 8.

The narrow scope is deliberate. Establishing the OAuth flow + the
rate-limit-aware client + the audit table is enough surface area for one phase.
Throwing sync jobs in here would inflate scope and obscure where bugs
originated.

---

## In scope

### Google Cloud project

- Create or reuse a Google Cloud project
- Enable the **YouTube Data API v3** and **YouTube Analytics API v2**
- Configure OAuth consent screen (test mode is fine for single-tenant Beta — the
  user's own Google account whitelisted)
- Create OAuth 2.0 web application client credentials
- Authorized redirect URIs:
  - `https://app.pitomd.com/auth/google/callback` — used for both production and
    dev, since the Cloudflare tunnel exposes the local Web Puma at the same
    domain
- Store `client_id` and `client_secret` in Rails credentials per environment

### `GoogleIdentity` model

This is the bridge between a Pito `User` (Phase 3) and a Google account. A user
can have multiple Google identities (Theta might surface this; Beta starts with
one).

- `id`
- `user_id` (FK to `User`)
- `tenant_id` (denormalized from User for default-scoping consistency)
- `google_subject_id` (unique; the stable Google user ID)
- `email`
- `access_token` (encrypted via Active Record Encryption)
- `refresh_token` (encrypted)
- `expires_at` (timestamp)
- `scopes` (jsonb array of granted Google OAuth scopes)
- `created_at`, `updated_at`
- `last_refreshed_at` (nullable; tracks when refresh was last performed)

### Google OAuth flow

Two distinct OAuth surfaces — keep them separated mentally and in routing:

**Sign-in flow (Phase 12 surfaces this in the login UI; Phase 7 wires the
plumbing):**

- `GET /auth/google` — redirects to Google with state parameter
- `GET /auth/google/callback` — handles code exchange, finds or creates
  `GoogleIdentity`, signs the user in (web session establishment is Phase 12;
  Phase 7 just persists the identity)
- Scopes requested at sign-in: `userinfo.email`, `userinfo.profile`
  (lightweight; no YouTube scopes yet)

**YouTube connection flow (Phase 7 surfaces this in Settings):**

- `GET /settings/youtube/connect` — kicks off Google OAuth with YouTube scopes
  appended
- Scopes requested: `youtube.readonly`, `youtube`, `yt-analytics.readonly` (plus
  userinfo if not already granted)
- On callback: fetch the user's YouTube channels
  (`channels.list?part=snippet,contentDetails,statistics&mine=true`)
- For each owned channel: upsert a `Channel` record with `connected: true`,
  `oauth_identity_id` linking to the `GoogleIdentity`
- Settings → YouTube shows the list of connected channels with disconnect option
- Disconnect: revoke the Google token via Google's revocation endpoint, clear
  `oauth_identity_id` and set `connected: false` on the Channel, but **keep the
  Channel record** (history preserved)

The flow uses the `omniauth-google-oauth2` gem (battle-tested, widely audited).
State parameter validation is built in. PKCE is optional for confidential web
app clients but fine to enable.

### Rate-limit-aware YouTube client

`YouTube::Client` service object. Every YouTube API call goes through it;
nothing in the app calls Google's gems directly.

- Wraps `google-apis-youtube_v3` and `google-apis-youtube_analytics_v2`
- Accepts a `GoogleIdentity` on instantiation; uses its access token
- Each call is recorded to a `YoutubeApiCall` audit table:
  - `endpoint`, `method`, `units` (estimated quota cost), `created_at`,
    `tenant_id`, `user_id`, `google_identity_id`, `outcome` (success / 401 /
    quota_exceeded / 5xx / etc.)
- **Quota cost map:** hardcoded per endpoint per YouTube's documented unit
  costs. Documented in `pito/docs/youtube_quota.md`. Conservative rounding
  (always round up).
- **Pre-call check:** estimate cost; verify
  `YoutubeApiCall.where(google_identity_id: id, created_at: today).sum(:units) + estimated_cost < 10000`;
  raise `YouTube::QuotaExhaustedError` if it would exceed
- **Token refresh:** if a call returns 401 and the access token is past
  `expires_at` (or close to it), refresh transparently before retrying once. If
  the refresh itself fails (e.g., refresh token revoked, password changed on
  Google's side), mark the identity as `needs_reauth: true` and surface in the
  UI.
- **Exponential backoff** on 5xx errors: max 3 retries, 1s / 2s / 4s
- **5xx after retries:** raise; don't silently fail

### `YoutubeApiCall` audit table

- `id`
- `tenant_id`, `user_id`, `google_identity_id`
- `endpoint` (string: `videos.list`, `channels.list`, etc.)
- `method` (string: `GET`, `POST`)
- `units` (integer: estimated quota cost)
- `outcome` (string: `success`, `quota_exceeded`, `auth_failed`, `server_error`,
  `rate_limited`)
- `error_message` (text, nullable)
- `created_at`

This table is the single source of truth for quota usage. Phase 8 reads it for
budget enforcement; Phase 13 reads it for observability dashboards.

### Public API key path (skeleton only)

Phase 8 fully implements public-data tracking for non-owned channels using the
YouTube public API key (separate quota pool from OAuth). Phase 7 just sketches
the skeleton:

- Add `YOUTUBE_PUBLIC_API_KEY` to Rails credentials (placeholder)
- Sketch `YouTube::PublicClient` service object — same shape as
  `YouTube::Client` but uses API key auth
- Quota tracking via the same `YoutubeApiCall` table with
  `google_identity_id: nil` (a sentinel value; Phase 8 may add a separate column
  or distinguishing value)

### Settings UI for YouTube

- Settings → YouTube sub-page (new in this phase)
- "Connect Google account" button → triggers the YouTube connection flow
- After connection: list of YouTube channels under the account with `[Connect]`
  buttons per channel
- After connecting a channel: it appears in Pito's `/channels` index with
  `connected: true` indicator
- Disconnect option per channel (revokes Google token for that identity if no
  other channels reference it)
- "Needs reauth" indicator for identities with revoked refresh tokens

### Out of scope

- Continuous sync of channel/video/analytics data (Phase 8)
- Video upload (Phase 11)
- Video metadata management (Phase 11)
- Analytics deep dives (Phase 8 + Phase 11)
- Multi-account-per-user UI for managing multiple Google identities (Phase 12)
- Public API key full implementation for tracking external channels — only the
  skeleton lands here (Phase 8 finishes it)
- Web sign-in via Google as an alternative to password (Phase 12 surfaces this;
  the model supports it from Phase 7)

---

## Plan checklist

### Google Cloud setup

- [x] Create or identify Google Cloud project
- [x] Enable YouTube Data API v3 and YouTube Analytics API v2
- [x] Create OAuth 2.0 web application client credentials
- [x] Configure OAuth consent screen with scopes `youtube.readonly`, `youtube`,
      `yt-analytics.readonly`, `userinfo.email`, `userinfo.profile`
- [x] Add the user's Google account as a test user (consent screen in test mode)
- [x] Authorized redirect URIs configured for production-ish (`app.pitomd.com`)
      and dev
- [x] Store `client_id` and `client_secret` in Rails credentials per environment

### Models and migrations

- [x] Migration: create `google_identities` table with encrypted token fields
      (Active Record Encryption)
- [x] `GoogleIdentity` model: associations, validations, expiry helper
      (`access_token_expired?`, `needs_reauth?`)
- [x] Migration: add `oauth_identity_id`, `connected` to `channels` table;
      nullable; existing seeded channels stay disconnected (note: `connected`
      column already existed from Phase 4 placeholder; this dispatch added
      `oauth_identity_id` only)
- [x] Update `Channel` model:
      `belongs_to :oauth_identity, class_name: 'GoogleIdentity', optional: true`
- [x] Migration: create `youtube_api_calls` audit table with the columns listed
      above
- [x] `YoutubeApiCall` model with default scoping by tenant

### OAuth integration

- [x] Add `omniauth-google-oauth2` gem
- [x] Configure OmniAuth in an initializer with the credentials
- [x] Routes: `/auth/google`, `/auth/google/callback`,
      `/settings/youtube/connect` (this last one chains through to OmniAuth with
      extended scopes)
- [x] Callback controller: extracts code, fetches user info, finds or creates
      `GoogleIdentity`, stores tokens encrypted
- [x] Specs: callback creates new identity, callback updates existing identity,
      callback handles errors (denied consent, expired code, missing state)

### YouTube connection flow

- [x] Settings → YouTube sub-page route and view
- [x] "Connect Google account" button kicks off OmniAuth with YouTube scopes
- [x] On callback (with YouTube scopes granted), fetch `channels.list?mine=true`
      and present the user's owned YouTube channels
- [x] User clicks `[Connect]` on a channel → upsert `Channel` record with
      `connected: true`, `oauth_identity_id` set, basic metadata populated
- [x] Show list of connected channels in Settings → YouTube with disconnect
      option
- [x] Disconnect: call Google's `oauth2/revoke` endpoint for the identity if no
      other channels reference it; clear `oauth_identity_id` and `connected` on
      the Channel
- [x] Specs: first-time connect, reconnect (existing channel becomes connected),
      disconnect (with and without other channels referencing the identity)

### YouTube::Client

- [x] Implement `YouTube::Client` service object — accepts `GoogleIdentity`;
      exposes methods `channels_list`, `videos_list`, `playlists_list`,
      `analytics_query` (and any others as needed)
- [x] Quota cost map as a frozen Ruby constant; documented in
      `pito/docs/youtube_quota.md` (constant frozen; doc deferred to
      docs-keeper)
- [x] Pre-call quota check: estimate cost, query today's usage, raise
      `YouTube::QuotaExhaustedError` if exceeding
- [x] Post-call audit: record `YoutubeApiCall` row with actual outcome and units
- [x] Token refresh wrapper: detect expiry, refresh before call; on 401
      mid-call, refresh and retry once; on second 401, mark identity
      `needs_reauth`
- [x] Exponential backoff on 5xx (max 3 retries, 1s/2s/4s)
- [ ] Specs with VCR cassettes (recorded against the user's real channel once,
      anonymized): happy path, quota check enforcement, token refresh, backoff,
      `needs_reauth` flow (deferred — decision 7.16: WebMock stubs against
      canned response shapes land in this dispatch; VCR cassettes recorded
      against the user's real account replace them in a follow-up
      post-Phase-7-implementation session)
- [ ] All cassettes scrubbed of bearer tokens, refresh tokens, API keys, PII
      before commit (deferred — gates on the cassette-recording session above)

### Public API key skeleton

- [x] Add `YOUTUBE_PUBLIC_API_KEY` to Rails credentials (can be empty
      placeholder until Phase 8 fills it) (skeleton reads
      `Rails.application.credentials.dig(:youtube, :public_api_key)`; no
      placeholder seeded — Phase 8 fills it)
- [x] Sketch `YouTube::PublicClient` service object — same shape as
      `YouTube::Client`; uses `api_key` auth
- [x] Quota tracking via `YoutubeApiCall` with a sentinel
      `google_identity_id: nil` (Phase 8 may refine)

### Documentation

- [ ] `pito/docs/architecture.md`: Google OAuth section, YouTube client
      architecture, quota strategy, audit table reference (out of rails-impl
      lane — flagged for the docs-keeper agent)
- [ ] `pito/docs/youtube_quota.md` (new): per-endpoint quota costs, daily
      budget, what happens on exhaustion, the audit table reference (out of
      rails-impl lane — flagged for the docs-keeper agent)
- [ ] `pito/docs/setup.md`: Google Cloud project setup steps for fresh local
      installs (out of rails-impl lane — flagged for the docs-keeper agent)

### Validation

- [ ] Manual: connect Google account; identity persisted in `google_identities`
      (gated on user's manual playbook)
- [ ] Manual: connect YouTube channel; Channel record updates with real
      metadata, `connected: true`, `oauth_identity_id` set
- [ ] Manual: simulate token expiry (set short expiry in dev), make an API call,
      observe automatic refresh, verify `last_refreshed_at` updated
- [ ] Manual: simulate quota exhaustion (set daily budget to a small value via
      dev override), make a call, observe `YouTube::QuotaExhaustedError`
- [ ] Manual: revoke the Google identity from Google's side, attempt a call,
      observe `needs_reauth` flag set and UI surfaces it
- [x] All RSpec specs pass (1751 examples, 0 failures)
- [x] Brakeman, bundler-audit, Dependabot — clean (no new warnings; pre-existing
      Brakeman items unchanged)

---

## Specs requirements

- `GoogleIdentity` model specs: encryption (verify tokens are not plaintext on
  disk), expiry helpers, `needs_reauth?` flag, association integrity.
- `YouTube::Client` specs (with VCR cassettes recorded against real responses,
  anonymized): each method's happy path, quota tracking, token refresh, backoff,
  `QuotaExhaustedError` raising, `needs_reauth` flow.
- OAuth callback request specs: happy path, denied consent, expired code, state
  mismatch, identity upsert.
- Channel connection specs: first-time connect, reconnect, disconnect with
  shared identity, disconnect with sole identity (Google revocation invoked).
- `YoutubeApiCall` audit specs: every call type produces a row; outcomes mapped
  correctly.
- Tenant scoping: `GoogleIdentity` and `YoutubeApiCall` both default-scoped to
  `Current.tenant`; cross-tenant leakage rejected.

## Security requirements

- OAuth tokens stored via Active Record Encryption (already in use from Alpha).
- HTTPS-only redirect URIs in production. Localhost is exempt for dev.
- State parameter on OAuth flow (OmniAuth handles this; verify it's not
  disabled).
- Refresh tokens stored encrypted; access tokens have shorter lifetimes (Google
  sets these — typically 1 hour).
- Quota budget enforcement is a soft control (refuses calls); Google enforces a
  hard limit too. Both align.
- VCR cassettes scrubbed of all secrets before commit. Use
  `vcr.filter_sensitive_data` or equivalent.
- Brakeman: no new warnings. Especially review the OAuth callback for CSRF
  concerns.
- bundler-audit: clean. Verify `omniauth-google-oauth2` and
  `google-apis-youtube_v3` gem versions have no open advisories.
- Dependabot: review after additions.
- `pito/docs/design.md`: Settings → YouTube section design documented (list of
  connected channels in bracketed table format, "needs reauth" indicator,
  connect/disconnect flow).

## Manual testing checklist

The user runs through this before commit:

1. Visit `app.pitomd.com/settings/youtube` — see "Connect Google account" button
2. Click → redirected to Google consent → approve → return to Pito Settings →
   YouTube
3. See list of YouTube channels owned by the Google account (real data) with
   `[Connect]` buttons per channel
4. Click `[Connect]` on one channel → verify in Rails console:
   `Channel.find_by(connected: true)` returns the record with metadata populated
5. Inspect `google_identities` table in `psql` — verify token columns are
   encrypted blobs, not plaintext
6. Wait until access token expires (or set short expiry in dev override) → make
   any API call (e.g., refresh the dashboard) → verify `last_refreshed_at`
   updates and the call succeeds
7. Simulate quota exhaustion: in dev, override the daily budget constant to a
   small number (e.g., 5) → make multiple API calls → verify
   `YouTube::QuotaExhaustedError` is raised after exhaustion
8. Revoke the OAuth grant from Google's account settings → make any API call →
   verify `needs_reauth` flag is set and the UI surfaces a banner
9. Disconnect a channel from Settings → YouTube → verify Channel record has
   `connected: false`, `oauth_identity_id: nil`, but the Channel record itself
   still exists
10. Inspect `youtube_api_calls` table — verify every call from steps 6-9 is
    recorded with appropriate `outcome`
11. `bundle exec rspec` — green

---

## Challenges to anticipate

- **Google OAuth consent screen approval.** Pito is in test mode for
  single-tenant Beta; only whitelisted users (the user themselves) can sign in.
  Production verification is a Theta concern (and only matters if Theta opens
  Pito to others).
- **YouTube quota costs are imprecise in docs.** Some endpoints documented as "1
  unit" vary by `part` parameter or response size. Conservative rounding: always
  round up. If actual usage diverges from estimates, the audit table reveals the
  truth and the cost map can be refined.
- **Refresh token expiry conditions.** Google refresh tokens can expire under
  specific conditions: 90+ days of inactivity, password change on the Google
  account, security action by the user. Handle gracefully — detect via 401 +
  `invalid_grant`, mark identity `needs_reauth`, surface in UI. Do not retry
  indefinitely.
- **Multiple YouTube channels per Google account.** The user has a personal/blog
  channel plus 2 gaming channels. The flow must list and let the user connect
  any/all of them. Test this case explicitly.
- **`google-apis-youtube_v3` gem ergonomics.** The official gem is verbose.
  Wrapping every call in `YouTube::Client` is the right call (which this phase
  already does); the wrapper is the single point of refinement.
- **VCR cassette anonymization.** Cassettes capture real channel titles,
  descriptions, video IDs. Channel-level data is public anyway, but bearer
  tokens and refresh tokens must be scrubbed. Set up `VCR.configure` filters
  before recording any cassette.
- **Test mode whitelist limit.** Google OAuth test mode supports up to 100 test
  users. Single-user Beta won't hit this; capture in `challenges.md` for Theta
  if multi-user becomes relevant.
- **Both Pumas and the env vars.** OAuth credentials need to be readable by Web
  Puma (which handles the callback flow) and by MCP Puma (which doesn't directly
  call OAuth, but Sidekiq jobs initiated from MCP requests will). Standard env
  propagation.

---

## Confirmation gates for Claude Code

Before executing, confirm with the user:

1. The user has access to Google Cloud Console and can create or use a project.
2. Production redirect URI uses `app.pitomd.com/auth/google/callback` (already
   aligned with Pito's domain plan from Alpha).
3. Daily quota of 10,000 units is acceptable for early Beta. If higher quota is
   needed, the user must apply via Google's quota increase form (multi-week
   process; not blocking for development).
4. The user is OK with OmniAuth-based flow. (Alternative: hand-rolled OAuth —
   more control, more code to audit. OmniAuth is the standard recommendation.)
5. Test mode on the consent screen is acceptable. Production verification is
   deferred to Theta.
6. The user is OK with VCR cassettes containing channel metadata (titles,
   descriptions) being committed — public data, but worth confirming.
