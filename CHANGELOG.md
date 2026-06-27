# Changelog

All notable changes to PITO are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/); the project aims for
[Semantic Versioning](https://semver.org/).

## [0.8.5] — Unreleased

A broad follow-up to **analtics**: a full `show channel` surface, sharper `sync`
and `analyze` reply flows, named conversations, a faster/cleaner notifications
panel, a self-hosted typeface, and an exhaustive dispatcher-recognition spec net
that hardens every verb/keyword combination across the slash, hashtag, and chat
stacks. (Bespoke analytics view components close out the tag.)

### Added

- **`show channel`** — a full channel surface: a `:system` detail card (with
  last-sync time and a trimmed linked-game card), an `:enhanced` repliable vids
  list, and an `:enhanced` channel analytics glance. Channels now carry a
  `description` synced from the YouTube snippet.
- **Named conversations** — `/new <name>` opens a titled conversation and
  `/resume <name>` jumps straight to it. A miss offers a clicky "create it"
  affordance plus up to five fuzzy-matched suggestions to resume instead.
- **`/rename`** — rename the current conversation from the chatbox.
- **`sync` targets specific vids** — `sync vid|vids|video|videos #id[,#id…]`
  syncs exactly those videos (ids win); bare `sync vids` obeys the shift+tab
  channel scope (mirroring `analyze`).
- **`show` replies route by card** — replying to a `:system` card runs `sync`
  for that entity; replying to an `:enhanced` glance runs `analyze` — for vids,
  games, and channels alike.
- **`/authenticate`** is now an alias for `/login`; while logged out, the slash
  suggestions surface only `/login`, and the other verbs explain that login is
  required.
- **`list … with <cols> sort by <col>`** combine cleanly, with `sort` / `sorted`
  / `order` / `ordered` (and an optional `by`) all accepted.
- **Game platforms** — `platform set` / `platform unset` add and remove a game's
  platforms.
- **Paginated notifications panel** — loads 50 at a time and fetches more as you
  scroll (or press ↓ at the bottom), with a shimmering-dot loader and a playful
  "end of the list" marker (a new reusable copy dictionary). Replaces the old
  load-everything panel.
- **Async conversation deletion** — `dd` in the /resume sidebar hands the
  (potentially slow) cascade to a background job while the row shows a
  shimmering-dots placeholder; the state is persisted, so reopening the sidebar
  mid-delete still shows the dots.
- **Chatbox history recall** — oh-my-zsh-style prefix recall: type a prefix and
  walk previous matching commands.
- **Self-hosted DejaVu Sans Mono** — the terminal typeface (plus a braille face)
  is now bundled and subset, replacing Iosevka; source-misaligned ASCII art fixed.
- **`vid` category column** in `list vids`.

### Changed

- **Notification badge** in the mini-status is a compact cyan-shimmer **`N*`**
  (was `N notifs`) and is **clickable** — click it (or `ctrl+/`) to toggle the
  notifications sidebar. The /resume sidebar shortcut labels are trimmed to
  `n rename` / `dd delete`.
- **`/config` credentials** dual-route to the right provider and mask secrets at
  the source.
- **Slash palette** triggers argument completion on a trailing space and sends on
  Enter at the verb stage.
- **`list channels`** is ordered by most-recently-published vid.

### Fixed

- **Owner-set game platforms survive an IGDB re-sync** (no longer overwritten).
- **`/connect`** no longer shows a no-handle confirmation when already connected.
- **Channel avatar filenames are channel-unique** so the CDN can't serve a stale
  cached image across channels.
- **Follow-up parity** — delete/publish aliases, implicit `price <id> <amount>`,
  footage reply parity, and repliable publish/unlist/schedule on a video card,
  with the schedule id-less reply bug fixed.

### Reliability

- **Exhaustive dispatcher-recognition specs** — a fast, DB-free spec net asserts
  the system's understanding of every verb × every keyword combination (with and
  without args, plus unknown inputs) across the slash, hashtag, and chat stacks.

## [0.8.0] — 2026-06-26

The **analtics** release — a chat-first `analyze` verb over the YouTube Analytics
API: per-video primitives cached (completed periods frozen forever), aggregated
across any scope, and rendered as metrics you refine with `with` / `without`.

### Added

- **`analyze` verb** (synonyms `analytics`, `stats`) — both as a chat verb
  (man-style `--help` + autosuggest) and via a `#<handle>` reply. Targets
  channels, vids, or games (id lists + synonyms accepted); scope resolves from the
  shift+tab channel filter and runs over the shift+space period. Each run fans out
  into atomic per-video / per-channel requests.
- **Analytics primitives store + completed-period freeze.** Per-video raw reports
  are cached in Postgres keyed by `(subject, report, date-range)` —
  entity-agnostic, so a video fetched for one scope warms every later scope that
  shares it (a channel analysis warms a later game analysis, no extra YouTube
  calls). A period whose end-date is ≥ 7 days past is **frozen permanently**
  (YouTube finalizes metrics in ~2–3 days); live periods carry a 1h TTL.
- **Two messages per analyze — `:system` + `:enhanced`** — each its own 50-variant
  copy dictionary. Every ordered metric renders as a "data-pulled" scaffold cell
  through one generic component (bespoke per-metric components come in a later
  pass). The per-message thinking indicator spans the message's full fan-out.
- **Refine with `with` / `without`.** Chat `analyze … with X,Y` / `without X,Y`
  whitelists or excludes metrics; replying `with` / `without` to an analyze message
  **mutates it in place** (re-rendered from the persisted scaffold, no re-fetch),
  while replying to a `show vid` / `show game` analytics glance emits a fresh
  analyze pair.
- **`show vid` / `show game` analytics glance is repliable** and now renders
  through the shared analytics component, with a witty nudge toward `analyze`.
- **ASCII art fits narrow screens.** A scale-to-fit controller uniformly shrinks
  the start-screen logo and in-message art (e.g. `/connect`) to fit mobile widths
  — alignment preserved, still live themed text — with desktop untouched.
- **`link` accepts multiple vids in one chat command** (`link game 1 with vid
15,14`), matching the reply path.

### Changed

- **"Comms" → "Comments" everywhere user-facing**, pluralized (1 comment / N
  comments). `comms` is still accepted as an input alias (with/without + columns).
