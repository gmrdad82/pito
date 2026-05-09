# Archived — Tenant scope and IDOR specification (12 rules)

> **This spec is archived as future-SaaS reference.** The current pito product
> is single-install + multi-user
> (`docs/decisions/0003-drop-tenant-single-install-multi-user.md`); IDOR rules
> do not apply. Preserved here in case the product ever pivots to multi-tenant
> SaaS — at which point the rules below are the starting point for
> re-introducing the tenant column. Original capture:
> `docs/notes/2026-05-09-19-00-35-tenant-scope-and-idor.md` (now deleted; this
> file is the durable home).

## Scope statement

pito is a **tenant-scoped tool for owned content only**. There is no concept of
"public videos," "public channels," or "browsing arbitrary creators' data."
Anything in pito belongs to exactly one tenant.

The product previously discussed concepts like "owned" or "OAuth-connected"
channels in opposition to public ones. **Drop that framing.** Everything is
owned-by-definition because everything is tenant-scoped. Earlier notes that
mention "owned channels" or "channels you have OAuth for" should be read as "the
tenant's channels" — there is no other kind.

## Tenancy model

- **Tenant** is the top-level isolation boundary. A new tenant = a brand new,
  empty workspace.
- **User** belongs to exactly one tenant. (If we later need multi-tenant users,
  that's a membership join table — not the v1 design. v1 is one user, one
  tenant.)
- Every domain object (channel, video, game, bundle, project, footage, note,
  saved view, composite cover, etc.) has a `tenant_id` and is reachable only
  through it.
- Provider credentials (YouTube OAuth tokens, IGDB / Twitch client credentials,
  Voyage AI keys when added, any future integration) are **per-tenant**. Each
  tenant supplies its own. There is no shared / app-level credential pool.
- Nothing is shared across tenants. No public catalog, no shared bundles, no
  shared anything. If we ever want sharing, it will be a deliberate new feature
  with its own threat model — not an emergent property.

## What "owned" means now

In docs, code, and UI:

- **Old**: "owned channel" / "OAuth-connected channel" / "the user's channel"
- **New**: "the tenant's channel"

The OAuth grant still exists technically — that's how we authenticate to YouTube
on the tenant's behalf — but the credential and the data it unlocks both live
inside the tenant. Treat the OAuth token as just another tenant-scoped secret.

## IDOR threat model

Insecure Direct Object Reference is the primary attack surface here. The risk:
user A discovers (or guesses, or scrapes from a URL, or sees in a screenshot)
the ID of an object belonging to user B's tenant, then sends a request that hits
that ID and gets back data they shouldn't see — or worse, mutates it.

**Concrete examples we must prevent:**

1. User A, tenant T1, calls `POST /api/footage/import` with
   `project_id = <T2's project>`. They imported footage into someone else's
   project.
2. User A calls `GET /api/videos/<T2's video id>` and reads the video's
   analytics, notes, or linked games.
3. User A calls `POST /api/games/<T2's game id>/sync` and either reads back the
   game data or burns T2's IGDB rate-limit budget.
4. User A calls `DELETE /api/bundles/<T2's bundle id>` and destroys T2's data.
5. User A calls `POST /api/integrations/voyage` with a tenant header pointing at
   T2 and rotates T2's Voyage credentials.
6. User A subscribes to or queries `events` / `webhooks` / `mcp tool calls` that
   reference T2's IDs and gets back leaked state.

All of these must be impossible by construction, not by convention.

## IDOR specification (mandatory)

These are non-negotiable rules. Every endpoint, every tool call, every database
query.

### Rule 1 — Tenant on every domain row

Every domain table has a `tenant_id` column. Not nullable. Indexed. Foreign key
to `tenant`.

The only tables exempt are global config (e.g., system feature flags) and the
`tenant` and `user` tables themselves. If you can't decide whether a table needs
`tenant_id`, the answer is yes.

### Rule 2 — Tenant scope is derived from the session, never from the request

`tenant_id` for any read or write is read from the **authenticated session**,
not from a header, query param, body field, URL segment, or any other
client-supplied source.

If a client sends a `tenant_id` in a request, it is **ignored** (not validated
against the session — ignored entirely). The session's tenant is authoritative.

This eliminates a whole class of bugs where validation logic accidentally trusts
a client-supplied tenant id.

### Rule 3 — Every query is tenant-scoped at the data-access layer

