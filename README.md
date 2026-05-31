# pito

[![CI](https://github.com/gmrdad82/pito/actions/workflows/ci.yml/badge.svg)](https://github.com/gmrdad82/pito/actions/workflows/ci.yml)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

self-hosted YouTube channel management for creators who run multiple channels —
track channels, videos, and analytics in one place, schedule across channels
without conflicts, and get game/channel recommendations. your laptop, your data.

> **alpha, actively rebuilding.** one person's tool, open-sourced as-is. no SLA,
> no roadmap, no support obligation. issues triaged when there's time; PRs
> welcome but not guaranteed to merge. no hosted service from this repo.

## stack

Rails 8.1 · Postgres 17 (pgvector) · Voyage AI · Hotwire · ViewComponent ·
Tailwind CSS · Kamal.

## getting started

Optimized for the author's own machine; setup docs are sparse on purpose during
the rebuild. To try it anyway, start with
[`docs/architecture.md`](docs/architecture.md).

## docs

- [`AGENTS.md`](AGENTS.md) — agent instructions (Claude Code / OpenCode)
- [`docs/EXTRA.md`](docs/EXTRA.md) — pito-specific conventions that override the
  generic agent guidance
- [`docs/architecture.md`](docs/architecture.md) — topology, models, namespaces
- [`docs/design.md`](docs/design.md) — visual contract, keybindings, terminology
- [`docs/footage_probe.md`](docs/footage_probe.md) — ffprobe integration, grading detection, rake task usage

## license

AGPL-3.0 — see [LICENSE](LICENSE). Use it for whatever you like — self-host it,
fork it, learn from it, build on it. Just don't pass it off as your own thing.
No warranty, as-is. Questions? Ping me: gmrdad82 [at] gmail [dot] com.
