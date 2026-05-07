# Phase 7 — Step 7B — `YouTube::Client`, Audit Table, Public Key Skeleton

> Second of three Phase 7 specs. Lands the rate-limit-aware YouTube API client,
> the `youtube_api_calls` audit table, and the skeleton of the public-API-key
> client. Depends on 7A (`GoogleIdentity` exists). Sibling spec:
> `7c-settings-youtube-ui.md`. Locked decisions are pinned exactly — do not
> reinvent.

---

## Goal

Every YouTube API call from Pito flows through one service object. `YouTube::Client`
takes a `GoogleIdentity`, mints / refreshes its access token transparently,
records each request to the `youtube_api_calls` audit table, enforces a daily
quota budget per identity, and applies exponential backoff on 5xx errors.
This spec also lays down the **skeleton** of `YouTube::PublicClient` — same
shape, API-key auth, audit row with `google_identity_id: nil`. Phase 8 fills
in `PublicClient`'s actual call methods; Phase 7 just establishes the seam so
audit-table consumers (Phase 11 observability) can rely on a stable schema.

This spec does **not** call the YouTube API from any controller, job, or MCP
tool yet. It builds the client, exercises it through specs (with VCR), and
provides a dev-console smoke path. 7C consumes it once for the
`channels.list?mine=true` call during the connect flow.

## Files touched

Rails (Lane 1):

- `app/services/youtube/client.rb` — main client.
- `app/services/youtube/public_client.rb` — API-key skeleton.
- `app/services/youtube/quota.rb` — quota cost map + budget check.
- `app/services/youtube/token_refresher.rb` — refresh logic, isolated for
  testability.
- `app/services/youtube/errors.rb` — `QuotaExhaustedError`, `NeedsReauthError`,
  `TransientError`, `PermanentError` (subclasses of `YouTube::Error`).
- `app/models/youtube_api_call.rb` — audit model.
- `db/migrate/<ts>_create_youtube_api_calls.rb`.
- `Gemfile` — confirm `google-apis-youtube_v3`,
  `google-apis-youtube_analytics_v2` are present (Alpha already pulled them in
  per `CLAUDE.md`; verify versions are current and not Dependabot-flagged).
- `config/credentials/development.yml.enc` and friends — `:youtube` block
  with `public_api_key` (placeholder allowed; Phase 8 fills it).
- `spec/services/youtube/client_spec.rb`
- `spec/services/youtube/public_client_spec.rb`
- `spec/services/youtube/quota_spec.rb`
- `spec/services/youtube/token_refresher_spec.rb`
- `spec/models/youtube_api_call_spec.rb`
- `spec/support/vcr.rb` — VCR + WebMock configuration with sensitive-data
  filters per §"VCR cassette policy".
- `spec/fixtures/vcr_cassettes/youtube/*.yml` — recorded once against a real
  account, scrubbed.

