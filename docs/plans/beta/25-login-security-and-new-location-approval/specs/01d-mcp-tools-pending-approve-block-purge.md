# Phase 25 — 01d: MCP Tools — Pending, Approve, Block, Unblock, Purge

> **Sub-spec 01d.** Promotes the read scaffolds from `01a` + `01b` to
> fully-gated MCP tools. Introduces the `auth` MCP scope, adds the destructive
> approve / block / unblock / purge tools, and threads two-step `confirm: "yes"`
> semantics across every destructive call.
>
> Reads the umbrella spec first. Locked decisions LD-8 / LD-13 / LD-15 apply
> directly. Open question Q-K resolves here.

## Goal

A Claude session — desktop or mobile — equipped with an `auth`-scoped token can:

- List currently-pending approvals (`login_attempts_pending`).
- Browse historical attempts (`login_attempts_list`).
- Approve a pending attempt (`login_attempt_approve`).
- Block a pending attempt and auto-add the pair (`login_attempt_block`).
- Unblock a `(fingerprint, ip_prefix)` pair (`login_attempt_unblock`).
- Bulk-purge attempts by filter (`login_attempt_purge`).

Every destructive tool requires `confirm: "yes"` (two-step pattern, mirroring
the existing `delete_records` / `sync_records` shape). Every action is
audit-logged with `source_surface: :mcp` (LD-13). The `auth` scope is opt-in per
token; the default Claude-mobile token does NOT include it.

This sub-spec also adds an `auth_audit_log_list` read tool so the audit trail is
visible from MCP (operational debugging from Claude).

## Files touched

### MCP scope catalog

- `app/mcp/scope_catalog.rb` — adds `auth` scope, with strip-on-release
  semantics matching the `dev` scope precedent (per
  `docs/decisions/0004-mcp-scope-simplification-dev-app.md`).
- `app/models/access_token.rb` (or wherever scopes are persisted) — gains the
  `auth` enum value.

### Tools (production)

- `app/mcp/tools/login_attempts_pending.rb` — promoted from `01b` scaffold; full
  param validation, scope-gated.
- `app/mcp/tools/login_attempts_list.rb` — promoted from `01a` scaffold; full
  filter set (`result`, `since`, `until`, `user_email`, `ip`, `fingerprint`,
  `page`, `per_page`).
- `app/mcp/tools/login_attempt_approve.rb` — new; calls
  `Auth::LoginAttemptApprover` with `source: :mcp`.
- `app/mcp/tools/login_attempt_block.rb` — new; calls
  `Auth::LoginAttemptBlocker`.
- `app/mcp/tools/login_attempt_unblock.rb` — new; calls
  `Auth::BlockedLocationUnblocker` (introduced here; full UI lives in `01f`).
- `app/mcp/tools/login_attempt_purge.rb` — new; calls `Auth::AttemptPurger`
  (introduced here).
- `app/mcp/tools/auth_audit_log_list.rb` — new; read-only audit log.

### Services (new for this sub-spec)

- `app/services/auth/blocked_location_unblocker.rb` — given a `BlockedLocation`
  (or `{fingerprint_hash, ip_prefix}` pair), stamps `unblocked_at` +
  `unblocked_by_user_id`. Audit-logs.
- `app/services/auth/attempt_purger.rb` — bulk-delete attempts by filter
  (`result:`, `since:`, `until:`, `ip:`, `fingerprint:`). Audit-logs the purge
  with `metadata: { filter: ..., row_count: ... }`. System-wide scope (Q-K).

### Documentation

- `docs/mcp.md` — adds the `auth` scope to the scope catalog table, documents
  the six new tools, repeats the strip-on-release semantics for the `auth` scope
  (parallel to `dev`).
- `docs/auth.md` — adds an "MCP auth surface" section pointing at the six tools.

### Specs (spec pyramid)

#### MCP tool specs

- `spec/mcp/tools/login_attempts_pending_spec.rb`
  - happy: returns active pending rows (state=pending_approval AND
    `approval_required_until > now`), yes/no Booleans.
  - sad: token missing `auth` scope → returns the standard scope error (matches
    existing precedent for scope rejection).
  - sad: token revoked → standard 401 shape.
  - edge: empty result set → `{"attempts": []}` (not 404).
  - boundary: `"is_expired": "no"` on every row.
