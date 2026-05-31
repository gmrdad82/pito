# pito — architecture

## Static UI baseline (Plan 1)

Plan 1 delivers the static visual chassis — no wiring, no real data, no Stimulus, no Action Cable.

### Production routes

| Path     | Controller#action    | Description                                                                     |
| -------- | -------------------- | ------------------------------------------------------------------------------- |
| `/`      | `terminal#show`      | Chat shell with hardcoded sample messages. Main pito interface.                 |
| `/start` | `start_screens#show` | Start screen for unauthenticated entry. Centered chatbox, ASCII logo, tip line. |

### Review-only routes (removed in Plan 2+)

| Path            | Controller#action   | Description                                                        |
| --------------- | ------------------- | ------------------------------------------------------------------ |
| `/_ui/palettes` | `_ui/palettes#show` | Static preview of slash and Ctrl+P command palettes.               |
| `/_ui/sidebar`  | `_ui/sidebar#show`  | Static preview of the game-detail sidebar as a right-edge overlay. |

These review routes exist only for visual inspection during development. In Plan 2+, palettes and sidebar become interaction-driven overlays and the `/_ui/*` routes are removed.

### UI stack

- **CSS**: Tailwind v4 via `tailwindcss-rails` (standalone CLI, zero Node.js). Theme tokens as CSS custom properties under `[data-theme="tokyo-night"]`.
- **Components**: `view_component` gem. Namespace: `Pito::*`. All visual primitives build on `Pito::Segment::Component` (bar+gap+content pattern).
- **i18n**: All user-facing copy in `config/locales/pito/<area>/en.yml`. Sample message bodies under `config/locales/pito/sample/en.yml` — replaced when real data is wired.
- **JS**: None in Plan 1. Turbo + Stimulus + importmap-rails available but unused.

### Component tree

```
Pito::Segment::Component          — bar+gap+content layout primitive
Pito::Cursor::Component           — inverted-character cursor

Pito::Shell::ChatboxComponent     — input area (uses Segment + Cursor)
Pito::Shell::MiniStatusComponent  — connection/auth status bar
Pito::Shell::PostCommandDotsComponent — animated comet dots
Pito::Shell::InProgressComponent  — spinner + shimmer verb

Pito::Event::UserMessageComponent     — user chat message
Pito::Event::AssistantTextComponent   — assistant response
Pito::Event::ThoughtComponent         — "Thought:" prefix + duration
Pito::Event::ToolOutputComponent      — expandable command output
Pito::Event::StatusFooterComponent    — mode · agent · duration

Pito::StartScreen::Component     — full-viewport start screen

Pito::Palette::Slash::Component        — /-prefixed command palette
Pito::Palette::CtrlP::Component        — centered modal command palette
Pito::Palette::CtrlP::SectionComponent — section inside Ctrl+P

Pito::Sidebar::Component         — fixed right-edge overlay panel
Pito::Sidebar::SectionComponent  — labeled section inside sidebar
```

### Sample data

Hardcoded sample content lives in `lib/pito/sample/`. Files are marked `# SAMPLE` and will be replaced when Plan 2+ wires real data:

- `lib/pito/sample/chat_shell.rb` — 17 events across 4 exchanges
- `lib/pito/sample/game_detail.rb` — Hollow Knight detail with 6 sections

## Game release-date representation

Pito stores a game's release date as **independent precision components**, not as a single date plus an enum. Nullability of each component encodes how much we know — there is no `release_precision` column, and the design is source-agnostic (IGDB happens to be the primary feeder; Steam, Epic, manual entries follow the same shape).

### Columns on `games`

| Column            | Type            | Meaning                                                                                                                                        |
| ----------------- | --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `release_year`    | integer         | NULL when truly TBA / unknown.                                                                                                                 |
| `release_quarter` | integer (1..4)  | NULL unless precision is specifically a quarter (e.g. "Q3 2026"). Mutually exclusive with `release_month`.                                     |
| `release_month`   | integer (1..12) | NULL when only the year (or quarter) is known.                                                                                                 |
| `release_day`     | integer (1..31) | NULL when only the month is known. Requires `release_month`.                                                                                   |
| `release_date`    | date            | **Derived** lower-bound of what we know. NULL when `release_year` is NULL. Used for sorts, range queries, and the "is it released?" predicate. |

