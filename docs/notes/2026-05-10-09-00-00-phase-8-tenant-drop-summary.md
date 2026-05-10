# Phase 8 — Tenant drop + email-only login

## Status

**Landed.** Implementation + reviewer + security + prose rewrites all in `main`.
Awaiting your manual validation.

## What changed

- Dropped `Tenant` model, `BelongsToTenant` concern, `Current.tenant`,
  `tenant_id` columns from 24 domain tables, the `tenants` table itself.
- `users.username` column dropped; login is email + password only.
- Storage paths flattened: `composites/`, `exports/`, etc. (no `tenant-X/`
  prefix).
- `:owner` credentials block shape: `{ email, password }` only.
- Audit-log key rename: `identifier_attempted` → `email_attempted`.
- Bonus: F1 timing-oracle fix in `bcrypt_dummy_compare` (Medium severity,
  pre-existing — fixed as a fix-forward).

## Quality gates

- 1663 RSpec examples → 0 failures.
- Rubocop clean.
- Brakeman clean.
- bundler-audit clean.

## Reviewer playbook

`docs/orchestration/playbooks/2026-05-10-phase-8-tenant-drop-and-email-only-login.md`

## Security findings

`docs/orchestration/playbooks/security-2026-05-10-phase-8-tenant-drop.md` —
Verdict: MERGE WITH FIX-FORWARD. 0 critical/high; 1 medium (F1, fixed); 3 low +
4 informational findings. Carry-forwards in `docs/orchestration/follow-ups.md`.

## Validation steps when you're back

1. `bin/rails credentials:edit --environment development` — confirm `:owner` is
   `{ email, password }` only. Same for `--environment test`.
2. Optional: `rm -rf <PITO_NOTES_PATH>/* <PITO_ASSETS_PATH>/*` to drop legacy
   `tenant-X/` segments.
3. `bin/rails db:drop db:create db:migrate db:seed`. Confirm one user + one dev
   token.
4. Visit `/login`. Single `email` field with `you@example.com` placeholder.
5. Visit `/settings/oauth_applications`, `/settings/tokens`,
   `/settings/sessions`, `/settings/youtube`. All should render.
6. Re-pair MCP from Claude Mobile + Desktop. Confirm `dev:save_note` lands a
   note under `docs/notes/`.

## Open follow-ups (non-blocking)

- F2 — placeholder credentials fallback in dev seed; should `abort` like the
  pepper path.
- F3 — weak email regex (academic for single-operator install).
- F4 — Brakeman strict-mode `Unscoped Find` warnings; document in `docs/auth.md`
  as expected per single-install posture.
- Brakeman ignore-file housekeeping (2 obsolete entries).
