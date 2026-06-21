# Changelog

All notable changes to pito are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/); the project aims for
[Semantic Versioning](https://semver.org/).

## [0.6.0] — unreleased

In progress; entries are added here as they land on `main` (tag created at release).

### Added

- **Shinies** — lifetime achievements across **subs, views, watch time, likes, and
  comms**, on a 22-step tier ladder (1 → 10M) color-coded by tier. Unlocked by a
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
  page never blocks on YouTube, and a refresh mid-fetch is safe.
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
- **Thinking indicator now cycles its verb** every 5s (`doing…` → `computing…` → …)
  instead of showing one fixed word, and the final `…ed for Ns` uses the verb that
  was on screen last. The 5s cadence is a single constant; the animation is
  refresh-safe (time-derived).
- **Stats & legends unified** into reusable components with consistent glyphs —
  `S` subs · `D` vids · `V` views · `L` likes · `C` comms — across `list channels`
  and the `show video` / `show game` cards (which now lead with a bold **Stats**
  heading, left-align their Shinies, and drop the redundant inline legend).
- **`show game` order** — the recommendations card (channel suggestions + similar games)
  now comes **before** the analytics card, so the recommendations land first while the
  slower analytics fill in.
- **Keyboard-shortcut hints shimmer** — every yellow shortcut token now has a slow diagonal
  (top-left → bottom-right) yellow→orange shimmer, staggered per token so they don't pulse in
  unison.
- **shift+r** reply (hashtag) picker now opens **inline above the chatbox** (was a
  centered modal).
- **Unified `--help`** — every command (`/config`, `/games`, slash + chat verbs) renders
  help in one man-page style.
- **Notifications panel** sorts unread-first then read (each newest-first), re-sorting
  live when you mark a row read/unread (cursor preserved).

### Fixed

- `list channels --help` now renders in the man-page format like the other list verbs.
- The intro timestamp (`HH:MM ·`) now leads the copy on a single line across every
  detail and enhanced card (`show video` / `show game`, the linked-game card, analytics,
  shinies) — long copy wraps beneath it instead of the timestamp dropping to its own row.
- `list channels` stat legend is now left-aligned.
- With the **ctrl+k palette open over a sidebar**, arrow/Enter keys now drive only the palette
  — the sidebar/picker keyboard nav bails while the palette is open (no more dual cursor).
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
- Removed the extra gap between the Stats counters and their legend.
- `list games` platform logos now reveal in step with their row (no longer pop in early).

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
