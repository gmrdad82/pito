# Phase 15 — Security Hardening Pass

> **Goal:** Comprehensive security review across the entire Beta-stage codebase
> before production deployment. Per-phase checks (Brakeman + bundler-audit +
> Dependabot + design.md review) caught issues phase by phase; this phase goes
> deeper. Threat modeling, header hardening for both Pumas, comprehensive rate
> limiting, CVE sweep across all five repos, dependency audit, secrets review,
> MCP scope audit, OAuth flow audit. The deliverable is a clean security posture
> and a documented hardening report.

**Depends on:** All prior phases.

**Unblocks:** Phase 16 (Hetzner deployment with maximal confidence).

---

## Why Phase 15 is now

Per-phase security checks ran on every phase — Brakeman, bundler-audit,
Dependabot, design.md alignment. They caught issues at the boundary of each
change. Phase 15 isn't fixing things those checks missed; it's the
**comprehensive integrated review** that no single phase could provide:

- Threat model against the full system, not just the phase being built
- Headers tuned for production with full knowledge of what each Puma serves
- Rate limits across every endpoint, not just the high-risk ones each phase
  happened to add
- CVE sweep against the now-stable dependency graph
- Cross-repo secret leakage scan (`pito`, `pito-dev-kb`, `pito-website`,
  `pito-sh`; the originally-listed `pito-yt-kb` was dropped on 2026-05-03 —
  channel-level notes will reuse the project-notes pattern from Phase 4 —
  Project Workspace)

Placing this immediately before Hetzner means production cutover happens with
maximal confidence. Issues found here block Phase 16 until resolved.

The phase is large. Some sub-tasks may take a full session each (the threat
model alone is multi-hour work). The user is expected to budget time
accordingly.

---

## In scope

### Comprehensive scanner sweep

- **Brakeman** with all checks enabled, including ones the per-phase scans
  skipped for performance. Run on the full `pito` codebase. Review every result;
  fix or document waiver in `security.md`.
- **bundler-audit** deep pass — all gems, including transitive dependencies.
  Resolve every advisory or document waiver.
- **Dependabot** dashboard review across all five repos. Update gems where
  compatible majors permit; document waivers for incompatible-but-known-safe
  versions.
- **`cargo audit`** for `pito-sh` Rust dependency CVEs.
- **`gitleaks detect`** on each of the five repos (or equivalent secret
  scanner). Historical commits inspected for accidentally committed secrets. Any
  historical leak: rotate the secret immediately, document in `security.md`.
- **CVE sweep** against critical dependencies by name: Rails, Puma, Sidekiq,
  Redis, Postgres driver (`pg`), Meilisearch, Doorkeeper, OmniAuth,
  `omniauth-google-oauth2`. Cross-reference with CVE databases for any open
  advisories that bundler-audit might have missed.

### HTTP security headers (per Puma)

The two Pumas have different content profiles and warrant different header
policies:

**Web Puma (`app.pitomd.com`):** serves HTML. Needs Hotwire-friendly CSP.

- `Content-Security-Policy` — strict but Hotwire-compatible. Allow inline styles
  only via nonce; allow inline scripts only for Stimulus controllers (or
  restructure to remove them entirely). Use
  `Content-Security-Policy-Report-Only` first to find violations during testing;
  promote to `Content-Security-Policy` once clean.
- `Strict-Transport-Security: max-age=31536000; includeSubDomains; preload`
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY` (or via CSP `frame-ancestors 'none'`)
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy: geolocation=(), camera=(), microphone=(), payment=()` —
  minimal, all denied unless needed

**MCP Puma (`mcp.pitomd.com`):** serves JSON only. Can be much stricter.

- `Content-Security-Policy: default-src 'none'; frame-ancestors 'none'` — JSON
  responses don't need to load anything; lock everything down
- Same HSTS, no-sniff, frame-options, referrer-policy as Web Puma
- No `Permissions-Policy` needed (no browser features in scope)

Use the `secure_headers` gem for declarative configuration; override per-Puma
where needed (`config/secure_headers_mcp.rb` loaded by MCP Puma's `Procfile`
entry).

