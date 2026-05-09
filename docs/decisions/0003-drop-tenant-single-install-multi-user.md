# ADR 0003 — Drop Tenant: Single-Install, Multi-User

## Status

Accepted, 2026-05-09.

## Context

Across Alpha and Beta phases 1–7.5, pito was built schema-first as a
multi-tenant application. `Tenant` exists as a top-level isolation boundary;
every domain table carries a `tenant_id NOT NULL` column; the `BelongsToTenant`
concern applies a default scope that raises when `Current.tenant_id` is missing;
HTML controllers seed `Current.tenant = Tenant.first`; API and MCP controllers
populate it from the authenticated bearer token. Phase 5 / Phase 6 / Phase 7 all
carry the same shape: tokens, sessions, Doorkeeper grants, and `GoogleIdentity`
rows are all denormalized with `tenant_id`. `docs/auth.md` §10 even documents
the global `users.username` / `users.email` uniqueness as a single-tenant
simplification that Theta (Phase 16+) would have to revisit.

On 2026-05-09 the user dropped a sequence of eight Mobile notes during a 2-hour
Claude Mobile session. The fifth note (`tenant-scope-and-idor.md`) attempted to
push the tenant model further by codifying a 12-rule IDOR specification. The
eighth note (`drop-tenant-and-future-install-wizard.md`) explicitly supersedes
it: pito is a single-install tool for the user's own creator workflow, with
multi-user as authentication-only ergonomics ("more than one person can log
in"), not data isolation. SaaS pito.com is explicitly NOT on the roadmap.
Distribution will be local-first now, possibly Hetzner-hosted for the user's own
use in ~6 months, with an optional ONCE-style installer in the v1 distribution.

The follow-up direction conversation between user and master agent on the same
date locked the decision: tenant scoping comes off; multi-user stays as
authentication boilerplate; the 12-rule IDOR spec is archived as a future-SaaS
reference.

## Decision

Drop tenant scoping entirely. pito becomes a **single-install, multi-user**
application:

- The whole database belongs to "this install."
- Authentication still gates access (every endpoint, every MCP tool, every
  controller action requires an authenticated session or bearer token).
- Anyone logged in has full read and write access to everything in the install.
  There is no per-user data isolation, no per-user activity tracking, no role
  hierarchy in v1.
- Multi-user is intentionally low-effort: another user row is enough to let a
  second person log in. There is no user-creation flow yet (Phase 12 may add a
  simple "invite" surface; a deferred install-wizard direction exists per note
  8).
- A `created_by_user_id` column lands on user-authored rows (notes, manual
  calendar entries, manual game entries, milestone rules, saved views) for an
  audit / display trail — never for access control. Nullable for system- created
  rows.

The 12-rule IDOR specification (originally captured in note 5,
`docs/notes/2026-05-09-19-00-35-tenant-scope-and-idor.md`) is **archived in this
repo**, not deleted. It is treated as a "v2 / SaaS spec, on ice" — if pito ever
pivots to a multi-tenant SaaS at pito.com, the rules there are the starting
point for re-introducing the tenant column. The durable archive home is
`docs/decisions/archives/idor-spec.md` (full 12-rule body with a clear
superseded-by header). The original Mobile note has been deleted as of the
2026-05-10 docs sweep; the archive is now the single source.

## Consequences

The unwind touches every layer of the application. The full concrete change list
(reproduced from note 8) is the basis for downstream implementation specs; this
ADR captures the architectural commitment rather than the implementation order.

### What unwinds

1. **Schema migration.** A migration drops `tenant_id` from every domain table,
   drops associated indexes (single-column and composite), drops the foreign-key
   constraints that point to `tenants`, then drops the `tenants` table itself.
   Tables affected today (non-exhaustive): `channels`, `videos`, `video_stats`,
   `playlists`, `playlist_videos`, `video_uploads`, `users`, `api_tokens`,
   `sessions`, `oauth_applications`, `oauth_access_grants`,
   `oauth_access_tokens`, `google_identities`, `youtube_api_calls`, `projects`,
   `collections`, `games`, `footages`, `notes`, `saved_views`,
   `bulk_operations`, `bulk_operation_items`, `timelines`, plus any audit / sync
   / settings tables that picked up `tenant_id` in flight.
2. **`BelongsToTenant` concern removed** from every model that includes it. The
   default scope (and its raise) goes away.
3. **`Current.tenant` removed** from `ActiveSupport::CurrentAttributes`. The API
   auth flow, MCP rack app, session resolver, and HTML
   `before_action :set_current_tenant_and_user` all simplify to setting
   `Current.user` only.
4. **`Tenant` model deleted** (or downgraded to a single-row `AppInstall` table
   if Settings prefer to live there — TBD in the implementation spec).
5. **MCP RackApp tenant scoping simplified.** Auth surface drops the tenant pin;
   the bearer token resolves to a user only. Future MCP tools no longer carry
   tenant context.
6. **Phase 6B's denormalized tenant on Doorkeeper reversed.** Doorkeeper tables
   drop `tenant_id`; the auth chain (Phase 6B's deliberate compromise) becomes
   simpler.
7. **Per-tenant credentials → install credentials.** The Settings UI collapses
   any "tenant settings" surface into a single install-level surface. One Voyage
   AI key, one IGDB / Twitch credential set, one Cloudflare token, one Discord
   webhook list, one Slack webhook list, one YouTube OAuth client. All
   install-scoped, never per-user.
8. **Storage paths drop the tenant prefix.** Composite covers, exports,
   thumbnails, and footage paths shed `tenant-{id}/`. A one-time migration
   script renames existing artifacts to the flat layout. Active Storage blobs
   for game cover art (Phase 4) follow the same pattern.
9. **IDOR test obligations removed from CI.** The cross-tenant leak spec(s) and
   any per-endpoint IDOR fixtures retire. Auth-required tests on every endpoint
   stay (a logged-out request must still 401 / 302).
10. **Per-user notification read state stays optional.** The calendar /
    notifications surface (note 6) defines an optional
    `notification_read(notification_id, user_id, read_at)` join. v1 decision
    deferred — see open questions in the realignment doc.
11. **`docs/auth.md` rewrite.** §10's "departures from the original Phase 3
    plan" loses the global-uniqueness rationale (no more "single-tenant
    simplification" framing — there is no other tenant). The four-surface auth
    map stays.
12. **`docs/architecture.md` rewrite.** The "Tenant + User + ApiToken schema"
    section collapses to "User + ApiToken." The "schema-level multi-tenancy"
    framing goes away.

### What stays

- Authentication is still mandatory. Sessions (Phase 6A) and bearer tokens
  (Phase 5) remain the access boundary.
- Doorkeeper / OAuth applications stay (see ADR 0005).
- UUIDs in URLs and API payloads. Cheap to do, makes any future SaaS migration
  easier, reduces accidental enumeration even within one install.
- Secrets (YouTube OAuth tokens, IGDB / Twitch credentials, future Voyage AI
  keys, webhook URLs) stay encrypted at rest. Never returned in API responses;
  edit-only through specific config endpoints.
- Logs do not surface raw stack traces or secrets to end-users in production.
- `Current.user` is real and required everywhere a user-authored row is written.

## Rationale

- The user is the only operator. SaaS plans are explicitly off the roadmap
  ("lots of data to share and publish — rather avoid the responsibility").
- Multi-user is "just so more than one person can log in" — no activity
  tracking, no isolation, no roles in v1.
- The 12-rule IDOR spec, while correct for its premise, is premature complexity
  for a single-install tool. It taxes every new feature with cross-resource
  tenancy checks that have no real-world adversary in v1.
- Holding the door open for future SaaS via opaque IDs (UUIDs) and install-level
  secret encryption is cheap. Adding the tenant column back, if pito ever needs
  it, is a planned schema migration — not a project rewrite.

## Alternatives considered

- **Keep multi-tenant for future SaaS.** Rejected as premature complexity. The
  user is the only operator and SaaS is not on the roadmap.
- **Drop multi-user too (single-user, single-install).** Rejected as
  ergonomically restrictive; "more than one person can log in" is a useful
  property at low cost.
- **Soft tenant: keep `tenant_id` columns NULL'd out, single-tenant by
  invariant.** Rejected as half-measure; the columns and the concern still cost
  reasoning at every model and every query.

## Migration path

The unwind is large but mostly mechanical. Sequencing follows note 8's concrete
change list:

1. **Schema migration**: drop `tenant_id` from every domain table; drop the
   `tenants` table.
2. **Models / repositories**: remove `belongs_to :tenant`, the `BelongsToTenant`
   include, and any default scope filtering by tenant.
3. **Sessions / auth**: keep authentication. Drop tenant-from-session
   resolution. `Current` carries `user`, `token` only.
4. **Controllers / endpoints**: drop tenant-param ignoring (note 5 Rule 2 is
   gone). Standard `Current.user`-based auth check at the controller level.
5. **MCP tools**: drop tenant context from every tool call. Auth = "is this MCP
   session authenticated to this pito install?"
6. **Storage paths**: rename / move existing files out of any `tenant-{id}/`
   prefix into flat directories. One-time script.
7. **Encrypted secrets table**: collapse from "per-tenant secrets" to "install
   secrets." Single row per kind (or single key-value table).
8. **Settings UI**: collapse "tenant settings" pages into "install settings."
   Same fields, no tenant selector.
9. **Tests**: drop the IDOR cross-tenant test obligations from CI. Keep
   auth-required tests on every endpoint.
10. **Docs**: rewrite `architecture.md`, `auth.md`, `setup.md`, `mcp.md`
    references. Cross-reference this ADR from the older tenant note as the
    supersession marker.

This unwind is dispatched as a single focused work unit — see the realignment
doc for the ordered roadmap.

## Migration posture

- No production data exists. Pito has not shipped to anyone outside the
  developer's machine.
- Therefore the tenant drop is **destructive-and-reseed**, not a backfill: drop
  the `tenants` table, drop `tenant_id` columns from every domain table, drop
  the `BelongsToTenant` concern, drop `Current.tenant`, drop seed entries that
  reference tenant. Reseed via `db:seed` to reach the new shape.
- No data preservation. ADR 0003 + git history are the only artifacts of the
  prior tenant-scoped era.
- This posture is what the user explicitly chose on 2026-05-10 ("we don't have
  yet production data and everything can be reseeded so pick the easiest way").

## Owned vs. tracked framing retired

- The earlier `Path A2` framing distinguished "owned" content (channels / videos
  with OAuth) from "tracked" content (read-only metadata).
- With tenant scoping gone and the product positioned as a personal /
  single-install creator workflow, the distinction collapses.
- Every Channel and Video in pito is owned by definition. There is no
  tracked-only mode.
- Note 1's Channel / Video schema expansion is the canonical model; it is not
  "Path A2 reversed" — Path A2 itself is retired.

## Date

2026-05-09 (original); 2026-05-10 (Migration posture + Owned vs. tracked
sections appended).

## Related

- `docs/decisions/archives/idor-spec.md` — the 12-rule spec being superseded;
  archived as future-SaaS reference. (Originally captured as
  `docs/notes/2026-05-09-19-00-35-tenant-scope-and-idor.md`; that note was
  deleted in the 2026-05-10 docs sweep.)
- `docs/future/install-wizard.md` — captures the future install-wizard hook
  derived from the supersession discussion. (Original supersession note,
  `docs/notes/2026-05-09-19-56-01-drop-tenant-and-future-install-wizard.md`, was
  deleted in the 2026-05-10 docs sweep; this ADR + the future-hook doc are the
  durable record.)
- `docs/decisions/0004-mcp-scope-simplification-dev-app.md` — the related scope
  simplification that lands in the same realignment.
- `docs/decisions/0005-doorkeeper-stays-for-claude-mobile.md` — clarifies that
  Doorkeeper survives the tenant drop.
- `docs/realignment-2026-05-09.md` — top-level direction map, ordered roadmap.