- `spec/mcp/tools/login_attempts_list_spec.rb`
  - happy: filters by `result`, `since`, `until`, `ip`, `fingerprint`,
    `user_email`.
  - happy: pagination with `page: 1, per_page: 25`.
  - sad: invalid `result` value → input validation error.
  - sad: invalid date string → input validation error.
  - sad: per_page > 100 → clamps to 100 (or rejects, depending on project
    precedent — match `list_docs`).
  - edge: filter combinations (`result + since + ip`) intersect correctly.
- `spec/mcp/tools/login_attempt_approve_spec.rb`
  - happy: `confirm: "yes"` → approves, returns the updated attempt
    - new session token (or "session is yours" shape).
  - sad: missing `confirm` → returns the two-step-confirm prompt with the
    attempt's detail preview.
  - sad: `confirm: "no"` → returns the same two-step prompt.
  - sad: attempt expired → returns expired error.
  - sad: attempt already resolved → returns already-resolved error.
  - sad: token missing `auth` scope → scope error.
  - audit: writes an `AuthAuditLog` row with `source_surface: :mcp`,
    `action: :approve`.
- `spec/mcp/tools/login_attempt_block_spec.rb`
  - happy: `confirm: "yes"` → blocks, creates BlockedLocation, revokes session,
    audit-logs.
  - sad: same set as approve.
  - edge: blocking an attempt whose pair is already blocked → noop on
    BlockedLocation, still audit-logs the action.
- `spec/mcp/tools/login_attempt_unblock_spec.rb`
  - happy: `confirm: "yes"` + valid `blocked_location_id` → unblocks.
  - happy: `confirm: "yes"` + `{fingerprint, ip_prefix}` pair → unblocks the
    matching active row.
  - sad: missing `confirm` → two-step prompt.
  - sad: no matching active blocked row → 404 shape.
  - sad: scope missing → scope error.
- `spec/mcp/tools/login_attempt_purge_spec.rb`
  - happy: filter `{result: "blocked", since: <iso>}` → deletes matching rows,
    returns `{deleted_count: N, filter: {...}}`.
  - happy: empty filter is rejected (require at least one filter to avoid
    accidental "delete all"; recommend in open questions below).
  - sad: missing `confirm` → two-step prompt with preview count.
  - sad: scope missing → scope error.
  - audit: writes an `AuthAuditLog` row with
    `metadata: { filter, deleted_count }`.
- `spec/mcp/tools/auth_audit_log_list_spec.rb`
  - happy: returns rows with yes/no Booleans, filterable by `action`,
    `source_surface`, `since`, `until`, `acting_user_email`.
  - sad: scope missing → scope error.

#### Service specs

- `spec/services/auth/blocked_location_unblocker_spec.rb`
  - happy: stamps `unblocked_at` + `unblocked_by_user_id`.
  - sad: already-unblocked row → no-op.
  - edge: concurrent unblock + unblock → idempotent.
  - audit: writes the row.
- `spec/services/auth/attempt_purger_spec.rb`
  - happy: filter deletes rows + audit-logs the count.
  - sad: empty filter → raises `ArgumentError` (per the safety rule).
  - edge: 10k rows in scope → batched delete (recommend 1k at a time) so the
    transaction stays small.

#### Scope catalog spec

- `spec/mcp/scope_catalog_spec.rb` (existing, gains)
  - `auth` scope is in the catalog.
  - `auth` is stripped from release builds (mirror the `dev` strip).
  - `auth` cannot be granted by default token-mint flows; requires explicit
    per-token opt-in.

### Integration / system

- System spec covered in `01g` (cross-surface journey: approve from MCP + block
  from TUI + unblock from web + purge from MCP).

## Tool input/output shapes (illustrative — yes/no boundary)

```json
// login_attempts_pending request
{}

// response
{
  "attempts": [
    {
      "id": 42,
      "browser": "Chrome",
      "os": "macOS",
      "ip": "203.0.113.5",
      "geo": "Berlin, DE",
      "fingerprint_short": "a3f9c2d1e4...",
      "created_at": "2026-05-10T11:04:57Z",
      "approval_required_until": "2026-05-10T11:14:57Z",
      "is_expired": "no"
    }
  ],
  "count": 1
}
```