### Comprehensive rate limiting via Rack::Attack

Phase 12 added basic login throttling. Phase 15 sweeps every endpoint:

**Web Puma rate limits:**

- `/login` — 5 per IP per 5 min (already from Phase 12)
- `/passwords/new`, `/passwords/edit` — 5 per IP per hour
- `/oauth/token` — 30 per client_id per minute
- `/oauth/authorize` — 30 per IP per minute
- `/api/*` — 60 per token per minute (configurable per-token in Settings if
  specific tokens need different limits)
- `/auth/google` — 5 per IP per minute (prevents OAuth flow spam)
- General catch-all: 600 req/min per IP for unauthenticated requests, 1200 for
  authenticated

**MCP Puma rate limits:**

- All MCP HTTP transport requests — 120 per token per minute (AI clients tend to
  burst, but a single conversation shouldn't sustain hundreds of calls per
  minute)
- General catch-all: 200 req/min per IP for unauthenticated (which should never
  succeed anyway since MCP requires bearer auth)

**Slack endpoints (if Phase 5 verdict was YES):**

- `/slack/events`, `/slack/commands` — 30 per IP per minute (already from Phase
  5; reaffirmed)

**Healthcheck exemption:**

- `/healthz` exempt from all rate limits (Phase 16's external pinger needs
  unconstrained access)

### OWASP Top 10 review

Document `pito/docs/owasp_review.md` with a section per category and the
application's posture:

1. **Broken access control** — tenant scoping audit (Phase 12 covered most;
   reverify in this pass; spot-check controllers added since Phase 12)
2. **Cryptographic failures** — encryption at rest (AR Encryption), in transit
   (HTTPS only), token handling (digest comparison constant-time)
3. **Injection** — SQL injection (ActiveRecord parametrization throughout; raw
   SQL audit), command injection (shell-out audit for `git`, `pg_dump`, image
   processing), template injection
4. **Insecure design** — review the threat model (below)
5. **Security misconfiguration** — production config audit
   (config/environments/production.rb), default credentials, debug endpoints
   disabled
6. **Vulnerable components** — dependency state from the scanner sweep
7. **Auth failures** — session/token/OAuth audit (below)
8. **Software/data integrity** — package signature verification (Bundler
   verifies gem signatures; verify Cargo does similar), MCP tool dispatch
   verification
9. **Logging failures** — security events logged appropriately (login attempts,
   token creation/revocation, scope denials, sandbox rejections, cross-tenant
   attempts)
10. **SSRF** — external URL fetching audit. Pito makes outbound calls to YouTube
    API, Voyage API, Slack API, Anthropic API. All use known fixed URLs from
    credentials/constants — no user-supplied URLs reach the HTTP client. Verify.