`SELECT`, `UPDATE`, `DELETE`, and `INSERT` for any domain table all carry a
`WHERE tenant_id = :session_tenant_id` (or equivalent constraint on insert).

This is **enforced in the data-access layer**, not in controllers. Controllers
cannot bypass it. Reasons:

- A new endpoint added without IDOR awareness still gets protection
  automatically.
- Code review on a controller change cannot be the line of defense.
- Background jobs, MCP tool calls, scripts, and admin tools all use the same
  data layer and get the same protection.

Concrete patterns (pick whatever fits the stack — at least one is mandatory):

- **Repository pattern**: every repository method takes a `TenantContext` and
  the SQL it generates always includes the tenant filter. No method exists
  without a tenant context.
- **Row-level security in the database** (Postgres RLS): policies on every
  domain table; the connection sets `SET LOCAL app.tenant_id = ...` at request
  start; the database refuses cross-tenant reads/writes. Belt and suspenders
  with the repository pattern.
- **ORM scope / global query filter**: e.g., a default scope at the model level
  that all queries inherit. Acceptable but weakest of the three because
  individual queries can opt out.

The strongest setup is repository pattern + Postgres RLS together. That's the
recommended target.

### Rule 4 — IDs in URLs are looked up, not trusted

When a client sends `GET /api/games/abc123`, the server resolves the game by
`(id = 'abc123' AND tenant_id = :session_tenant_id)`. If no row matches, return
**404, not 403**.

