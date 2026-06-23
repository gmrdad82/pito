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
- **Shinies** — lifetime achievements across subs, subs gained, views, watch time,
  likes, and comms. They unlock as your channels, videos, and games grow, each
  arriving as a 🏆 notification and collected right on the video/game.
- **The shell** — terminal-style chat UI, one font, no hover; **full keyboard
  navigation** (ditch the mouse); themes; per-conversation scope/period that
  persists; self-hosted in Docker; free.

## Themes

pito ships **19 built-in themes** — familiar editor palettes — switched live with
`/themes` (opens a picker; your choice persists):

- **Dark** — `ayu-dark` · `ayu-mirage` · `catppuccin-mocha` · `dracula` · `github-dark` · `gruvbox-dark` · `nord` · `one-dark` · `solarized-dark` · `synthwave` · `tokyo-night` · `tomorrow-night`
- **Light** — `ayu-light` · `catppuccin-latte` · `github-light` · `gruvbox-light` · `one-light` · `solarized-light` · `tomorrow`

Every theme is a set of CSS custom properties in
[`app/assets/tailwind/themes.css`](app/assets/tailwind/themes.css), so all 19 are
fully supported. That said — I personally run **synthwave**, so most of the visual
tuning (shimmer colors, the `#5170ff` pito-blue accent, contrast choices) is dialed
in around that theme. Everything still works on the others, but if a palette doesn't
feel quite right to you, the tokens are right there: tune them to your preference.

## Stack

Rails 8 · Hotwire · Postgres · Voyage AI · IGDB · YouTube API · Tailwind CSS.

## Requirements

The easy path needs **only Docker** (+ Docker Compose). The image is prebuilt and
pulled from GitHub's registry, so there's nothing to compile and no Ruby to install.

Hacking on it natively instead? You'll want:

- **Ruby 3.4.9** (pinned in `.ruby-version`; `mise` / `rbenv` / `asdf` will read it)
- **PostgreSQL 17** with the **pgvector** extension (for the recommendation embeddings)
- **imagemagick** · **libvips** (game cover / thumbnail image processing)

No Redis — background jobs, cache, and websockets all ride on Postgres
(Solid Queue / Cache / Cable). And **no ffmpeg**: pito itself never shells out to it.
The only place it comes up is the optional `footage snippet` helper — a copyable
one-liner _you_ run in your own video folder (it uses `ffprobe`) to total your raw
hours. Install ffmpeg only if you want that convenience, wherever your footage lives.
Heads-up: setup is hands-on. This is a one-person tool wearing its "as-is" sticker
proudly.

## Install & run

Two ways in. **Docker runs production mode; native runs development mode.**

### Docker — the easy path (only Docker needed)

No clone, no Ruby. One command fetches a small `./pito` install (a compose file + the
`pito` CLI), generates your _own_ secrets, pulls the prebuilt image, and walks you
through enrolling a login:

```bash
curl -fsSL https://raw.githubusercontent.com/gmrdad82/pito/main/script/install.sh | sh
```

