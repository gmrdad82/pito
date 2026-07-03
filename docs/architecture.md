# PITO — architecture

## Routes

| Path                           | Controller#action                             | Description                                            |
| ------------------------------ | --------------------------------------------- | ------------------------------------------------------ |
| `GET /`                        | `start_screens#show`                          | Start screen — centered chatbox, ASCII logo, tip line. |
| `POST /chat`                   | `chat#create`                                 | Submit a message; usually `head :no_content` (async).  |
| `GET /chat/:uuid`              | `conversations#show`                          | Conversation view — scrollback + chatbox.              |
| `PATCH /chat/:uuid`            | `conversations#update`                        | Conversation mutation (e.g. rename).                   |
| `DELETE /chat/:uuid`           | `conversations#destroy`                       | Delete a conversation.                                 |
| `GET /resume`                  | `conversations#resume`                        | Resume the latest conversation.                        |
| `POST /suggestions`            | `suggestions#create`                          | Chatbox command/handle suggestions (JSON).             |
| `POST /games/search`           | `games/search#create`                         | IGDB game search for the import sidebar (JSON).        |
| `POST /games/import`           | `games/import#create`                         | Enqueue `GameImportJob`; `204`.                        |
| `POST /channels/visit_consume` | `channels/visits#consume`                     | Mark a channel-visit event consumed.                   |
| `GET /notifications`           | `notifications#index`                         | Notifications list.                                    |
| `PATCH /notifications/:id`     | `notifications#update`                        | Mark a notification read.                              |
| `PATCH /settings/theme`        | `settings#theme`                              | Persist the active theme.                              |
| `match /auth/youtube/callback` | `youtube_connections/oauth_callbacks#create`  | Google OAuth callback; imports channels.               |
| `GET /auth/failure`            | `youtube_connections/oauth_callbacks#failure` | OAuth failure landing.                                 |

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
- otherwise → `Pito::Dispatch::Router` (natural language)

**Config-driven dispatch (0.9.5).** Every verb — chat, slash, and hashtag-reply
— is declared ONCE in `config/pito/verbs.yml` (the verb ontology): aliases,
slots/kwargs with named resolver paths (`lib/pito/dispatch/resolvers.rb`),
segments with named guard predicates, per-target reply availability + modes,
the `universal_reply:` set, auth tiers, page sizes, and `dispatch:` targets.
`Pito::Dispatch::Config` loads and freezes it; `Pito::Dispatch::Schema`
validates every key and reference at spec time (unknown keys are rejected with
did-you-mean hints — see `spec/dispatch/schema_integrity_spec.rb`);
`Pito::Dispatch::Matrix` derives the reply matrix; `Pito::Grammar::ConfigSource`
builds the recognition Specs and vocabularies; and `Pito::Dispatch::Router`
executes chat and reply verbs through the uniform handler contract
`call(kwargs:, context:) → Result`. There is no Ruby verb table, no per-handler
availability DSL, and no verb→handler conditional: adding a verb is a YAML
entry plus a handler class (proven end-to-end by
`spec/dispatch/add_a_verb_proof_spec.rb`); `spec/dispatch/help_sync_spec.rb`
fails CI when help copy drifts from the config.

The job runs the handler, then hands the result events to
`Pito::Dispatch::Finalizer`, which persists each one, gives EACH message its own
thinking indicator (the first reuses the controller's pre-dispatch placeholder;
the rest are emitted just before their message and linked to it via payload
`for_event_id`), resolves each indicator when THAT message is ready, and
completes the turn only once ALL indicators are resolved. A pending-analytics
card keeps its own indicator spinning until `AnalyticsFillJob` fills it and
resolves just that one. All output is delivered via Turbo Stream broadcasts over
Action Cable.

