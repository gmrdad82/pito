# Phase 4 — Scope Additions and Deviations

The original `project-workspace.md` master spec captures the planned scope. This
file appends scope additions discovered mid-phase. Each entry dates the
addition, names the rationale, and points at the sibling spec or driver.

## 2026-05-04 — MCP Dev KB surface (Step 0)

**Item.** Adds three MCP tools (`list_docs`, `read_doc`, `save_note`) to expose
the docs tree to Claude Mobile and capture on-the-road notes. Lands BEFORE Phase
A's nine sequential foundation steps as Step 0.

**Rationale.** The user wants natural conversation flow between Desktop Claude
and Claude Mobile — Mobile reads logs / specs / curated docs to recover context,
captures thoughts as timestamped notes; Desktop curates and commits. The
`project:*` MCP work remains paused per master spec §2; this is a `dev:*`
surface, distinct.

**Plan link.** Sits ahead of Phase A in the §14 implementation steps. The master
spec's §2 line "MCP (Lane 2b) paused. No `project:*` MCP tools." stands
unchanged — `dev:*` is a different surface.

**Driver.** Sibling spec: `specs/mcp-dev-kb-surface.md`.
