# pito — architecture

## Routes

| Path                        | Controller#action                            | Description                                            |
| --------------------------- | -------------------------------------------- | ------------------------------------------------------ |
| `GET /`                     | `start_screens#show`                         | Start screen — centered chatbox, ASCII logo, tip line. |
| `POST /chat`                | `chat#create`                                | Submit a message; responds `head :no_content`.         |
| `GET /chat/:uuid`           | `conversations#show`                         | Conversation view — scrollback + chatbox.              |
| `GET /connect`              | `youtube_connections#new`                    | YouTube OAuth entry point.                             |
| `GET /auth/google/callback` | `youtube_connections/oauth_callbacks#create` | OAuth callback; imports channels.                      |

## UI stack

- **CSS**: Tailwind v4 via `tailwindcss-rails`. Theme tokens as CSS custom
  properties under `[data-theme="tokyo-night"]`.
- **Components**: `view_component` gem. All visual work is a ViewComponent.
- **i18n**: All user-facing copy in `config/locales/pito/<area>/en.yml`.
- **JS**: Turbo + Stimulus + importmap-rails. Stimulus controllers under
  `app/javascript/controllers/pito/`.

## Component tree

```
Pito::Segment::Component          — bar+gap+content layout primitive
Pito::Cursor::Component           — inverted-character terminal cursor

Pito::Shell::ChatboxComponent     — input area (Segment + Cursor + filter line)
Pito::Shell::MiniStatusComponent  — connection/auth/audio/shortcut status bar

Pito::Event::EchoComponent        — user input echo
Pito::Event::AssistantTextComponent — assistant response
Pito::Event::ThinkingComponent    — Braille spinner + cycling word while dispatching
Pito::Event::ErrorComponent       — error response
Pito::Event::ConfirmationPromptComponent — confirmation prompt

Pito::StartScreen::Component      — full-viewport start screen

Pito::Palette::CtrlK::Component        — Ctrl+K command palette
Pito::Palette::CtrlK::SectionComponent — section inside the palette

Pito::Footage::ProbeCommandComponent — copyable ffprobe rake command block
```

## Dispatch pipeline

A single `POST /chat` endpoint handles all input. `ChatController#create` reads
`params[:input]`:

- Leading `/` → `Pito::Slash::Dispatcher` (slash commands)
- No leading `/` → `Pito::Chat::Dispatcher` (natural language)

The controller always responds `head :no_content`. All output is delivered via
Turbo Stream broadcasts over Action Cable. Dispatch is async: the controller
persists an echo event, emits a thinking indicator, enqueues `ChatDispatchJob`,
and returns immediately. The job runs the handler, persists the result event, and
broadcasts it to the scrollback.

### Broadcast pipeline

`Pito::Stream::Broadcaster.new(conversation:)` is the only way to add items to
the scrollback. It: validates the payload, persists an `Event`, renders the
matching ViewComponent, and broadcasts a Turbo Stream `append` to
`"pito:conversation:#{conversation.id}"` targeting `#pito-scrollback`.

### Slash system (`Pito::Slash::*`)

- Infrastructure under `lib/pito/slash/`.
- Handlers under `app/services/pito/slash/handlers/`.
- Every handler inherits `Pito::Slash::Handler`, declares `self.verb`, and
  returns a `Result` (`Ok` / `Error` / `NeedsConfirmation`).
- `Pito::Slash::Registry` auto-discovers and registers handlers at boot.

### Chat system (`Pito::Chat::*`)

- Infrastructure under `lib/pito/chat/`.
- Handlers under `app/services/pito/chat/handlers/`.
- The parser classifies input into `:new_turn`, `:refinement`, or `:unknown`.
- Every handler returns a `Pito::Chat::Result` (`Ok` / `Error` / `Refine`).

### Cross-system invariants

- `lib/pito/slash/**` does not reference `Pito::Chat::*`. `lib/pito/chat/**`
  does not reference `Pito::Slash::*`.
