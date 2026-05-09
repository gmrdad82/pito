# Phase 12 — Auth UI + Multi-User Readiness · Dropped

> Items removed from this phase's scope by the 2026-05-09 realignment. See
> `docs/realignment-2026-05-09.md` for the top-level direction map and the ADRs
> in `docs/decisions/0003`–`0005` for the locked decisions driving these
> removals.

## 2026-05-09 — Tenant scoping work undone

### Multi-tenant audit pass

The Phase 12 plan called for "audit and prove multi-tenant scoping is
bulletproof through every layer" — controllers, Sidekiq jobs, MCP tools, all
asserted not to leak data across tenants. ADR 0003 drops tenant scoping
entirely. The audit pass becomes moot:

- The cross-tenant leak spec retires.
- Per-endpoint IDOR fixtures retire.
- The "Beta only has one tenant in production but the schema is
  multi-tenant-ready" framing retires — pito is single-install, not
  single-tenant-of-many.
- The "schema-level multi-tenancy" rationale in `docs/architecture.md` rewrites
  away.

### Phase 6B Doorkeeper denormalized `tenant_id`

Phase 6B documented the denormalized `tenant_id` columns on
`oauth_applications`, `oauth_access_grants`, and `oauth_access_tokens` as a
"tenant-leak audit" mitigation. ADR 0003 drops the columns; the audit framing
was the rationale and goes away with the columns. ADR 0005 confirms the surface
itself stays — only the denormalized `tenant_id` work is what unwinds.

### Phase 6C tenant-leak audit (if planned in this phase)

Most of the work originally scoped becomes moot once `tenant_id` is gone from
every domain table. The auth-required-on-every-endpoint property is preserved as
a separate concern (auth-required tests on every endpoint stay). Drop the
cross-tenant assertions.

### `users.email` / `users.username` per-tenant uniqueness revisit

`docs/auth.md` §10 noted that "when multi-tenancy lands at Theta, two tenants
can't share a username or email" and that "Theta's spec will revisit." With ADR
0003 committing to single-install permanently, the revisit retires. Global
uniqueness is the permanent shape.

### Future per-tenant admin tooling references

Any references in this phase's spec to "Theta will add multi-tenant admin
tooling" become obsolete. SaaS pito.com is explicitly off the roadmap per
ADR 0003.

## What survives

The Phase 12 plan's user-facing surfaces all stay:

- Login form / `/login` / `/logout` / "Remember me"
- Password reset
- Session management (`/settings/sessions`, the active-sessions list,
  per-session revocation)
- Settings → Account (email change, password change)
- Mature API token management UI (with the simplified two-scope catalog per
  ADR 0004)
- Doorkeeper / OAuth-application surface (per ADR 0005)
- Failed-login rate limiting

The shape of the work is unchanged for these surfaces; only the tenant-related
additions to each are dropped.

## Cross-references

- `docs/decisions/0003-drop-tenant-single-install-multi-user.md`
- `docs/decisions/0004-mcp-scope-simplification-dev-app.md`
- `docs/decisions/0005-doorkeeper-stays-for-claude-mobile.md`
- `docs/realignment-2026-05-09.md`
