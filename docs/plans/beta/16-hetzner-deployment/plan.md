# Phase 16 — Hetzner Deployment

> **Goal:** Move Pito off the laptop and onto Hetzner. Use Kamal 2.x for
> orchestration. Configure DNS, secrets, monitoring, automated backups to
> off-site, rollback procedure. Both Pumas (Web and MCP) deploy as separate
> Kamal web roles. End the Beta with Pito running in production-grade
> infrastructure.

**Depends on:** All prior phases. Especially Phase 14 (backup/restore tooling
proven via the mandatory drill) and Phase 15 (security hardening clean) — both
must be complete before deploying real-world data to internet-facing
infrastructure.

**Unblocks:** Theta. From here, Pito is on real infrastructure; Theta begins
distribution thinking.

---

## Why Phase 16 is last

Phase 16 is the last phase intentionally. Until backups are tested (Phase 14),
security is hardened (Phase 15), and observability is in place (Phase 13),
deploying to Hetzner just creates a more fragile version of the laptop setup.
With Phases 13-15 done, the cutover is mostly procedural.

This phase is also where laptop-only assumptions get caught. Every env var that
defaulted to `/home/<user>/...` needs a server path. Every "run this command in
another terminal" workflow needs to work over SSH. Both Pumas need to start
cleanly under Kamal's process management.

---

## In scope

### Hetzner server provisioning

- **Cloud server:** CX22 (4 GB RAM, 2 vCPU) at €4.5/mo to start. Upsize to CPX21
  (8 GB) if memory pressure surfaces during Voyage embedding workloads.
- **OS:** Ubuntu 24.04 LTS or Debian 12
- **Region:** Falkenstein or Helsinki — pick lowest-latency to user
- **SSH:** key-only access; password auth disabled; `pito` user with sudo; root
  login disabled
- **UFW firewall:** deny by default; allow 22 (SSH from anywhere with key-only
  is fine; tighter restriction by IP if user prefers), 80 (HTTP for Lets Encrypt
  or Cloudflare cert provisioning), 443 (HTTPS only). MCP Puma and Web Puma both
  serve over 443 — different domains, same port, distinguished at the
  proxy/load-balancer layer.
- **fail2ban** on SSH (Kamal can install via accessory or it's a manual setup
  step)
- **Automatic security updates** for the OS (`unattended-upgrades` on
  Debian/Ubuntu)

### Kamal 2.x deployment

`config/deploy.yml` declares Pito as a multi-role service:

- **Web role** — Web Puma serving `app.pitomd.com`. Worker count and thread
  count tuned per CX22 capacity.
- **MCP role** — MCP Puma serving `mcp.pitomd.com`. Independent scaling. Same
  Docker image, different Procfile entry / environment.
- **Job role** — Sidekiq worker process. Tuned for the embeddings queue plus
  default queue.
- **Accessories:**
  - `postgres` — `pgvector/pgvector:pg17` image with persistent volume mount
  - `meilisearch` — official image with persistent volume
  - `redis` — official image with persistent volume

Kamal builds the Docker image locally (or on a build host), pushes to a registry
(Docker Hub free tier is fine for a private single-image repo, or self-hosted —
the user picks), deploys via SSH. Zero-downtime deploys via Kamal's blue-green
for the web/mcp roles.

The two web-class roles (Web and MCP) deploy independently. A change that only
touches MCP code can deploy MCP without restarting Web. Kamal supports per-role
deploys.

### Database services in Docker via Kamal accessories

- **Postgres:** `pgvector/pgvector:pg17` image; persistent volume
  `postgres_data`; healthcheck via `pg_isready`
- **Meilisearch:** official image; persistent volume `meili_data`; healthcheck
  via `/health` endpoint
- **Redis:** official image with persistent volume `redis_data`; healthcheck via
  `redis-cli ping`

Volume backups handled by Phase 14's tooling running on the host server (cron +
Pito CLI commands).

### Secrets management

- **Rails master key:** in Kamal secrets file (`.kamal/secrets`). The
  `.kamal/secrets` file is committed encrypted via `kamal secrets`; the key to
  decrypt lives in a separate password manager (1Password / Bitwarden).
- **All third-party API keys** (Voyage, YouTube OAuth, YouTube public,
  Anthropic, Slack if survived, off-site backup): stored in Rails credentials,
  decrypted via the master key at runtime.
