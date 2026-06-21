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

Everything happens in one chatbox: type a `verb`, or reply to any message with
`#<handle> <action>` (the message shows you its handle). `<verb> --help` prints a
man page for any verb. Keywords are case-insensitive and a little natural-language.
The full reference lives in [`CHANGELOG.md`](CHANGELOG.md); the short version:

- **Channels** — connect via Google OAuth (`/connect`), see them all at once with
  basic stats (subs · vids · views), `visit @handle`, or `/disconnect`. Read-only
  except the four YouTube writes below.
- **Videos** — `list vids` with stats columns (views, likes, comments, length,
  status, scheduled, channel, game); `show vid <id>` for detail. The only YouTube
  writes: `publish`, `unlist`, `schedule`, `delete` a video. `sync vids` pulls the
  latest (private uploads included).
- **Games** — `import game [title]` from IGDB; `show game <id>` for genres, themes,
  developer/publisher, release, footage, and **price**. Set fields with
  `platform`, `price set/unset`, and a manual `footage` total.
- **Recommendations** — every game card surfaces **similar games** and the
  **channels** it best fits, powered by Voyage embeddings.
- **Linking** — explicit `link` / `unlink` between a video and a game, both
  directions; **pito** never guesses from titles.
- **Planning** — `schedule <id> slate` shows what's already on the calendar so you
  can spread releases; per-game `price` and `footage` help you budget and plan.
- **Notifications** — Slack + Discord integration (rich, colored, emoji'd) for
  reauth reminders, sync summaries, and upcoming-release countdowns, plus a live
  in-app unread badge.
- **Shinies** — lifetime achievements across subs, views, watch time, likes, and
  comms. They unlock as your channels, videos, and games grow, each arriving as a
  🏆 notification and collected right on the video/game.
- **The shell** — terminal-style chat UI, one font, no hover; **full keyboard
  navigation** (ditch the mouse); themes; per-conversation scope/period that
  persists; self-hosted in Docker; free.

## Stack

Rails 8 · Hotwire · Postgres · Voyage AI · IGDB · YouTube API · Tailwind CSS.

## Requirements

The easy path is **Docker + Docker Compose**. Going native instead, you'll want:

- **Ruby 3.4.9** (pinned in `.ruby-version`; `mise` / `rbenv` / `asdf` will read it)
- **PostgreSQL 17** with the **pgvector** extension (for the recommendation embeddings)
- **ffmpeg** · **imagemagick** · **libvips** (footage probing + cover/thumbnail images)
- A **Rails master key** (your stored API keys are encrypted at rest)

No Redis — background jobs, cache, and websockets all ride on Postgres
(Solid Queue / Cache / Cable). Heads-up: setup is hands-on. This is a one-person
tool wearing its "as-is" sticker proudly.

## Install & run

```bash
git clone https://github.com/gmrdad82/pito && cd pito
```

**One-time secrets** (the bundled `config/credentials.yml.enc` is the author's —
you can't decrypt it, so make your own):

```bash
rm -f config/credentials.yml.enc config/master.key
EDITOR=nano bin/rails credentials:edit        # creates a fresh config/master.key
bin/rails db:encryption:init                  # paste the printed keys into the credentials file
```

(No local Ruby? Run those `bin/rails …` lines inside the container with
`docker compose run --rm web bin/rails …`.)

**Docker (same on Linux, macOS, and Windows via WSL2):**

```bash
RAILS_MASTER_KEY=$(cat config/master.key) bin/boot --totp   # boots Rails + Postgres, enrolls your login
```

Open **http://localhost:3028**. The `--totp` step prints an `otpauth://` URI +
secret — scan it into any authenticator app.

**Native (for hacking on it):** install the deps for your OS, then `bin/setup`
(brings up Postgres + prepares the DB) and `bin/dev` → **http://localhost:3027**.
Enroll your login with `bin/rails pito:tools:totp`.

| OS                | System packages                                                                      |
| ----------------- | ------------------------------------------------------------------------------------ |
| Arch              | `sudo pacman -S postgresql ffmpeg imagemagick libvips` + `pgvector` (extra/AUR)      |
| Ubuntu/Debian/WSL | `sudo apt install postgresql-17 postgresql-17-pgvector ffmpeg imagemagick libvips42` |
| Fedora            | `sudo dnf install postgresql-server pgvector ffmpeg ImageMagick vips`                |
| macOS             | `brew install postgresql@17 pgvector ffmpeg imagemagick vips`                        |

(Package names drift between distro versions — adjust as needed.)

## Accounts & API keys

**pito** needs three sets of credentials. Grab them, then paste them into the chatbox
with `/config` (stored encrypted). Only Google is strictly required to do anything
useful; IGDB and Voyage unlock the game features.

**1. Google / YouTube** _(required — it's the whole point)_

1. [Google Cloud Console](https://console.cloud.google.com/) → create a project.
2. **APIs & Services → Library** → enable **YouTube Data API v3**.
3. **OAuth consent screen** → _External_ → add your own Google account as a test user.
4. **Credentials → Create credentials → OAuth client ID → Web application**. Add the
   authorized redirect URI **`http://localhost:3028/auth/youtube/callback`** (use your
   real host/tunnel if not local). Copy the **Client ID** + **Client secret**.
5. **Credentials → Create credentials → API key**. Copy it.
6. In **pito**: `/config google client_id=… client_secret=… api_key=…`, then `/connect`
   to authorize each channel.

**2. IGDB** _(game data — runs on Twitch)_

1. [Twitch Developer Console](https://dev.twitch.tv/console/apps) → **Register Your
   Application** (any name; OAuth redirect `http://localhost` is fine).
2. Copy the **Client ID** and generate a **Client Secret**.
3. In **pito**: `/config igdb client_id=… client_secret=…`.

**3. Voyage AI** _(embeddings — similar games + channel recommendations)_

1. Sign up at [voyageai.com](https://www.voyageai.com/) → **API Keys** → create one.
2. In **pito**: `/config voyage api_key=…`.

**Optional — Slack / Discord notifications:** create an incoming webhook in each,
then `/config webhook slack=… discord=…`.

## First run

1. `/login <6-digit code>` (from the authenticator you enrolled above).
2. `/config` your keys, then `/connect` your first channel.
3. `list channels` → `sync vids` → `list games`. You're off.

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
| notify  | `/sounds/notify.mp3`  | `mail.wav`     | [516867](https://freesound.org/s/516867/) by PokeyWokey      | CC0       |

## Support

**pito** is one person's tool, but if you're stuck, lost, or just want to report that
the cover art _finally_ loaded — there's a Discord. Pop in, ask away, judgment
kept to a minimum:

👉 **[discord.gg/q947UyDTqJ](https://discord.gg/q947UyDTqJ)**

Or find me on X: 👉 **[@GamerDady82](https://x.com/GamerDady82)**

No SLA, no ticket queue, no "your call is important to us." Just a channel and a
human who checks it between renders.

## License

AGPL-3.0 — see [LICENSE](LICENSE). Use it for whatever you like — self-host it,
fork it, learn from it, build on it. Just don't pass it off as your own thing.
No warranty, as-is. Questions? Ping me: gmrdad82 [at] gmail [dot] com.
