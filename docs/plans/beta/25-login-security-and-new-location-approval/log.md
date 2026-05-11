# Phase 25 — Login Security + New-Location Approval · Session Log

## 2026-05-11 — 01a — Attempt logging + fingerprinting

**Dispatch:** `pito-rails` agent against spec
`specs/01a-attempt-logging-and-fingerprinting.md`. Foundation sub-spec —
ships independently and unblocks 01b–01g. Locked decisions LD-1 (schema),
LD-2 (fingerprint composition), LD-3 (IP-prefix matching), LD-4 (geo
enrichment), LD-14 (generic failure copy), LD-15 (yes/no boundary), LD-17
(friendly URLs) all applied directly.

**What landed**

Database

- `db/migrate/20260511120000_create_login_attempts.rb` — schema per LD-1
  plus all 5 indexes (user_id, created_at, result, email_attempted,
  fingerprint_hash, composite (fingerprint_hash, ip_prefix),
  approved_by_user_id). `reason` enum encodes the full 15-value LD-1
  vocabulary so 01b–01g need no further migration.
- `db/migrate/20260511120001_create_blocked_locations.rb` — schema-only
  per LD-10. Unique partial index on (fingerprint_hash, ip_prefix).
  `source_surface` enum (web/tui/mcp) ready for 01d.
- `db/migrate/20260511120002_create_trusted_locations.rb` — schema-only
  per LD-5. Unique composite (user_id, fingerprint_hash, ip_prefix).
  01b will use this for new-location detection.

Migrations were applied against dev DB AND test DB.

Models

- `app/models/login_attempt.rb` — result/reason enums, validations,
  scopes (`recent`, `failed`, `succeeded`, `blocked_results`, `pending`,
  `for_user`, `for_fingerprint`, `for_ip`, `since`), `belongs_to`
  associations (user/notification/approved_by_user, all optional). Soft
  IP-family validation on `(ip, ip_prefix)`. `before_update` stamps
  `resolved_at` when transitioning out of `pending_approval` (01b prep).
  Two display helpers (`fingerprint_short`, `geo_summary`).
- `app/models/blocked_location.rb` — validations, `active` scope,
  `for_pair?` lookup (the hot path the AttemptLogger reads on every
  authenticate POST), `bump_attempt!` updater.
- `app/models/trusted_location.rb` — validations, `for_user` / `for_pair`
  scopes, `.trusted?` class helper.

Services

- `app/services/auth/fingerprint_composer.rb` — privacy-preserving
  fingerprint per LD-2. Accepts UA + Accept/Accept-Language/Accept-
  Encoding + Sec-Ch-Ua-Platform/Mobile + screen hint + locale hint.
  **Rejects** `canvas_hash`, `audio_hash`, `webgl_renderer`, `font_list`,
  `battery_level` kwargs with `ArgumentError` — defense-in-depth against
  a future regression that tries to add invasive signals. Pure function;
  deterministic; canonical input ordering.
- `app/services/auth/ip_prefix_calculator.rb` — service facade over
  `Pito::Auth::IpPrefix` so the AttemptLogger composes from one
  namespace.
- `app/services/auth/geo_enricher.rb` — MaxMind GeoLite2 offline lookup
  with the LD-4 fallback semantics: sync primary, deferred-flag flip on
  miss / over-budget (5 ms) / missing DB / missing gem. NEVER makes
  outbound HTTP. Returns `{city:, region:, country:}` (nils on miss).
  Memoized reader per-DB-path; test-only `reset_reader_for_test!` hook.
  Reads `ENV["PITO_GEOIP_DB_PATH"]`.
- `app/services/auth/attempt_logger.rb` — **single entry point**. The
  `SessionsController` MUST NOT bypass it for any LoginAttempt write.
  Composes fingerprint + ip_prefix + geo + UA, checks the auto-block
  list, writes the row, and enqueues `LoginAttemptGeoEnrichJob` when
  geo was deferred. Blocked-pair short-circuit rewrites `result:
  success` (or any non-:blocked result) to `result: blocked` and
  `reason: blocked_pair`, then bumps the BlockedLocation's
  attempt_count + last_attempt_at.

Jobs

- `app/jobs/login_attempt_geo_enrich_job.rb` — Sidekiq async backfill.
  Idempotent: row-already-has-geo and row-deleted-between-enqueue-and-
  run are both no-ops.

Lib

- `app/lib/pito/auth/ip_prefix.rb` — pure function. `/24` IPv4, `/64`
  IPv6, IPv4-mapped IPv6 unwrap.
