# Phase 25 — 01a: Attempt Logging + Fingerprinting

> **Sub-spec 01a.** Foundation. Ships independently and unblocks every other
> 01\* sub-spec. Introduces the `LoginAttempt` model, the fingerprint
> composition pipeline, IP-prefix matching, geo enrichment, and a read-only
> attempt log surface on web + TUI + MCP.
>
> Reads the umbrella spec (`01-overview...md`) first. Locked decisions LD-1 /
> LD-2 / LD-3 / LD-4 / LD-14 / LD-15 / LD-17 apply directly.

## Goal

Every login attempt — success, failure, pending, blocked, rate-limited — gets a
`LoginAttempt` row with a fingerprint hash, IP, IP-prefix, geo enrichment,
parsed UA, and a precise internal reason. The row is durable (never
auto-purged), surfaced read-only on `/settings/security/attempts` and the TUI
security pane, and readable via the `login_attempts_list` MCP tool's stub (full
tool in `01d`).

This sub-spec stops short of NEW-LOCATION DETECTION (that's `01b`) and
PENDING-APPROVAL semantics (also `01b`). Here we only LOG.
`result: pending_approval` is added to the enum so the schema is
forward-compatible, but the only results this sub-spec writes are `success`,
`failed`, and `blocked` (the last only when a `BlockedLocation` row matches;
`01f` builds the auto-block, but the table + match logic land here so the schema
is complete).

## Files touched

### Migrations

- `db/migrate/<ts>_create_login_attempts.rb` — table per LD-1.
- `db/migrate/<ts>_create_blocked_locations.rb` — table per LD-10 (schema only;
  insertion comes in `01f`).
- `db/migrate/<ts>_create_trusted_locations.rb` — table per LD-5 (schema only;
  upsert comes in `01b`).
- `db/migrate/<ts>_add_security_indexes_to_attempts.rb` — indexes on `user_id`,
  `created_at`, `(fingerprint_hash, ip_prefix)`, `result`, `email_attempted`.

### Models

- `app/models/login_attempt.rb` — model + enum + scopes.
- `app/models/blocked_location.rb` — model stub (validations + scopes).
- `app/models/trusted_location.rb` — model stub (validations + scopes).

### Services

- `app/services/auth/fingerprint_composer.rb` — composes the fingerprint string
  from request headers + screen / locale hints, returns the SHA256 hex.
- `app/services/auth/ip_prefix_calculator.rb` — wraps `IPAddr` to yield the CIDR
  string per LD-3.
- `app/services/auth/geo_enricher.rb` — MaxMind GeoLite2 offline lookup; returns
  `{city:, region:, country:}` or empty.
- `app/services/auth/attempt_logger.rb` — single entry point that the
  `SessionsController` calls; takes the request + result + reason and writes the
  `LoginAttempt` row, enqueues the geo-backfill job if needed.

### Jobs

- `app/jobs/login_attempt_geo_enrich_job.rb` — async backfill when the
  synchronous geo lookup misses or is slow (LD-4 fallback).

### Lib

- `app/lib/pito/auth/ip_prefix.rb` — domain primitive used by the service. Pure
  function; testable in isolation.
- `app/lib/pito/auth/user_agent_parser.rb` — wraps `useragent` gem (or
  `device_detector`); returns `{browser:, os:}`.

### Controllers

- `app/controllers/sessions_controller.rb` — existing controller (Phase 6) gains
  a call to `Auth::AttemptLogger.call` on every authenticate POST, before the
  redirect / re-render.
- `app/controllers/settings/security_controller.rb` — new; index pane showing
  2FA status + recent attempts summary.
- `app/controllers/settings/security/attempts_controller.rb` — new; paginated
  `index` and `show`.

### Views

- `app/views/settings/security/index.html.erb` — pane index for the security
  surface.
- `app/views/settings/security/attempts/index.html.erb` — paginated attempt log,
  filterable by result / since / IP / fingerprint.
- `app/views/settings/security/attempts/show.html.erb` — detail row.
- `app/views/settings/security/_attempt_row.html.erb` — partial for one row in
  the table.
- `app/views/sessions/new.html.erb` — gains a hidden field + Stimulus controller
  for the screen / locale hint.

### Stimulus

- `app/javascript/controllers/fingerprint_hints_controller.js` — reads
  `window.screen.*` + `Intl.DateTimeFormat()` and stuffs them into hidden form
  fields on the login page before submit. No canvas, no AudioContext, no WebGL
  (per LD-2).

### Components

- `app/components/login_attempt_row_component.rb` + `_component.html.erb` —
  single attempt row renderer. Used in both the attempts table and (later) the
  pending-approval notification card.

### Helpers

- `app/helpers/login_attempts_helper.rb` — result-badge text / bracketed-link
  copy, geo formatting (`"city, country (region)"`).

### Routes

- `config/routes.rb` — adds:
  ```
  namespace :settings do
    resource :security, only: [:show], controller: "security"
    namespace :security do
      resources :attempts, only: [:index, :show]
    end
  end
  ```

### MCP

- `app/mcp/tools/login_attempts_list.rb` — read-only list tool scaffold. Full
  filter set + auth scope wiring lives in `01d`; the scaffold here returns
  recent rows with `result` / `ip` / `geo` / `fingerprint_hash` (truncated) /
  `created_at`. Yes / no boundary on every Boolean field.

### TUI

- `extras/cli/src/api/security.rs` — client struct for the JSON endpoint.
- `extras/cli/src/security/mod.rs` — module.
- `extras/cli/src/security/attempts.rs` — list view rendered as a Ratatui table.
- `extras/cli/src/security/api.rs` — fetcher.
- TUI hotkey: `g s a` (go → security → attempts), per the existing keymap
  convention.

### Specs (spec pyramid)

#### Model specs

- `spec/models/login_attempt_spec.rb`
  - validations: `result` presence, `result` in enum, `fingerprint_hash`
    presence, `ip` presence + valid inet, `ip_prefix` matches `ip`'s family.
  - scopes: `recent`, `failed`, `for_user(user)`, `since(ts)`,
    `for_fingerprint(fp)`, `pending`.
  - associations: `belongs_to :user, optional: true`,
    `belongs_to :notification, optional: true`,
    `belongs_to :approved_by_user, optional: true`.
  - callbacks: stamps `resolved_at` when `result` flips from `pending_approval`
    to anything else.
- `spec/models/blocked_location_spec.rb`
  - validations: `fingerprint_hash` presence, `ip_prefix` presence (valid CIDR),
    `blocked_by_user` presence.
  - scopes: `active` (where `unblocked_at` IS NULL),
    `for_pair(fingerprint_hash, ip_prefix)`.
- `spec/models/trusted_location_spec.rb`
  - validations: `user_id` presence, `fingerprint_hash` presence, `ip_prefix`
    presence.
  - scopes: `for_user(user)`, `for_pair(fp, pp)`.

#### Service specs

- `spec/services/auth/fingerprint_composer_spec.rb`
  - happy: returns SHA256 hex on a full set of inputs.
  - sad: missing UA → composes with empty string (no crash).
  - edge: identical inputs in different orders → same hash (canonical ordering).
  - edge: same inputs minus one header → different hash.
  - edge: emoji / non-ASCII in `Accept-Language` → still hashes.
  - flaw: rejects an attempt to include a `canvas_hash:` kwarg — the composer
    must not accept canvas / audio / WebGL fingerprints (raises
    `ArgumentError`).
- `spec/services/auth/ip_prefix_calculator_spec.rb`
  - happy: `1.2.3.4` → `1.2.3.0/24`.
  - happy: `2001:db8::1` → `2001:db8::/64`.
  - edge: loopback `127.0.0.1` → `127.0.0.0/24` (don't special-case).
  - edge: IPv6 mapped IPv4 (`::ffff:1.2.3.4`) → IPv4 path.
  - sad: invalid input → raises `ArgumentError`.
- `spec/services/auth/geo_enricher_spec.rb`
  - happy: known IP in MaxMind fixture → returns city / region / country.
  - sad: DB file missing → returns empty hash + logs warning + sets a
    thread-local flag the logger reads to enqueue the async job.
  - sad: unknown IP → returns empty hash without enqueuing.
  - edge: lookup >5 ms → returns empty hash, sets the flag, lets the sync path
    proceed.
  - flaw: never makes an outbound HTTP call (WebMock disables net).
- `spec/services/auth/attempt_logger_spec.rb`
  - happy: success path → writes row with `result: success`, correct
    fingerprint, correct ip_prefix, geo populated, no job enqueued.
  - sad: wrong password → writes row with `result: failed`,
    `reason: wrong_password`, `user_id: <user.id>`.
  - sad: unknown email → writes row with `result: failed`,
    `reason: unknown_account`, `user_id: nil`, `email_attempted: <raw>`.
  - sad: blocked-pair match → writes row with `result: blocked`,
    `reason: blocked_pair`, bumps `BlockedLocation#attempt_count` +
    `last_attempt_at`.
  - edge: geo enricher missed → row written without geo, async job enqueued.
  - edge: rate-limited → row written with `result: failed`,
    `reason: rate_limited` (driven by Rack::Attack middleware in `01g`; contract
    documented here).
  - flaw: never logs the raw password or any of its hashes.

#### Job specs

- `spec/jobs/login_attempt_geo_enrich_job_spec.rb`
  - happy: row missing geo → looks up via enricher, updates row.
  - sad: row already has geo → no-op.
  - sad: row deleted between enqueue and run → no crash.
  - edge: DB still missing → no-op + logs.

#### Lib specs

- `spec/lib/pito/auth/ip_prefix_spec.rb` — mirrors the service spec but at the
  lib level (pure function).
- `spec/lib/pito/auth/user_agent_parser_spec.rb`
  - happy: Chrome on macOS → `{browser: "Chrome", os: "macOS"}`.
  - happy: Firefox on Linux.
  - sad: empty UA → `{browser: "Unknown", os: "Unknown"}`.
  - edge: bot UA (`curl/8.0`) → `{browser: "curl", os: "Unknown"}`.

#### Component specs

- `spec/components/login_attempt_row_component_spec.rb`
  - happy: success row → renders green-ish badge, geo line, masked fingerprint
    (first 12 hex chars).
  - happy: failed row → renders muted badge.
  - happy: blocked row → renders the destructive-red badge.
  - sad: row missing geo → renders `"location unknown"` placeholder.

#### Helper specs

- `spec/helpers/login_attempts_helper_spec.rb` — result-to-copy mapping, geo
  formatting variants (city-only, country-only, full).

#### Request specs

- `spec/requests/settings/security_spec.rb`
  - GET /settings/security → 200, renders pane with 2FA status (off in this
    sub-spec), recent attempts summary.
  - GET when not signed in → 302 → /login.
- `spec/requests/settings/security/attempts_spec.rb`
  - GET /settings/security/attempts → 200, lists rows sorted desc.
  - GET with `?result=failed` filter → 200, only failed rows.
  - GET with `?since=<iso8601>` → 200, only newer rows.
  - GET with `?ip=1.2.3.4` → 200, matches by exact IP.
  - GET with `?fingerprint=<hash>` → 200, matches by hash.
  - GET /settings/security/attempts/:id → 200.
  - GET when not signed in → 302.
  - GET `.json` variant → JSON with yes/no Booleans (e.g.,
    `"is_success": "yes"`).
- `spec/requests/sessions_spec.rb` (existing, gains)
  - POST /login on a fresh request → writes a `LoginAttempt` row.
  - POST with wrong password → writes a row with `result: failed`,
    `reason: wrong_password`, returns generic `Login failed.` flash (LD-14).
  - POST with unknown email → writes a row with `reason: unknown_account`,
    returns the same generic flash.
  - POST with blocked-pair (BlockedLocation row matches) → writes
    `result: blocked`, returns the same generic flash.
  - POST without screen / locale hint fields → composes fingerprint without
    them; row still written.

#### MCP tool spec

- `spec/mcp/tools/login_attempts_list_spec.rb`
  - happy: returns rows, yes/no Booleans at the boundary.
  - sad: without `auth` scope token → returns scope error (stub here; full
    enforcement in `01d`).
  - filter: `result: "failed"`, `since: <iso>`, `ip: "1.2.3.4"`,
    `fingerprint: "<hash>"`.

#### System spec

None at this sub-spec — the cross-cutting journeys live in `01g`. The attempt
log is exercised end-to-end via the request specs.

#### Routing spec

- `spec/routing/settings_security_routing_spec.rb` — confirms the three new
  routes resolve to the right controllers (one-line each).

## Migration shape (illustrative)

```ruby
class CreateLoginAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :login_attempts do |t|
      t.references :user, foreign_key: true
      t.citext :email_attempted
      t.integer :result, null: false  # enum
      t.inet :ip, null: false
      t.string :ip_prefix, null: false  # CIDR string
      t.string :geo_city
      t.string :geo_region
      t.string :geo_country, limit: 2
      t.string :user_agent, null: false
      t.string :browser
      t.string :os
      t.string :fingerprint_hash, null: false
      t.integer :reason, null: false  # enum
      t.references :notification, foreign_key: true
      t.references :approved_by_user, foreign_key: { to_table: :users }
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :login_attempts, [:fingerprint_hash, :ip_prefix]
    add_index :login_attempts, :created_at
    add_index :login_attempts, :result
    add_index :login_attempts, :email_attempted
  end
end
```

## Service decomposition

```
Auth::AttemptLogger
  ├── Auth::FingerprintComposer   (request → hash)
  ├── Auth::IpPrefixCalculator    (request.remote_ip → CIDR)
  ├── Auth::GeoEnricher           (ip → {city, region, country})
  ├── Pito::Auth::UserAgentParser (UA string → {browser, os})
  └── BlockedLocation.for_pair?   (fp + prefix → active block?)
```

The logger is the single entry point. The controller calls
`Auth::AttemptLogger.call(request:, email:, result:, reason:, user: nil)` and
gets the persisted row back.

## Acceptance

- [ ] Migrations applied; all three tables exist with the listed columns and
      indexes.
- [ ] `LoginAttempt` model validations + scopes + associations covered.
- [ ] `BlockedLocation` + `TrustedLocation` models present (schema +
      validations + scopes only; behavior in `01b` / `01f`).
- [ ] `Auth::FingerprintComposer` produces deterministic SHA256 hashes from the
      locked input set. No canvas / audio / WebGL inputs.
- [ ] `Auth::IpPrefixCalculator` yields `/24` for IPv4 and `/64` for IPv6.
- [ ] `Auth::GeoEnricher` uses MaxMind offline DB; falls back to async backfill
      when miss / slow.
- [ ] `Auth::AttemptLogger` is the single entry point. Sessions controller no
      longer writes attempts directly.
- [ ] `LoginAttemptGeoEnrichJob` backfills geo when the sync path missed.
- [ ] Every login POST writes a `LoginAttempt` row, regardless of outcome.
- [ ] Blocked-pair attempts short-circuit before password check and log
      `result: blocked`.
- [ ] `Login failed.` is the only user-visible failure copy.
- [ ] `/settings/security` + `/settings/security/attempts` render the pane
      primitives correctly (`pane--standalone` per project rule).
- [ ] Bracketed links follow `[label]` (no inner spaces).
- [ ] Lead paragraph under each H1 is one-sentence-per-line per project rule.
- [ ] No JS confirm / alert / prompt.
- [ ] JSON / MCP responses use `"yes"` / `"no"` at the boundary.
- [ ] `login_attempts_list` MCP scaffold returns rows + filters work; full scope
      gating in `01d`.
- [ ] TUI `g s a` opens the attempts list, mirrors the web columns.
- [ ] `bin/setup` downloads (or documents downloading) GeoLite2 DB.
- [ ] `.env.example` documents `PITO_GEOIP_DB_PATH`.
- [ ] `docs/auth.md` (or `docs/architecture.md`) gains a "login attempt logging"
      section.
- [ ] Full RSpec green; Brakeman clean; bundler-audit clean.

## Manual test recipe

1. `git pull --rebase`, `bin/setup`, `bin/dev`.
2. Open `http://127.0.0.1:3027/login` in a fresh incognito window.
3. Submit a wrong password → see generic `Login failed.` flash.
4. Visit `http://127.0.0.1:3027/settings/security/attempts` after logging in
   correctly → see the failed attempt + the success row, each with geo
   (localhost → `"location unknown"`) and a truncated fingerprint hash.
5. Filter `?result=failed` → only the failed row.
6. Detail `?` link → renders show page with full hash.
7. Open the TUI (`pito`), navigate `g s a` → the same rows render.
8. From a Claude session with an `auth`-scoped MCP token (or the dev harness),
   call `login_attempts_list` → JSON rows with `"yes"` / `"no"` Booleans.
9. Verify `LoginAttempt.count` matches what's on screen.
10. Teardown: `LoginAttempt.delete_all` from `bin/rails console` (full purge UI
    ships in `01f`).

## Cross-stack scope

| Surface | Status                                                                    |
| ------- | ------------------------------------------------------------------------- |
| Rails   | In scope.                                                                 |
| TUI     | Read-only attempts list under `g s a`.                                    |
| MCP     | `login_attempts_list` scaffold (full scope gating + auth scope in `01d`). |
| Website | Out of scope.                                                             |

## Open questions

- **Q-A** (GeoIP source): locked to MaxMind offline per umbrella. Confirm before
  dispatch.
- **Q-B** (fingerprint composition): include `Sec-Ch-Ua-Platform` and
  `Sec-Ch-Ua-Mobile`? Canonicalize timezone? Lock here before dispatch.
- **Q-I** (geo timing): sync primary with async fallback. Confirm 5 ms
  threshold.
- New: should the `LoginAttempt` table partition by month if it grows past 10k
  rows? Out of scope for this sub-spec; track as a Phase 25 follow-up if needed.
- New: should the TUI attempts list paginate, or load N most-recent? Lock
  pagination at 50 rows / page to match the web list.