- **Off-server secret store:** the user must have the Rails master key in
  1Password / Bitwarden / encrypted storage. Phase 14's runbook documented this;
  Phase 16 enforces it during initial setup.

### DNS cutover

- `app.pitomd.com` and `mcp.pitomd.com` — Cloudflare DNS A records repointed
  from laptop tunnel IP to Hetzner server IP
- Cloudflare proxy (orange cloud) — recommended. Provides DDoS protection, edge
  caching for static assets, and Cloudflare's WAF rules can be layered if useful
  in Theta.
- TLS at origin: **Cloudflare Origin Certificate** (recommended; longer-lived,
  only Cloudflare can validate it, no Lets Encrypt rate-limit concerns).
  Alternative is Lets Encrypt via Kamal — works but more moving parts.
- TTL set low (60s) during cutover; raise to 300-3600s after stability confirmed
  (1+ week of observation)
- `pitomd.com` apex continues pointing at Cloudflare Pages (Phase 6, no change
  here)

### Monitoring

- **Hetzner-internal metrics dashboard** — comes free with the cloud server;
  CPU, memory, disk, network charts
- **Pito-internal metrics** — `/stats` page (Phase 13); same as on the laptop,
  just on production
- **External pinger** — UptimeRobot or Better Stack (free tier sufficient)
  monitoring `https://app.pitomd.com/healthz` and
  `https://mcp.pitomd.com/healthz`. Email alert on downtime.
- **Error tracking** — Sentry / GlitchTip (free tier). Pito reports server-side
  exceptions. Optional but recommended; if not configured, rely on logs.
- **Hetzner email alerts** for high CPU / disk usage

### Logging

- Pito logs to `/var/log/pito/` on the host (mounted as a Docker volume from
  container)
