# Phase 25 — 01f: Auto-Block List + Purge UI

> **Sub-spec 01f.** Promotes `BlockedLocation` from the schema stub in `01a` to
> a fully-managed list with web UI and TUI read surface. Adds the purge UI
> (`/settings/security/attempts/purge` and `/settings/security/blocks/purge`)
> using the action-screen framework.
>
> Reads the umbrella spec first. Locked decisions LD-10 / LD-15 / LD-16 / LD-17
> apply directly. Open question Q-E resolves here.

## Goal

Block list lives at `/settings/security/blocks` (web). The user can:

- Browse blocked `(fingerprint_hash, ip_prefix)` pairs.
- See per-entry stats: blocked-at, blocked-by, source, attempt counter,
  last-attempt-at.
- Unblock individual entries (`/settings/security/blocks/:id/unblock`) through
  the action-screen.
- Bulk-purge the block list by filter (`/settings/security/blocks/purge`).
- Bulk-purge the attempt log by filter (`/settings/security/attempts/purge`).

The MCP equivalents (covered in `01d`) call the same services. TUI gets
read-only access to the block list (TUI-side unblock / purge deferred to a Phase
26 follow-up).

## Files touched

### Controllers

- `app/controllers/settings/security/blocks_controller.rb` — new. `index`
  (list), `show` (detail), `unblock` action-screen.
- `app/controllers/settings/security/blocks/unblockings_controller.rb` — new.
  `show` (action-screen), `create` (perform).
- `app/controllers/settings/security/blocks/purges_controller.rb` — new. `show`
  (action-screen with filter preview), `create` (perform).
- `app/controllers/settings/security/attempts/purges_controller.rb` — new.
  Mirror shape for attempt log purge.

### Services

- `app/services/auth/blocked_location_lister.rb` — paginated, filterable lister.
- `app/services/auth/blocked_location_unblocker.rb` (introduced in `01d`; reused
  here).
- `app/services/auth/blocked_location_purger.rb` — new. Bulk-delete blocked rows
  (hard delete; not soft-unblock) by filter. Audit- logs.
- `app/services/auth/attempt_purger.rb` (introduced in `01d`; reused here).

### Views

- `app/views/settings/security/blocks/index.html.erb` — paginated list with
  filters: source surface, blocked-by user, since, until, fingerprint,
  ip_prefix.
- `app/views/settings/security/blocks/show.html.erb` — detail row
  - `[unblock]` link + `[purge]` link.
- `app/views/settings/security/blocks/unblockings/show.html.erb` —
  action-screen.
- `app/views/settings/security/blocks/purges/show.html.erb` — action-screen with
  preview count.
- `app/views/settings/security/attempts/purges/show.html.erb` — action-screen
  with preview count + filter summary.

### Components

- `app/components/blocked_location_row_component.rb` / `_component.html.erb` —
  single row renderer with the `[unblock]` bracketed-link.

### Helpers

- `app/helpers/blocked_locations_helper.rb` — source-surface badge text, reason
  copy, age formatter.

### Routes

```
namespace :settings do
  namespace :security do
    resources :blocks, only: [:index, :show] do
      resource :unblocking, only: [:show, :create]
      collection do
        resource :purge, only: [:show, :create], controller: "blocks/purges"
      end
    end
    namespace :attempts do
      resource :purge, only: [:show, :create]
    end
  end
end
```

(Two-level nesting is intentional to keep the purge action-screens
discoverable.)

### TUI

- `extras/cli/src/security/blocks.rs` — read-only paginated table. Hotkey:
  `g s b` (go → security → blocks).
- TUI does NOT support unblock / purge in this phase. Show a footer hint:
  `actions on web only — open /settings/security/blocks`.

### Specs (spec pyramid)

#### Service specs

- `spec/services/auth/blocked_location_lister_spec.rb`
  - happy: returns paginated rows sorted desc.
  - happy: filters by source_surface, blocked_by_user, since, until,
    fingerprint, ip_prefix.
  - happy: active vs. soft-unblocked filter.
  - sad: invalid date → input validation error.
- `spec/services/auth/blocked_location_purger_spec.rb`
  - happy: hard-deletes matching rows + audit-logs the count.
  - sad: empty filter → raises (same safety rule as attempt purge).
  - edge: 10k rows → batched delete.
  - flaw: never deletes audit-log rows; only `blocked_locations`.

#### Request specs

- `spec/requests/settings/security/blocks_spec.rb`
  - GET index → 200, lists rows.
  - GET index with filters → 200, narrows results.
  - GET show → 200.
  - GET show on soft-unblocked row → 200 with "unblocked" badge.
  - All routes auth-required.
- `spec/requests/settings/security/blocks/unblockings_spec.rb`
  - GET show → 200, action-screen.
  - POST create with `confirm: "yes"` → soft-unblocks, audit-logged.
  - POST without confirm → 422.
  - POST on already-unblocked → no-op + 302 with notice.
- `spec/requests/settings/security/blocks/purges_spec.rb`
  - GET show with filter → 200, preview count.
  - POST create with filter + `confirm: "yes"` → hard-deletes, audit-logged.
  - POST without filter → 422.