It asks for the public URL (default **http://localhost:3028**), mints a fresh master
key + credentials (no editor required), enrolls TOTP (scan the printed `otpauth://`
into any authenticator), and offers a Cloudflare tunnel + a systemd unit for
reboot-persistence. When it finishes, open the URL and `/login`.

Everything after that runs from the `./pito` dir:

```bash
./pito logs -f     # tail the app
./pito console     # a Rails console in the container
./pito update      # pull the latest image + restart
./pito --help      # the rest
```

Same on Linux, macOS, and Windows (WSL2) — and on both amd64 and arm64 (the image
is multi-arch, so a Raspberry Pi 5 or Apple Silicon box is fine too).

### Native — for hacking on it (development mode)

```bash
git clone https://github.com/gmrdad82/pito && cd pito
```

Make your own secrets (the bundled `config/credentials.yml.enc` is the author's —
you can't decrypt it):

```bash
rm -f config/credentials.yml.enc config/master.key
EDITOR=nano bin/rails credentials:edit   # creates a fresh config/master.key
bin/rails db:encryption:init             # paste the printed keys into the credentials file
```

Then install your OS deps (below), run `bin/setup` (brings up Postgres + prepares the
DB) and `bin/dev` → **http://localhost:3027**. Enroll your login with
`bin/rails pito:tools:totp` — or, in development, just type `/login 123456` (a
dev-only dummy code; see [Operating pito](#operating-pito)).

| OS                | System packages                                                               |
| ----------------- | ----------------------------------------------------------------------------- |
| Arch              | `sudo pacman -S postgresql imagemagick libvips` + `pgvector` (extra/AUR)      |
| Ubuntu/Debian/WSL | `sudo apt install postgresql-17 postgresql-17-pgvector imagemagick libvips42` |
| Fedora            | `sudo dnf install postgresql-server pgvector ImageMagick vips`                |
| macOS             | `brew install postgresql@17 pgvector imagemagick vips`                        |

(Package names drift between distro versions — adjust as needed. Add `ffmpeg` only if
you want the optional `footage snippet` helper.)

### Not a cloud thing

pito is built to run **on your own machine** — your laptop, a home server, a NUC under
the TV. There's no hosted service from this repo and no cloud-deploy story baked in
(no Kamal, no Helm, no "click to deploy"). You're welcome to put it behind a domain
with a Cloudflare tunnel (see [Exposing pito](#exposing-pito-cloudflare-tunnel)) or
deploy it however you please — it's AGPL, go wild — but the supported, tested path is
local self-host.

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

## Operating pito

The Docker stack is driven by the **`pito`** CLI (run from your install dir):

| Command            | What it does                                          |
| ------------------ | ----------------------------------------------------- |
| `pito up` / `down` | start / stop the stack                                |
| `pito logs [-f]`   | tail container logs (Docker's own — capped + rotated) |
| `pito console`     | a Rails console inside the running container          |
| `pito rake [task]` | list `pito:*` tasks, or run one in the container      |
| `pito clean`       | clear `tmp/` scratch (keeps storage/pids) + dev logs  |
| `pito totp`        | (re)enroll your login                                 |
| `pito update`      | pull the latest image + restart                       |

In-app, **`/jobs`** is your window into the background queue: `/jobs status`
(workers, state counts, recent failures), `/jobs requeue <id|all>`, `/jobs run <key>`
(run a recurring task now), and `/jobs pause` / `/jobs resume`.

**Dev conveniences** (development only — inert in production):

- Recurring jobs are **off** under `bin/dev`, so nothing hits YouTube/Discord while
  you hack. Want the scheduler running? `PITO_DEV_JOBS=1 bin/dev`.
- `/login 123456` just works — no authenticator needed. Change the code with
  `PITO_DEV_TOTP_CODE=…`, or disable it (`PITO_DEV_TOTP_CODE=off`) to exercise the
  real TOTP flow. The dummy code is **impossible** outside development.

## Exposing pito (Cloudflare Tunnel)

pito forces HTTPS in production, so anything past `localhost` needs TLS in front. The
tidiest option is a **Cloudflare Tunnel** — no open ports, no certs to babysit. Set
your public URL at install time (or in `.env` as `PITO_APP_BASE_URL`, e.g.
`https://app.example.com`); that single value wires Host Authorization, link
generation, and asset delivery.

Install `cloudflared` (`pacman -S cloudflared`, `brew install cloudflared`, or
Cloudflare's apt repo), then the installer — or `./pito cloudflared` — drops a starter
`config.yml` and prints the steps:

```bash
cloudflared tunnel login
cloudflared tunnel create pito
cloudflared tunnel route dns pito app.example.com
cloudflared tunnel --config ./cloudflared-config.yml run pito
```

Point the tunnel at `127.0.0.1:3028` and set Cloudflare's SSL/TLS mode to **Full**.

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