```json
// login_attempt_block request (two-step)
{
  "id": 42,
  "confirm": "no"
}

// response
{
  "preview": {
    "attempt": { /* same shape as pending */ },
    "side_effects": {
      "will_create_blocked_location": "yes",
      "will_revoke_session": "yes",
      "will_resolve_notification": "yes"
    },
    "warning": "This blocks future attempts from this fingerprint + IP prefix."
  },
  "next_step": "Resubmit with confirm: \"yes\" to perform the block."
}
```

```json
// login_attempt_block request (confirmed)
{
  "id": 42,
  "confirm": "yes"
}

// response
{
  "blocked": "yes",
  "blocked_location_id": 7,
  "audit_log_id": 19,
  "result": "ok"
}
```

## Acceptance

- [ ] `auth` MCP scope is in the catalog; stripped from release builds.
- [ ] Per-token opt-in for `auth` scope on the settings/tokens edit page
      (project precedent for opt-in scopes).
- [ ] All six tools registered + scope-gated.
- [ ] `login_attempts_pending` returns active pending rows only.
- [ ] `login_attempts_list` supports the full filter set + pagination.
- [ ] `login_attempt_approve` / `login_attempt_block` / `login_attempt_unblock`
      / `login_attempt_purge` require `confirm: "yes"` (two-step pattern).
      Missing confirm returns a preview shape.
- [ ] Every destructive tool audit-logs via `Auth::AuditLogger` with
      `source_surface: :mcp`.
- [ ] Purge requires at least one filter; empty filter is rejected.
- [ ] System-wide purge scope per Q-K (any authenticated user can purge any
      rows; audit-logged).
- [ ] Yes / no Booleans at every external boundary.
- [ ] `auth_audit_log_list` returns rows with filters.
- [ ] `docs/mcp.md` documents the six tools + the new scope.
- [ ] Full RSpec green; Brakeman clean; bundler-audit clean.

## Manual test recipe

1. `git pull --rebase`, `bin/dev`, `bin/mcp-web`.
2. Mint a fresh access token at `/settings/tokens/new`. Opt into the `auth`
   scope (new checkbox). Save the token.
3. From an MCP harness (`bin/mcp` or Claude desktop), connect with the new
   token.
4. Trigger a new-location pending login (browser B with correct password,
   ask-for-approval path).
5. Call `login_attempts_pending` → JSON list with one row.
6. Call `login_attempt_block` with `{id: <id>, confirm: "no"}` → preview
   response.
7. Call `login_attempt_block` with `{id: <id>, confirm: "yes"}` → blocked,
   audit-logged.
8. Call `auth_audit_log_list` → confirms the audit row with
   `source_surface: "mcp"`.
9. Call `login_attempts_list` with `{result: "blocked"}` → finds the row.
10. Call `login_attempt_unblock` with
    `{fingerprint: "<hash>", ip_prefix: "203.0.113.0/24", confirm: "yes"}` →
    unblocks.
11. Call `login_attempt_purge` with
    `{result: "failed", since: "2026-05-01T00:00:00Z", confirm: "yes"}` →
    confirms deletion count; audit-logged.
12. From a fresh token WITHOUT the `auth` scope, call `login_attempts_pending` →
    scope error.
13. Teardown: revoke the auth-scoped token at /settings/tokens.

## Cross-stack scope

| Surface | Status                                          |
| ------- | ----------------------------------------------- |
| Rails   | Per-token scope opt-in UI on /settings/tokens.  |
| TUI     | Out of scope (TUI uses Rails session, not MCP). |
| MCP     | Full (six new tools + new scope + scope strip). |
| Website | Out of scope.                                   |

## Open questions

- **Q-K** (cross-account purge): system-wide; any authenticated user with `auth`
  scope can act on any row. Audit-logs identify the actor. Confirm.
- New: should `login_attempt_purge` cap at N rows per call (e.g., 10k)?
  Recommend yes; require multiple calls beyond the cap.
- New: should the `auth` scope auto-include `notifications` read (since
  approve/block actions surface in notifications)? Recommend no; keep scopes
  orthogonal.
- New: should the tools return the full attempt detail (including
  `fingerprint_hash`) or only the short form? Recommend full detail on the gated
  `auth` scope, short form elsewhere.
- New: do we need a `login_attempt_revoke_session` tool separate from block?
  Recommend no; block already revokes. If a session needs revocation without
  blocking the pair, use the existing `/settings/sessions` UI.