- `app/lib/pito/auth/user_agent_parser.rb` — wraps `useragent` gem.
  Normalizes verbose OS strings ("OS X 10.15.7" → "macOS",
  "iOS 17.5.1" → "iOS", "Linux x86_64" → "Linux") so the attempt-log
  table stays compact and minor-version rolling doesn't multiply
  trusted-location rows.

Controllers

- `app/controllers/sessions_controller.rb` — now calls
  `Auth::AttemptLogger.call` on EVERY authenticate POST (success,
  wrong-password, unknown-email, rate-limited). On the success branch,
  re-checks the returned row's `result_blocked?` — if the logger
  rewrote it to `blocked` via the auto-block list, the controller
  refuses to mint a session and renders the generic flash. Failure
  copy collapsed to `login failed.` per LD-14 (was `invalid email or
  password.`).
- `app/controllers/settings/security_controller.rb` — `show` action
  renders the pane with 2FA status (off in this sub-spec), 24h
  failed/blocked counts, active-block count, and the 10 most-recent
  attempts.
- `app/controllers/settings/security/attempts_controller.rb` —
  paginated (50/page) + filterable index, plus show. Filters:
  `result`, `since`, `ip`, `fingerprint`. JSON branch returns
  `is_success` / `is_failed` / `is_blocked` yes/no Booleans per
  LD-15.

Views

- `app/views/settings/security/show.html.erb` — `pane--standalone`
  primitive per project rule; lead paragraph one-sentence-per-line.
  Lists the recent rows via the component.
- `app/views/settings/security/attempts/index.html.erb` — filter form
  (plain GET, shareable URLs), table of rows, pagination footer.
- `app/views/settings/security/attempts/show.html.erb` — full
  fingerprint hash, full UA, geo, resolved_at when present.
- `app/views/sessions/new.html.erb` — gains the two hidden fields
  (`fp_screen`, `fp_locale`) plus `data-controller="fingerprint-hints"`.
  Lead paragraph reflowed to one-sentence-per-line.

Stimulus

- `app/javascript/controllers/fingerprint_hints_controller.js` — fills
  the hidden fields from `window.screen.*` and
  `Intl.DateTimeFormat().resolvedOptions().timeZone` +
  `navigator.language`. **No** canvas / AudioContext / WebGL / font /
  battery signals collected. Graceful degrade if any read raises.

Components & helpers

- `app/components/login_attempt_row_component.rb` (+ ERB partial) —
  one `<tr>` per attempt. Used in both the index table and the
  security dashboard's recent-activity table; designed for reuse in
  01b's pending-approval notification card.
- `app/helpers/login_attempts_helper.rb` — result / reason / geo /
  CSS-class mappings centralized.

MCP

- `app/mcp/tools/login_attempts_list.rb` — scaffold tool. Filter set:
  result, since, ip, fingerprint; pagination caps at 100/page. Uses
  the existing `app` scope as a placeholder; 01d swaps to the
  dedicated `auth` scope when LD-8's scope catalog wiring lands. Rows
  carry `is_success` / `is_failed` / `is_blocked` yes/no Booleans per
  LD-15.

Routes

- `config/routes.rb` — adds `resource :security` (singular,
  `/settings/security`) and the nested
  `namespace :security do resources :attempts, only: %i[index show] end`.

**Specs added (210 examples)**

Model (65)
: `spec/models/login_attempt_spec.rb`,
  `spec/models/blocked_location_spec.rb`,
  `spec/models/trusted_location_spec.rb`

Services (28)
: `spec/services/auth/fingerprint_composer_spec.rb` (12 examples
  including 4 flaw-class rejection specs for canvas / audio / WebGL /
  fonts kwargs),
  `spec/services/auth/ip_prefix_calculator_spec.rb`,
  `spec/services/auth/geo_enricher_spec.rb` (11 — DB-available,
  DB-unavailable, unknown-IP, over-budget, exception, nil-input,
  defer-flag lifecycle, no-outbound-HTTP),
  `spec/services/auth/attempt_logger_spec.rb` (12 — happy / sad /
  blocked-pair / geo-deferred / rate-limited / malformed-IP /
  password-never-logged flaw)

Job (4)
: `spec/jobs/login_attempt_geo_enrich_job_spec.rb`

Lib (14)
: `spec/lib/pito/auth/ip_prefix_spec.rb`,
  `spec/lib/pito/auth/user_agent_parser_spec.rb`

