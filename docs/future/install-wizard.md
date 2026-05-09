# Install wizard

## Status

**Future / deferred. Not on the v1 roadmap.** Captured here to preserve the
design constraint while doing today's work. The wizard itself is far-future;
this doc keeps the shape visible so today's secret-config flows are
wizard-friendly when the wizard finally lands.

## Why it matters today

Even though the wizard is deferred, today's design choices should keep it
possible. Every secret-config feature shipped TODAY should land in a way the
wizard can sequence later without rework.

- Every credential pito asks for (YouTube OAuth, IGDB / Twitch, Voyage AI,
  Cloudflare token, Discord webhooks, Slack webhooks) must be configurable
  through a database / UI path, not only through `Rails.application.credentials`
  editing.
- Settings UI for each credential exists FROM DAY ONE, even if today only the
  operator (the user) uses it.
- No "edit `config/credentials.yml.enc` and restart" — that's a developer
  pattern; the wizard era requires UI-only flows.
- Every "service connection" surface follows a self-validating pattern: enter
  credentials, click Test, see green / red.
- This already aligns with current pito direction (single-install + multi-user,
  settings UI per service) — the wizard just sequences these settings flows for
  first-time install.

## What the wizard does

Lifted from
`docs/notes/2026-05-09-19-56-01-drop-tenant-and-future-install-wizard.md` (part
2):

- **Resumable** — state persisted to DB on every step; killed mid-wizard, picks
  up at the last unconfirmed step on next launch.
- **One service per screen** — each integration its own screen, skippable with
  explicit "Skip for now" buttons. Re-entering a skipped service later is just
  navigating back to that screen via Settings.
- **Self-validating** — submitting a screen tests the credential live (or a
  representative call) and shows green / red feedback. No "wait until later to
  find out you typed your client secret wrong."
- **Locked until done** — main app routes redirect to the wizard until the user
  confirms "finish."
- **Reachable after completion** — accessible from Settings as "Re-run setup
  wizard" but no longer mandatory.
- **No file editing** — everything writes to DB / runtime config. If the wizard
  can't write it, it doesn't belong in the wizard.

## Suggested screen sequence

Order roughly by dependency — earlier screens unlock later ones.

1. **Welcome / app basics** — required.
   - App name (cosmetic, e.g. "Andrei's pito")
   - Time zone (IANA, defaults from browser)
   - Public URL (the hostname users will reach this install at, e.g.
     `pito.example.com` or `localhost:3000`)
2. **First user (admin)** — required.
   - Email, password, display name. This account can configure everything else.
3. **YouTube OAuth (Google Cloud project)** — required (core of pito).
   - Inline guidance: open Google Cloud Console, create a project, enable
     YouTube Data API v3 and YouTube Analytics API, create OAuth credentials,
     paste them here. Link button to the right Google Cloud page.
   - Fields: client ID, client secret, redirect URI (auto-filled from "public
     URL" + the right path).
   - Prerequisite: "Public URL" from screen 1 (used to build the redirect URI).
4. **IGDB / Twitch app** — skippable if the user doesn't care about games.
   - Inline guidance: go to dev.twitch.tv, register an app, paste client ID and
     secret here.
   - Fields: client ID, client secret.
5. **Voyage AI** — skippable.
   - Fields: API key.
   - Marked "advanced / optional — used for [whatever Voyage ends up doing in
     pito]."
6. **Discord webhooks** — skippable.
   - 0..N entries. Each entry: name, webhook URL, digest time (default 09:00 in
     the install's tz), severity threshold (default `urgent` immediate, all in
     digest).