- `spec/requests/settings/security/attempts/purges_spec.rb`
  - Mirror of blocks/purges, on the attempt log.

#### Component specs

- `spec/components/blocked_location_row_component_spec.rb`
  - happy: active row shows `[unblock]` bracketed link.
  - happy: soft-unblocked row shows "unblocked at" muted note, no link.
  - happy: source_surface badge present.

#### Helper specs

- `spec/helpers/blocked_locations_helper_spec.rb`

#### MCP tool spec

`login_attempt_unblock` and `login_attempt_purge` covered in `01d`. This
sub-spec adds:

- `spec/mcp/tools/blocked_locations_list_spec.rb` — new tool; read-only
  paginated lister, same filter set as the web index. Yes / no boundary on
  Booleans.

#### System spec

Cross-cutting journey in `01g`:

- wrong-block → unblock from web → reattempt login succeeds via trusted-location
  path (because TrustedLocation wasn't created during the failed-then-blocked
  attempt — confirm in `01b`/`01c` semantics).

#### Routing spec

- `spec/routing/settings_security_blocks_routing_spec.rb`.

## Service decomposition

```
Settings::Security::BlocksController#index
  └── Auth::BlockedLocationLister.call(filters:, page:, per_page:)

Settings::Security::Blocks::UnblockingsController#create
  ├── verify Confirmable
  ├── Auth::BlockedLocationUnblocker.call(blocked_location:, acting_user:, source: :web)
  └── Auth::AuditLogger.call(action: :unblock)

Settings::Security::Blocks::PurgesController#create
  ├── verify Confirmable
  ├── Auth::BlockedLocationPurger.call(filter:, acting_user:, source: :web)
  └── Auth::AuditLogger.call(action: :purge, metadata: { kind: :blocks, filter, deleted_count })

Settings::Security::Attempts::PurgesController#create
  ├── verify Confirmable
  ├── Auth::AttemptPurger.call(filter:, acting_user:, source: :web)
  └── Auth::AuditLogger.call(action: :purge, metadata: { kind: :attempts, filter, deleted_count })
```

## Acceptance

- [ ] `/settings/security/blocks` paginated index, filterable.
- [ ] `/settings/security/blocks/:id` detail with `[unblock]` and `[purge]`
      bracketed-links.
- [ ] Unblock + purge action-screens (no JS confirm).
- [ ] Unblock soft-marks via `unblocked_at`; row stays for audit.
- [ ] Purge hard-deletes rows; audit log captures filter + count.
- [ ] Purge requires at least one filter (safety rule).
- [ ] Attempt log purge mirrors the same UX at
      `/settings/security/attempts/purge`.
- [ ] No JS confirm / alert / prompt.
- [ ] Yes / no Booleans at every external boundary.
- [ ] TUI `g s b` opens the read-only block list with a footer hint directing to
      web for actions.
- [ ] New MCP tool `blocked_locations_list` (read-only) returns the same shape
      as the web index.
- [ ] `docs/auth.md` documents the unblock + purge procedures.
- [ ] Auto-block decay (Q-E): blocks persist forever until manually unblocked /
      purged. Document this in `docs/auth.md`.
- [ ] Full RSpec green; Brakeman clean; bundler-audit clean.

## Manual test recipe

1. `git pull --rebase`, `bin/dev`.
2. Trigger a new-location pending → block (via the `01c` flow).
3. Visit `/settings/security/blocks` → confirm the row.
4. Click the row → detail page. Click `[unblock]` → action-screen → confirm →
   row marked soft-unblocked.
5. Trigger another pending → block. Repeat. Now have one active + one
   soft-unblocked row.
6. From `/settings/security/blocks?active=yes` → only the active row shows.
7. Visit `/settings/security/blocks/purge` → enter a filter (e.g.,
   `source_surface: web`, `since: 2026-05-01`) → preview count → confirm → rows
   hard-deleted.
8. Visit `/settings/security/audit` → confirm a `purge` event with metadata.
9. Visit `/settings/security/attempts/purge` → filter `result: failed`,
   `since: 2026-05-01` → preview count → confirm → attempts deleted.
10. Open the TUI → `g s b` → confirm the read-only list mirrors the web index.
    Footer hint visible.
11. MCP: call `blocked_locations_list` → JSON matches.
12. Teardown: optional further `BlockedLocation.destroy_all`.

## Cross-stack scope

| Surface | Status                                                        |
| ------- | ------------------------------------------------------------- |
| Rails   | In scope (full block list + purge UI).                        |
| TUI     | Read-only block list under `g s b`.                           |
| MCP     | `blocked_locations_list` read tool; unblock + purge in `01d`. |
| Website | Out of scope.                                                 |

## Open questions

- **Q-E** (auto-block decay): blocks persist forever until manually unblocked /
  purged. Confirm.
- New: should we expose a "block this fingerprint going forward" link on the
  attempt detail page (so a non-pending failed attempt can be pre-emptively
  blocked)? Recommend yes; minor addition to the attempt show page. Lock here.
- New: should the unblock UI re-prompt the user when the same pair is re-blocked
  within N minutes (anti-flap)? Recommend no; the audit log captures the
  pattern.
- New: TUI unblock / purge — defer to Phase 26 (P2). Confirm.