Returning 403 leaks the existence of the resource ("yes, this ID is real, but
you can't see it"). 404 says "no such resource visible to you" and is
indistinguishable from a typo.

Same rule for every nested resource: `POST /api/projects/<project_id>/footage`
must verify `project_id` belongs to the session's tenant before accepting any
payload. The verification is a query, not a guess.

### Rule 5 — Cross-resource references are tenant-checked too

When user input contains a reference to another resource (e.g.,
`video_game_link` referencing both a `video_id` and a `game_id`), **both** must
be verified to belong to the session's tenant before the link row is created. A
foreign key constraint alone is not enough — FKs don't know about tenants.

Example anti-pattern to avoid:

```
POST /api/video_game_links
{
  "video_id": "<T1's video>",
  "game_id":  "<T2's game>"
}
```

A naive implementation would write the row because both IDs are valid in the
database. The check must be: video belongs to session tenant AND game belongs to
session tenant. Two separate queries, both required, before the insert.

### Rule 6 — IDs are non-enumerable

Use UUIDs (v4 or v7) or similar opaque identifiers for all domain objects. Never
sequential integers in URLs or API payloads. Sequential IDs invite enumeration
attacks ("let me try `/games/1`, `/games/2`, ..."). UUIDs make blind enumeration
impractical.

Sequential PKs are fine internally for performance; expose UUIDs externally.
Either two columns (`id bigint` internal, `public_id uuid` external), or just
use UUIDs everywhere if performance allows.

### Rule 7 — Provider credentials are tenant-scoped and never echoed

- YouTube OAuth tokens, IGDB / Twitch credentials, Voyage AI keys, and any
  future provider credential live in a per-tenant secrets table or vault.
- Encrypted at rest with a key not stored alongside the ciphertext.
- Reads are scoped by `tenant_id` like any other table.
- API responses **never** include the secret value, even masked. Endpoints can
  return "configured" / "not configured" booleans and a last-rotated timestamp;
  the value itself is write-only from outside.
- A request that targets provider X for tenant T1 uses T1's credentials only.
  There is no fallback to an "app-level" credential — there isn't one.

### Rule 8 — Background jobs and MCP tool calls run with explicit tenant context

Anything that runs outside an HTTP request — daily sync jobs, webhook handlers,
MCP tools, CLI commands — must explicitly carry a `tenant_id` and run all data
access through the same tenant-scoped layer. There is no "system user" with
cross-tenant read/write.

Concrete:

- A job queue message includes `tenant_id`. The worker sets the tenant context
  before doing any work and clears it after.
- An MCP tool invocation is bound to the calling session's tenant. A tool cannot
  be tricked into operating on another tenant by passing in a different ID — see
  Rule 4.
- Webhooks (e.g., from YouTube or future providers) carry enough info to
  identify the tenant; if not, they're rejected. Never "look up the only tenant
  that has this provider configured" — that's a cross-tenant leak vector when
  more than one tenant uses the same provider.

### Rule 9 — Logs and error messages do not leak cross-tenant data

- Log lines include `tenant_id` for filtering, but error messages returned to a
  client never reference IDs the client didn't send.
- Stack traces are not surfaced to clients in production.
- "Resource not found" errors don't differentiate "doesn't exist" from "exists
  but not yours" (per Rule 4).
- Error aggregation tools (Sentry, etc.) must be configured with tenant tagging,
  not tenant data leakage.

### Rule 10 — Bulk operations are still tenant-scoped

Endpoints that take a list of IDs (`DELETE /api/games?ids=a,b,c`) verify every
single ID belongs to the session's tenant before performing any operation. If
any ID fails the check, the entire operation is rejected — not partial-success.
Partial success leaks which IDs were valid for the requesting tenant.

### Rule 11 — File / blob paths are tenant-namespaced

User-generated artifacts (composite covers, exported reports, cached thumbnails,
footage files) are stored under tenant-namespaced paths or buckets:

```
storage/
  tenant-{tenant_id}/
    composites/
    exports/
    thumbnails/
    footage/
```

Filesystem (or S3 prefix) ACLs reflect this. A signed URL is issued only after a
tenant-scoped database check confirms the requesting session owns the artifact.
The signed URL itself is short-lived and tied to the session.

Never serve a file by path alone — always go through an authorization layer
first.

### Rule 12 — Tests enforce IDOR coverage

For every endpoint and every MCP tool that touches a domain object, there must
be at least one test that:

1. Creates two tenants with overlapping data (same names, similar shapes).
2. Authenticates as user-of-tenant-1.
3. Sends a request referencing tenant-2's resource ID.
4. Asserts a 404 (not 403, not 500, not 200) and asserts no data leak in the
   response body or headers.

Plus a test that asserts the database state was not modified.

This is a hard CI gate. Adding a new endpoint without an IDOR test fails review.

## What this means for existing notes

The earlier notes (`video-model-youtube-api`, `analytics-model-youtube-api`,
`game-model-igdb`) implicitly assumed a single-tenant setup. None of their
content is wrong, but every domain table and every query in those notes inherits
**all twelve rules above** when implemented. Specifically:

- Every table mentioned (`channel_daily`, `video_daily`, `video_window_summary`,
  `top_videos_window`, `video_retention`, `game`, `bundle`, `bundle_member`,
  `video_game_link`, `game_genre`, `game_platform`, `game_developer`,
  `video_daily_by_*`, etc.) gets a `tenant_id` column and the corresponding
  query filter.
- Every API call to YouTube / IGDB / Twitch / future Voyage AI uses the
  requesting tenant's credentials only.
- Composite cover paths become
  `composites/tenant-{tenant_id}/{bundle_type}-{bundle_id}.jpg`.
- The `video_game_link` cross-resource check (Rule 5) is mandatory: the video
  AND the game/bundle must both belong to the session tenant before the link is
  created.
- Cross-channel analytics aggregations live within a tenant. There is no "rank
  my videos against everyone else's" — that would require cross-tenant reads,
  which are forbidden.
- "Active video" classification, "windowed summaries," "top videos," etc. all
  run per-tenant.

## Future-proofing for Voyage AI (placeholder)

Voyage AI is mentioned as a future integration. When added:

- Per-tenant credentials. Each tenant supplies their own Voyage API key.
- Stored in the same secrets table as YouTube OAuth and IGDB / Twitch
  credentials.
- Embeddings or any derived data are tenant-scoped — vectors generated for
  tenant T1's content live in a tenant-scoped vector store / namespace, never
  queryable by T2.
- If Voyage exposes any shared knowledge (e.g., a public model), the model is
  shared (it's external) but the inputs and outputs are tenant-scoped.

## Summary checklist for any new feature

Before merging anything that touches the database or an external provider:

- [ ] Every new table has `tenant_id`, NOT NULL, indexed.
- [ ] Every query filters by `tenant_id` from the session, never from the
      request.
- [ ] Every endpoint resolves resource IDs by `(id, tenant_id)`; 404 on miss.
- [ ] Every cross-resource reference verifies tenancy on **both** sides.
- [ ] Every external provider call uses the tenant's credentials.
- [ ] Every artifact path is tenant-namespaced.
- [ ] An IDOR test covering the new endpoint / tool exists and is passing in CI.