Documentation (parallel docs-keeper dispatch — out of this spec's lane):

- `docs/youtube_quota.md` (new) — per-endpoint quota cost map, daily budget,
  exhaustion behavior, audit table reference.
- `docs/architecture.md` — "YouTube client" subsection.

Cross-stack scope: Rails-only.

## Schema

`youtube_api_calls` — append-only audit log. One row per API call attempt.

| Column                 | Type      | Constraints                                          |
| ---------------------- | --------- | ---------------------------------------------------- |
| id                     | bigint    | pk                                                   |
| tenant_id              | bigint    | not null, fk → tenants                               |
| user_id                | bigint    | nullable, fk → users (nil for `PublicClient`)        |
| google_identity_id     | bigint    | nullable, fk → google_identities (nil for public)    |
| client_kind            | string    | not null, `"oauth"` or `"public"` (sentinel-clean)   |
| endpoint               | string    | not null, e.g. `"channels.list"`, `"videos.list"`    |
| http_method            | string    | not null, `"GET"` / `"POST"`                         |
| units                  | integer   | not null, estimated quota cost (rounded up)          |
| outcome                | string    | not null, see §"Outcome enum"                        |
| http_status            | integer   | nullable, the actual HTTP status                     |
| error_message          | text      | nullable                                             |
| duration_ms            | integer   | nullable, request wall time                          |
| created_at             | datetime  | not null                                             |

Indexes:

- `(tenant_id, google_identity_id, created_at)` — daily-budget aggregate.
- `(tenant_id, client_kind, created_at)` — public-vs-oauth split for
  Phase 11 dashboards.
- `(tenant_id, outcome, created_at)` — failure trend lookups.

No `updated_at` — append-only.

`YoutubeApiCall` model:

- Default scope: `where(tenant_id: Current.tenant&.id)`.
- `scope :today, ->(zone = "UTC") { where("created_at >= ?", Time.current.in_time_zone(zone).beginning_of_day) }`
- Validations on presence of `endpoint`, `http_method`, `units`, `outcome`,
  `client_kind`. Inclusion check on `outcome` and `client_kind`.

### Outcome enum

String values, validated by inclusion:

- `"success"` — 2xx response, parsed correctly.
- `"auth_failed"` — 401 even after a refresh attempt; `needs_reauth` set on
  the identity.
- `"quota_exceeded"` — Google returned 403 with reason `quotaExceeded` /
  `dailyLimitExceeded`, OR Pito's pre-call budget check refused the call.
- `"rate_limited"` — 429 (Google occasionally returns this for burst limits;
  separate from quota exhaustion).
- `"server_error"` — 5xx after retries exhausted.
- `"client_error"` — non-401 / non-403 / non-429 4xx.
- `"network_error"` — connection refused, timeout, DNS, etc.

## Quota cost map

Single frozen hash in `YouTube::Quota::COSTS`. Pinned to YouTube's documented
unit costs (https://developers.google.com/youtube/v3/determine_quota_cost),
rounded up where the cost varies by `part`:

```ruby
COSTS = {
  "channels.list"       => 1,
  "videos.list"         => 1,
  "playlists.list"      => 1,
  "playlistItems.list"  => 1,
  "search.list"         => 100,    # the expensive one
  "subscriptions.list"  => 1,
  "captions.list"       => 50,
  # YouTube Analytics v2:
  "reports.query"       => 1,
}.freeze
```

`Quota.cost_for(endpoint)` returns the value, or raises
`YouTube::UnknownEndpointError` (treat as a programming error, not a runtime
condition).

`DAILY_BUDGET_UNITS = 10_000` (Google's default per-project daily quota).
Configurable via `Rails.application.config.youtube_daily_budget_units` to
support the Phase 7 plan's manual-test step "set daily budget to a small
value via dev override".

`Quota.budget_remaining(google_identity)`:

```
DAILY_BUDGET_UNITS -
  YoutubeApiCall.today
    .where(google_identity_id: google_identity.id, client_kind: "oauth")
    .sum(:units)
```

Public-client budget tracking is bucketed separately under
`google_identity_id IS NULL AND client_kind = "public"` — Phase 8 finalizes
the public-key budget value.

## `YouTube::Client` contract

```ruby
client = YouTube::Client.new(google_identity)

client.channels_list(mine: true, parts: %i[snippet contentDetails statistics])
# => { items: [...], next_page_token: nil }

client.videos_list(ids: %w[abc123 def456], parts: %i[snippet statistics])
# => { items: [...], next_page_token: nil }

client.playlists_list(channel_id: "UC...", parts: %i[snippet])
client.analytics_query(ids: "channel==MINE", metrics: %w[views], ...)
```

Method surface for Phase 7:

- `#channels_list(**)` — needed by 7C.
- `#videos_list(**)` — useful for 7C verification; reused by Phase 8.
- `#playlists_list(**)` — reused by Phase 8 / 10.
- `#analytics_query(**)` — minimal wrapper; reused by Phase 8.

Each method:

1. Resolves an endpoint key (e.g. `"channels.list"`).
2. Calls `ensure_token_fresh!` (refresh if `expires_at` within 60s).
3. Calls `Quota.budget_remaining(identity) - cost >= 0`; if not, raise
   `QuotaExhaustedError` and audit `outcome: "quota_exceeded"` with
   `http_status: nil`.
4. Issues the underlying `Google::Apis::YoutubeV3::YouTubeService` (or
   `YoutubeAnalyticsV2`) call, wrapped in retry/backoff per §"Retry
   policy".
5. On success: audit `outcome: "success"`, return a stable hash (Pito's
   shape, not the Google gem's nested structs — convert at the boundary).
6. On any error: audit appropriately, raise a `YouTube::*Error` subclass.

The Pito-shape conversion is intentional: we never let
`Google::Apis::YoutubeV3::Channel` leak past `YouTube::Client`. Callers see
plain Ruby Hashes with snake_case keys.

### Token refresh

`YouTube::TokenRefresher.call(google_identity)` — pure function, no side
effects on the client object, easy to spec.

- POST to `https://oauth2.googleapis.com/token` with `grant_type=refresh_token`,
  `client_id`, `client_secret`, `refresh_token`.
- On 200: update `access_token`, `expires_at`, `last_refreshed_at`. Persist.
- On 400 with `error: "invalid_grant"`: set `needs_reauth: true`, persist,
  raise `NeedsReauthError`.
- On other failures: raise `TransientError`; the caller's retry path may
  retry once.

Refresh is invoked:

- **Pre-call** when `access_token_expired?(skew: 60.seconds)` is true.
- **Mid-call** when a 401 comes back unexpectedly (clock skew, server-side
  early invalidation). Refresh, retry the original call **once**. A second
  401 → `auth_failed`, `needs_reauth: true`, raise `NeedsReauthError`.

### Retry policy

- 5xx (500, 502, 503, 504) → exponential backoff with jitter, max 3 attempts.
  Sleep `1.0 ± 0.2`, `2.0 ± 0.4`, `4.0 ± 0.8` seconds. After exhaustion:
  `outcome: "server_error"`, raise `TransientError`.
- 429 → respect `Retry-After` if present (cap at 30s); otherwise sleep 5s,
  retry once. After exhaustion: `outcome: "rate_limited"`, raise
  `TransientError`.
- 401 → refresh + retry once (see "Token refresh").
- 403 with reason `quotaExceeded` / `dailyLimitExceeded` → `outcome:
  "quota_exceeded"`, raise `QuotaExhaustedError`. Do not retry.
- Other 4xx → `outcome: "client_error"`, raise `PermanentError`.
- Connection errors / `Faraday::TimeoutError` etc. → treated as 5xx for retry
  purposes; final outcome `"network_error"`.

The retry loop **always** writes exactly one `YoutubeApiCall` row per logical
API call (the row reflects the final outcome). Per-attempt rows are out of
scope; if Phase 11 observability needs them later, add a
`youtube_api_call_attempts` table at that time.

## `YouTube::PublicClient` skeleton

Same constructor signature as `Client`, but takes no identity:

```ruby
YouTube::PublicClient.new
```

Reads `Rails.application.credentials.dig(:youtube, :public_api_key)` (may be
`nil` in Phase 7; the constructor raises `NotConfiguredError` if any method
is invoked without a key).

Phase 7 implements:

- The class with the constructor and a `#configured?` predicate.
- Audit-row writing helper shared with `Client` (extract a tiny
  `YouTube::Auditor` module so both clients audit through the same path).
- One smoke method `#channels_list(ids:, parts:)` to exercise the path —
  enough to assert `client_kind: "public"` rows land in the audit table.

Out of Phase 7 scope (Phase 8 finishes):

- The full method surface (`videos_list`, `playlists_list`, etc.) on
  `PublicClient`.
- A separate quota budget for public calls (Phase 8 picks the number; this
  spec leaves `PublicClient` unbounded — every call lands in the audit
  table, but the pre-call budget check is skipped).

## VCR cassette policy

`spec/support/vcr.rb`:

- Configure WebMock; allow connections only to `localhost`.
- VCR record mode: `:none` in CI, `:new_episodes` locally for fresh
  recordings, switched via `VCR_RECORD` env var.
- `filter_sensitive_data("<GOOGLE_BEARER_TOKEN>")` — captures the
  `Authorization: Bearer ...` header.
- `filter_sensitive_data("<GOOGLE_REFRESH_TOKEN>")` — captures the request
  body of the refresh endpoint.
- `filter_sensitive_data("<GOOGLE_CLIENT_SECRET>")` — captures
  `client_secret=...` in form bodies.
- `filter_sensitive_data("<YOUTUBE_PUBLIC_API_KEY>")` — captures the
  `key=...` query parameter.
- `filter_sensitive_data("<GOOGLE_SUBJECT_ID>")` — captures the user's
  Google numeric ID. (Not strictly secret, but a privacy hygiene win and
  trivial to redact.)
- `before_record` hook strips `Set-Cookie` headers entirely.

Cassette naming:
`spec/fixtures/vcr_cassettes/youtube/{client,public_client}/{method_name}/{scenario}.yml`,
e.g. `youtube/client/channels_list/happy_path.yml`,
`youtube/client/channels_list/quota_exceeded.yml`.

The `quota_exceeded`, `rate_limited`, `server_error`, `network_error`
cassettes are **synthetic** — created by hand to mock Google's error response
shapes. The `happy_path` cassettes are recorded once against the user's real
account, then committed.

**Locked decision — channel metadata in cassettes is OK.** Channel titles,
descriptions, video IDs are public anyway. The cassette filter list above
covers everything sensitive. Do not over-filter; the cassettes need to be
deterministic for spec assertions.

## Acceptance

- [ ] Migration creates `youtube_api_calls` with all columns, types, indexes
      per §"Schema".
- [ ] `YoutubeApiCall` model: default-scoped to `Current.tenant`, validates
      `outcome` and `client_kind` inclusion, `today` scope works.
- [ ] `YouTube::Quota::COSTS` is frozen; `cost_for("channels.list") == 1`;
      unknown endpoint raises `UnknownEndpointError`.
- [ ] `Quota.budget_remaining` correctly subtracts today's `oauth` units for
      the given identity.
- [ ] `YouTube::TokenRefresher.call` updates `access_token`, `expires_at`,
      `last_refreshed_at` on success (VCR happy path).
- [ ] `TokenRefresher` sets `needs_reauth: true` and raises `NeedsReauthError`
      on `invalid_grant` (synthetic cassette).
- [ ] `YouTube::Client#channels_list(mine: true)` returns Pito-shape
      `{ items: [...], next_page_token: ... }` — never a Google gem struct.
- [ ] Pre-call quota check refuses calls when budget < cost; one audit row
      with `outcome: "quota_exceeded"`, `http_status: nil` is written.
- [ ] On expired access token, `Client` refreshes, retries, and succeeds;
      one audit row with `outcome: "success"`.
- [ ] On 401 mid-call, `Client` refreshes once, retries once; second 401
      → `auth_failed`, `needs_reauth: true`, raises `NeedsReauthError`.
- [ ] On 5xx, `Client` retries up to 3 times with backoff; final failure
      → `server_error`, `TransientError`.
- [ ] On 403 `quotaExceeded`, `Client` does not retry; one row with
      `outcome: "quota_exceeded"`, raises `QuotaExhaustedError`.
- [ ] `YouTube::PublicClient.new#configured?` is false when the API key is
      blank; methods raise `NotConfiguredError`.
- [ ] When `public_api_key` is set, `PublicClient#channels_list` writes one
      audit row with `client_kind: "public"`, `google_identity_id: nil`,
      `user_id: nil`.
- [ ] VCR cassettes for the happy paths are committed and contain no
      bearer tokens, refresh tokens, client secrets, or API keys (verify by
      grepping `spec/fixtures/vcr_cassettes/youtube/`).
- [ ] Tenant-scoping spec: `YoutubeApiCall` rows from tenant A are not
      visible under `Current.tenant = B`.
- [ ] No JS `alert` / `confirm` / `prompt` introduced.
- [ ] Brakeman clean. bundler-audit clean (verify no advisories on
      `omniauth-google-oauth2`, `google-apis-youtube_v3`,
      `google-apis-youtube_analytics_v2`).

## Manual test recipe

Prereq: 7A landed; the user has connected a Google identity per 7A's manual
recipe. The `:youtube` credentials block has `public_api_key` left as
placeholder for now (Phase 8 fills it).

1. `bin/dev` running.
2. `bin/rails console`:

   ```ruby
   identity = GoogleIdentity.last
   client   = YouTube::Client.new(identity)
   result   = client.channels_list(mine: true, parts: %i[snippet statistics])
   result[:items].first[:snippet][:title]
   # => the user's YouTube channel title (real data)
   ```

3. Inspect the audit row:

   ```ruby
   YoutubeApiCall.last.attributes.slice(
     "endpoint", "http_method", "units", "outcome", "client_kind", "http_status"
   )
   # => { "endpoint" => "channels.list", "http_method" => "GET",
   #      "units" => 1, "outcome" => "success", "client_kind" => "oauth",
   #      "http_status" => 200 }
   ```

4. Force quota exhaustion:

   ```ruby
   Rails.application.config.youtube_daily_budget_units = 0
   client.channels_list(mine: true, parts: %i[snippet])
   # => raises YouTube::QuotaExhaustedError
   YoutubeApiCall.last.outcome  # => "quota_exceeded"
   YoutubeApiCall.last.http_status  # => nil (refused before HTTP)
   ```

   Reset:
   `Rails.application.config.youtube_daily_budget_units = 10_000`.

5. Force token refresh:

   ```ruby
   identity.update!(expires_at: 5.minutes.ago)
   client.channels_list(mine: true, parts: %i[snippet])
   # succeeds; observe identity.last_refreshed_at updated
   identity.reload.last_refreshed_at  # => Time.current-ish
   ```

6. Force `needs_reauth`:
   - From https://myaccount.google.com/permissions, revoke Pito's grant.
   - `identity.update!(expires_at: 5.minutes.ago)` to force a refresh path.
   - `client.channels_list(mine: true, parts: %i[snippet])`
   - => raises `YouTube::NeedsReauthError`.
   - `identity.reload.needs_reauth?` => `true`.
   - 7C surfaces this in the UI; here we only check the column.

7. `bundle exec rspec spec/services/youtube/ spec/models/youtube_api_call_spec.rb`
   — all green. Cassettes replay from disk; no network hits.

8. `grep -RE "ya29\.|1//[0-9A-Za-z_-]{40,}|AIza[0-9A-Za-z_-]{35}" spec/fixtures/vcr_cassettes/`
   — should return nothing. (Three patterns: Google access tokens, refresh
   tokens, and API keys.)

Teardown:
`YoutubeApiCall.delete_all` if you want a clean slate before continuing to
7C.

## Cross-stack scope

- Rails — **in scope**.
- `pito` CLI (`extras/cli/`) — **skipped.** The CLI does not call the
  YouTube API directly; if it ever needs YouTube data, it goes through the
  Rails JSON API (Phase 8).
- MCP — **skipped this phase.** Phase 8 introduces `yt:*` tools that wrap
  `YouTube::Client` server-side. The audit table is shaped to support that
  expansion.
- Cloudflare Pages website — **skipped.**

## Open questions

1. **Quota strategy: per-identity, per-tenant, or per-Google-Cloud-project?**
   This spec defaults to **per-identity** for OAuth calls (the daily 10k
   units are scoped per Google Cloud project, not per OAuth user — but
   Beta is single-user, single-tenant, single-project, so all three
   strategies converge). Phase 11 / Theta may need to revisit when a
   tenant has multiple identities all hammering one Cloud project.
   Default: per-identity, document the assumption in `docs/youtube_quota.md`.
2. **Burst handling.** This spec implements "fail fast on quota
   exhaustion" — `QuotaExhaustedError` is raised, the caller decides what
   to do. Phase 8's sync jobs may want a "queue and retry tomorrow"
   strategy. Default: Phase 7 fails fast; Phase 8 chooses its retry
   semantics on top.
3. **Public-key quota number.** The plan defers this to Phase 8.
   `PublicClient` in Phase 7 has no pre-call budget check. Confirm this
   is acceptable.
4. **Per-attempt audit rows.** This spec writes one row per logical call
   (final outcome). Phase 11 observability may want per-attempt detail
   (a 5xx + retry that ultimately succeeded is currently invisible).
   Default: one row per call; revisit in Phase 11 with a separate
   attempts table if needed.
5. **`google-apis-youtube_v3` version pin.** The Alpha codebase pulled in
   a specific version; verify `bundler-audit` and Dependabot are clean,
   and pin to a current-as-of-Phase-7 patch version to keep VCR cassettes
   stable. Surface the chosen version in the 7B implementation log.
6. **Webhook / PubSubHubbub subscriptions for new uploads.** Out of scope
   for Phase 7 (and the plan agrees). Confirm — the plan's "Out of scope"
   list does not mention PubSubHubbub explicitly; this spec records the
   defer.
