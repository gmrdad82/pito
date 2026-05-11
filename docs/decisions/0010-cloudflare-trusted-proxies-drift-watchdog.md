# ADR 0010 — Weekly drift watchdog for Cloudflare trusted-proxy CIDR list

## Status

Accepted, 2026-05-12. [skipci]

## Context

Pito's production deployment terminates TLS at Cloudflare and proxies HTTP
to the Rails Puma processes via a `cloudflared` tunnel. Rails uses the
trusted-proxy mechanism (`config.action_dispatch.trusted_proxies` in
`config/environments/production.rb`) to recognize Cloudflare edges so that
`request.remote_ip` resolves to the originating client IP rather than the
Cloudflare edge IP.

Cloudflare publishes its edge CIDR list at:

- `https://www.cloudflare.com/ips-v4` — IPv4 CIDRs, one per line.
- `https://www.cloudflare.com/ips-v6` — IPv6 CIDRs, one per line.

The list is small (~15 IPv4 + ~7 IPv6 entries as of 2026-05) and stable
month-to-month, but it does drift: Cloudflare adds a CIDR when a new edge
region comes online, and very occasionally retires one. Pito's
`production.rb` carries the list as a hardcoded array — the price of not
having a runtime fetch is that a Cloudflare CIDR addition silently breaks
`request.remote_ip` resolution for a slice of traffic until an operator
notices and bumps the hardcoded list.

Phase 25 (Login Security) made this drift load-bearing: the new-location
detection signal compares the current login's IP against the user's
trusted-location list. If `request.remote_ip` returns a Cloudflare edge IP
instead of the originating client IP (because Cloudflare added a CIDR
pito hasn't trusted yet), every login from clients routed through that
new edge gets flagged as a new location. False-positive new-location
notifications are operator-noise and erode trust in the genuine signal.

A runtime fetch of the Cloudflare CIDR list on every request (or even on
process boot) is unattractive: third-party HTTP at boot is a startup-time
liability; per-request fetching is absurd. The middle ground is a
scheduled watchdog: fetch periodically, compare against the hardcoded
list, surface a notification on drift, let the operator merge the bump
manually.

## Decision

Ship a weekly drift watchdog. Compare the live Cloudflare CIDR list
against the hardcoded `production.rb` list; emit a `sync_error`
notification on drift; the operator manually bumps the CIDR list in
`production.rb` and ships the diff.

Concretely:

- **Job:** `CloudflareTrustedProxiesRefresherJob`
  (`app/jobs/cloudflare_trusted_proxies_refresher_job.rb`). Performs an
  HTTP GET against the two CIDR URLs, parses each into a sorted set,
  diffs against the hardcoded set extracted from
  `config/environments/production.rb`. The hardcoded set is exposed via a
  small `Pito::TrustedProxies::CONFIGURED` constant so the diff doesn't
  re-parse the environment file.
- **Schedule:** every Monday at 09:00 UTC. Wired through `sidekiq-cron` in
  `config/sidekiq_cron.yml` (matching the existing weekly-cadence jobs).
  Monday 09:00 UTC was chosen to land during European working hours so a
  drift notification surfaces with the operator awake and able to act
  before the US morning.
- **Drift output:** a `Notification` row with `kind: :sync_error`,
  `severity: :warn`, payload carrying the added / removed CIDRs and
  the live list. The notification surfaces on `/notifications` and on
  the digest if the install runs one. No automatic patch is applied —
  the change to `production.rb` is a code change that wants a
  human-reviewed commit, not a runtime-mutated trust list.
- **Failure mode:** the fetch itself can fail (Cloudflare 5xx, network
  partition). The job catches transient errors and re-enqueues with
  backoff; persistent failures (3+ consecutive misses) emit a separate
  `sync_error` notification flagging the watchdog itself, not a drift.
  Better to know the watchdog is silent than to wait for a drift
  notification that never comes.
- **Test coverage:** request-stubbed specs assert the diff shape (added,
  removed, unchanged), the notification payload, and the consecutive-
  failure escalation path. The hardcoded list is held under
  `Pito::TrustedProxies::CONFIGURED` so the spec asserts against a
  stable surface.

## Consequences

- **Drift becomes visible.** A Cloudflare CIDR addition surfaces within
  seven days on a notification the operator already monitors. False-
  positive new-location flags from un-trusted edges have a bounded
  window.
- **No runtime mutation of trusted proxies.** The trust list stays
  source-controlled in `production.rb`. A drift is a PR-equivalent
  commit, not a `Rails.application.config.action_dispatch.trusted_proxies
  =` patch at runtime.
- **Operator action required.** The watchdog detects; it doesn't fix.
  The operator copies the added CIDRs into `production.rb`, runs the
  test suite, and ships. The friction is intentional — runtime mutation
  of trust scope is a security-relevant change that wants the same
  review path any other security change gets.
- **Notification scope.** The drift notification is install-level (not
  per-user). It surfaces to whoever the install's notification anchor is
  (per the daily-digest install-level dispatch decision in Phase 26).
- **Cron cadence is conservative.** Weekly is slower than necessary for
  a list that changes ~once per quarter, but it avoids hammering
  Cloudflare's static endpoint with daily requests for a list that
  rarely moves. Bump to daily if a real drift slips through and the
  weekly window proves too long.

## Open questions (deferred)

- **Automatic patch + PR.** A future improvement: when drift is detected,
  the job opens a PR against the repo with the CIDR bump. Requires
  GitHub-app credentials in the deployed install, which is a
  distribution-shaped problem (per-install bot token, scope, revocation
  story). Defer to the theta-phase distribution work; the manual-merge
  path is the right default for a single-operator install.
- **IPv6-only fetch failure handling.** Today, if `ips-v6` fetches but
  `ips-v4` doesn't, the job emits a partial-drift notification. Whether
  to suppress the partial diff and re-fetch both atomically is open.
  Defer until a real failure shows the current shape is wrong.

## Alternatives considered

- **Runtime per-request fetch of the Cloudflare list.** Rejected.
  Per-request third-party HTTP for a trust-list lookup is a
  latency disaster.
- **Boot-time fetch of the Cloudflare list.** Rejected. Boot-time
  third-party HTTP makes process restarts brittle (a Cloudflare 5xx
  prevents Puma from coming up). Boot-time wants to be deterministic.
- **Daily cron cadence instead of weekly.** Considered. The CIDR list
  changes infrequently enough that weekly is sufficient; daily costs
  7x the request volume against Cloudflare for marginal recency. Keep
  weekly; revisit if a drift slips through.
- **Move the trust list off `production.rb` into `AppSetting`.**
  Rejected. The trust list is a deploy-time security configuration,
  not a runtime-rotatable secret. Putting it in the DB invites
  in-product mutation of trust scope, which is the opposite of what
  the trust mechanism is for.

## Date

2026-05-12. [skipci]

## Related

- `app/jobs/cloudflare_trusted_proxies_refresher_job.rb` — the watchdog
  job.
- `config/sidekiq_cron.yml` — Monday 09:00 UTC schedule entry.
- `config/environments/production.rb` — `trusted_proxies` declaration
  and the `Pito::TrustedProxies::CONFIGURED` constant the job diffs
  against.
- `docs/plans/beta/25-login-security-and-new-location-approval/log.md` —
  new-location detection mechanism the drift signal protects.
- `docs/architecture.md` → "Hosting topology" — Cloudflare tunnel
  description (the live deployment shape the watchdog protects).
- ADR 0003 — single-install multi-user. The notification-anchor pattern
  the drift notification rides on lives on a per-install row, not a
  per-user row.
