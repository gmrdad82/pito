# pito

self-hosted YouTube channel management for creators who run multiple
channels.

> **status: alpha — actively rebuilding. no SLA, no support guarantees.**
> See [project philosophy](#project-philosophy) below.

## what it does

- track channels + videos + analytics in one place
- schedule videos across multiple channels without conflicts
- recommend games to cover + channels to publish on
- self-hosted: your laptop, your data

## stack

Rails 8.1 · Postgres 17 · Redis · Meilisearch · Voyage AI · Hotwire ·
ViewComponent · ratatui (Rust CLI, planned).

## getting started

Currently optimized for the author's own machine. Setup docs are sparse
on purpose during the rebuild phase. If you want to try it anyway, see
[`docs/architecture.md`](docs/architecture.md).

## docs

- [`CLAUDE.md`](CLAUDE.md) — collaboration rules for AI agents working in the repo
- [`docs/architecture.md`](docs/architecture.md) — system topology + models + canonical namespaces
- [`docs/design.md`](docs/design.md) — visual contract + keybindings + terminology
- [`docs/mcp.md`](docs/mcp.md) — MCP surface (parked)
- [`docs/tui.md`](docs/tui.md) — Rust client contract (planned)
- [`docs/website.md`](docs/website.md) — Astro landing

## project philosophy

- **share but not be accountable.** pito is one person's tool,
  open-sourced for fellow creators who want to self-host. No SLA, no
  roadmap commitments, no support obligation.
- **issues are triaged when there's time.** PRs welcome but not
  guaranteed to be merged.
- **no hosted service from this repo.** for commercial use, contact the
  author.

## license

AGPL-3.0. See [LICENSE](LICENSE).
