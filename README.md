# PITO

[![CI](https://github.com/gmrdad82/pito/actions/workflows/ci.yml/badge.svg)](https://github.com/gmrdad82/pito/actions/workflows/ci.yml)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-ff69b4?logo=githubsponsors)](https://github.com/sponsors/gmrdad82)

<!-- prettier-ignore -->
<p align="center"><a href="https://youtu.be/7y3R403XtDE"><img src="docs/media/pito-tour-thumb.png" width="760" alt="▶ PITO — Inception Wednesday: a guided tour"></a></p>
<p align="center"><em>▶ A guided tour of PITO — <a href="https://youtu.be/7y3R403XtDE">watch the tour</a>, on <a href="https://www.youtube.com/@gmrdad82">@gmrdad82</a>.</em></p>

## Why does this thing exist?

Twenty-odd years building Ruby on Rails apps for other people's companies — a lot of
companies, a lot of apps — and then I started my own YouTube adventure with a fistful
of channels. That's when I discovered the tooling situation is grim. YouTube Studio,
in its infinite wisdom, lets you manage exactly **one channel at a time** — log out,
log in, log out, log in, repeat until your will to live quietly files for
unemployment.

So I went shopping. Social Blade, vidIQ, TubeBuddy — I paid for them, gave each a fair
shot, and not one did the specific things I actually needed. They'd love **€50+ a
month**, please, forever, amen, for the privilege of _almost_ fitting.

So I did the math. The math said "build it yourself, you cheapskate." Two decades of
Rails muscle memory agreed. So I did.

## The name

One evening I heard my son singing a little song from school — the old Spanish
counting rhyme kids use to pick who's "it":

> _Pito, pito, gorgorito, ¿a dónde vas tú tan bonito?_

I fell for it on the spot: the sound, the daftness, the way it lodges in your head and
won't leave. So I baptized the thing **PITO** and never looked back.

## What I wanted it to be

Awesome. Glamorous. Charming. Stupidly easy. And **mine** — all mine, built exactly
the way I work, answering to no product manager and no quarterly roadmap.

Then it occurred to me that maybe someone else runs their channels the way I do and
wants the same thing. So here it is: **you can have it too.** Charmingly awesome, and
now open. One dashboard, every channel, zero monthly ransom, and nobody handing a
random SaaS company the keys to my business. My laptop, my data, my rules. It scratched
my own itch first — if it scratches yours, wonderful. That's what the AGPL is for.

And hey — if this saves you a headache (or fifty euros), the nicest possible "thank
you" is a click on one of the channels that dragged this tool into existence in the
first place:

<!-- prettier-ignore -->
<p align="center"><a href="https://www.youtube.com/@gmrdad82"><img src="docs/avatars/@gmrdad82.png" width="80" alt="@gmrdad82"></a> <a href="https://www.youtube.com/@gmrdad82good"><img src="docs/avatars/@gmrdad82good.png" width="80" alt="@gmrdad82good"></a> <a href="https://www.youtube.com/@gmrdad82hard"><img src="docs/avatars/@gmrdad82hard.png" width="80" alt="@gmrdad82hard"></a> <a href="https://www.youtube.com/@gmrdad82fighter"><img src="docs/avatars/@gmrdad82fighter.png" width="80" alt="@gmrdad82fighter"></a> <a href="https://www.youtube.com/@gmrdad82survivor"><img src="docs/avatars/@gmrdad82survivor.png" width="80" alt="@gmrdad82survivor"></a> <a href="https://www.youtube.com/@gmrdad82strategist"><img src="docs/avatars/@gmrdad82strategist.png" width="80" alt="@gmrdad82strategist"></a></p>

---

Self-hosted YouTube tool for creators who run multiple channels — track channels,
videos, and games in one place, schedule across channels without conflicts, and get
game/channel recommendations. Your laptop, your data.

> **one person's tool**, open-sourced as-is. no SLA, no roadmap, no support
> obligation. issues triaged when there's time; PRs welcome but not guaranteed to
> merge. no hosted service from this repo.

## What PITO does that no one else does — not even Studio

Everything in this section is native to PITO and simply **absent** from YouTube
Studio, TubeBuddy, and vidIQ. Not "better" — absent. Studio knows your videos
inside out; it has just never once asked which _game_ you were playing. PITO is
built around that question.

### Which of your channels owns a game

<p align="center"><img src="docs/media/mkt-02-coverage.png" width="760" alt="PITO — cross-channel game coverage: distribution + recommendation"></p>

`show game` answers the one question a multi-channel gamer actually has: side by
side, how this game's coverage is **distributed** across your channels (weighted by
vids + views + lifetime watch-time, streaming in as braille bars) and which channel
it best **fits** next (top-5 recommendation, avatar and score, row-aligned with the
distribution). Nobody else has a cross-channel game view — Studio doesn't even let
a second channel into the same tab.

### And the rest of the loot

<p align="center"><img src="docs/media/mkt-04-releases.png" width="760" alt="Per-platform release dates"></p>

**Release dates per platform — PlayStation, Switch, Xbox, and Steam** — grouped by
date with their logos, and a countdown that names _which_ platform lands ("…on
PlayStation + Steam in 3 days"). Unreleased games re-sync nightly until the date is real.

<p align="center"><img src="docs/media/mkt-01-linkage.png" width="760" alt="Game–video linkage"></p>

**Games ↔ videos, explicitly linked** — `link` / `unlink`, never guessed from titles.
Your library finally knows which game every video covers — and everything below runs
on that graph.

<p align="center"><img src="docs/media/mkt-06-game-analytics.png" width="760" alt="Game-level analytics"></p>

**Analytics at the game level** — avg % viewed, retention, avg view duration,
aggregated across a game's linked vids (channels get the same treatment). Studio does
these strictly one video at a time.

<p align="center"><img src="docs/media/mkt-07-heatmap.png" width="760" alt="Day-of-week heatmap"></p>

**Day-of-week heatmap** — Mon→Sun bars computed from your daily views, busiest day
green. The YouTube API doesn't even offer this dimension; PITO does the math itself.

<p align="center"><img src="docs/media/mkt-05-footage.png" width="760" alt="Per-game footage on the time-to-beat bar"></p>

**Footage hours per game** — your recorded backlog, sitting right on the time-to-beat
bar. "Do I have enough material for this one?" — answered at a glance.

<p align="center"><img src="docs/media/mkt-03-price.png" width="760" alt="Game price"></p>

**Game price, tracked** — coins on the card. Know what covering a slate costs before
you promise it to an audience.

<p align="center"><img src="docs/media/mkt-08-schedule.png" width="760" alt="Schedule slate"></p>

**A calendar that finds the gap** — `schedule … slate` lays out what's already booked
across _every_ channel, so releases spread out instead of quietly stacking on a Tuesday.

<p align="center"><img src="docs/media/mkt-09-share.png" width="760" alt="Shareable message"></p>

**Any message is a link** — `share` mints a public URL to that exact reply, chart
included. Go ahead, try sending someone a Studio screen.

<p align="center"><img src="docs/media/mkt-10-snapshot.png" width="760" alt="Conversation snapshot"></p>

**Conversations are snapshots** — an old conversation still shows your numbers _as
they were_. A time machine no dashboard gives you.

<p align="center"><img src="docs/media/mkt-11-mobile.png" width="760" alt="PITO on mobile"></p>

**Happily mobile** — the chatbox works on your phone. Studio on a phone is… an app
that isn't this.

<p align="center"><img src="docs/media/mkt-13-similar.png" width="760" alt="Similar games"></p>

**Similar games** — Voyage embeddings surface what sits near your library, right on
the game card, with the channels each one fits.

<p align="center"><img src="docs/media/mkt-14-shinies.png" width="760" alt="Shinies"></p>

**Shinies** — lifetime achievement badges across channels, vids, and games.
Gaming-flavored bragging rights that unlock as you grow.

<p align="center"><img src="docs/media/mkt-12-chatbox.png" width="760" alt="The one chatbox"></p>

**And the whole thing is a conversation** — one chatbox, one monospace font, full
keyboard navigation. The features above aren't buried in menus; you _type_ them.

## Features

PITO is best _seen_ — it moves. Animated walkthroughs land here as I record them; for
now, the captions mark the spot.

### 1. One chatbox — that's the entire app

<p align="center"><img src="docs/media/01-chat.gif" width="760" alt="PITO — one chatbox demo"></p>

No menus, no forty-tab settings labyrinth. You type, PITO answers — a terminal-style
chat with keyboard-first UI/UX that gets out of your way and stays out of it.

### 2. Ask in plain language, get your data at a glance

<p align="center"><img src="docs/media/02-language.gif" width="760" alt="PITO — plain-language query demo"></p>

Type the way you think. PITO reads a little natural language, so `list vids`,
`show game`, or a quick question gets you your numbers without hunting through
dashboards.

### 3. Smart linkage: games ↔ videos ↔ channels

<p align="center"><img src="docs/media/03-linkage.gif" width="760" alt="PITO — game/video/channel linkage demo"></p>

Explicitly `link` a video to a game and PITO builds the graph: which games you cover,
which channels they fit, and — via Voyage embeddings — the similar games and best-fit
channels you hadn't thought of. It never guesses from titles; the links are yours.

### 4. A scheduling helper that finds your open slots

<p align="center"><img src="docs/media/04-schedule.gif" width="760" alt="PITO — scheduling helper demo"></p>

`schedule <id> slate` lays out what's already on the calendar across every channel, so
you spread releases instead of stacking them and never quietly double-book a day.

### 5. Themes for every desire

<p align="center"><img src="docs/media/05-themes.gif" width="760" alt="PITO — live theme switching demo"></p>

19 built-in palettes — familiar editor themes, dark and light — switched live with
`/themes` and remembered per your taste. Don't love one? The tokens are right there to
tune.

### 6. Zero infra cost — guides for every step, $0

It runs on a machine you already own, on free, open tooling. The walkthroughs below get
you from nothing to running for **exactly €0** — no servers to rent, no subscription, no
"starter plan."

### 7. Free, and built to grow

Free today and expandable tomorrow: richer natural-language understanding, deeper
analytics, and MCP integrations are on the cards. No feature is going to vanish behind
a paywall later.

### 8. Built by a pro, for himself — no corporate agenda

Two decades of Rails, built for an actual creator's daily workflow — not a growth team's
OKRs. No dark patterns, no upsell nags, no telemetry phoning home. Best from the best,
shipped because it had to exist.

### Everything you can type

Everything happens in one chatbox: type a `verb`, or reply to any message with
`#<handle> <action>` (the message shows you its handle). `<verb> --help` prints a man
page for any verb. Keywords are case-insensitive and a little natural-language. The
full reference lives in [`CHANGELOG.md`](CHANGELOG.md); the short version:

- **Channels** — connect via Google OAuth (`/connect`), see them all at once with
  basic stats (subs · vids · views, `with likes` to add the summed like count),
  `visit @handle`, or `/disconnect`. Read-only except the four YouTube writes below.
- **Videos** — `list vids` with addable columns (channel, visibility, game,
  duration, views, likes, category — `with`/`without`, sortable);
  `show vid <id>` for detail. The only YouTube writes: `publish`, `unlist`,
  `schedule`, `delete` a video. `sync vids` pulls the latest (private uploads
  included).
- **Games** — `import game [title]` from IGDB; `show game <id>` for genres, themes,
  developer/publisher, release, footage, and **price**; `list games` grows columns
  the same way (platform, genre, developer, publisher, channels, footage, price,
  views, likes). Set fields with `platform`, `price set/unset`, and a manual
  `footage` total.
- **Recommendations** — every game card surfaces **similar games** and the
  **channels** it best fits, powered by Voyage embeddings.
- **Linking** — explicit `link` / `unlink` between a video and a game, both
  directions; **PITO** never guesses from titles.
- **Planning** — `schedule <id> slate` shows what's already on the calendar so you can
  spread releases; per-game `price` and `footage` help you budget and plan.
- **Notifications** — Slack + Discord integration (rich, colored, emoji'd) for reauth
  reminders, sync summaries, and upcoming-release countdowns, plus a live in-app unread
  badge.
- **Shinies** — lifetime achievements across subs, subs gained, views, watch time,
  likes, and comms. They unlock as your channels, videos, and games grow, each arriving
  as a 🏆 notification and collected right on the video/game.
- **The shell** — terminal-style chat UI, one font, no hover; **full keyboard
  navigation** (ditch the mouse); themes; per-conversation scope/period that persists;
  self-hosted in Docker; free.

## Themes

PITO ships **19 built-in themes** — familiar editor palettes — switched live with
`/themes` (opens a picker; your choice persists):

- **Dark** — `ayu-dark` · `ayu-mirage` · `catppuccin-mocha` · `dracula` · `github-dark` · `gruvbox-dark` · `nord` · `one-dark` · `solarized-dark` · `synthwave` · `tokyo-night` · `tomorrow-night`
- **Light** — `ayu-light` · `catppuccin-latte` · `github-light` · `gruvbox-light` · `one-light` · `solarized-light` · `tomorrow`

Every theme is a set of CSS custom properties in
[`app/assets/tailwind/themes.css`](app/assets/tailwind/themes.css), so all 19 are fully
supported. That said — I personally run **synthwave**, so most of the visual tuning
(shimmer colors, the `#5170ff` pito-blue accent, contrast choices) is dialed in around
that theme. Everything still works on the others, but if a palette doesn't feel quite
right to you, the tokens are right there: tune them to your preference.

<details>
<summary><b>🎨 Theme gallery — click to expand all 19</b></summary>

**Dark**

|                                                                                        |                                                                                    |
| :------------------------------------------------------------------------------------: | :--------------------------------------------------------------------------------: |
|         **ayu-dark**<br><img src="docs/media/themes/ayu-dark.png" width="380">         |     **ayu-mirage**<br><img src="docs/media/themes/ayu-mirage.png" width="380">     |
| **catppuccin-mocha**<br><img src="docs/media/themes/catppuccin-mocha.png" width="380"> |        **dracula**<br><img src="docs/media/themes/dracula.png" width="380">        |
|      **github-dark**<br><img src="docs/media/themes/github-dark.png" width="380">      |   **gruvbox-dark**<br><img src="docs/media/themes/gruvbox-dark.png" width="380">   |
|             **nord**<br><img src="docs/media/themes/nord.png" width="380">             |       **one-dark**<br><img src="docs/media/themes/one-dark.png" width="380">       |
|   **solarized-dark**<br><img src="docs/media/themes/solarized-dark.png" width="380">   |      **synthwave**<br><img src="docs/media/themes/synthwave.png" width="380">      |
|      **tokyo-night**<br><img src="docs/media/themes/tokyo-night.png" width="380">      | **tomorrow-night**<br><img src="docs/media/themes/tomorrow-night.png" width="380"> |

**Light**

|                                                                                |                                                                                        |
| :----------------------------------------------------------------------------: | :------------------------------------------------------------------------------------: |
|    **ayu-light**<br><img src="docs/media/themes/ayu-light.png" width="380">    | **catppuccin-latte**<br><img src="docs/media/themes/catppuccin-latte.png" width="380"> |
| **github-light**<br><img src="docs/media/themes/github-light.png" width="380"> |    **gruvbox-light**<br><img src="docs/media/themes/gruvbox-light.png" width="380">    |
|    **one-light**<br><img src="docs/media/themes/one-light.png" width="380">    |  **solarized-light**<br><img src="docs/media/themes/solarized-light.png" width="380">  |
|     **tomorrow**<br><img src="docs/media/themes/tomorrow.png" width="380">     |                                                                                        |

</details>

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
(Solid Queue / Cache / Cable). And **no ffmpeg**: PITO itself never shells out to it.
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

<p align="center"><img src="docs/media/pito-install-cast.gif" width="820" alt="curl | sh installing PITO — version picker, then it fetches + sets up"></p>

It first asks **which version** to install — pick a **stable** release (the newest
is the default + recommended) or **edge** (latest image + bleeding-edge CLI from
`main`). Then it asks for the public URL (default **http://localhost:3028**), mints a
fresh master key + credentials (no editor required), enrolls TOTP (scan the printed
`otpauth://` into any authenticator), and — for a non-localhost host — **configures a Cloudflare
tunnel and brings up both the tunnel and pito as systemd services**, so everything
survives a reboot with no manual `cloudflared tunnel run`. When it finishes, open the
URL and `/login`. (The only thing a public host needs that can't be scripted is the
one-time `cloudflared tunnel login` browser approval, which the installer launches for
you. If you already have a tunnel, it's reused untouched.)

**Custom host or in-place install.** Flags pass through with `sh -s --`:

```bash
# set the public host up front, and install into the CURRENT folder (no ./pito subdir):
curl -fsSL https://raw.githubusercontent.com/gmrdad82/pito/main/script/install.sh \
  | sh -s -- --host https://app.example.com --dir .
```

The script's `--help` lists them all: `--host URL`, `--dir DIR` (default `./pito`),
`--version vX.Y.Z` (pin a release) / `--edge` (skip the version prompt),
`--skip-pull`, plus `--service-only` / `--cloudflared-only` to (re)run just the
systemd or tunnel step. You provide nothing else — the master key + credentials are
generated for you; API keys go in later via `/config`.

**Versions: stable vs edge.** `stable` pins a release — image tag _and_ CLI/scripts
come from the same `vX.Y.Z` git tag, so the whole install is reproducible. `edge`
runs the `:latest` image with the CLI tracking `main`. `pito --version` shows which
you're on (`pito 0.7.3 (stable)`); `pito update` lets you move between them.

**Re-running is safe.** Running the installer again keeps your existing master key +
credentials, never touches the Postgres volume (channels, videos, games, `/config`
keys + webhooks), and does **not** re-enroll TOTP — your authenticator keeps working.
To just pull a newer image, use `pito update` (image swap + restart only, nothing
else touched).

The installer symlinks the CLI onto your `PATH`, so **`pito` runs from anywhere**
(if that step is skipped — no sudo — use `./pito` from the install dir instead):

```bash
pito logs -f     # tail the app
pito console     # a Rails console in the container
pito update      # pull the latest image + restart
pito --help      # the rest
```

Same on Linux, macOS, and Windows (WSL2) — and on both amd64 and arm64 (the image is
multi-arch, so a Raspberry Pi 5 or Apple Silicon box is fine too).

**The MCP service.** Alongside the `web` container, the compose file ships a second
Puma, `pito-mcp` — the same image on an isolated port, so a slow AI tool-loop can
never starve the app. `pito update` re-fetches `docker-compose.yml`, then bring it
up with `docker compose up -d pito-mcp`. Your tunnel/reverse proxy routes the paths
`^/(mcp|oauth|\.well-known)` to it (port 3029) and everything else to `web`.

### Connect an AI chat (MCP)

PITO speaks the [Model Context Protocol](https://modelcontextprotocol.io) at
`/mcp`, so an AI assistant can **read** your PITO — your games, videos, channels,
analytics, breakdowns, at-a-glance snapshots, similar games, channel coverage,
shinies, and your past conversations — as first-class tools. It is strictly
**read-only**: nothing it can call changes anything, and MCP calls never appear in
your scrollback or resume sidebar.

To attach a client (e.g. claude.ai, on your phone or desktop):

1. In the client's connector settings, add a custom MCP connector with the URL
   `https://<your-pito-host>/mcp` (whatever domain your tunnel serves, e.g.
   `https://app.pitomd.com/mcp`).
2. The client discovers PITO's OAuth automatically and opens a **consent page** in
   your browser. It shows the app name and the read-only tool list, and asks for
   your current **6-digit TOTP code** — the same code you use for `/authenticate`.
3. Enter the code once to approve. That's it — the client refreshes its access
   silently from then on; you never enter a code again for that client (revoke by
   deleting its `OauthClient` / `OauthToken` rows in `pito console`).

Then ask the assistant things like _"what games does @gmrdad82 play?"_ or _"what did
PITO say about retention yesterday?"_ and it will call the matching tool.

### Native — for hacking on it (development mode)

```bash
git clone https://github.com/gmrdad82/pito && cd pito
```

Make your own secrets (the bundled `config/credentials.yml.enc` is the author's — you
can't decrypt it):

```bash
rm -f config/credentials.yml.enc config/master.key
EDITOR=nano bin/rails credentials:edit   # creates a fresh config/master.key
bin/rails db:encryption:init             # paste the printed keys into the credentials file
```

Then install your OS deps (below), run `bin/setup` (brings up Postgres + prepares the
DB) and `bin/dev` → **http://localhost:3027**. Enroll your login with
`bin/rails pito:totp` — or, in development, just type `/login 123456` (a dev-only
dummy code; see [Operating PITO](#operating-pito)).

| OS                | System packages                                                               |
| ----------------- | ----------------------------------------------------------------------------- |
| Arch              | `sudo pacman -S postgresql imagemagick libvips` + `pgvector` (extra/AUR)      |
| Ubuntu/Debian/WSL | `sudo apt install postgresql-17 postgresql-17-pgvector imagemagick libvips42` |
| Fedora            | `sudo dnf install postgresql-server pgvector ImageMagick vips`                |
| macOS             | `brew install postgresql@17 pgvector imagemagick vips`                        |

(Package names drift between distro versions — adjust as needed. Add `ffmpeg` only if
you want the optional `footage snippet` helper.)

### Not a cloud thing

PITO is built to run **on your own machine** — your laptop, a home server, a NUC under
the TV. There's no hosted service from this repo and no cloud-deploy story baked in
(no Kamal, no Helm, no "click to deploy"). You're welcome to put it behind a domain
with a Cloudflare tunnel (see [Exposing PITO](#exposing-pito-cloudflare-tunnel)) or
deploy it however you please — it's AGPL, go wild — but the supported, tested path is
local self-host.

## Accounts & API keys

**PITO** needs three sets of credentials. Grab them, then paste them into the chatbox
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
6. In **PITO**: `/config google client_id=… client_secret=… api_key=…`, then `/connect`
   to authorize each channel.

**2. IGDB** _(game data — runs on Twitch)_

1. [Twitch Developer Console](https://dev.twitch.tv/console/apps) → **Register Your
   Application** (any name; OAuth redirect `http://localhost` is fine).
2. Copy the **Client ID** and generate a **Client Secret**.
3. In **PITO**: `/config igdb client_id=… client_secret=…`.

**3. Voyage AI** _(embeddings — similar games + channel recommendations)_

1. Sign up at [voyageai.com](https://www.voyageai.com/) → **API Keys** → create one.
2. In **PITO**: `/config voyage api_key=…`.

**Optional — Slack / Discord notifications:** create an incoming webhook in each, then
`/config webhook slack=… discord=…`.

## First run

1. `/login <6-digit code>` (from the authenticator you enrolled above).
2. `/config` your keys, then `/connect` your first channel.
3. `list channels` → `sync vids` → `list games`. You're off.

## Operating PITO

The Docker stack is driven by the **`pito`** CLI (on your `PATH` after install —
or `./pito` from the install dir):

<p align="center"><img src="docs/media/pito-cli-cast.gif" width="820" alt="the pito CLI in action — help, version, logs, rake, backup"></p>

| Command            | What it does                                           |
| ------------------ | ------------------------------------------------------ |
| `pito up` / `down` | start / stop the stack                                 |
| `pito logs [-f]`   | tail container logs (Docker's own — capped + rotated)  |
| `pito console`     | a Rails console inside the running container           |
| `pito rake [task]` | list `pito:*` tasks, or run one in the container       |
| `pito clean`       | clear `tmp/` scratch (keeps storage/pids) + dev logs   |
| `pito totp`        | (re)enroll your login                                  |
| `pito version`     | show the running version + channel (stable/edge)       |
| `pito update`      | update — pick a release (stable) or edge, then restart |
| `pito backup`      | dump DB + Active Storage to `./backups/<ts>/` (host)   |
| `pito build`       | build the image **locally** from a source checkout     |
| `pito self-update` | refresh just the CLI (no image pull / restart)         |
| `pito caddy`       | direct HTTPS via Caddy — the no-tunnel alternative     |
| `pito hetzner`     | provision a Hetzner Cloud box ready to run PITO        |
| `pito autoupdate`  | pull new releases automatically (15-min systemd timer) |

**`pito update`** is the one you'll reach for most — it's interactive: it lists the
available releases (or **edge**) and switches the whole stack (image **and** CLI) to
your pick in one step:

<p align="center"><img src="docs/media/pito-update-cast.gif" width="820" alt="pito update — pick a stable release, the whole stack switches"></p>

### Running a locally-built image

To run your own build instead of a published release — on the **same Docker host**:

```sh
# 1) in a source checkout — build + tag it locally (default tag: `local`)
PITO_TAG=local pito build

# 2) in your install dir — point the stack at that tag and (re)start
echo 'PITO_TAG=local' >> .env      # or edit the existing PITO_TAG line
pito up -d                         # runs the local image; no pull
```

`pito build` tags the image `ghcr.io/gmrdad82/pito:local`; because the install-dir
compose resolves `image: ghcr.io/gmrdad82/pito:${PITO_TAG}`, setting `PITO_TAG=local`
makes `pito up` run your build (Compose uses a present image and never pulls). The
`local` tag keeps it from colliding with a real release. Use **`pito up`**, not
**`pito update`** — `update` pulls from GHCR and would replace the local image. To
return to a release, set `PITO_TAG` back (e.g. `0.8.5`) and run `pito update`.

In-app, **`/jobs`** is your window into the background queue: `/jobs status` (workers,
state counts, recent failures), `/jobs requeue <id|all>`, `/jobs run <key>` (run a
recurring task now), and `/jobs pause` / `/jobs resume`.

**Dev conveniences** (development only — inert in production):

- Recurring jobs are **off** under `bin/dev`, so nothing hits YouTube/Discord while you
  hack. Want the scheduler running? `PITO_DEV_JOBS=1 bin/dev`.
- `/login 123456` just works — no authenticator needed. Change the code with
  `PITO_DEV_TOTP_CODE=…`, or disable it (`PITO_DEV_TOTP_CODE=off`) to exercise the real
  TOTP flow. The dummy code is **impossible** outside development.

### Backups

`pito backup` writes a timestamped folder on the **host** (`./backups/<ts>/`,
git-ignored) with two artifacts:

- `database.sql.gz` — `pg_dump` run inside the Postgres container (version-matched,
  includes the pgvector embeddings).
- `active_storage.tar.gz` — your avatars/thumbnails/covers **and their variants**
  from the assets volume.

It runs against the live stack, so bring it up first (`pito up -d`). The full surface:

| Command                | What it does                                                      |
| ---------------------- | ----------------------------------------------------------------- |
| `pito backup`          | back up DB + assets; **prunes to the newest 7** afterward         |
| `pito backup --list`   | list existing backups with their sizes                            |
| `pito restore <dir>`   | restore a backup over the live stack (prompts — it's destructive) |
| `pito backup-schedule` | install a **daily** systemd timer that runs `pito backup`         |

Tune retention + location with `PITO_BACKUP_KEEP` (default `7`) and `PITO_BACKUP_DIR`
(default `./backups`). `pito backup-schedule` is also offered during install; once set,
backups run daily at 03:00 and self-prune — hands-off rolling backups on the host.

Restore is deliberate (`pito restore` confirms first, then reloads the DB + assets and
restarts the service). The equivalent manual one-liners, if you prefer:

```bash
gunzip -c backups/<ts>/database.sql.gz | docker compose exec -T postgres psql -U pito -d pito_production
gunzip -c backups/<ts>/active_storage.tar.gz | docker compose exec -T web tar xf - -C /var/lib/pito-assets
```

### Auto-update (your server pulls new releases)

Your server keeps itself current — CI never logs in anywhere. **`pito autoupdate`**
checks GitHub for a newer release, waits until the release's multi-arch image is
actually live on GHCR, and applies it with the **same `pito update`** you'd type
by hand. One command turns it on:

```bash
pito autoupdate --install     # systemd timer, every 15 min + logrotate rule
```

Why pull instead of push:

- **Zero deploy credentials in GitHub.** No SSH keys, no host secrets — nothing
  for a public repo to leak, nothing for a compromised action to steal.
- **No inbound access.** CI runners never connect to your server.
- **Fork-friendly.** Any self-hosted instance updates itself without touching
  the upstream repo's CI at all.
- **Race-proof.** `pito update` holds a single-updater lock (`flock` on
  `.pito-update.lock`), so the timer and a manual `pito update` — for when you
  don't feel like waiting 15 minutes — can never run on top of each other.

Everything it does lands in `log/autoupdate.log` (rotated weekly). Optional:
set `SLACK_WEBHOOK=<url>` in the install dir's `.env` and every applied (or
failed) update pings you via a plain `curl`. `pito autoupdate --check` dry-runs
the decision; `pito autoupdate --uninstall` removes the timer.

From then on: `git tag v1.2.3 && git push origin v1.2.3` → green CI gate →
multi-arch image on GHCR → within 15 minutes your server is running it,
hands-off. (Edge-channel installs are deliberately skipped — `latest` stays a
by-hand choice.)

## Exposing PITO (HTTPS)

PITO forces HTTPS in production, so anything past `localhost` needs TLS in front.
Set your public URL at install time (or in `.env` as `PITO_APP_BASE_URL`, e.g.
`https://app.example.com`); that single value wires Host Authorization, link
generation, and asset delivery. The installer offers both mechanisms below —
pick at the HTTPS prompt, or run the matching `pito` command later.

### Cloudflare Tunnel (the default)

The tidiest option for a machine behind NAT (a home box, a laptop) — no open
ports, no certs to babysit.

Install `cloudflared` (`pacman -S cloudflared`, `brew install cloudflared`, or
Cloudflare's apt repo), then the installer — or `pito cloudflared` — drops a starter
`config.yml` and prints the steps:

```bash
cloudflared tunnel login
cloudflared tunnel create pito
cloudflared tunnel route dns pito app.example.com
cloudflared tunnel --config ./cloudflared-config.yml run pito
```

Point the tunnel at `127.0.0.1:3028` and set Cloudflare's SSL/TLS mode to **Full**.

### Caddy direct HTTPS (no tunnel)

For a server with its own public IP (a VPS — see `pito hetzner`), skip the tunnel:
**`pito caddy`** writes a `Caddyfile` for your domain and enables the dormant
`caddy` compose profile in `.env`. Caddy terminates TLS with automatic
Let's Encrypt certificates and proxies to the web container (WebSockets included).

```bash
pito caddy            # writes ./Caddyfile + sets COMPOSE_PROFILES=caddy
pito down && pito up -d
```

Needs your domain's **A record** pointing at the server and ports **80/443** open.
The profile lives in the stock `docker-compose.yml`, so `pito update` never
disturbs it; installs that never ran `pito caddy` don't even start the container.
If the domain is behind Cloudflare's proxy (orange cloud), set SSL/TLS mode to
**Full (strict)** — or keep the record DNS-only and let Caddy carry TLS alone.

## Beyond the browser

The server renders ONE app; everything else is a thin window onto it. No
separate APIs to version, no second UI to maintain — your instance already
serves them all.

- [**`pito-android`**](https://github.com/gmrdad82/pito-android) — a thin
  [Hotwire Native](https://native.hotwired.dev) shell around the same
  server-rendered app, with native navigation and back-stack (the path
  configuration lives at `/configurations/android_v1.json`). Self-hoster
  friendly by design: on first launch the app asks for your instance URL, so
  it works with ANY domain you host PITO on — not just the author's. Signed
  APKs ship on the releases page (no Play Store required), and PITO itself
  offers the download in a dismissible banner when you visit from an Android
  browser.
- [**`pito-tui`**](https://github.com/gmrdad82/pito-tui) — the same chatbox
  in your terminal: Go + Bubble Tea, raw text in, the server's JSON events
  out, live over ActionCable. The grammar stays server-side, so the TUI can
  never lag behind the web.

And when you want the guided-strut version of all this,
[**pitomd.com**](https://pitomd.com)
([source](https://github.com/gmrdad82/pitomd)) is the over-the-top showcase.

## Docs

- [`CLAUDE.md`](CLAUDE.md) — working agreement, plan discipline, condensed architecture + stack principles (read first)
- [`docs/architecture.md`](docs/architecture.md) — topology, models, namespaces
- [`docs/design.md`](docs/design.md) — visual system: typography, theming, color/message palette, component rules
- [`docs/extending.md`](docs/extending.md) — how to add a theme, a language, a new message-content type, or a new fx
- [`docs/footage.md`](docs/footage.md) — per-game manual footage total + `footage snippet` ffprobe one-liner

## Sponsor

PITO is free, AGPL, and costs nothing to give away — but it costs _time_. If it saves
you the €50-a-month the others wanted, you can point a fraction of that back at keeping
it alive and growing, through **GitHub Sponsors**:

👉 **[github.com/sponsors/gmrdad82](https://github.com/sponsors/gmrdad82)**

How it works: pick a tier — a few euros a month, or a one-time tip — and that's it.
GitHub takes **0%** and covers payment processing, so what you pledge is what lands.
There's no paywall and never will be; sponsoring buys you exactly **nothing extra**
except my genuine gratitude and the quiet satisfaction of keeping an indie tool indie.
Monthly pledges are what keep the lights on and the feature list moving; one-time tips
are the "this saved my afternoon" handshake. Either is appreciated more than the badge
can convey.

## Sounds

| event   | file                  | original       | source                                                       | license   |
| ------- | --------------------- | -------------- | ------------------------------------------------------------ | --------- |
| send    | `/sounds/send.mp3`    | `vs-pop_5.mp3` | [Pop_5.mp3](https://freesound.org/s/463395/) by Vilkas_Sound | CC BY 4.0 |
| receive | `/sounds/receive.mp3` | `pop-1.wav`    | [Pop 1](https://freesound.org/s/545201/) by theplax          | CC BY 4.0 |
| notify  | `/sounds/notify.mp3`  | `mail.wav`     | [516867](https://freesound.org/s/516867/) by PokeyWokey      | CC0       |

## Support

**PITO** is one person's tool, but if you're stuck, lost, or just want to report that
the cover art _finally_ loaded, there's a Discord — pop in, ask away, judgment kept to
a minimum 👉 **[discord.gg/q947UyDTqJ](https://discord.gg/q947UyDTqJ)**

Prefer elsewhere? Find me on X 👉 **[@GamerDady82](https://x.com/GamerDady82)**, or on
YouTube at **[@gmrdad82](https://www.youtube.com/@gmrdad82)** — my engineering/personal
channel, where PITO gets its tour. (The gaming side is the **Manfy** network linked up
top.)

No SLA, no ticket queue, no "your call is important to us." Just a channel and a human
who checks it between renders.

## License

AGPL-3.0 — see [LICENSE](LICENSE). Use it for whatever you like — self-host it, fork
it, learn from it, build on it. Just don't pass it off as your own thing. No warranty,
as-is. Questions? Ping me: gmrdad82 [at] gmail [dot] com.
