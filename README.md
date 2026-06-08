# pito

[![CI](https://github.com/gmrdad82/pito/actions/workflows/ci.yml/badge.svg)](https://github.com/gmrdad82/pito/actions/workflows/ci.yml)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

## Why does this thing exist?

Picture it: you run a fistful of YouTube channels. YouTube Studio, in its
infinite wisdom, lets you manage exactly **one channel at a time** — log out, log
in, log out, log in, repeat until your will to live quietly files for unemployment.
The third-party tools that _do_ juggle multiple channels at once? They'd love
**€50+ a month**, please, forever, amen.

So I did the math. The math said "build it yourself, you cheapskate." So I did.

**pito** is that: one dashboard, every channel, zero monthly ransom, and nobody
handing a random SaaS company the keys to my business. My laptop, my data, my
rules. It scratches my own itch first — if it happens to scratch yours too,
wonderful, that's what the AGPL is for.

And hey — if this saves you a headache (or fifty euros), the nicest possible
"thank you" is a click on one of the channels that dragged this tool into
existence in the first place:

<!-- prettier-ignore -->
<p align="center"><a href="https://www.youtube.com/@gmrdad82"><img src="docs/avatars/@gmrdad82.png" width="80" alt="@gmrdad82"></a> <a href="https://www.youtube.com/@manfyfighting"><img src="docs/avatars/@manfyfighting.png" width="80" alt="@manfyfighting"></a> <a href="https://www.youtube.com/@manfygreats"><img src="docs/avatars/@manfygreats.png" width="80" alt="@manfygreats"></a> <a href="https://www.youtube.com/@manfyhard"><img src="docs/avatars/@manfyhard.png" width="80" alt="@manfyhard"></a> <a href="https://www.youtube.com/@manfystrategy"><img src="docs/avatars/@manfystrategy.png" width="80" alt="@manfystrategy"></a> <a href="https://www.youtube.com/@manfysurvival"><img src="docs/avatars/@manfysurvival.png" width="80" alt="@manfysurvival"></a></p>

---

self-hosted YouTube tool for creators who run multiple channels — track channels,
videos, and analytics in one place, schedule across channels without conflicts,
and get game/channel recommendations. your laptop, your data.

> **alpha, actively rebuilding.** one person's tool, open-sourced as-is. no SLA,
> no roadmap, no support obligation. issues triaged when there's time; PRs
> welcome but not guaranteed to merge. no hosted service from this repo.

## Stack

Rails 8 · Hotwire · Postgres · Voyage AI · Tailwind CSS.

## Getting started

Optimized for the author's own machine; setup docs are sparse on purpose during
the rebuild. To try it anyway, start with
[`docs/architecture.md`](docs/architecture.md).

## Docs

- [`AGENTS.md`](AGENTS.md) — agent instructions (Claude Code / OpenCode)
- [`docs/EXTRA.md`](docs/EXTRA.md) — pito-specific conventions that override the
  generic agent guidance
- [`docs/architecture.md`](docs/architecture.md) — topology, models, namespaces
- [`docs/design.md`](docs/design.md) — visual contract, keybindings, terminology
- [`docs/footage_probe.md`](docs/footage_probe.md) — ffprobe integration, grading detection, rake task usage

## Sounds

| event   | file                  | original       | source                                                       | license   |
| ------- | --------------------- | -------------- | ------------------------------------------------------------ | --------- |
| send    | `/sounds/send.mp3`    | `vs-pop_5.mp3` | [Pop_5.mp3](https://freesound.org/s/463395/) by Vilkas_Sound | CC BY 4.0 |
| receive | `/sounds/receive.mp3` | `pop-1.wav`    | [Pop 1](https://freesound.org/s/545201/) by theplax          | CC BY 4.0 |

## License

AGPL-3.0 — see [LICENSE](LICENSE). Use it for whatever you like — self-host it,
fork it, learn from it, build on it. Just don't pass it off as your own thing.
No warranty, as-is. Questions? Ping me: gmrdad82 [at] gmail [dot] com.
