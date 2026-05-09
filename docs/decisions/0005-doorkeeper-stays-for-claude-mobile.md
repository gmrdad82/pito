# ADR 0005 — Doorkeeper Stays: Required for Claude Mobile + Web MCP

## Status

Accepted, 2026-05-09.

## Context

Phase 6B shipped a Doorkeeper-based OAuth 2.0 server inside the Rails app.
Today's surface includes:

- A Doorkeeper-backed `/oauth/applications` admin UI under
  `/settings/oauth_applications` for the user to register third-party clients
  that want to talk to pito.
- Authorization Code + PKCE flow at `/oauth/authorize` and `/oauth/token`.
- 2-hour access tokens / 14-day refresh tokens.
- Same `Api::AuthConcern` consumes Doorkeeper-issued tokens and the Phase 5
  bearer `ApiToken`s; only the storage / issuance differs.
- Tables (`oauth_applications`, `oauth_access_grants`, `oauth_access_tokens`)
  carry `tenant_id NOT NULL` denormalized off the owning user — Phase 6B
  documented this as a "tenant-leak audit" mitigation rather than a happy
  design.

ADR 0003 (the tenant drop) eliminates much of the rationale for the denormalized
`tenant_id` on Doorkeeper tables. That raises the natural question: with the
tenant column gone, does the OAuth-application surface itself still earn its
keep, or could Phase 5's `ApiToken` (PAT) surface alone serve every plausible
MCP / API client?

The follow-up direction conversation between user and master agent on 2026-05-09
considered the question and locked the answer: **keep Doorkeeper.**

## Decision

The OAuth-application surface and the Doorkeeper-backed flow stay. Concretely:

- `/settings/oauth_applications` stays in the navigation.
- The OAuth Authorization Code + PKCE flow stays at `/oauth/authorize` and
  `/oauth/token`.
- Doorkeeper tokens continue to authenticate at the bearer-token surface
  alongside `ApiToken` rows.
- Doorkeeper scopes follow the simplification in ADR 0004 (collapse to `dev`
  - `app`).
- Post-tenant-drop, the Doorkeeper tables drop their `tenant_id` columns along
  with every other domain table (the "tenant-leak audit" framing is no longer
  relevant). The auth chain simplifies — the access-grant resolves directly to a
  `User`.

## Rationale

- **Claude Mobile + Web MCP connectivity is load-bearing.** The user's primary
  on-the-road interaction with pito is via Claude Mobile making MCP calls
  against `mcp.pitomd.com`. That surface needs an auth flow that Mobile clients
  can walk — typing a 64-character bearer token into a phone is not an option.
  Doorkeeper's Authorization Code + PKCE flow is the designed solution for that
  shape and is what Mobile expects.
- **Claude Desktop's stdio path alone is not enough.** Desktop (local stdio, no
  auth) covers the developer-operator's curation workflow but doesn't help
  Mobile capture-on-the-go. The HTTP MCP Puma at port 3028 + Cloudflare Tunnel +
  Doorkeeper-issued tokens IS the Mobile path.
- **Future distributed users would still want it.** Even if pito stays a
  single-install tool forever (as ADR 0003 commits to), a future where the user
  lets a collaborator log in to their install — or where the user themselves
  uses pito from a friend's machine — both want a Mobile-walkable OAuth flow.
  PAT-only auth would force every such user to drop into the Settings UI on a
  desktop browser to mint a token, copy-paste it into the client, and never
  rotate it.
- **Doorkeeper is mature.** Reimplementing a usable Authorization Code flow from
  scratch is months of work for marginal benefit; the gem is small, well-tested,
  and integrates cleanly with the existing `Api::AuthConcern`.

## Consequences

- **Minor cleanup post-tenant-drop.** Doorkeeper tables drop `tenant_id` along
  with everything else. The denormalized-tenant-id-on-Doorkeeper compromise from
  Phase 6B is reversed in the same migration sweep that touches every other
  domain table.
- **The "rotate-on-deploy or in-place rename" decision for tokens (ADR 0004)**
  applies symmetrically to Doorkeeper-issued tokens. Master agent's lean is the
  same: in-place rename via data migration.
- **`docs/auth.md`'s four-surface map stays.** Surface #3 (third-party clients
  via Doorkeeper) stays in the table; only the `tenant_id` column reference goes
  away.
- **Documentation update.** The "tenant-leak audit" rationale in Phase 6B's spec
  (`docs/plans/beta/12-auth-ui-multi-user-readiness/specs/6b-doorkeeper-oauth-server.md`)
  reads as superseded once ADR 0003 lands — the audit becomes moot. Note this in
  `docs/plans/beta/12-auth-ui-multi-user-readiness/dropped.md`.
- **The OAuth-application-CRUD UI (`/settings/oauth_applications`) does not
  become more complex.** No per-user / per-tenant filtering needed. Every
  logged-in user sees every application; revocation and creation are unscoped.
  (If a future role split adds "viewer" vs "admin", the UI gates on role at that
  point.)

## Alternatives considered

- **Drop Doorkeeper, PAT-only auth.** Rejected. PAT minting requires a desktop
  browser session (or a CLI rake task). Mobile would have no walkable enrollment
  path. The user explicitly relies on Claude Mobile via `mcp.pitomd.com`.
- **Keep Doorkeeper but collapse to a single scope.** Considered. Reversed in
  ADR 0004 — the dev / app split is genuinely useful (release-build packaging
  strips dev). But Doorkeeper consumes the simplified two-scope catalog cleanly.
- **Build a custom mobile-friendly bearer-token enrollment flow on top of PAT.**
  Rejected as reinventing OAuth. The gem is mature; the wheel doesn't need
  re-inventing.

## Date

2026-05-09.

## Related

- `docs/decisions/0003-drop-tenant-single-install-multi-user.md` — drives the
  Doorkeeper-tables tenant-id drop.
- `docs/decisions/0004-mcp-scope-simplification-dev-app.md` — Doorkeeper
  consumes the simplified scope catalog.
- `docs/auth.md` — surface #3 in the four-surface map.
- `docs/plans/beta/12-auth-ui-multi-user-readiness/specs/6b-doorkeeper-oauth-server.md`
  — the live Doorkeeper spec; "tenant-leak audit" framing is superseded.
- `docs/realignment-2026-05-09.md` — the realignment doc captures the
  Doorkeeper-stays decision in the green-keep-as-is list.