`#<handle> <verb> <rest>` replies to an addressable event are intercepted
**before** async dispatch by `Pito::FollowUp::Router`; availability and modes
come from the verb's `reply:` branch in verbs.yml (via `Dispatch::Matrix`),
kwarg/ref extraction from its declared resolver paths (via
`Dispatch::ReplyBinding`), and execution runs through the SAME
`Pito::Dispatch::Router` via `Pito::FollowUp::VerbDelegator` (reply-specific
`call` bodies remain under `app/services/pito/follow_up/handlers/`).

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
- Verbs: `config`, `themes`, `games`, `disconnect`, `notifs`, `help`, and
  **`jobs`** — the operator's window into SolidQueue (`status` / `requeue` /
  `run` / `pause` / `resume`), delegating to `Pito::Jobs::{Status,RequeueFailed,
RunRecurring,PauseResume}` and reading the `SolidQueue::*` models directly.

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

| Kind                     | Payload keys                                                                                                                    |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| `echo`                   | `text:`                                                                                                                         |
| `thinking`               | `dictionary:, word_index:, resolved:, elapsed_seconds:`                                                                         |
| `system`                 | `body:` / `message_key:, message_args:` / `text:`, plus optional `html:, table_rows:, sections:, info_lines:, reply_handle:, …` |
| `enhanced`               | same as `system` (Pito-accent 2nd+ segment)                                                                                     |
| `system_follow_up`       | same as `system` (rendered as a follow-up reply)                                                                                |
| `enhanced_follow_up`     | same as `system` (rendered as a follow-up reply)                                                                                |
| `confirmation`           | `body:, reply_handle:, processing:, resolved:, outcome:, outcome_text:`                                                         |
| `confirmation_follow_up` | `outcome:, outcome_text:`                                                                                                       |
| `error`                  | `message_key:, message_args:` (or already-resolved `text:`)                                                                     |
| `theme_diff`             | `phase:, granularity:, from_text:, previewed_slug:, sections:, body:, reply_handle:`                                            |

`Pito::Stream::EventRenderer.component_for(event)` is the single source of truth
for kind → component lookup (`COMPONENT_CLASSES`).

## Caching (0.9.0 — "cache the cache")

Layered, all derived and disposable; **events stay canonical** (structured
`jsonb` + baked body HTML — never the source of truth for data).

| Layer             | Store                                           | What                                                                                          | Key                                                                   | Expiry                                                        |
| ----------------- | ----------------------------------------------- | --------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------- |
| **L0 primitives** | `analytics_primitives`                          | per-subject raw YouTube metrics (video, or channel-wide `:channel`) per report per window     | (subject, report, start, end)                                         | Window policy (below)                                         |
| **L0.5 cells**    | `analytics_cache` (`Pito::Analytics::Cache`)    | one analyze metric's computed raw ingredient (chart/bars/likes data)                          | `cell:v1:<metric>:<level>:<ids-digest>:<window>` — **selection-free** | Window policy                                                 |
| **L1 fragments**  | SolidCache (`Pito::Stream::FragmentCache`)      | one rendered event's HTML, meta line replaced by a `data-pito-meta-slot` filled at serve time | kind + event id + zone + SHA256(payload minus `reply_consumed`)       | digest rotation + 1wk TTL                                     |
| **L2 snapshot**   | SolidCache (`Pito::Stream::ScrollbackCache`)    | the assembled scrollback (turn containers + filled fragments)                                 | conversation uuid + zone                                              | busted at every Broadcaster chokepoint; rebuilt on read       |
| **Share page**    | SolidCache (`Pito::Share::PageCache`)           | intro + shared event (reply-suppressed) + outro                                               | content-addressed (uuid + event digest + counts + zone)               | 1wk; revoke needs no bust (controller gates on the Share row) |
| **IGDB search**   | SolidCache (`Pito::Search::Modules::IgdbGames`) | successful search envelopes only                                                              | case-folded query digest + limit                                      | 1 day                                                         |

**Window expiry policy — ONE place** (`Pito::Analytics::Window.expires_at_for`):
finalized (period ended ≥ `FINALIZED_AFTER` = 7 days ago; YouTube aggregates in
~48h) → **frozen forever** · lifetime → **24h** · live → **4h**. New
window-keyed caches call it; never re-derive TTLs.

**Selection invariant.** `analyze … with/without <metrics>` filters the
_render_, never the fetch: markers store the full role metric set, L0/L0.5 are
keyed selection-free, and any selection composes from the same cached cells
(spec: `selection_invariant_spec.rb`).

