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

Self-hosted YouTube tool for creators who run multiple channels — track channels,
videos, and games in one place, schedule across channels without conflicts,
and get game/channel recommendations. your laptop, your data.

> **one person's tool**, open-sourced as-is. no SLA, no roadmap,
> no support obligation. issues triaged when there's time;
> PRs welcome but not guaranteed to merge. no hosted service from this repo.

## Features

What pito actually does, no asterisks:

- **Every channel at a glance** — basic stats per channel (subs, vids, views),
  no logging out and back in like it's 2009.
- **Video stats too** — views, likes, comments per vid, right there.
- **Multiple channels at once** — the whole roster on one screen, finally.
- **Actually change things** — publish, schedule, unlist, or delete a video
  straight from the chatbox.
- **`schedule <id> slate`** — see what's already booked this week (and the rest of
  your window) so you don't drop two bangers on the same Tuesday.
- **Upcoming-release radar** — pito nudges you when a game you care about is about
  to launch.
- **Game brains, courtesy of IGDB** — full game info, similar-game suggestions,
  and channel recommendations so you know where a game belongs.
- **Notifications that travel** — Slack and Discord integration, colored and
  emoji'd, for reauth nags, sync summaries, and countdowns.
- **A terminal you'll actually like** — chat-style UI, one font, one size, no
  hover. Full keyboard navigation — throw the mouse in a drawer.
- **Mostly read-only, on purpose** — pito reads your channels and only ever WRITES
  four things: publish, unlist, schedule, delete. Your data stays your data.
- **Natural language, within reason** — type like a human. Limited, but fun, cool,
  and easy to follow.
- **Self-hosted and free** — runs locally in Docker. No SaaS, no subscription, no
  monthly ransom.

## Stack

Rails 8 · Hotwire · Postgres · Voyage AI · IGDB · YouTube API · Tailwind CSS.

## Getting started

Optimized for the author's own machine; setup docs are sparse on purpose during
the rebuild. To try it anyway, start with
[`docs/architecture.md`](docs/architecture.md).

## Docs

- [`CLAUDE.md`](CLAUDE.md) — working agreement, plan discipline, condensed architecture + stack principles (read first)
- [`docs/architecture.md`](docs/architecture.md) — topology, models, namespaces
- [`docs/design.md`](docs/design.md) — visual system: typography, theming, color/message palette, component rules
- [`docs/footage.md`](docs/footage.md) — per-game manual footage total + `footage snippet` ffprobe one-liner

## Sounds

| event   | file                  | original       | source                                                       | license   |
| ------- | --------------------- | -------------- | ------------------------------------------------------------ | --------- |
| send    | `/sounds/send.mp3`    | `vs-pop_5.mp3` | [Pop_5.mp3](https://freesound.org/s/463395/) by Vilkas_Sound | CC BY 4.0 |
| receive | `/sounds/receive.mp3` | `pop-1.wav`    | [Pop 1](https://freesound.org/s/545201/) by theplax          | CC BY 4.0 |

## Support

pito is one person's tool, but if you're stuck, lost, or just want to report that
the cover art _finally_ loaded — there's a Discord. Pop in, ask away, judgment
kept to a minimum:

👉 **[discord.gg/q947UyDTqJ](https://discord.gg/q947UyDTqJ)**

No SLA, no ticket queue, no "your call is important to us." Just a channel and a
human who checks it between renders.

## License

AGPL-3.0 — see [LICENSE](LICENSE). Use it for whatever you like — self-host it,
fork it, learn from it, build on it. Just don't pass it off as your own thing.
No warranty, as-is. Questions? Ping me: gmrdad82 [at] gmail [dot] com.