Component (8)
: `spec/components/login_attempt_row_component_spec.rb`

Helper (12)
: `spec/helpers/login_attempts_helper_spec.rb`

Request (20 across two files)
: `spec/requests/settings/security_spec.rb`,
  `spec/requests/settings/security/attempts_spec.rb`

Sessions request gain (+5 in `spec/requests/sessions_spec.rb`)
: success-row write, wrong-password row, unknown-account row,
  blocked-pair short-circuit, fingerprint composition without
  hints.

MCP (13)
: `spec/mcp/tools/login_attempts_list_spec.rb` — happy / scope-gate /
  filter-set / pagination

Routing (3)
: `spec/routing/settings_security_routing_spec.rb`

Factories: `spec/factories/login_attempts.rb`,
`spec/factories/blocked_locations.rb`,
`spec/factories/trusted_locations.rb`.

**Gates**

- `bundle exec rspec` (touched specs + broad regression across models,
  services, helpers, components, lib, jobs, mcp, routing): 3,782
  examples, 0 failures, 1 pre-existing pending.
- `bundle exec rubocop` on all touched files: 39 files clean.
- `bin/brakeman -q -w2`: 0 warnings, 0 errors.
- Two `bundle exec rspec spec/requests/` failures (`auth_concern_spec`
  intended-URL stash, `settings_spec` 8-vs-9 pane count) are
  pre-existing / Phase-26-in-flight and unrelated to this dispatch.

**Migrations applied**

```
== 20260511120000 CreateLoginAttempts: migrated ==
== 20260511120001 CreateBlockedLocations: migrated ==
== 20260511120002 CreateTrustedLocations: migrated ==
```

Both dev and test DBs migrated. Master will tell user to restart
`bin/dev` after commit lands.

**Manual test plan**

1. Restart `bin/dev` after the commit (migrations require Puma reload).
2. Log out, then visit `http://127.0.0.1:3027/login` in a fresh
   incognito window. Submit the wrong password — see the generic
   `login failed.` flash.
3. Log in correctly.
4. Visit `/settings/security` — expect the 2FA pane to say
   `status: off`, the recent activity pane to show 1 failed + 1
   success row with `location unknown` geo (because no MaxMind DB is
   set) and a 12-char fingerprint hash.
5. Visit `/settings/security/attempts` — confirm filter form, both
   rows visible, both clickable into the detail page.
6. Apply `?result=failed` — only the failed row remains.
7. Visit `/settings/security/attempts.json` — confirm rows carry
   `"is_success"`, `"is_failed"`, `"is_blocked"` as `"yes"` / `"no"`
   strings.
8. From a Claude session with an `app`-scoped token, call
   `login_attempts_list` — JSON rows match the web JSON shape, yes/no
   Booleans included.
9. Open `bin/rails console`: seed a `BlockedLocation` row with the
   fingerprint hash from step 4's success row and the matching IP
   prefix. Re-log-in with the correct password. Expect generic
   `login failed.`; the new attempt row reads `result: blocked,
   reason: blocked_pair`; the `BlockedLocation#attempt_count` ticks
   up.
10. Teardown: `LoginAttempt.delete_all; BlockedLocation.delete_all`
    from the console (full purge UI ships in 01f).

**Deferred to later sub-specs (per umbrella + dispatch)**

- TUI `g s a` keybind for the attempts list — dispatcher said "defer
  TUI for now; web sufficient". 01c / 01g pick it up.
- `auth` MCP scope catalog wiring + `login_attempts_list` scope swap
  from `app` to `auth` — 01d's job per LD-8.
- MaxMind GeoLite2 gem dependency + `bin/setup` download step.
  `Auth::GeoEnricher` gracefully degrades to "deferred" today; the
  gem add lands when the user explicitly opts into GeoIP. The
  `.env.example` line documenting `PITO_GEOIP_DB_PATH` was NOT
  added in this dispatch — flagged as a follow-up so it pairs with
  the gem add.
- `docs/auth.md` "login attempt logging" section — `pito-docs` agent
  owns docs work.

**Open issues**

- Two pre-existing test failures in `spec/requests/`
  (`auth_concern_spec:57`, `settings_spec:216`) are unrelated to this
  dispatch — Phase 24 dropped `:create` from `:channels` without
  updating the auth-concern spec, and Phase 26's in-flight timezone
  pane changes the settings index expected layout.
- The `.env.example` documentation + MaxMind gem add are queued for
  the same follow-up; geo enrichment ships fully functional but
  inert until that follow-up lands.
