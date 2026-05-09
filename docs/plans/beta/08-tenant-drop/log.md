# Phase 08 — Tenant Drop · Log

## 2026-05-10 — Realignment paperwork landed; tenant-drop spec dispatch pending

**Done:**

- Realignment finished: 10 ambiguities resolved + 2 structural calls
  (Login-with-Google drop, destructive-and-reseed migration posture).
- ADRs landed:
  - **0003** updated with the destructive-and-reseed migration posture and the
    owned/tracked retirement (the `connected` flag plus the owned-vs-tracked
    distinction is collapsed; see ADR for details).
  - **0004** — MCP scope simplification to `dev` + `app`.
  - **0005** — Doorkeeper stays for Claude Mobile.
  - **0006** (new) — drop Login-with-Google.
- IDOR spec archived to `docs/decisions/archives/idor-spec.md`.
- Mobile notes triage: 5 notes deleted (their content is captured durably in the
  realignment doc and ADRs); 5 preserved (still load-bearing for unwritten
  work-unit specs — Video/Channel/Analytics/Game/Calendar surfaces).
- Phase 7.5 pre-specs 08 / 09 / 10 deleted outright in this cleanup pass:
  - `08-timelines-resurrection-prespec.md` — superseded by direct
    `Video.project_id` association scheduled in the tenant-drop-and-rebuild work
    (realignment work unit 4).
  - `09-mcp-sync-prespec.md` — superseded by the per-domain MCP coverage matrix.
  - `10-terminal-sync-prespec.md` — superseded by the per-domain CLI coverage
    matrix.
  - Phase 7.5 `dropped.md` updated with a 2026-05-10 entry recording the
    deletions.

**Decisions:**

- Phase numbering for the tenant-drop work lives at
  `docs/plans/beta/08-tenant-drop/`. (The legacy `08-youtube-data-sync/` folder
  predates the realignment and will be reconciled by the architect when phase
  numbering is revisited per the realignment doc's open notes.)
- Migration posture for the tenant drop is **destructive-and-reseed** (per ADR
  0003): drop `tenant_id` columns, drop the `Tenant` model, drop
  `BelongsToTenant`, drop `Current.tenant`, drop seed entries for tenants, and
  reseed. No data preservation; the running install is dev-only.

**Next:**

- Architect-spec dispatch: write the tenant-drop implementation spec under
  `docs/plans/beta/08-tenant-drop/specs/`. The spec should cover, at minimum:
  - Drop `tenant_id` columns from every table that carries one.
  - Drop the `Tenant` model and the `BelongsToTenant` concern.
  - Drop `Current.tenant` and every `Current.tenant`-derived scope / filter.
  - Drop seed entries that materialize a tenant.
  - Reseed flow that produces a working dev install without tenants.
- After the tenant drop lands, the next dispatch is MCP scope simplification
  (ADR 0004), followed by per-domain spec dispatches in the order specified in
  the realignment doc.

**Cross-references:**

- `docs/realignment-2026-05-09.md`
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md`
- `docs/decisions/0006-drop-sign-in-with-google.md`
- `docs/orchestration/follow-ups.md`
