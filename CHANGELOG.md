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
- **Footage** row on the `show game` card (before Price).
- **Stats counters under the cover** on `show game` (views / likes / comms, summed
  from linked videos), like `show video`.

### Changed

- `show video` & `show game`: the key-value table moves up with **Title as its first
  row**; the **Description** moves below it.
- **`comments` → `comms`/`Comms`** everywhere user-facing (`comments` still accepted
  as an alias).
- **Mini-status bar:** "notification(s)" → **notif / notifs**; "authenticated / not
  authenticated" → **well known / unknown**.
- **shift+r** reply (hashtag) picker now opens **inline above the chatbox** (was a
  centered modal).

### Fixed

- `list channels --help` now renders in the man-page format like the other list verbs.

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
