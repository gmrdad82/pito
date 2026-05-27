# pito

[![CI](https://github.com/gmrdad82/pito/actions/workflows/ci.yml/badge.svg)](https://github.com/gmrdad82/pito/actions/workflows/ci.yml)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

self-hosted YouTube channel management for creators who run multiple channels.

> **status: alpha — actively rebuilding. no SLA, no support guarantees.** See
> [project status](#project-status) below.

## what it does

- track channels + videos + analytics in one place
- schedule videos across multiple channels without conflicts
- recommend games to cover + channels to publish on
- self-hosted: your laptop, your data

## stack

Rails 8.1 · Postgres 17 (pgvector) · Voyage AI · Hotwire · ViewComponent ·
Tailwind CSS · Kamal · Astro (landing).

## getting started

Currently optimized for the author's own machine. Setup docs are sparse on
purpose during the rebuild phase. If you want to try it anyway, see
[`docs/architecture.md`](docs/architecture.md).

## docs

- [`AGENTS.md`](AGENTS.md) — agent instructions readable by Claude Code and
  OpenCode
- [`docs/EXTRA.md`](docs/EXTRA.md) — pito-specific conventions that override the
  generic agent guidance
- [`docs/architecture.md`](docs/architecture.md) — system topology + models +
  canonical namespaces
- [`docs/design.md`](docs/design.md) — visual contract + keybindings +
  terminology
- [`docs/website.md`](docs/website.md) — Astro landing

## project status

- **share but not be accountable.** pito is one person's tool, open-sourced for
  fellow creators who want to self-host. No SLA, no roadmap commitments, no
  support obligation.
- **issues are triaged when there's time.** PRs welcome but not guaranteed to be
  merged.
- **no hosted service from this repo.** for commercial use, contact the author.

## license

AGPL-3.0. See [LICENSE](LICENSE).