7. **Slack webhooks** — skippable. Same shape as Discord.
8. **Cloudflare** — skippable but recommended for any non-localhost install.
   - Three paths, user picks one:
     - **Path A — DNS only.** User has a public IP / VPS. Fields: zone (domain),
       API token (scoped to DNS edit on that zone), desired hostname. Wizard
       creates the A or CNAME record. User still needs a reverse proxy in their
       compose (Caddy default, ships with pito-server's compose).
     - **Path B — `cloudflared` tunnel.** User has no public IP (home server,
       NAT). Wizard runs `cloudflared tunnel login` (or guides through it via
       browser auth flow), creates a named tunnel, writes the tunnel config,
       ensures the `cloudflared` sidecar container is enabled in the running
       compose. Hostname becomes `<sub>.<their-zone>` routed through
       Cloudflare's tunnel network.
     - **Skip.** User configures their own reverse proxy / DNS / SSL externally.
       Wizard records the choice and moves on.
   - Prerequisite: "Public URL" from screen 1.
9. **Review & finish** — required.
   - Show every configured + skipped service with green / red / dash indicators.
   - "Edit any of these later from Settings" link.
   - Confirm button writes the "setup complete" flag, kicks off any first-time
     background jobs (e.g. enqueue an initial channel-list fetch from YouTube
     once OAuth is done), redirects to the dashboard.

## Cloudflare specifics

Two killer use cases for `cloudflared`:

- **Home server with no public IP.** Tunnel makes pito reachable at a real
  hostname without router config, port forwarding, dynamic DNS, or self-signed
  certs.
- **Privacy / DDoS shielding.** Cloudflare proxies the traffic, the real origin
  IP isn't exposed.

For pito specifically, this matters because the natural pito user (a YouTube
creator running their own instance on a Mac mini, a NAS, or a small VPS) likely
doesn't want to deal with reverse proxy + DNS + SSL themselves. `cloudflared`
collapses all of that into one wizard screen.

Implementation sketch: pito-server's docker-compose includes a `cloudflared`
service that's disabled by default. The wizard's Cloudflare-Path-B writes the
tunnel credentials to a known file path under `/storage`, flips the service on,
and reloads the compose. Existing pattern — see Cloudflare's Docker docs for
`cloudflared tunnel` and the `tunnel run` command using a credentials JSON file.

## What stays out of the wizard (deliberately)

- **Database choice / config.** Pito picks one default; the user doesn't choose.
- **SMTP for email.** Email is deferred per the calendar note. When it comes
  back, it'll be its own wizard screen.
- **Backup destination.** Pito has built-in local backup (per the ONCE
  inspiration). Offsite backup is a future feature with its own UI, not a wizard
  step.
- **Migrations.** Run automatically on container boot. Not a thing the user
  does.
- **Anything that requires editing files on the host.** If the wizard can't
  write it, it doesn't belong in the wizard.

## Distribution shape (for context only)

The wizard is what makes pito distributable to non-developers without internal
docs. End-state experience:

1. User downloads / pulls / installs pito-server (one command via ONCE-style
   installer per the ONCE distribution research note).
2. pito-server boots, opens at localhost (or wherever they pointed it at).
3. User opens the URL in a browser → wizard.
4. ~10 minutes later, pito is configured and running.
5. They never read a dev doc.

That's the bar.

## Relationship to other deferred work

- **ONCE the platform** —
  `docs/notes/2026-05-09-19-32-19-once-distribution-model-research.md` covers
  the ONCE platform research. Decision: pito does NOT go on ONCE. The wizard
  concept lives independently of ONCE.
- **Single-binary installer** — Option 1 from the ONCE research note. The wizard
  runs _inside_ pito after pito is installed; the installer (curl-bash → binary
  → run) is what gets pito onto the user's machine. Two separate tools.
- **Tenant model** — wizard assumes single-install (post-tenant-drop direction).
  If pito ever goes SaaS, the wizard reshapes for per-tenant onboarding; that's
  well outside current scope.

## Today's design constraints derived from this future

A short checklist that guides every secret-config feature shipped TODAY. When
implementing any new integration, audit against this list.

- [ ] Credential entered through a Settings UI form (not requires-edit
      `credentials.yml.enc`).
- [ ] Form has a "Test connection" button that hits the live service.
- [ ] Failure surfaces a useful error (not "credential rejected" — "Twitch
      returned 401: client_id invalid").
- [ ] Credential value never echoed back; UI shows "configured" / "not
      configured" + last-rotated timestamp.
- [ ] Credential can be cleared / rotated through the same UI.