- `logrotate` configured: daily rotation, 30 days retention, gzipped past 7 days
  (matches Phase 13's log discipline)
- Audit logs (MCP namespaces from Phases 1, 6, 9; auth audit from Phase 3 + 12;
  operational audit from Phase 14) all included

### Automated backups + off-site

Phase 14's tooling extends to production:

- Cron on the Hetzner server runs `bin/pito backup:all` daily at 03:00 UTC (or
  whenever lowest traffic)
- **Off-site upload to Hetzner Storage Box or Backblaze B2** (~€3-5/mo for
  storage). Configured via `BACKUP_REMOTE_*` env vars set in Kamal secrets.
- Retention: 30 daily / 8 weekly / 6 monthly (server-local) + 30 daily / 12
  weekly (off-site)
- Backup status alerts via email when last upload > 36h (Phase 13's threshold
  banner becomes an actual email alert in production via a small daemon or
  cron-checked script)
- A second restore drill **on the Hetzner server** before final cutover — proves
  the on-server backup-and-restore tooling works in production conditions

### Production cutover plan

A documented sequence, executed deliberately:

1. Final laptop backup via `bin/pito backup:all` + manual git push of all KB
   repos
2. Provision Hetzner server, run `kamal setup`, verify all containers running
   cleanly
3. Clone the KB repos onto the server: `git clone` for `pito-dev-kb`,
   `pito-website` (and any project-notes roots from Phase 4 — Project Workspace)
   into `/opt/`. The original spec also listed `pito-yt-kb`; that repo was
   dropped on 2026-05-03.
4. Restore Postgres dump on server (using Phase 14's
   `bin/pito restore:postgres`)
5. Restore Meilisearch snapshot on server
6. Verify on server: dashboard renders, search works, related-content queries
   work, KB integration works, all token-based auth still works
7. Run a second restore drill on the server (parallel test environment using
   Docker — same as Phase 14's local drill)
8. Switch DNS A records (Cloudflare); TTL pre-lowered
9. Smoke test from outside the laptop network (mobile data, friend's wifi,
   public coffee shop wifi)
10. Run for 1 week in parallel — laptop tunnel still up as fallback
11. After 7 days of stability, decommission the laptop tunnel for
    `app.pitomd.com` and `mcp.pitomd.com`

### Rollback plan

If anything goes wrong during cutover or in the first week:

- DNS reverts to laptop tunnel IP
- Laptop continues running the production setup as before
- The Hetzner server is left running and debuggable; investigate, fix, retry
  cutover
- Document the exact rollback steps in `pito/docs/runbook.md` and rehearse
  mentally before cutover

### Production runbook

`pito/docs/runbook.md` covers:

- SSH access procedure
- Common diagnostics commands (`kamal status`, `kamal logs`, `docker ps`, log
  file locations)
- Restart procedure per service (Web Puma, MCP Puma, Sidekiq, Postgres, Meili,
  Redis)
- Log inspection workflow
- Backup and restore from production
- Rollback procedure to laptop
- Emergency contacts (just the user; documented for completeness)

### Decommission laptop

- Verify Hetzner stable for 7 days under real usage (not just smoke tests)
- Final laptop backup archived to off-site
- Stop laptop's Cloudflare tunnel for `app.pitomd.com` and `mcp.pitomd.com`
- Laptop becomes pure development environment — local Postgres, local Meili,
  local Redis for dev; no longer serving production
- Update `pito/docs/setup.md` to reflect the laptop's new dev-only role

### Beta retrospective

End of phase: write a Beta retrospective in
`docs/plans/beta/16-hetzner-deployment/log.md`'s final session entry. Topics:

- What worked across the 16 phases
- What was harder than expected
- What got dropped (Slack probe outcome; any other deferred items)
- What was learned about the stack
- Cost summary: Hetzner monthly, Voyage spent so far, YouTube quota usage
  patterns, Anthropic API costs
- Theta thinking: should it happen? what would Theta look like if so?

The retrospective marks the end of Beta.

### Out of scope

- High availability / multi-server (Theta scale concern; one CX22 is fine for
  one user)
- Auto-scaling (overkill)
- Geo-distribution (overkill)
- Database replication (Theta if user count grows; Beta single-server is fine
  with backups + off-site)
- Container registry beyond local-build-and-push (avoid the cost and complexity
  for one image)
- Public CDN beyond Cloudflare (already covered)
- Production-grade external load balancer (Cloudflare proxy serves the role)

---

## Plan checklist

### Provisioning

- [ ] Create Hetzner project; add SSH key
- [ ] Provision CX22 (or CPX21 if Phase 14's restore drill suggests memory
      pressure)
- [ ] Choose region close to user
- [ ] Initial hardening: disable root SSH password, create `pito` user with
      sudo, install Docker, set up UFW, install fail2ban, enable
      unattended-upgrades

### Kamal config

- [ ] Add `kamal` gem to Pito
- [ ] `config/deploy.yml`: declare web role, mcp role, job role, all three
      accessories (postgres, meilisearch, redis)
- [ ] `.kamal/secrets`: master key, all third-party API keys, BACKUP*REMOTE*\*
      config
- [ ] Run `kamal setup` — provisions all services on the Hetzner server
- [ ] Run `kamal deploy` — first deploy of the application image
- [ ] Verify on server: SSH, `kamal status` shows all containers running, logs
      clean

### Database initial state

- [ ] Take a fresh `pg_dump` of laptop Pito
- [ ] Take a fresh Meili snapshot
- [ ] On the server: `git clone` each KB repo into `/opt/pito-dev-kb` and
      `/opt/pito-website` (plus any project-notes roots from Phase 4 — Project
      Workspace). The original spec also cloned `pito-yt-kb`; that repo was
      dropped on 2026-05-03.
- [ ] Set Kamal env vars: `PITO_DEV_KB_PATH=/opt/pito-dev-kb`,
      `PITO_WEBSITE_PATH=/opt/pito-website` (plus any project-notes path env
      vars introduced by Phase 4)
- [ ] Restore Postgres dump on server
- [ ] Restore Meili snapshot on server
- [ ] Verify counts match laptop

### DNS cutover

- [ ] Test Hetzner IP responds correctly via direct IP test
      (`curl -H "Host: app.pitomd.com" https://<server-ip>` with cert
      verification disabled for the test)
- [ ] Lower Cloudflare DNS TTL to 60s
- [ ] Change `app.pitomd.com` and `mcp.pitomd.com` A records to Hetzner server
      IP
- [ ] Cloudflare proxy ON (orange cloud)
- [ ] Origin TLS: install Cloudflare Origin Certificate on the server
      (configured via Kamal proxy/Traefik)
- [ ] Verify HTTPS works end-to-end from external network
- [ ] After 7+ days stability, raise TTL to 300-3600s

### Monitoring + alerting

- [ ] UptimeRobot account; monitors for `https://app.pitomd.com/healthz` and
      `https://mcp.pitomd.com/healthz`; email alert configured
- [ ] Sentry/GlitchTip set up; Pito reports exceptions; user verifies alert
      delivery via a deliberate test exception
- [ ] Hetzner email alerts for high CPU / disk usage configured
- [ ] Phase 13's `/stats` page accessible at `app.pitomd.com/stats`

### Backups + off-site

- [ ] Hetzner Storage Box (or Backblaze B2 / Wasabi) account created
- [ ] `BACKUP_REMOTE_*` env vars set in Kamal secrets
- [ ] Cron on the server: daily backup + upload at 03:00 UTC
- [ ] **Second restore drill on the Hetzner server** — same procedure as Phase
      14, on the production-class hardware
- [ ] Email alert on backup failure (cron sends email if non-zero exit)

### Decommission laptop

- [ ] Verify Hetzner stable for 7 days under real usage (track in `log.md`)
- [ ] Final laptop backup archived to off-site
- [ ] Stop laptop Cloudflare tunnel for `app.pitomd.com` and `mcp.pitomd.com`
- [ ] Laptop reverts to dev-only

### Documentation

- [ ] `pito/docs/deploy.md` (new): Kamal config, deploy procedure, environment
      setup, two-Puma role explanation
- [ ] `pito/docs/runbook.md` (new): operational procedures, common issues,
      rollback steps
- [ ] Update `pito/docs/architecture.md`: production deployment topology with
      both Pumas as Kamal web roles
- [ ] Update `pito/docs/setup.md`: laptop is dev-only; production runs on
      Hetzner
- [ ] Beta retrospective in `docs/plans/beta/16-hetzner-deployment/log.md`

### Validation — smoke test from external network

This is the validation that matters most. Run from a network OTHER than the
laptop's:

- [ ] Web app: `app.pitomd.com` loads, login works, dashboard renders, search
      works, all major pages render
- [ ] MCP: Claude mobile connects to `mcp.pitomd.com` with a token; tool calls
      succeed
- [ ] Terminal app: `pito-sh` from a different machine completes OAuth flow
      against production; navigates all screens
- [ ] Slack (if survived): commands work
- [ ] Landing: `pitomd.com` loads (unchanged from Phase 6)
- [ ] Background jobs: Sidekiq web at `app.pitomd.com/sidekiq` shows activity
      from the server
- [ ] Scheduled YouTube sync runs at 03:00 UTC and completes (verify next
      morning)
- [ ] Voyage embedding job runs and writes to server's Postgres
- [ ] Backup ran overnight; off-site copy verified in remote bucket
- [ ] All RSpec specs pass against staging environment (a parallel
      non-production deploy used for testing)
- [ ] Brakeman, bundler-audit, Dependabot — clean (already from Phase 15)

---

## Specs requirements

- Healthcheck endpoint (`/healthz`) spec — returns 200 when DB + Redis + Meili
  reachable; 503 when any dependency down. Same endpoint exposed on both Pumas.
  Both endpoints exempt from rate limits.
- Production env config spec — asserts critical env vars are set (run against
  staging env, not production).
- Backup automation spec — cron entry exists, script runs successfully (run
  against staging env).

## Security requirements

- All secrets in Kamal-encrypted secrets file; nothing committed in repo.
- SSH key-only auth; no password.
- UFW: deny by default; only 22/80/443 open.
- Fail2ban active.
- HTTPS-only end-to-end. HTTP redirects to HTTPS via Cloudflare.
- Cloudflare proxy provides edge protection.
- Origin certs from Cloudflare with auto-renewal handled by Cloudflare itself.
- Server logs (`/var/log/pito/`) reviewed during cutover for anomalies.
- Logrotate to 90 days, gzipped past 7 days (matches Phase 13).
- All Phase 15 hardening continues to apply (CSP, rate limits, headers — same
  code, same effect on the server).
- `pito/docs/design.md`: no changes (production deploy is infrastructure; UI
  unchanged).

## Manual testing checklist

The user runs through this before commit (and during the 7-day parallel running
window):

1. SSH to Hetzner: `ssh pito@<server-ip>` — works
2. `kamal status` — all containers running (web role, mcp role, job role,
   postgres, meilisearch, redis)
3. From phone (mobile data): visit `app.pitomd.com` — loads, login works,
   dashboard renders
4. From phone: visit `pitomd.com` — landing page loads (unchanged from Phase 6)
5. From phone: connect Claude mobile to `mcp.pitomd.com`; call a tool; verify
   response
6. From a different machine: run `pito-sh`; OAuth flow completes against
   production; tool calls work
7. Trigger a manual sync from Settings → confirm Sidekiq executes on the server
   (visible in `/sidekiq`), not the laptop
8. SSH to server; run `bin/pito backup:all`; confirm backup files created
   locally; off-site upload runs successfully
9. Cause a deliberate test exception (a controller endpoint that raises if a
   known-only-to-user query param is set) → verify Sentry receives the report
   and alert reaches user's email
10. UptimeRobot dashboard: both healthcheck endpoints showing green
11. Wait 7 days of real usage; track stability in `log.md`
12. Decommission laptop tunnel; verify all services still respond exclusively
    from the Hetzner server
13. `bundle exec rspec` against staging — green
14. Final session: write Beta retrospective in `log.md`

---

## Challenges to anticipate

- **First-time Kamal setup is fiddly.** Budget several hours for the first
  deploy. Kamal docs are good but real-world snags happen — Docker version
  mismatches, network rules, file permission issues. Subsequent deploys are
  minutes.
- **DNS propagation.** Allow time after cutover; some DNS resolvers cache
  aggressively. The 60s TTL helps but doesn't eliminate it. Plan the cutover at
  a time when the user can monitor for an hour.
- **TLS cert chain.** Cloudflare Origin Cert is recommended (15-year cert that
  only Cloudflare can validate). Alternative: Lets Encrypt via Kamal — works but
  adds renewal complexity and rate-limit risk. Pick one path; document.
- **Persistent volume backup vs container backup.** Ensure Postgres/Meili/Redis
  volumes persist across deploys. Kamal accessories handle this if `volumes`
  directive is used — verify in `config/deploy.yml`. A volume that gets
  destroyed on `kamal redeploy` is a disaster.
- **Memory pressure on CX22.** 4 GB is enough for one user's Postgres + Meili +
  Redis + Web Puma + MCP Puma + Sidekiq, but it's not generous. Monitor; if
  memory consistently > 80%, upsize to CPX21 (8 GB, ~€8.5/mo).
- **OAuth redirect URIs.** Google OAuth requires registered redirect URIs.
  Production redirect URIs (`app.pitomd.com/auth/google/callback`) might already
  be registered from Phase 7's Cloudflare-tunneled dev — verify or add.
- **Laptop tunnel decommission timing.** Don't shut down the laptop tunnel until
  Hetzner has been stable for at least one full week of actual use. Premature
  decommission means a partial outage if Hetzner hiccups.
- **Sidekiq scheduled jobs running on both laptop and server during parallel
  period.** During the 7-day overlap, the laptop should NOT run scheduled jobs
  (would double-sync, double-bill quota). Disable Sidekiq schedules on the
  laptop before cutover; the laptop becomes a "warm standby" not a "hot active"
  instance.
- **Both Pumas under Kamal.** Kamal's web role is typically singular. Declaring
  two web-class roles (one for `app.pitomd.com`, one for `mcp.pitomd.com`)
  requires careful config — separate `Procfile.web` and `Procfile.mcp` entries,
  separate Traefik routing rules per role. Test thoroughly in staging before
  production cutover.

---

## Confirmation gates for Claude Code

Before executing, confirm with the user:

1. The user has a Hetzner account and budget for ~€10/mo (server + storage box).
2. Cloudflare proxy is acceptable (vs DNS-only). Recommend proxy for DDoS + edge
   cache + Origin Cert convenience.
3. Sentry / GlitchTip preference. Or skip and rely on server logs only —
   acceptable for single-user.
4. The user is OK with a 1-week parallel running period (laptop + Hetzner)
   before decommissioning the laptop tunnel.
5. The user understands that this phase is the end of Beta. Beta retrospective
   is part of the deliverable.
6. CX22 is the starting size. Upsize to CPX21 if memory pressure surfaces during
   initial testing.
7. Cloudflare Origin Cert vs Lets Encrypt — pick one path. Recommend Origin
   Cert.
8. Off-site backup destination: Hetzner Storage Box (recommended; same vendor
   billing) vs Backblaze B2 vs Wasabi. Confirm.