`release_date` is recomputed from the components on every save (`before_save :recompute_release_date` on `Game`). It is **not** the source of truth — the components are. The single column exists purely so existing index-friendly queries (`release_date <= today`, `BETWEEN ? AND ?`) keep working.

### What each combination means

| Real-world fact                    | year | quarter | month | day | date (derived) |
| ---------------------------------- | ---- | ------- | ----- | --- | -------------- |
| Released Oct 15, 2026              | 2026 | –       | 10    | 15  | 2026-10-15     |
| Coming October 2026                | 2026 | –       | 10    | –   | 2026-10-01     |
| Coming Q3 2026                     | 2026 | 3       | –     | –   | 2026-07-01     |
| Coming 2026                        | 2026 | –       | –     | –   | 2026-01-01     |
| TBA                                | –    | –       | –     | –   | NULL           |
| "Christmas, year unknown" (manual) | –    | –       | 12    | 25  | NULL           |

### Validations

`Game` enforces:

- `release_quarter` and `release_month` are **mutually exclusive** — quarter precision means we don't know the month.
- `release_day` requires `release_month` — you can't have a day without a month.
- `release_year` in 1900..2100; `release_quarter` in 1..4; `release_month` in 1..12; `release_day` in 1..31.

A consistency violation raises `Pito::Error::ReleaseDateInconsistent` (defined in `app/lib/pito/error.rb`) when triggered from a service path; on `Game#save` it surfaces as a normal `ActiveModel::Errors` entry.

### Source adapters

`Pito::Game::ReleaseDateMapper.call(input)` is the single entry point that maps a normalized component hash → the 5-column attribute hash (with `release_date` derived). Source-specific adapters do the translation **into** that input shape:

- **IGDB** (`Game::Igdb::GameMapper`): pulls `first_release_date` + the `release_dates[]` association (`category, y, m, d`), picks the canonical row (the one whose `date == first_release_date`, falling back to the most-precise category when null), and maps IGDB's `category` enum (0..7) into `{year:, quarter:, month:, day:}`. The IGDB→pito enum table:

  | IGDB `category` | Pito components            |
  | --------------- | -------------------------- |
  | 0 (day)         | `{year:y, month:m, day:d}` |
  | 1 (month)       | `{year:y, month:m}`        |
  | 2 (year)        | `{year:y}`                 |
  | 3..6 (Q1..Q4)   | `{year:y, quarter:cat-2}`  |
  | 7 (TBD)         | `{}`                       |

- **Manual / future sources** would write directly through `ReleaseDateMapper.call(...)` with the same input shape.

### Scopes & predicates

Defined on `Game`:

- `Game.released_in(year)` → `where(release_year: year)`.
- `Game.tba` → `where(release_year: nil)`.
- `Game.upcoming` → `where("release_date IS NULL OR release_date > ?", Date.current)` — covers both future-dated and TBA cohorts (the daily-refresh job in P38).
- `Game#released?` → `release_date.present? && release_date <= Date.current`.
- `Game#tba?` → `release_year.nil? && igdb_synced_at.present?` (synced but no year known; distinguishes from "we haven't synced yet").
- `Game#release_label` (presenter) → `"Oct 15, 2026"` / `"October 2026"` / `"Q3 2026"` / `"2026"` / `"TBA"` / `"Dec 25"` (year-unknown), driven by component nullability.

### Indexes

- `release_date` — sorts, ranges, "is it released?".
- `release_year` — fast year-bucket queries.
- `(release_month, release_day)` composite — "games released on Christmas, any year" and similar month-day queries.

### What this design is NOT

- It's **not** a single-date column with an enum: that approach loses the "Christmas, year unknown" case and conflates "Q3 2026" with "July 1, 2026" at the storage layer.
- It does **not** fake future dates: writing `1.month.from_now` for a TBA game is data fiction that breaks every consumer downstream.
- It does **not** depend on IGDB's enum: changing source (or adding a second source) does not change the schema.