Each category gets a finding ("compliant" / "compliant with note" / "needs
attention") and a disposition.

### Threat model document

`pito/docs/threat_model.md` (new):

- **Assets:** user data (channels, videos, KB content), OAuth tokens (Google),
  API keys (Voyage, Anthropic, YouTube public, Slack), source code (five repos),
  the Pito codebase itself running with the user's credentials, the Hetzner
  server (Phase 16)
- **Threat actors:** external attacker (random scanning), targeted attacker
  (someone who knows about Pito), compromised dependency (supply chain),
  shoulder surfer / device theft, accidental insider (the user themselves making
  a mistake — relevant single-tenant)
- **STRIDE analysis** per asset: Spoofing, Tampering, Repudiation, Information
  disclosure, Denial of service, Elevation of privilege
- **Mitigations** documented per threat
- **Residual risks** documented — every system has them; honesty serves the
  operator

This is a single-user threat model. Defense against nation-states, APTs,
sophisticated phishing campaigns is out of scope (per `beta.md`'s pragmatism).
The threat model is appropriate for "single user, single laptop, single Hetzner
server, valuable but not critical YouTube content."

### Secrets audit

- Inventory every Rails credential. For each: needed? rotated recently? Stale
  credentials removed.
- Inventory `.env` and `.env.development` keys. No production secrets here.
  Confirm.
- `gitleaks detect --source <repo>` on all five repos. Inspect history (default
  depth is full history). If any historical leak: rotate the secret immediately
  and add to `security.md`.
- Document the credential inventory in `pito/docs/security.md`.

### MCP scope audit

- Build a script that enumerates every MCP tool, dumps its declared required
  scope, asserts a corresponding spec exists that exercises scope rejection
- Document the tool → scope mapping in `pito/docs/mcp.md` (verify still accurate
  after all the additions)
- Sandbox stress test: each sandbox (`Dev::Sandbox`, `Yt::KbSandbox`,
  `Website::Sandbox`) gets stress-tested for race conditions (TOCTOU), symlink
  escape via various OS path tricks, encoded traversal in filenames, null bytes,
  control characters, mixed encoding

### OAuth flow audit (Doorkeeper from Phase 12)

- Authorization code single-use enforced (try replaying a used code; verify
  rejection)
- PKCE required for public clients (try without PKCE for `pito-sh`; verify
  rejection)
- State parameter validated (try with mismatched state; verify rejection)
- Refresh token rotation (use a refresh token; verify the old one is revoked,
  new one returned)
- Token introspection / revocation endpoints work
- Redirect URI strict matching (try with a slight redirect URI variation; verify
  rejection — no wildcards in production)

### Slack flow audit (if Phase 5 survived)

- Signing secret validation tested under various failure modes
- Replay attack window (5 min) enforced (forge a request with old timestamp;
  verify rejection)
- Bot scopes minimized (no scope granted that isn't actively used)

### Image upload audit (Phase 11 thumbnails)

- Server-side MIME validation via magic bytes (extension trust forbidden)
- Image processing in `ruby-vips` (no shell-out; memory-bounded)
- File size hard limit enforced before processing
- EXIF data stripped on every uploaded image

### Audit log review

- Every audit log file: format consistent, permissions 0600, rotation configured
  (logrotate or Ruby Logger rotation)
- Sensitive content NOT in logs: no full bearer tokens, no full PII, no OAuth
  tokens, no passwords. Token last-4 only.
- Authentication events logged: login, logout, password change, token creation,
  token revocation, scope denial, sandbox rejection
- Log files inventoried in `pito/docs/security.md`

### Dependency update sweep

- All Ruby gems to latest stable within compatible majors (`bundle outdated`)
- All Rust crates in `pito-sh` to latest stable (`cargo outdated`)
- Major version upgrades evaluated case-by-case — only upgrade if
  security-driven or low-risk
- After updates: full RSpec + cargo test + manual smoke test of all major flows

### Out of scope

- Penetration testing by external party (Theta concern if Pito ever has external
  users)
- Bug bounty program (Theta)
- Automated DAST scanning in CI (overkill for single-user; document option for
  Theta)
- HSM-backed credential storage (overkill)
- Compliance certifications (SOC2, etc.) — Theta enterprise concern
- Red team exercises (Theta)

---

## Plan checklist

### Scanner sweep

- [ ] Brakeman full pass: `bundle exec brakeman -A --color`; review every
      result; fix or document waiver in `security.md`
- [ ] bundler-audit: `bundle exec bundle-audit check --update`; clean
- [ ] Dependabot dashboard review across all five repos; address every open
      alert
- [ ] `cargo audit` in `pito-sh`; clean
- [ ] `gitleaks detect` (or `trufflehog`) on each of the five repos; review
      history; rotate any leaked secrets; document in `security.md`
- [ ] CVE name-based sweep on critical dependencies; cross-reference advisories

### Headers

- [ ] Add `secure_headers` gem
- [ ] Configure Web Puma headers (Hotwire-compatible CSP, HSTS, frame, referrer,
      permissions)
- [ ] Configure MCP Puma headers separately (strict CSP for JSON-only)
- [ ] Test CSP in Report-Only mode first; promote to enforcement once clean
- [ ] Verify all major flows still work under enforced CSP (file upload, Hotwire
      stream, Stimulus controllers, search, OAuth flows)

### Rate limiting

- [ ] Implement Rack::Attack rules per the in-scope list above
- [ ] Apply to both Pumas (rules are shared via Rails initializer; both Puma
      processes load the same)
- [ ] `/healthz` endpoint exempt from rate limits
- [ ] Specs for each rule: throttle triggers correctly; throttle resets after
      window; healthcheck never throttled

### OWASP Top 10

- [ ] Document `pito/docs/owasp_review.md` with a section per category
- [ ] Assign disposition (compliant / compliant with note / needs attention) per
      category
- [ ] Address findings; document waivers with rationale

### Threat model

- [ ] Create `pito/docs/threat_model.md`
- [ ] Asset inventory
- [ ] STRIDE analysis per asset
- [ ] Mitigations table
- [ ] Residual risks list
- [ ] **Review with the user** — this is not just author-it-and-move-on; the
      user reads it and confirms the threat model matches their actual risk
      tolerance

### Secrets sweep

- [ ] `gitleaks detect --source ~/Dev/pito` — clean (or rotate + document)
- [ ] Same for `pito-dev-kb`, `pito-website`, `pito-sh` (`pito-yt-kb` was
      dropped 2026-05-03; channel/video notes reuse the Phase 4 — Project
      Workspace project-notes pattern)
- [ ] Inventory of all Rails credentials with descriptions in
      `pito/docs/security.md`

### MCP audit

- [ ] Script enumerating every MCP tool with its required scope
- [ ] Verify spec exists for each tool's scope rejection
- [ ] Sandbox stress test specs: TOCTOU, symlink escape, encoded traversal, null
      bytes, control chars, mixed encoding

### OAuth audit

- [ ] Test authorization code single-use enforcement
- [ ] Test PKCE-required for public clients
- [ ] Test state parameter validation
- [ ] Test refresh token rotation
- [ ] Test redirect URI strict matching

### Slack audit (conditional)

- [ ] If Phase 5 survived: signing secret tests, replay window test, bot scope
      minimization

### Image upload audit

- [ ] Magic-byte MIME validation tests
- [ ] EXIF stripping tests
- [ ] File size enforcement tests
- [ ] Memory-bounded image processing

### Audit logs

- [ ] Format consistency review across all audit log files
- [ ] Permissions: every audit log file is `chmod 600`
- [ ] Rotation configured (logrotate or Ruby Logger rotation; 90 days, gzipped
      past 7 days)
- [ ] Sample log entries: no secrets, no full PII, no full tokens

### Dependency updates

- [ ] `bundle outdated`; review; conservative updates within compatible majors
- [ ] `cargo outdated`; review; conservative updates
- [ ] Full RSpec + cargo test + manual smoke after updates

### Documentation

- [ ] `pito/docs/security.md` (new): comprehensive security posture, what's
      protected and how, master-key handling, incident response basics
- [ ] `pito/docs/threat_model.md` (above)
- [ ] `pito/docs/owasp_review.md` (above)
- [ ] Update `pito/docs/architecture.md` with security layers documented

### Validation

- [ ] All RSpec specs pass
- [ ] Brakeman, bundler-audit, Dependabot, cargo audit, gitleaks — all clean (or
      all waivers documented)
- [ ] Manual: every rate limit triggers correctly when exceeded
- [ ] Manual: CSP doesn't block any functionality (test all major pages with
      browser DevTools network/console panels)
- [ ] Manual: HSTS header present on every response from both Pumas
- [ ] Manual: `pito/docs/security.md` and `threat_model.md` reviewed by user —
      not just authored

---

## Specs requirements

- One spec per Rack::Attack rule asserting throttle triggers, resets, and never
  throttles `/healthz`.
- CSP-related specs: pages render with CSP header set; no inline-without-nonce
  violations under the production CSP.
- Sandbox stress tests: TOCTOU race attempts, symlink escape, encoded traversal,
  null bytes, control chars.
- MCP tool scope enforcement spec: meta-test that iterates all tools and asserts
  a corresponding scope-rejection spec exists.
- OAuth flow specs: code single-use, PKCE-required, state validation, refresh
  rotation, redirect URI matching — each verifies rejection of the corresponding
  bypass attempt.
- Image upload specs: extension-mismatch rejection, EXIF strip verification,
  oversized file rejection.

## Security requirements

This entire phase is the security requirement. By phase end:

- Brakeman: 0 unwaived warnings.
- bundler-audit: 0 unwaived advisories.
- Dependabot: 0 open alerts (all resolved or documented waivers).
- `cargo audit`: 0 unwaived advisories.
- `gitleaks`: 0 detections in any of the 5 repos' history (or all rotated and
  documented).
- Every HTTP response has HSTS, CSP, X-Content-Type-Options, X-Frame-Options or
  `frame-ancestors`, Referrer-Policy.
- Both Pumas serve appropriate-for-their-content CSP.
- Every non-public endpoint rate-limited.
- Threat model documented and reviewed by user.
- OWASP Top 10 addressed with documented dispositions.

## Manual testing checklist

The user runs through this before commit:

1. Run all automated scanners (Brakeman, bundler-audit, cargo audit, gitleaks);
   confirm clean
2. Browser DevTools → Network on every major page → verify all 5 security
   headers present on both Pumas
3. Browser DevTools → Console → no CSP violations on any page (login, dashboard,
   channel show, video show, search, settings, every flow)
4. Burst 100 logins to `/login` from one IP → verify throttle kicks in at
   attempt 6
5. Burst 100 API calls to a token-protected endpoint → verify per-token throttle
6. Burst 100 MCP HTTP requests → verify MCP Puma's per-token throttle
7. Try uploading a PNG renamed `.jpg` thumbnail → server rejects via magic bytes
   despite extension
8. Inspect Rails credentials list → all keys still needed; nothing stale
9. Read `pito/docs/threat_model.md` end-to-end with the user; agree on residual
   risks
10. Read `pito/docs/security.md` end-to-end; confirm operator understanding
11. `bundle exec rspec` — green

---

## Challenges to anticipate

- **CSP without breaking pages.** Strict CSP often blocks legitimate inline
  styles, Hotwire partials, Stimulus actions. Iterate. Use
  `Content-Security-Policy-Report-Only` first to find violations, then promote.
- **Major-version dependency update.** If a Rails major bump is needed for
  security, that's multi-day work. Stay on the current major if no critical CVE
  forces a jump.
- **Brakeman false positives.** Waivers are normal. Document each one with
  reasoning in `security.md`.
- **Threat model scope creep.** Keep it pragmatic. Single-user Beta doesn't need
  defense against nation-state actors. Document at the level appropriate for
  Pito's actual threat surface — don't inflate the model just to look thorough.
- **Header ordering on Cloudflare.** Cloudflare may add or modify headers. Test
  both at the origin and through the Cloudflare proxy/CDN.
- **Dual-Puma CSP differences.** Web Puma needs Hotwire-friendly CSP; MCP Puma
  can be ultra-strict. Two configurations, not one. Verify both are loaded
  correctly per Puma.
- **Rate limit shared store.** Rack::Attack uses Rails cache by default; for
  cross-Puma rate limit accuracy (a token used against both Pumas should share
  its budget), ensure the cache is Redis-backed (already the case from Alpha —
  verify).
- **`gitleaks` on the dev-kb repos.** Plans and logs may reference secrets by
  name (e.g., `VOYAGE_API_KEY`); these aren't actual leaks but can trip the
  scanner. Use `.gitleaks.toml` to whitelist obvious false positives.

---

## Confirmation gates for Claude Code

Before executing, confirm with the user:

1. The user is OK with potentially significant time on this phase (multi-session
   effort; a thorough security pass cannot be rushed).
2. Major dependency updates may break things; the user agrees to budget time for
   fixes.
3. The user agrees with the OWASP Top 10 documentation as the level-of-rigor
   target — not deeper, not shallower.
4. The threat model gets reviewed by the user — not just authored by Claude
   Code. The user reads it end-to-end and confirms.
5. The user accepts that this phase blocks Phase 16. Issues found here delay
   Hetzner deployment until resolved.
6. CSP enforcement (vs report-only) is the end-state target. Acceptable to ship
   Phase 15 with CSP in report-only mode if blockers remain, but document this
   in `security.md` as a known waiver.
