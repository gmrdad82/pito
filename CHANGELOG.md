# Changelog

All notable changes to pito are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/); the project aims for
[Semantic Versioning](https://semver.org/).

## [0.5.0] — 2026-06-20

### Added

- **`schedule <id> slate`** — an upcoming-schedule planner (chat + reply): a
  `:system` "this week" table plus an `:enhanced` "rest of the period" table,
  obeying the shift+tab channel scope and shift+space stats period, excluding the
  reference vid. Columns: `#` · Title · Channel · Scheduled (dd-mm-yyyy hh:mm) · Game.
- **Game price** — `price set <id> <amount>` / `price unset <id>` (chat + reply),
  a right-aligned `€` list column (`list games with price`), an always-shown
  detail/linked-game card row, and `--help`.
- **`today` schedules** — `schedule <id> today [at <time>]`.
- **Rich Slack/Discord notifications** — colored attachments/embeds with a
  severity emoji + color (info / success / warning / error), driven by a
  notification `level`. New notification types plug in with zero webhook changes.
- **Live mini-status** — a new notification broadcasts the unread count to every
  open window without a refresh.
- **Show-game video table** — `show game` now renders the game's videos in the
  real `list videos` table, preceded by a witty channels line.
- **Image sweep tooling** — `rake pito:images:sweep` / `pito:images:fix`
  re-attaches game covers and video thumbnails whose backing files went missing.

### Changed

- `:enhanced` segments share `:system`'s full render template (tables, sections,
  info-lines); accent/background is the only difference.
- A reply that mutates a segment (sort / add column) lifts it onto the surface
  background as a "just changed" cue.
- Game-list **Channels** column collapses to one line (`@first +N more`).
- Case-insensitive keyword input — phone auto-titleization is sanitized, and the
  chatbox no longer auto-capitalizes.
- Stats legend convention: `s` subs · `v` vids · `V` views · `L` likes · `C` comments.
- Game cards label footage **Footage** and always show a **Price** row (`—` when unset).

### Removed

- The root `VERSION` file — versioning now lives in git tags + this changelog.