- Both share only `Pito::Lex` and `Pito::Stream::*`.
- Events store structured payloads (`jsonb`), never rendered HTML. Re-rendering
  from the payload always produces current timestamps and translations.

### Event kinds

| Kind                  | Payload keys                                            |
| --------------------- | ------------------------------------------------------- |
| `echo`                | `text:`                                                 |
| `assistant_text`      | `message_key:, message_args:` or `text:`                |
| `error`               | `message_key:, message_args:`                           |
| `confirmation_prompt` | `prompt_key:, prompt_args:, command_text:`              |
| `thinking`            | `dictionary:, word_index:, resolved:, elapsed_seconds:` |
| `logout`              | _(empty)_                                               |

`Pito::Stream::EventRenderer.component_for(event)` is the single source of truth
for kind → component lookup.

## Conversation model

One conversation per UUID. `POST /chat` with no UUID (blank input on the start
screen) creates the conversation and returns `{ uuid, signed_stream_name }`.
Subsequent POSTs carry the UUID. The home → chat transition animates the chatbox
in place; `history.pushState` sets the `/chat/:uuid` URL without a page reload.

## Namespace policy

- **`Pito::*`** — cross-cutting infrastructure and utilities.
- **Domain layer**: `Channel::*`, `Video::*`, `Game::*`, `Footage::*`. Each owns
  its external API integration (YouTube, IGDB), indexers, and services.
- **`Tui::*`** — legacy panel primitive components (retained from earlier TUI work).
- `Settings::*` is gone. Don't reintroduce it.

## Game release-date representation

Pito stores a game's release date as independent precision components, not as a
single date plus an enum. Nullability of each component encodes how much we know.

### Columns on `games`

| Column            | Type            | Meaning                                                                                   |
| ----------------- | --------------- | ----------------------------------------------------------------------------------------- |
| `release_year`    | integer         | NULL when truly TBA / unknown.                                                            |
| `release_quarter` | integer (1..4)  | NULL unless precision is specifically a quarter. Mutually exclusive with `release_month`. |
| `release_month`   | integer (1..12) | NULL when only the year (or quarter) is known.                                            |
| `release_day`     | integer (1..31) | NULL when only the month is known. Requires `release_month`.                              |
| `release_date`    | date            | Derived lower-bound. NULL when `release_year` is NULL. Used for sorts and range queries.  |

`release_date` is recomputed from the components on every save
(`before_save :recompute_release_date`). It is not the source of truth — the
components are. The column exists so index-friendly queries keep working.

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

- `release_quarter` and `release_month` are mutually exclusive.
- `release_day` requires `release_month`.
- `release_year` in 1900..2100; `release_quarter` in 1..4; `release_month` in
  1..12; `release_day` in 1..31.

### Source adapters

`Pito::Game::ReleaseDateMapper.call(input)` is the single entry point that maps a
normalized component hash → the 5-column attribute hash. Source-specific adapters
translate into that shape:

- **IGDB** (`Game::Igdb::GameMapper`): maps `category` enum (0..7) → components.

  | IGDB `category` | Pito components            |
  | --------------- | -------------------------- |
  | 0 (day)         | `{year:y, month:m, day:d}` |
  | 1 (month)       | `{year:y, month:m}`        |
  | 2 (year)        | `{year:y}`                 |
  | 3..6 (Q1..Q4)   | `{year:y, quarter:cat-2}`  |
  | 7 (TBD)         | `{}`                       |

### Scopes and predicates

- `Game.released_in(year)` — `where(release_year: year)`.
- `Game.tba` — `where(release_year: nil)`.
- `Game.upcoming` — `where("release_date IS NULL OR release_date > ?", Date.current)`.
- `Game#released?` — `release_date.present? && release_date <= Date.current`.
- `Game#tba?` — `release_year.nil? && igdb_synced_at.present?`.
- `Game#release_label` — `"Oct 15, 2026"` / `"October 2026"` / `"Q3 2026"` /
  `"2026"` / `"TBA"` / `"Dec 25"` (year-unknown), driven by component nullability.
