# Changelog

All notable changes to pito are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/); the project aims for
[Semantic Versioning](https://semver.org/).

## [0.6.0] — 2026-06-23

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
  page never blocks on YouTube, and a refresh mid-fetch is safe. The metrics lay out in
  uniform key/value columns that fill the card width and wrap aligned (every key shares one
  width, every value another, so a metric landing on the next row lines up with the row above).
- **Smarter `list` parsing** — `list …` now ignores conversational filler (`list rpg ps5 please`
  just works, never a "didn't understand" error), and for a near-miss genre/platform/noun typo it
  suggests a correction (`list rpgg` → *"Did you mean `rpg`?"*) instead of failing. Noun aliases —
  `gamez`, and singular `video`/`channel`/`game` — route consistently (the `game`/`games` nouns
  still work).
- **Message intros shimmer their subject** — the subject of an intro (the video / game / channel
  title, or the `count` + noun in list intros like "11 games" / "6 channels") now carries a
  pito-blue→purple shimmer, and channel `@handle` references in intros shimmer cyan. Titles stay
  HTML-escaped.
- **Every message types out, each with its own thinking indicator** — response messages now
  reveal via the typewriter (including the detail / list / analytics / shinies HTML cards, not just
  plain text), and each message carries its **own** thinking indicator that resolves when *that*
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
  (`ctrl+arrow`, `Home`/`End`, or a far click) the trail draws a **morphing comet** — full height
  at both ends, pinching thin through the middle — that streaks from the old caret position to the
  new one and retracts toward the cursor. The caret and its trail are **pito-blue**. Respects
  `/config motion` + reduced-motion (solid block, no trail/blink when off).
- **`/config` autosuggest** — typing `/config ` shows a **browsable list** of providers, and
  `/config <provider> ` lists that provider's setting/credential key names (secrets masked) —
  navigate with ↑/↓ + Enter (the suggestion also now layers above the cursor, fixing a case where
  it was hidden).
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
- **Thinking indicator now cycles its verb** every 5s (`doing…` → `computing…` → …)
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
- **Notifications panel** sorts unread-first then read (each newest-first), re-sorting
  live when you mark a row read/unread (cursor preserved).
- **Analytics now follow the shift+space interval.** The glance figures on `show video` /
  `show game` are computed for whatever window you've selected (7d / 28d / 3m / 1y /
  lifetime), default **7d**, persisted per conversation — change it with shift+space and it
  sticks across reloads. The default lives on the conversation, not in the analytics layer.
- **Analytics table** — a clean two-column grid, each value right-aligned: `Views | Watched
  hours`, `Avg view duration | Avg viewed %`, `Subs | Likes`, then `Comms` on its own row.
  **Subs shows
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
- **Similar-games line** drops the middot — now just `#id Game Title` (shimmer id + a single
  space + title).
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
  keeps the two-column layout. (pito's first responsive breakpoint.)
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
- **Command-palette commands are clickable** — clicking a `ctrl+k` palette row selects + runs
  it (same as arrow-to-it + Enter), and the command token (e.g. `/connect`) shimmers cyan.
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
- **Conversation rename shortcut** moved from `` ` `` to `n` (and `ctrl+`` ` ``` → `ctrl+n`).
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