**Meta slot.** The only thing that mutates old messages — reply-handle
consumption — renders through the serve-time meta-slot fill
(`EventRenderer.fill_meta_slot`), so fragments are immune to it (same pattern
as `data-pito-ts-slot` for timestamps).

**Copy variants.** Scrollback bodies freeze their 1-of-50 variant at build time
(baked HTML); chrome re-samples per render and is never cached. `Pito::Copy`
itself is µs-scale (benched) — it has **no cache** by design.

**Hygiene.** `CacheSweepJob` (daily 04:00) sweeps expired `analytics_cache` +
`analytics_primitives` rows and `api_requests` older than 90 days. Everything
else expires lazily / by LRU (SolidCache 256MB cap).

**Benchmarks.** `rake pito:bench` — strictly READONLY (network kill switch +
read-only DB session): replay/component/Copy/fold timings, cache-temperature
inventory, and dry request-plan counters (`Pito::Bench::DryRun`). Snapshots
land in `tmp/bench/` for release-over-release diffs.

## Conversation model

One conversation per UUID. `POST /chat` with no UUID (blank input on the start
screen) creates the conversation and returns `{ uuid, signed_stream_name }`.
Subsequent POSTs carry the UUID. The home → chat transition animates the chatbox
in place; `history.pushState` sets the `/chat/:uuid` URL without a page reload.

## Namespace policy

- **`Pito::*`** — cross-cutting infrastructure and utilities.
- **Domain layer**: `Channel::*`, `Video::*`, `Game::*`, `Footage::*`. Each owns
  its external API integration (YouTube, IGDB), indexers, and services.
- **`Tui::*`** — panel primitive components.

## Game release-date representation

PITO stores a game's release date as independent precision components, not as a
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

`Pito::Games::ReleaseDateMapper.call(input)` is the single entry point that maps a
normalized component hash → the 5-column attribute hash. Source-specific adapters
translate into that shape:

- **IGDB** (`Game::Igdb::GameMapper`): maps `category` enum (0..7) → components.

  | IGDB `category` | PITO components            |
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

## Self-host & operator tooling (0.7.0)

PITO is **local-first**: it runs on your own machine, two ways. Native development
uses `bin/dev` (Rails on the host, **development** env, recurring jobs off — see the
`PITO_DEV_JOBS` toggle). Self-host uses Docker (**production** env) with a prebuilt
multi-arch image.

- **Image** — `.github/workflows/release.yml` builds `ghcr.io/gmrdad82/pito` and
  pushes it on a version-tag push only (never per-commit). `docker-compose.yml`
  references that image (with `build: .` as a fallback) and mounts the owner's
  `config/master.key` + `credentials.yml.enc` over the baked-in copies.
- **`bin/pito`** — the self-contained operator CLI (no repo / no host Ruby): drives
  `docker compose` against the compose file beside it (an install dir) or one level
  up (this repo). Subcommands: `up`/`down`, `totp`, `console`, `logs`, `rake`,
  `clean`, `install`, `update`, `service`, `cloudflared`. `bin/boot` is a thin
  compatibility shim forwarding to it.
- **`script/install.sh` / `update.sh`** — `curl | sh` install/update: fetch the
  compose file + CLI, generate secrets non-interactively, pull the image, enroll
  TOTP, and optionally configure a Cloudflare tunnel + systemd unit. No git clone.
- **Host** — `PITO_APP_BASE_URL` (read in `production.rb`, mirrored by
  `Pito::PublicHosts`) drives Host Authorization, URL helpers, and `asset_host`. SSL
  is always forced, so a non-localhost host sits behind a TLS proxy (e.g. cloudflared).
- **Hygiene** — `pito:clean` (`Pito::Tools::Clean`) clears the `tmp/` scratch
  (keeping `tmp/storage`, `tmp/pids`, `.keep`) + truncates dev `log/*.log`; dev blobs
  live in `public/pito-storage`, not tmp/. In Docker, logs are STDOUT (json-file rotation).
