# Phase 18 — CLI Parity · Log

> Phase folder created on 2026-05-10 by the architect-spec agent.
> See `docs/realignment-2026-05-09.md` work unit 10 for framing.
>
> This is a **meta-phase**: it consolidates CLI surface across every other
> realignment work unit. Implementation lands per-domain alongside each
> domain's Rails dispatch (Lane 2a per existing convention).

## 2026-05-10 — Architect-spec dispatch: CLI coverage matrix locked

**Session.** Architect-spec agent dispatched by master to write the CLI parity
coverage matrix consolidating every web action across realignment work units
into a per-domain matrix of `pito <noun> <verb>` subcommands.

**Implemented.** Wrote `specs/01-cli-coverage-matrix-and-subcommands.md`. The
spec covers:

- A coverage matrix grouped by realignment work unit (tenant drop,
  scope simplification, channels, videos, analytics, games + bundles,
  calendar, notifications, MCP expansion) plus baseline Phase 4 surfaces.
  Every web action is enumerated with HTTP route, CLI subcommand, MCP
  yes/no, and notes.
- Subcommand naming conventions (verb-first, hyphen-case, plural nouns,
  comma-separated bulk ids) locked.
- Standard flags (`--json`, `--limit`, `--help`) locked.
- Auth file location and schema locked: `~/.config/pito/auth.toml`.
- HTTP status to exit code translation table locked.
- Crate structure: per-noun module under `commands/<noun>.rs`, shared
  `auth.rs` / `output.rs` / `confirm.rs`.
- Test posture: per-subcommand unit tests + integration tests with
  `wiremock` + `cargo clippy` + `cargo fmt`.
- Manual playbook for per-domain validation.

**Files changed.**

- `docs/plans/beta/18-cli-parity/specs/01-cli-coverage-matrix-and-subcommands.md`
  (new).
- `docs/plans/beta/18-cli-parity/log.md` (this file, new).

**References.**

- `docs/realignment-2026-05-09.md` — work unit 10 framing; resolved
  ambiguities 2/3.
- `docs/decisions/0003-drop-tenant-single-install-multi-user.md` —
  tenant-free posture.
- `CLAUDE.md` — hard rules (no JS confirm, bulk-as-foundation, yes/no
  boolean discipline).
- `extras/cli/CLAUDE.md` — `cli-impl` agent file scope.

**Next.** Master agent reviews, asks the user any open questions (TUI scope,
color default, pagination default, etc.), then dispatches the per-domain
`cli-impl` agents in the order recommended in the spec
(tenant-drop cleanup → auth + tokens → channels → videos → analytics →
games + bundles → calendar → notifications). Each per-domain dispatch is
small (one noun group, 6-12 subcommands) and reuses the plumbing locked
in this spec.