- **IGDB import sidebar** renders at the single 14px base size (no font-size drift).

### Fixed

- **Shinies pluralize at a count of 1** — "1 Like" / "1 Sub" / "1 View" /
  "1 Comment", not "1 Likes" — across every metric.
- **Compact counts round down, never up** (`2,259` → `2.2K`), so a displayed count
  never overstates the real number.
- **A new `:system` / `:confirmation` message retires all prior live `#<handle>`
  replies** uniformly — typed verbs and replies-that-append alike — so stale reply
  affordances don't linger. Repeatable verbs (link/unlink) and in-place mutations
  are exempt.

## [0.7.6] — 2026-06-25

The **golden tape** release — the README now _moves_, and game prices read as coins.

### Added

- **CLI casts in the README** (recorded with [VHS](https://github.com/charmbracelet/vhs),
  themed in PITO's own synthwave palette):
  - **Operating PITO** — `pito --help` → `version` → `logs` → `rake` → `backup`, live.
  - **Install** — `curl | sh` showing the version picker → fetch (the "one line" proof).
  - **`pito update`** — the interactive stable/edge version picker switching the stack.
- **`Pito::Coin` — price as coin tiers.** Game prices now read at a glance as
  spinning gold coins instead of a bare `€`: 1 coin (≤ €9.99, budget) up to 5
  (> €79.99, premium/collector), thresholds at `9.99 / 29.99 / 59.99 / 79.99`.
  Price has three meanings: **unset** (`nil`) renders `—`, an **explicit 0** renders
  a Mario-style **star** + `0.00` (deliberately free — "genuine value", its own state,
  settable via `price set <id> 0`), and **> 0** renders the coins + the number
  (`🪙🪙🪙 59.99`). `Pito::Coin` owns the tier; `Pito::Formatter::Price` owns the number
  and the nil-vs-0 distinction (`unpriced?` / `free?`); `Pito::Game::PriceGlyphs`
  renders. Shows in the game list Price column, the game detail card (`:system`), and
  the linked-game card (`show vid` `:enhanced`).
- **`price` verb in `shift+r` replies.** Reply to a `list games` message with
  `#<handle> price set <id> <amount>` (or `price set <id> 0` for free) — previously
  only `show game` replies could set price.
- **Linked games in `list vids with games`.** The Game column now shows
  `#<id> <title>`, with `#<id>` a clickable cyan shimmer token (like the vid `#` id)
  that opens `show game #<id>`.

### Fixed

- **A not-found reply no longer consumes the `#<handle>`.** Replying to a
  `list games` / `list vids` / a `show game` linked-vids `:enhanced` list with a bad
  id (`#<handle> show 999`) returned the friendly "Don't have 999." but silently
  consumed the source's reply handle, so you couldn't retry without repeating the
  whole command. The not-found now keeps the list repliable (`Chat::Result::Ok` gained
  a `consume:` flag, set `false` for not-founds and forwarded by `ChatResultAdapter`).

## [0.7.5] — 2026-06-24

The **papercuts** release — chat/slash autosuggest + reply-shortcut fixes.

### Fixed

- **`/config` now submits cleanly.** The slash palette kept offering credential
  keys even while you typed a value or after you'd supplied them all, so Enter
  re-selected a key instead of sending. It now suggests nothing while you type a
  value and excludes keys already set — once they're all in, the palette closes and
  Enter submits. (No more dummy token to dismiss it.)
- **`sync` autosuggest.** Typing `sync channels ` now ghost-suggests `with`, then
  `with ` suggests `vids` — matching how `list … with` already completes.
- **`shift+r` (reply) works without focusing the chatbox first.** It's a global
  shortcut again: when the box isn't focused (and you're not typing in another
  field), `shift+r` focuses it and starts the reply.
- **`import` help is no longer truncated.** The hint read `import game <title>`, and
  `<title>` was parsed as an HTML tag — eating the rest of the line. Now `[title]`.

## [0.7.4] — 2026-06-24

The **safety-net & self-service** release: hands-off restorable backups, version
channels you pick at install/update time, and `pito` as a real PATH command.

### Added

- **Version channels (stable / edge).** Install and `pito update` are now
  interactive — pick a **stable** release (image tag _and_ CLI/scripts pinned to the
  same `vX.Y.Z` git tag, fully reproducible) or **edge** (`:latest` image + CLI from
  `main`). Available releases are listed live from the GitHub API. Non-interactive
  flags: `--version vX.Y.Z` / `--edge`. `.env` records `PITO_TAG` + `PITO_REF`.
- **`pito --version`** — shows the running version + channel (e.g.
  `pito 0.7.3 (stable)`), read from the image's OCI labels + `.env`.
- **Scheduled backups.** `pito backup-schedule` installs a daily systemd timer
  (`pito-backup.timer`, 03:00) that runs `pito backup` and self-prunes to the
  newest **7** — rolling, hands-off backups on the host. Also offered during
  install. Retention + location tune via `PITO_BACKUP_KEEP` / `PITO_BACKUP_DIR`.
- **`pito restore <dir>`** — restore a backup over the live stack (DB + assets),
  with a confirmation prompt (it's destructive) and a service restart after.
- **`pito backup --list`** — list existing backups with their artifact sizes.
- **`pito` on your `PATH`.** The installer now symlinks the CLI to
  `/usr/local/bin/pito`, so it runs as a bare `pito` from anywhere (the CLI
  resolves the symlink back to its install dir). `pito link` / `--link-only`
  (re)adds it, `pito update` keeps it current; `./pito` from the install dir
  still works if the symlink step is skipped.

### Changed

- **`pito backup` now prunes** to the newest `PITO_BACKUP_KEEP` (default 7) after
  each run, and honors `PITO_BACKUP_DIR`. The asset archive already captured
  rendered variants (same disk root); that's now documented.
- **README tour thumbnail** — the hero now uses the real "Inception Wednesday"
  tour-video thumbnail, pre-sized to its display width (no browser downscaling).

## [0.7.3] — 2026-06-24

The **less-is-more** release. The published image goes on a serious diet —
**870 MB → 365 MB (−58 %)** — without giving up a single feature, backups move out
of the container onto the host where they actually survive, and the installer
finally finishes the job (services enabled, tunnel running) on its own.

### Added

- **`pito backup`** — a host-side, durable backup. Writes `./backups/<timestamp>/`
  on the host: `database.sql.gz` (via `pg_dump` run inside the Postgres container —
  version-matched, pgvector embeddings included) and `active_storage.tar.gz` (your
  avatars/thumbnails/covers). Restore is a documented one-liner. Replaces the old
  in-container task, which quietly wrote backups _inside_ the ephemeral web
  container — i.e. straight into the void on the next recreate.
- **Hands-off self-host.** The installer now **enables + starts** the `pito` systemd
  service itself (no more "here's the command to run"), and **configures + runs
  cloudflared as a service** — tunnel config lands in `~/.cloudflared/config.yml`,
  an existing tunnel is reused, and the tunnel comes up on boot with no manual
  `cloudflared tunnel run`. Re-running the installer is idempotent: it keeps your
  master key, Postgres volume (channels/videos/games/`/config` keys), and TOTP.
  `pito update` is systemd-aware too — it pulls, restarts via the service (`sudo
systemctl restart pito`) so the unit stays the owner, and prunes the old image.
- **Dev tabs are unmistakable.** In development the favicon turns **red** and a
  full-width **DEVELOPMENT** banner pins to the bottom (label from `Pito::Copy`), so
  a dev tab is never confused for production.

### Changed

- **Image rebuilt on Alpine/musl: 870 MB → 365 MB.** `ruby:3.4-alpine`; the runtime
  stage carries only shared libraries (`vips`, `libpq`); the build toolchain and
  `-dev` headers live in the discarded build stage. Native gems (nokogiri, pg, ffi,
  ruby-vips) and Thruster run on musl; the POSIX-sh entrypoint replaces the bash one.

### Removed

- **From the runtime image:** the build-only **Tailwind CLI** (~114 MB; CSS is
  precompiled at build time), the shipped **bootsnap cache** (rebuilt lazily — first
  boot is a touch slower, the only tradeoff), gem documentation, **`postgresql-client`**
  (backup is host-side now), **`curl`**, the C toolchain, and **bash/zsh** (busybox
  `sh` is the shell).
- **In-container backup** — `Pito::Tools::Backup` + the `pito:tools:backup` rake task,
  superseded by `pito backup`.

### Fixed

- **The DEVELOPMENT banner reaches both edges** — dropped a dead `scrollbar-gutter:
stable` that reserved a permanent ~6 px strip down the right of every page (the
  window never scrolls; only the inner scrollback does).

## [0.7.2] — 2026-06-24

The **polish, prose & paper-cuts** release. PITO gets its proper name (uppercase,
at last), a README that actually moves, a guide for extending it — and a fistful of
fixes for the ways it used to quietly eat your message or refuse to install.

### Added

- **`docs/extending.md`** — concrete, code-grounded guides for the four common
  extensions: a new **theme**, a new **language**, a new **message-content type**,
  and a new reveal **fx**. Dual-audience (human contributors and AI agents alike).
- **README revamp** — the origin story (the name is a Spanish nursery rhyme), the
  "why it exists" pitch, **animated GIFs** of the chat / linkage / scheduling /
  themes, a **collapsible 19-theme gallery**, and a Sponsor section. Install docs gain
  the `--host` / `--dir .` flags for a non-interactive, in-place install.

### Changed

- **pito → PITO.** The product name is now written PITO in all prose and user-facing
  copy. Code identifiers stay lowercase — the `Pito::` namespace, the `pito` CLI,
  `bin/pito`, `pito.copy.*` i18n keys, URLs, and paths are unchanged.
- **Leaner image.** `.dockerignore` now excludes `node_modules`, `docs/` (incl. the
  ~14 MB media gallery), `spec/`, and the dev `public/pito-storage` blobs — roughly
  60 MB off a local build, ~17 MB off the published image.

### Fixed

- **The chatbox no longer eats your message.** Removing the `/up` route in 0.7.0 left
  the cable-health monitor pinging a now-404 endpoint, so ~60 s into every session it
  falsely flagged the WebSocket "offline" — after which hitting Enter reloaded the
  page (restoring a previous view) instead of sending. The brittle HTTP poll is gone;
  submission always POSTs over HTTP regardless of cable state.
- **The Docker install actually installs.** Two fresh-install crashes fixed: an unset
  `RAILS_MASTER_KEY` was injected as a blank string and corrupted credential
  generation (dropped from compose — the mounted master key is the source of truth);
  and the compose `:ro` mount auto-created `config/credentials.yml.enc` as a
  read-only **directory** before it existed, crashing the generator (bootstrap now
  uses a plain `docker run`).
- **Shinies messages are no longer falsely repliable** — they carried a `#handle`
  reply target nothing consumed; the dead handle (and its `shift+r` affordance) is
  gone.

## [0.7.1] — 2026-06-23

The **polish** release on top of 0.7.0: PITO now keeps your pictures, talks back
when you say hello, ships its arm64 image without the emulation tax, and stops
pinging Slack five times for one green push.

### Fixed

- **Active Storage blobs now persist.** The production image runs as a non-root
  user, but the Active Storage `:local` root (`/var/lib/pito-assets`, backed by
  the persistent `rails_storage` volume) was never created in the image — so a
  freshly-attached Docker volume came up root-owned and the first avatar / cover
  art / video thumbnail upload (and its vips variants) failed with `EACCES`. The
  `Dockerfile` now creates that directory owned by the runtime user **before**
  dropping privileges, so the volume is seeded writable and your media survives
  container recreate, rebuild, and `docker compose pull`. (Postgres data already
  persisted via its own volume.)

### Added

- **Greetings & farewells.** `hi` / `hello` / `hola` / `hey` / `yo` / `good
morning` … and `bye` / `goodbye` / `hasta luego` / `ciao` / `later` … now get a
  witty reply (one of 50 variants each) instead of an error — matched as
  whole-input phrases in the chat parser, isolated from the verb grammar.
- **Witty fallback for nonsense.** Input PITO genuinely can't parse ("boo!", "I'm
  hungry") no longer errors; it returns a `:system` reply from 50 variants, always
  nudging toward `help`. Errors are now reserved for _recognised_ verbs with bad
  arguments.

### Changed

- **Release builds arm64 on a native runner.** Multi-arch publishing moved off
  QEMU emulation onto native per-arch runners (`ubuntu-24.04` for amd64,
  `ubuntu-24.04-arm` for arm64) with a digest-merge step — far faster, same
  `linux/amd64 + linux/arm64` result, so Apple Silicon / Raspberry Pi self-hosters
  keep a native image.
- **Slack CI notifications de-spammed + randomized.** One push used to fire ~5
  green pings (CI ×2 + JS + Docs + Release). Now exactly one green "heartbeat"
  (the CI `rails` job); every other workflow notifies only on failure. The
  Deadpan Butler also picks from a pool of lines so it stops repeating itself.

## [0.7.0] — 2026-06-23

The **local-first self-host** release. PITO stops being "clone the repo and pray"
and becomes "one command, on your own machine." No cloud, no Kamal, no monthly
anything — your laptop, your data, still.

### Added

- **Docker self-host in one command.** `curl … script/install.sh | sh` lands a tiny
  `./pito` install (compose file + CLI), generates your _own_ secrets
  non-interactively (no editor, no host Ruby), pulls a **prebuilt multi-arch image**
  from `ghcr.io/gmrdad82/pito`, enrolls your TOTP login, and offers a Cloudflare
  tunnel + a systemd unit for reboot-persistence. No git clone.
- **`pito` operator CLI** — one self-contained script (no repo, no Ruby) for the
  Docker stack: `up`/`down`, `totp`, `console`, `logs`, `rake`, `clean`, `install`,
  `update`, `service`, `cloudflared`.
- **`/jobs` slash command** — your window into SolidQueue: `status` (workers, state
  counts, recent failures), `requeue <id|all>`, `run <key>` (run a recurring task
  now), `pause` / `resume`. Its subcommands autocomplete in the command palette.
- **Background jobs actually run in production** — the Docker stack runs the
  SolidQueue supervisor inside Puma (`SOLID_QUEUE_IN_PUMA`), so chat-triggered jobs
  and the recurring schedule (nightly sync, achievements, release countdowns) fire on
  a single self-host box without a separate worker process.
- **`pito:tools:clean`** — clears the `tmp/` scratch (keeping `tmp/storage`, `tmp/pids`,
  and `.keep`) and truncates dev `log/*.log`. Safe for blobs: dev Active Storage lives
  under `public/pito-storage`, not `tmp/`.
- **`PITO_APP_BASE_URL`** — set your public host once; it wires Host Authorization,
  URL helpers, and asset delivery. Pairs with a Cloudflare Tunnel for remote access.
- **Dev conveniences** — `PITO_DEV_JOBS=1 bin/dev` to run the recurring scheduler
  locally, and a development-only `/login 123456` dummy code (override with
  `PITO_DEV_TOTP_CODE`, disable with `…=off`) so you can sign in without an
  authenticator. Both are impossible outside development.
- **Release pipeline** — `.github/workflows/release.yml` builds + pushes the
  multi-arch image to GHCR on a **version-tag push only** (never per-commit); a new
  CI `scripts` job shellchecks every shell script.

### Changed

- **Explicit environments**: Docker runs **production**, native `bin/dev` runs
  **development** — documented end to end.
- **Recurring jobs are off under `bin/dev`** by default, so a dev box never quietly
  hits YouTube/Discord on a cron.
- **Leaner, tidier container**: production image drops test-group gems
  (`BUNDLE_WITHOUT="development test"`); compose caps container log growth via the
  json-file driver and mounts each owner's own secrets over the baked-in copies.
- **Fixed the stock `bin/` scripts**: `bin/setup` no longer waits on a phantom
  `redis` (and uses the right compose stack); `bin/test` works again (added the
  missing `bin/test-prepare`). `bin/boot` is now a thin shim forwarding to `pito`.
- **The `shift+r` reply hint now shows on every addressable message** (not just the
  most recent), so any message with a `#handle` is one click from a reply.
- Agent/working docs moved from `tmp/docs` to a gitignored `docs/claude/`.

### Fixed

- **Authenticated 404s no longer 500.** The not-found page rendered the start screen
  with `channels: nil`, blowing up `@channels.any?`; channels now coerce to `[]`.
  (Also explains the occasional dropped chat turn — a request that 500s never finishes.)
- **The game picker no longer hijacks the chatbox.** With a picker sidebar open, its
  keyboard nav stole Enter — injecting `show`/`rm game #id` over whatever you were
  typing. It now ignores keys while focus is in a field outside the picker.

### Removed

- **Kamal** (`config/deploy.yml`, `.kamal/`, `bin/kamal`) — PITO is local-only; there
  was never a cloud-deploy story to maintain.
- The stock **`/up` health route** — single-owner tool, not a load balancer.
- **Action Mailer, Action Mailbox, and Action Text** — all unused (notifications ride
  Slack/Discord webhooks).
- The **`jbuilder`** and **`bcrypt`** gems — neither was used.

## [0.6.0] — 2026-06-23

The **it-has-to-look-good** release. PITO grows a trophy cabinet (shinies),
learns to shimmer, trails a comet behind your cursor, and surfaces analytics at a
glance — because if you're going to stare at your numbers all day, they ought to
look good doing it.

### Added

- **Shinies** — lifetime achievements across **subs, subs gained, views, watch time, likes,
  and comms** (subs is channel-only; subs gained is per video/game), on a 22-step tier ladder
  (1 → 10M) color-coded by tier. Unlocked by a
  standalone 3×/day refresh; each unlock fires a **🏆 notification** (Slack /
  Discord + in-app), and the biggest shiny per metric shows on the video/game.
- **`shinies` command** — `shinies channel @handle` / `shinies video <id>` /
  `shinies game <id>` (also context-aware as a reply): a full per-metric breakdown —
  title, a full-width progress track, and the obtained shinies in order.
- **Footage** row on the `show game` card (before Price).
- **Stats counters under the cover** on `show game` (views / likes / comms, summed
  from linked videos), like `show video`.
- **Notification sound** — a short chime plays when a notification arrives
  (debounced for bursts; never on read/unread toggles; respects `/config sound off`).
- **`/notifications` renamed to `/notifs`** — opens the notifications panel (same as `ctrl+/`).
- **Analytics on `show video` & `show game`** — the enhanced card now shows a scalar
  table (views, watch hours, avg view duration, avg % viewed, subs gained/lost, likes,
  dislikes, comms) with **trend-coloured numbers** vs the prior period (green up / red
  down, neutral otherwise). For a game the figures are **summed across its linked
  videos**. The card appears instantly with a one-line intro and **fills in the
  background** — the "thinking…" spinner keeps cycling until the numbers land, so the
  page never blocks on YouTube, and a refresh mid-fetch is safe. The metrics lay out in
  uniform key/value columns that fill the card width and wrap aligned (every key shares one
  width, every value another, so a metric landing on the next row lines up with the row above).
- **Smarter `list` parsing** — `list` with no noun lists the **games** library, and filter terms
  are matched against a known vocabulary (genre aliases like `rpg`/`fps`, platform synonyms like
  `ps5`/`switch`, and `upcoming`); any token that isn't recognized vocabulary is treated as filler
  and **silently dropped** instead of rejected. So `list rpg ps5 please` lists games filtered to the
  **Role-playing** genre on **PlayStation 5**, ignoring `please` — no "didn't understand" error.
  When an unrecognized token (≥4 chars) is within two edits of a real genre/platform/`upcoming`/noun
  term, `list` offers that correction (`list rpgg` → _"Did you mean `rpg`?"_) instead of listing.
  Noun routing runs through one shared vocabulary: `games`/`game`/`gamez` → games,
  `channels`/`channel` → channels, `videos`/`video`/`vids`/`vid` → videos.
- **Message intros shimmer their subject** — the subject of an intro (the video / game title, or
  the `count` + noun in list intros like "11 games" / "6 channels") now carries a pito-blue→purple
  shimmer, and channel `@handle` references in intros shimmer cyan. Titles stay HTML-escaped.
- **Every message types out, each with its own thinking indicator** — response messages now
  reveal via the typewriter (including the detail / list / analytics / shinies HTML cards, not just
  plain text), and each message carries its **own** thinking indicator that resolves when _that_
  message is ready; a turn finishes only when all resolve, so a still-filling analytics card keeps
  its own spinner while the rest of the turn settles. Your typed command also **types itself back**
  as the echo, and the working-dots clear the moment that echo lands (not when the whole turn
  finishes). Under the hood, typed commands and `#handle` replies now run through one
  shared dispatch finalizer, so replies get identical canonical message kinds and honor the
  selected period / channel / viewport — exactly like typing the command.
- **Custom block cursor with a kitty-style trail** — the chatbox's block cursor now leaves a
  short, fast-fading trail as it moves (matching kitty's `cursor_trail`), and the same custom
  block cursor now appears on the single-line inputs too — game/video pickers, IGDB search,
  conversation rename, and the `ctrl+k` palette (made monospace to match). On a word-jump
  (`ctrl+arrow`, `Home`/`End`, or a far click) the trail draws a **continuous morphing comet** (3–5
  stretched segments that tile edge-to-edge, no gaps) — full height at both ends, pinching thin
  through the middle — that streaks from the old caret position to the new one and retracts toward
  the cursor. The caret and its trail are **pito-blue**. Respects
  `/config motion` + reduced-motion (solid block, no trail/blink when off).
- **`/config` autosuggest** — typing `/config ` shows a **browsable list** of providers, and
  `/config <provider> ` lists that provider's setting/credential key names (secrets masked) —
  navigate with ↑/↓ + Enter (the suggestion now layers _below_ the block cursor — above the
  type-fx and trail layers — fixing a case where the cursor was hidden while a suggestion showed).
- **Reveal effects** — pick how messages reveal with **`/config fx <typewriter|scramble|comet>`**
  (default typewriter): **typewriter** (now log-scaled, so long messages don't drag — a fast floor,
  capped ceiling), **scramble** (the whole line sits as random-glyph noise and decrypts left→right
  to the real text), or **comet** (a blurred light-sweep wipes across the line, revealing the text
  behind it as it passes). `/config fx --help` shows each one live, looping. Bars, avatars, covers,
  and thumbnails always pop in whole; respects `/config motion` + reduced-motion.
- **`dd` deletes a conversation** — in the conversations sidebar, pressing `d` twice (arm →
  confirm) deletes the highlighted conversation; a `dd` hint shows beside the rename hint.
- **Mobile swipe-to-delete** — on touch screens, swipe a conversation row left to reveal a red
  **delete** button (tap to confirm; no accidental full-swipe). Desktop keeps `dd`.
- **Searchable picker sidebars** — `show game` with no id now has a **search box** and shows
  **PS · Switch · Steam** icons beside each game; `show vid` with no id opens a matching picker
  with a search box and the channel **@handle** beside each video (it previously errored
  "Which game?"). Both load 50 rows and re-query the whole library as you type — with the
  same shimmering dots indicator the game-import search shows while a query is in flight;
  pick with ↑/↓ + Enter.

### Changed

- `show video` & `show game`: the key-value table moves up with **Title as its first
  row**; the **Description** moves below it.
- **`comments` → `comms`/`Comms`** everywhere user-facing (`comments` still accepted
  as an alias).
- **Mini-status bar:** "notification(s)" → **notif / notifs**; the auth label is now a
  configurable **nickname** (set with `/config me nickname=…`, default `gmrdad82`) when
  signed in, and **tarnished** when not.
- **Thinking indicator now cycles its verb** every 5s (`Executing…` → `Computing…` → …)
  instead of showing one fixed word, and the final `…ed for Ns` uses the verb that
  was on screen last. The 5s cadence is a single constant; the animation is
  refresh-safe (time-derived).
- **Stats counters reworked** into reusable components — `show video` / `show game` read
  `42 Views · 4👍 · 0💬` (full-word labels, with thumbs-up / message-square icons for likes &
  comments), `list channels` reads `Subs · Views` with `Vids` on its own row; both lead with a
  **Stats** heading and left-aligned Shinies. The separate stat **legend is gone** (self-explanatory).
  Icons are vendored **Lucide** outlines (no gem, ≤1em, theme-aware via `currentColor`).
- **`show game` order** — the recommendations card (channel suggestions + similar games)
  now comes **before** the analytics card, so the recommendations land first while the
  slower analytics fill in.
- **Keyboard-shortcut hints shimmer** — every yellow shortcut token has a slow diagonal
  yellow→orange shimmer, staggered per token so they don't pulse in unison.
- **Identifiers shimmer** — channel `@handles`, video/game `#ids`, and the `@all` /
  period (e.g. `28d`) scope chips now carry a slow diagonal **cyan→pito-blue** shimmer
  everywhere they appear (detail cards, list rows & sortable column headers, pickers,
  recommendations, the chatbox filter). Reply tokens (`#chi-4450`) get a distinct
  **blue→purple** shimmer so they read apart from `@handles`/`#ids`. All shimmer kinds
  share 20 staggered offsets so neighbouring tokens never pulse in sync, and all respect
  `prefers-reduced-motion`.
- **shift+r** reply (hashtag) picker now opens **inline above the chatbox** (was a
  centered modal).
- **Unified `--help`** — every command (`/config`, `/games`, slash + chat verbs) renders
  help in one man-page style.
- **Notifications panel** sorts unread-first then read (each newest-first), applied server-side
  when the panel opens (marking a row read/unread updates it in place without re-sorting — see
  _Notifications read-state_ below).
- **Analytics now follow the shift+space interval.** The glance figures on `show video` /
  `show game` are computed for whatever window you've selected (7d / 28d / 3m / 1y /
  lifetime), default **7d**, persisted per conversation — change it with shift+space and it
  sticks across reloads. The default lives on the conversation, not in the analytics layer.
- **Analytics table** — each metric is a label/value pair (label left, value right-aligned) that
  flows in a flex-wrap row, auto-filling as many columns as the width allows, in canonical order
  Views, Watched hours, Avg view duration, Avg viewed %, Subs, Likes, Comms. **Subs shows
  `+gained/-lost`** (green gained / red lost); **Likes is compacted to `N👍/N👎`** in a single
  cell (thumbs-up green / thumbs-down red — the standalone Dislikes row is gone); Comms is a
  plain count.
- **Trend numbers** (the green/red analytics figures) now shimmer in the same diagonal
  direction as the other shimmers, sharing the same 20 staggered offsets.
- **Reply tokens recoloured** — the `#chi-4450` reply handle shimmer is now **purple→blue**
  (it was blue→purple), keeping it visually distinct from the cyan `@handle` / `#id` shimmer.
- **Shimmer phases scatter properly** — neighbouring tokens (sequential `#ids`, similar
  `@handles`) no longer drift into near-sync; the offset is now a hashed (CRC32) bucket so
  close values land far apart in the 20-slot cycle.
- **Similar-games line** drops the middot — now just `#id Game Title` (shimmer id + a thin flex
  gap + title).
- **Shinies badges redesigned** — every badge now uses one uniform **rounded** border (was a
  per-metric ASCII box), with a soft highlight that **travels around the border edge**, and the
  unlock date is muted. (This also fixes badges rendering with a misaligned right edge on mobile.)
- **Shinies badges: two forms + full-word labels** — badges render as **compact** (value + word,
  e.g. `1K Subs`) or **extended** (value + word, with the muted unlock date on a second line),
  and use full-word labels (Subs / Views / Likes / Comms / Watched) instead of abbreviations.
- **Milestone track points at your next goal** — the reached portion of a shinies progress
  track now shimmers in the **colour of the next tier** you're climbing toward (blue heading to
  2K, cyan heading to 500, …), so the track shows momentum, not just history.
- **Score & time-to-beat bars shimmer** — a subtle pito-blue highlight sweeps across the
  gradient bars on the `show game` card.
- **`show game` cover pans** — the tall portrait cover now sits in a 16:9 box matching the video
  thumbnail and slowly drifts top↔bottom (Ken-Burns) to reveal the whole art; static and
  top-anchored when `/config fx` is off or reduced-motion is on.
- **Mobile-adaptive detail cards** — on narrow screens (< 768px) the `show video` /
  `show game` cards (and the linked-game card) stack into a single column — cover/thumbnail
  on top, the details table beneath — instead of being squeezed into two columns; desktop
  keeps the two-column layout. (PITO's first responsive breakpoint.)
- **Linked-game card upgraded** — when a video links a game, `show video`'s linked-game card now
  uses the same big Ken-Burns cover + two-column layout as `show game` (was a small static cover),
  stacking on mobile.
- **Mobile hairline divider** — on narrow screens (< 768px), a faded hairline now separates the
  cover/thumbnail column from the details table on the `show video` / `show game` / linked-game
  cards (hidden on desktop, where the two-column layout needs no divider).
- **Keyboard-shortcut hints are now tappable** — every shortcut hint (`Esc`, `shift+r`,
  `shift+tab`, `shift+space`, `ctrl+k`, `ctrl+/`, `m`, …) responds to a click/tap by firing
  the same action as the key, so the app is usable on touch/mobile. They also show a pointer
  cursor so the tap target is obvious; otherwise unchanged.
- **`Esc` hint is now a real keybinding** — the `Esc` shown on the command palette and the
  sidebars renders as the standard yellow shortcut (with the shimmer) and is tappable, like
  every other keyboard hint, instead of plain dim text.
- **Mobile sidebar overlay** — on narrow screens (< 768px) the sidebar (conversations,
  notifications, pickers, themes) opens as a **full-width overlay on top** of the
  conversation instead of squeezing it; desktop keeps the side-by-side panel. Still respects
  `/config fx` (snaps instead of animating when motion is off).
- **Command-palette commands are clickable** — clicking a `ctrl+k` palette row selects it and
  prefills the command into the chatbox (same as arrow-to-it + Enter — press Enter to run), and the
  command token (e.g. `/connect`) shimmers cyan.
- **Sidebar rows are clickable** — game/video pickers, `/resume` conversations, and IGDB
  import results activate on click, identical to highlighting + Enter.
- **Notifications read-state** — moving the cursor onto a notification marks it read; clicking
  toggles read/unread; the list no longer re-sorts live (it re-sorts only when the panel is
  re-opened, so rows don't jump). The `SPACE`-to-toggle binding is removed.
- **Shinies progress track** — the in-progress segment (your current standing → the next tier)
  now shimmers too, in the next tier's colour. The track also **collapses** to a compact
  windowed view — `1 … prev current next … 10M` — with a shimmering `─···─` ellipsis bridging
  the skipped tiers, so it reads cleanly (especially on mobile).
- **Click an `#id` to open it** — clicking a video/game `#id` anywhere in the scrollback
  (detail/recommendation cards, list rows, the linked-videos/linked-game cards) fills
  `show video #id` / `show game #id` and **runs it** (auto-submit). Clicking a reply `#handle`
  (or its `shift+r` hint) fills `#handle ` ready for a verb — prefill only, no submit.
- **Timestamp middot dropped everywhere** — message intros now read `HH:MM intro` (a single
  space, no `·`) across every message, not just the similar-games line.

### Fixed

- `list channels --help` now renders in the man-page format like the other list verbs.
- Clicking the `shift+tab` / `shift+space` hints now **cycles the channel / period in place**
  instead of yanking focus into the chatbox (the other tappable hints still focus, as before).
- The intro timestamp (`HH:MM`) now leads the copy on a single line across every
  detail and enhanced card (`show video` / `show game`, the linked-game card, analytics,
  shinies) — long copy wraps beneath it instead of the timestamp dropping to its own row.
- With the **ctrl+k palette open over a sidebar**, arrow/Enter keys now drive only the palette
  — the conversation list, notifications, the game/video pickers, and the IGDB import-results picker
  all bail while the palette is open (no more dual cursor).
- The notification chime no longer plays when you **toggle a notification read/unread** — it
  sounds only for a genuinely new notification (tracked by the latest notification id, not the
  unread count, which a toggle also moves).
- Sidebar lists (notifications, pickers, conversations) now scroll fully to the top — the
  first row is no longer clipped by the top fade gradient at max scroll.
- The sidebar no longer lingers on the **start screen / 404** — deleting your last
  conversation drops you to the start screen with the sidebar dismissed (it was being
  re-opened from `localStorage` right after the dismiss).
- **Analytics now actually appear** on `show video` / `show game` — the filled table was
  rendering without a replaceable DOM id, so the background job's live update never landed
  on the page (it sat on the intro). The card now updates in place the moment the data is ready.
- `list games` platform logos now reveal in step with their row (no longer pop in early).
- **Avatars, video thumbnails and game cover art no longer vanish** — local (dev)
  ActiveStorage moved out of `tmp/` (which gets wiped) into a gitignored `public/` folder
  that survives, and the image-repair sweep (`rake pito:images:fix`) now also re-attaches
  missing channel avatars (not just covers/thumbnails).
- **Replies now behave exactly like typed commands.** Triggering `show` (or any verb) from a
  `#handle` reply previously diverged from typing it: its analytics card stayed stuck on the
  placeholder and never filled, errors were swallowed silently, and no "thinking…" spinner
  showed. Replies now fill analytics, surface errors in the scrollback, and show the spinner —
  same as chat.
- **`show vid` linked-game card was missing its `#id` row** — added, with the shimmer id, to
  match the full game card.
- **Security:** list-mutation replies (`#handle add/remove/sort …`) now require an active
  session, like every other command (they were ungated).
- **Recommendation score bar** no longer touches the game title above it (added spacing).
- **Stats / Shinies headings** on the `show video` / `show game` cards render at normal weight
  (not bold), and their badges use the compact dateless form.
- **Removed the redundant "Scheduled" column** from `list videos` — it showed `—` for nearly
  every row. (The `list videos scheduled` filter still works.)
- **Removed the underline** on the `list channels` `@handle` link (it kept the cyan shimmer).
- **`schedule` and `slate` now autosuggest** — the `schedule` reply verb shows in the
  typeahead and `slate` (schedule to the next open slot) is offered for its argument, in both
  chat (`schedule <id> slate`) and replies (`#<handle> schedule slate`).
- **List-column reply verbs renamed `add`/`remove` → `with`/`without`** — matching the
  `list … with <col>` chat syntax (`#<handle> with views, likes` / `#<handle> without game`).
  The old `add`/`remove` are no longer accepted.
- **Lists default to newest-first** — `list channels`, `list videos`, and `list games` now
  sort by **ID descending** (biggest/newest first) by default instead of alphabetically; an
  explicit `sort by <col>` still overrides.
- **Reply typeahead shows every available verb** — typing `#<handle> ` now opens a palette of
  all the actions valid for that message (`with`, `without`, `shinies`, `schedule`, `show`,
  `link`, …), navigable with arrows/Tab, instead of only ever ghosting the first one (`show`).
  Fixes `with`/`without`/`shinies`/`schedule` being effectively invisible in replies.
- **Bar / track shimmers now stagger** — the score & time-to-beat bars and the shinies progress
  track had their per-element offset reset by an `animation` shorthand (defined after the offset
  classes), so they pulsed in unison; switched to animation longhands so the 20 staggered offsets
  apply.
- **Time-to-beat bar glyphs no longer vanish mid-shimmer** — the `=` fill stays painted at every
  frame (the highlight now rides over the glyphs instead of dropping the text clip).
- **Shinies badge ring & progress-track highlight** use a **per-tier contrasting accent** instead
  of white (white read poorly on the lighter tiers); theme-aware across all palettes.
- **Repeated list tokens no longer pulse in sync** — the shimmer offset is now seeded by row id,
  so the same `@handle` repeated down every row scatters across the 20 offsets.
- **Consumed list headers go quiet** — once a list message is consumed (historical scrollback),
  its sortable column headers render plain muted instead of shimmering and bold; live lists still
  shimmer.
- **Conversation rename shortcut** moved from `` ` `` to `n` (and `ctrl+`` ` ```→`ctrl+n`).
- **`/config fx` is now `/config motion`** for the on/off animation toggle — `/config fx` was
  repurposed to select the reveal effect (above).
- Analytics "Watch hours" label corrected to "Watched hours".
- Mobile sidebar no longer opens scrolled below the fold — the conversations header + list are
  anchored to the top on open (an in-place rename no longer yanks the list back to the top).

## [0.5.0] — 2026-06-20

The first tag. The actual headline: **it exists, and it mostly works.** One person
can run a fistful of YouTube channels from a single chatbox without renting a SaaS
subscription by the month — there are almost certainly a few bugs lurking in here,
but the core loop holds and the lights stay on.

Because it's the first release, this entry documents the **whole command language**
rather than a diff; future releases will only note what changed. Everything below
is typed into the one chatbox; replies use a `#<handle>` prefix the message itself
shows you.

### What works today

- Manage **many YouTube channels** from one chat-style terminal — mostly
  read-only; the only writes to YouTube are **publish / unlist / schedule / delete**.
- **Games** from IGDB with **similar-game** and **channel** recommendations
  (Voyage embeddings), explicit **video ↔ game linking**, a manual **footage**
  total, and a per-game **euro price**.
- **Slack & Discord** notifications (rich, colored, emoji'd) for reauth, sync
  summaries, and upcoming-release countdowns — with a live in-app unread badge.
- Full **keyboard navigation**, self-hosted via Docker, free.

### Command language — chat verbs

Each verb has a `--help` man page (`<verb> --help`).

| Verb                  | Forms                                                                   | What it does                                                                        |
| --------------------- | ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `list`                | `list games \| list vids \| list channels`                              | List your library; games/vids take `with <columns>` and `sorted by <column> [desc]` |
| `show`                | `show game <id>` · `show vid <id>`                                      | Detail card (by id); vids also show the linked-game card                            |
| `delete` (alias `rm`) | `delete game <id>` · `delete video <id>`                                | Delete a game or vid (confirmation first)                                           |
| `link`                | `link video <id> to game <id>[,…]` · `link game <id> to video <id>[,…]` | Link a vid to a game (explicit, both directions)                                    |
| `unlink`              | `unlink video <id> from game <id>[,…]`                                  | Remove a video ↔ game link                                                          |
| `publish`             | `publish video <id>`                                                    | Set a vid public on YouTube (clears any schedule)                                   |
| `unlist`              | `unlist video <id>`                                                     | Set a vid unlisted on YouTube                                                       |
| `schedule`            | `schedule video <id> <when>` · `schedule <id> slate`                    | Schedule a future publish, or show the upcoming slate                               |
| `price`               | `price set <id> <amount>` · `price unset <id>`                          | Set/clear a game's euro price (> 0)                                                 |
| `footage`             | `footage update <id> <hours>` · `footage snippet`                       | Set a game's manual footage total, or copy an ffprobe one-liner                     |
| `platform`            | `platform <id> <name>`                                                  | Set a game's platform from free text (ps5, switch, steam)                           |
| `reindex`             | `reindex game <id>` · `reindex video <id>`                              | Re-embed in Voyage                                                                  |
| `import`              | `import game [title]` · `import vids [for @handle]`                     | Import a game from IGDB, or pull newer YouTube vids                                 |
| `sync`                | `sync vids [only id,…]` · `sync channels [with vids]`                   | Sync vids/channels from YouTube (scope via shift+tab)                               |
| `find`                | `find [<status>] [<genre>] [for <platform>]`                            | Search vids                                                                         |
| `help`                | `help`                                                                  | List every reply target and its actions                                             |

**`list games with <columns>`** — `platform`, `genre`, `developer`, `publisher`,
`channels`, `release`, `year`, `footage`, `price`. **`list vids with <columns>`** —
`channel`, `status`, `game`, `scheduled`, `length`, `views`, `likes`, `comments`.
Both accept `sorted by <column> [desc]`.

**`schedule … <when>`** (local, ≥30 min out): `today`, `today at 14:30`,
`today at 3am`, `in 30m`, `in 2 hours`, `in 3 days`, `tomorrow`, `tomorrow at noon`,
`tomorrow night`, `at 2pm`, `at 3:10am`, `at 23`, `at 15:30`, `saturday at noon`,
`next friday`, `next week`, `3 weeks from now`, `next month`, `for DD.MM.YYYY HH:MM`,
`DD-MM-YYYY HH:MM`. Keywords are case-insensitive (phone titleization is tolerated).

### Command language — replies (`#<handle> <action>`)

Repliable messages carry a `#<handle>`; reply to act on that message's subject.

| Surface      | Actions                                                                                                                                                                                                            |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Game detail  | `rm`/`delete`, `reindex`, `link to vid <id>[,…]`, `unlink from vid <id>[,…]`, `footage <hours>`, `platform <name>`, `price set <amount>` / `price unset`                                                           |
| Game list    | `show <id>`, `rm`/`delete <id>`, `add`/`remove <columns>`, `sort`/`order by <col> [desc]`, `link`/`unlink <game> to/from <vid>[,…]`                                                                                |
| Video detail | `rm`/`delete`, `reindex`, `link to game <id>[,…]`, `unlink from game <id>[,…]`                                                                                                                                     |
| Video list   | `show <id>`, `schedule <id> <when>` / `schedule <id> slate`, `publish <id>`, `unlist <id>`, `delete`/`rm <id>`, `add`/`remove <columns>`, `sort`/`order by <col> [desc]`, `link`/`unlink <vid> to/from <game>[,…]` |
| Channel list | `visit @handle`                                                                                                                                                                                                    |
| Confirmation | `confirm` (`yes`/`y`/`ok`) · `cancel` (`no`/`n`)                                                                                                                                                                   |

### Command language — slash commands

`/login <TOTP>`, `/logout`, `/new`, `/resume`, `/connect`, `/disconnect @handle`,
`/games import [title]`, `/themes`, `/help`, and `/config <provider> [key=value …]`
(providers: `google`, `voyage`, `igdb`, `webhook`, `sound`, `fx`, `timezone`).

### Notifications & integrations

- Rich Slack attachments + Discord embeds with a severity emoji + color
  (`info` / `success` / `warning` / `error`); new notification types plug in with
  zero webhook changes.
- New notifications broadcast their unread count to every open window live.
- Sources: YouTube reauth reminders, video-sync summaries, upcoming-release
  countdowns, and write-through rejections.

### Other UI/behaviour

- `:enhanced` segments share `:system`'s full render template (tables, sections);
  accent/background is the only difference.
- A reply that mutates a segment (sort / add column) lifts it onto the surface
  background as a "just changed" cue.
- Game-list **Channels** column is one line (`@first +N more`).
- Stats legend: `s` subs · `v` vids · `V` views · `L` likes · `C` comments.
- Per-conversation channel scope (shift+tab) + stats period (shift+space) persist
  across reloads.

### Removed

- The root `VERSION` file — versioning now lives in git tags + this changelog.
