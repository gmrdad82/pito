# pito — architecture

## Routes

| Path                          | Controller#action                            | Description                                                  |
| ----------------------------- | -------------------------------------------- | ----------------------------------------------------------- |
| `GET /`                       | `start_screens#show`                         | Start screen — centered chatbox, ASCII logo, tip line.      |
| `POST /chat`                  | `chat#create`                                | Submit a message; usually `head :no_content` (async).       |
| `GET /chat/:uuid`             | `conversations#show`                         | Conversation view — scrollback + chatbox.                   |
| `PATCH /chat/:uuid`           | `conversations#update`                       | Conversation mutation (e.g. rename).                        |
| `DELETE /chat/:uuid`          | `conversations#destroy`                      | Delete a conversation.                                      |
| `GET /resume`                 | `conversations#resume`                       | Resume the latest conversation.                             |
| `POST /suggestions`           | `suggestions#create`                         | Chatbox command/handle suggestions (JSON).                  |
| `POST /games/search`          | `games/search#create`                        | IGDB game search for the import sidebar (JSON).             |
| `POST /games/import`          | `games/import#create`                        | Enqueue `GameImportJob`; `204`.                            |
| `POST /channels/visit_consume`| `channels/visits#consume`                    | Mark a channel-visit event consumed.                       |
| `GET /notifications`          | `notifications#index`                        | Notifications list.                                        |
| `PATCH /notifications/:id`    | `notifications#update`                        | Mark a notification read.                                  |
| `PATCH /settings/theme`       | `settings#theme`                             | Persist the active theme.                                  |
| `match /auth/youtube/callback`| `youtube_connections/oauth_callbacks#create` | Google OAuth callback; imports channels.                   |
| `GET /auth/failure`           | `youtube_connections/oauth_callbacks#failure`| OAuth failure landing.                                     |

Auth is TOTP-only via the chatbox (`/authenticate <code>`); there are no
login/connect form routes — `/connect`, `/new`, `/resume`, `/themes`, etc. are
chatbox slash commands, not HTTP routes.

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
Pito::Event::ThinkingComponent    — Braille spinner + cycling word while dispatching
Pito::Event::SystemComponent      — standard assistant message (body/table/sections)
Pito::Event::EnhancedComponent          < SystemComponent — Pito-accent 2nd+ segment
Pito::Event::SystemFollowUpComponent    < EnhancedComponent — follow-up reply, system
Pito::Event::EnhancedFollowUpComponent  < EnhancedComponent — follow-up reply, enhanced
Pito::Event::ConfirmationComponent       — confirmation prompt (#<handle> yes/no)
Pito::Event::ConfirmationFollowUpComponent — resolved confirmation reply
Pito::Event::ErrorComponent       — error response
Pito::Event::ThemeDiffComponent   — theme preview/diff message

Pito::StartScreen::Component      — full-viewport start screen

Pito::Palette::CtrlK::Component        — Ctrl+K command palette
Pito::Palette::CtrlK::SectionComponent — section inside the palette

Pito::Footage::SnippetComponent   — copyable ffprobe one-liner (footage snippet)
```

## Dispatch pipeline

A single `POST /chat` endpoint handles all input. `ChatController#create` reads
`params[:input]`. A handful of commands that must touch the HTTP response
(`/authenticate`, `/connect`, `/new`, `/resume`, sidebar pickers) are handled
synchronously in the controller. Everything else is dispatched async: the
controller persists an echo event, emits a thinking indicator, enqueues
`ChatDispatchJob`, and responds `head :no_content` (the home-transition case
returns JSON instead — see "Conversation model").

Inside `ChatDispatchJob`, the input is routed by its shape:

- `turn.slash?` (leading `/`) → `Pito::Slash::Dispatcher`
- `turn.hashtag?` (leading `#`) → `Pito::Hashtag::Dispatcher`
- otherwise → `Pito::Chat::Dispatcher` (natural language)

The job runs the handler, persists each result event, resolves the thinking
indicator, and completes the turn. All output is delivered via Turbo Stream
broadcasts over Action Cable.

`#<handle> <verb> <rest>` replies to an addressable event are intercepted
**before** async dispatch by `Pito::FollowUp::Router`, which re-runs the same
chat verb handler via `Pito::FollowUp::VerbDelegator` (handlers under
`app/services/pito/follow_up/handlers/`).

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
- Handlers under `app/services/pito/chat/handlers/` — one subclass per verb, each
  declaring `self.verb`. Verbs: `list`, `show`, `import`, `sync`, `delete`,
  `reindex`, `link`, `unlink`, `publish`, `unlist`, `schedule`, `footage`,
  `platform` (plus internal `help` / `unknown`). Nouns `vids` / `subs` are
  canonical, with `videos` / `subscribers` accepted as aliases.
- The parser classifies input into `:new_turn` or `:unknown`.
- Every handler returns a `Pito::Chat::Result` (`Ok` / `Error`).

### Cross-system invariants

- `lib/pito/slash/**` does not reference `Pito::Chat::*`. `lib/pito/chat/**`
  does not reference `Pito::Slash::*`.
- Both share only `Pito::Lex` and `Pito::Stream::*`.
- Events store structured payloads (`jsonb`), never rendered HTML. Re-rendering
  from the payload always produces current timestamps and translations.

### Event kinds

| Kind                     | Payload keys                                              |
| ------------------------ | -------------------------------------------------------- |
| `echo`                   | `text:`                                                  |
| `thinking`               | `dictionary:, word_index:, resolved:, elapsed_seconds:`  |
| `system`                 | `body:` / `message_key:, message_args:` / `text:`, plus optional `html:, table_rows:, sections:, info_lines:, reply_handle:, …` |
| `enhanced`               | same as `system` (Pito-accent 2nd+ segment)              |
| `system_follow_up`       | same as `system` (rendered as a follow-up reply)         |
| `enhanced_follow_up`     | same as `system` (rendered as a follow-up reply)         |
| `confirmation`           | `body:, reply_handle:, processing:, resolved:, outcome:, outcome_text:` |
| `confirmation_follow_up` | `outcome:, outcome_text:`                                |
| `error`                  | `message_key:, message_args:` (or already-resolved `text:`) |
| `theme_diff`             | `phase:, granularity:, from_text:, previewed_slug:, sections:, body:, reply_handle:` |

`Pito::Stream::EventRenderer.component_for(event)` is the single source of truth
for kind → component lookup (`COMPONENT_CLASSES`).

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
- `Game.upcoming` — `where("release_date > ? OR release_year IS NULL", Date.current)`.
- `Game#released?` — true when the derived date (`release_date`, or freshly
  derived from the components) is present and `<= Date.current`.
- `Game#tba?` — `igdb_synced_at.present? && release_year.nil?`.
- `Game#release_label` — delegates to `Pito::Formatter::ReleaseDate.call(self)`:
  `"Oct 15, 2026"` / `"October 2026"` / `"Q3 2026"` / `"2026"` / `"TBA"` /
  `"Dec 25"` (year-unknown), driven by component nullability.
