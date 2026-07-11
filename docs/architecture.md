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
| `POST /session`                | `sessions#create`                             | JSON login for non-browser clients (`{otp}`).          |
| `DELETE /logout`               | `sessions#destroy`                            | Clear the session (204 to JSON, redirect to HTML).     |
| `match /auth/youtube/callback` | `youtube_connections/oauth_callbacks#create`  | Google OAuth callback; imports channels.               |
| `GET /auth/failure`            | `youtube_connections/oauth_callbacks#failure` | OAuth failure landing.                                 |

Auth is TOTP-only via the chatbox (`/authenticate <code>`); there are no
login/connect form routes — `/connect`, `/new`, `/resume`, `/themes`, etc. are
chatbox slash commands, not HTTP routes. (`POST /session` is the same TOTP
verify+mint as `/authenticate`, packaged for cookie-jar clients.)

## JSON client surface (1.0.0 — pito-tui et al.)

The scrollback has always been client-agnostic — events persist structured
`jsonb` payloads, never HTML — so the JSON surface is a projection, not a
second app. A non-browser client (the Go/Bubble Tea `pito-tui`, and anything
after it) speaks:

1. **`POST /session` `{otp}`** → `201 {authenticated: true}` + the same
   encrypted `pito_session` cookie the web mints (`Pito::Auth::ChatLogin`
   verbatim, per-IP throttle included), or `401 {authenticated: false,
error:, message:}`. The client keeps a cookie jar; the cookie also rides
   the cable handshake.
2. **`GET /chat/:uuid.json`** → `{conversation: {uuid, title, display_name,
created_at}, events: [EventJson…]}` position-ordered — the backfill.
   Anonymous → explicit `401` (the HTML page withholds silently instead).
3. **`POST /chat` (JSON body)** → `201 {uuid, turn_id}` so the client can
   correlate its pending spinner (`turn_id` is `null` for reply mutations).
   Web-only fast-paths (sidebars/navigations: `/connect`, `/new`, `/resume`,
   `/themes`, pickers, imports) → `422 {error: "web_only", message}` — a
   printable refusal from the `pito.copy.errors.web_only` dictionary.
4. **`GET /resume.json`** → `{recent: […], older: […]}` rows of
   `{uuid, title, display_name, last_activity_at}` — the conversation picker.
5. **`Pito::JsonChannel`** — subscribe with the bare `uuid` (auth-gated, not
   signed-token-gated: guests and unknown uuids are REJECTED — the cable is
   no leakier than the page). Messages:
   `{type: "event.append"|"event.replace", event: EventJson}`.

`Pito::Stream::EventJson` (`lib/pito/stream/event_json.rb`, EventRenderer's
sibling) is the one shape — `{id, turn_id, kind, payload, position,
created_at}` — used by both the backfill and the live mirror, so they can
never drift. The mirror is fed by the Broadcaster's private `broadcast_json`
at its THREE persisted-event choke points (`broadcast_event`,
`replace_event`, `resolve_one` — the thinking resolve broadcasts directly,
not via `replace_event`). Ephemeral chrome (context meter, auth updates,
sidebars, metric fragments, done-div) is NOT mirrored; a client renders its
own pending state and treats the thinking event's `event.replace`
(`payload.resolved: true`, `elapsed_seconds`) as the turn-done signal.

CSRF: requests whose body is `application/json` skip the authenticity token
(`ApplicationController`) — an HTML form cannot produce that content type, a
cross-origin JSON fetch triggers a CORS preflight that never passes, and the
session cookie is `SameSite=lax`. The skip is keyed on `request.media_type`
(attacker-influencable only via a non-form body), never `request.format`
(influencable via the URL). Anonymous JSON requests to auth-gated actions get
`401 {error: "unauthenticated"}` from `Sessions::AuthConcern` instead of the
browser redirect-to-root.

## MCP server (read-only — G130)

A second non-browser surface: an AI chat client (claude.ai, ChatGPT, any MCP
client) connects over the Model Context Protocol and READS PITO. Strictly
read-only, OAuth-gated, and isolated in its own container.

- **Ontology is config.** Every tool is declared ONCE in `config/pito/verbs.yml`
  — a per-verb `mcp:` block promotes a read-only chat verb to a tool, and a
  top-level `mcp_readers:` block declares the two verb-less readers
  (`pito_conversations`, `pito_messages`). No Ruby tool tables. `Pito::Dispatch::
Schema` validates the blocks (read-only allowlist, unique tool names, template
  placeholders ⊆ params); the add-a-tool proof pins the config-only contract.
- **`Pito::Mcp::Registry`** projects those blocks into the MCP `tools/list` JSON
  (name + description + JSON-Schema `inputSchema`).
- **`Pito::Mcp::Executor`** builds the chat grammar string from a tool call's
  `input` template + `input_suffixes` (arrays comma-joined; `period` forwarded to
  `Router.call`), routes it through the UNMODIFIED `Pito::Dispatch::Router`, and
  projects the Result via `Pito::Mcp::EventText`. It NEVER persists (the dispatch
  jobs — which persist + broadcast — are never invoked). `Pito::Mcp::AnalyticsFill`
  computes the three pending-analytics families (glance / analyze+breakdowns /
  channel-distribution) INLINE via the same services the fill jobs use, so a caller
  never receives a "pending" marker. `Pito::Mcp::EventText` renders payloads to
  markdown (tables → GH tables, breakdowns → % lists, cards de-HTML'd).
- **Readers** (`Pito::Mcp::Readers`) SELECT persisted `source: "app"` rows only.
- **Conversation separation.** `conversations.source` is `app` | `mcp`. The
  Executor dispatches against `Conversation.mcp_anchor` (a single `source: "mcp"`
  row, context only — its events are never persisted). `singleton` and
  `by_recent_activity` (→ resume sidebar, `/resume.json`, auto-purge) scope to
  `source: "app"`, so the anchor never leaks into any app-facing listing.
- **Endpoint.** `McpController` (`ActionController::Base`, no cookie session) serves
  JSON-RPC 2.0 at `POST /mcp` (protocol `2025-06-18`): `initialize`,
  `notifications/initialized`, `tools/list`, `tools/call`, `ping`. Bearer-gated
  (`Pito::Mcp::Auth` → `OauthToken`); a missing/invalid token gets `401` +
  `WWW-Authenticate: Bearer resource_metadata="…/.well-known/oauth-protected-resource"`.
- **OAuth 2.1 (hand-rolled, public clients).** Three tables (`oauth_clients`,
  `oauth_codes`, `oauth_tokens` — digests only, never a raw secret), four endpoints
  (`/oauth/register` RFC 7591, `GET/POST /oauth/authorize` = the TOTP consent page,
  `/oauth/token` = PKCE-S256 code exchange + refresh), and two discovery docs
  (`/.well-known/oauth-authorization-server`, `/.well-known/oauth-protected-resource`).
  PKCE is mandatory; codes are single-use + 5-minute; access tokens are 24h and
  rotate on refresh; refresh tokens never expire (revocation only — the owner
  approves once per client with one TOTP). Consent reuses `Pito::Auth::TotpVerifier`
  - the `SessionThrottle` IP throttle; comparisons are timing-safe.
- **Container.** `docker-compose.yml` runs a dedicated `pito-mcp` Puma (same image,
  `-p 3001`, no SolidQueue supervisor) exposed at `127.0.0.1:3029`; cloudflared on
  the host routes `^/(mcp|oauth|\.well-known)` there and everything else to `web`,
  so a stuck tool call cannot starve the app/APK/TUI workers.

## AI assistant (2.0.0)

The `ai` chat verb runs an agentic loop against a configurable LLM provider.
The AI reads pito through its own tools and NEVER writes — it suggests commands
the owner runs himself.

- **Providers are config.** `config/pito/ai_providers.yml` declares HOW to reach
  each provider (base_url, wire format, auth style, models endpoint, capability
  flags); `Ai::ProviderRegistry` validates + freezes it. WHICH provider/model is
  active lives in AppSetting (encrypted key/value store), set via `/config ai` —
  either the picker overlay (`Pito::Ai::PickerComponent` + `pito--ai-picker`,
  mounted by a ChatController fast-path; persistence via `PATCH /settings/ai`)
  or masked text kwargs (`/config ai api_key=… model=…`). `Ai::ModelCatalog`
  live-fetches the provider's model list (1-day cache, pinned fallbacks).
- **Two wire adapters, N providers.** `Ai::Wire::OpenAiChat` (OpenAI-compatible
  chat completions — OpenCode Zen, OpenAI, OpenRouter, DeepSeek, Qwen, HF) and
  `Ai::Wire::AnthropicMessages`. Both normalize to `Ai::Wire::Response`
  (text / ToolCall rows / Usage / stop_reason) and raise `Ai::Wire::Error` on
  any failure. Tool traffic is wire-native: each adapter builds its own
  assistant-tool / tool-result history messages. `Ai::Client.current` resolves
  the ACTIVE provider per call, so a mid-conversation switch applies next turn.
- **The loop.** `Chat::Handlers::Ai` emits one pending `:ai` event; the
  Finalizer's ai-pending gate enqueues `AiOrchestratorJob` (the analytics-fill
  pattern — the message's own thinking indicator spins until the answer lands,
  while `Broadcaster#broadcast_ai_status` narrates the current tool in an
  ephemeral slot). Messages = `Ai::History` (last 10 turns, mixed grammar/AI,
  role-coalesced) + the prompt; tools = `Ai::Toolset` (every MCP tool + two
  terminals). Mid-loop reads execute via `Ai::ToolExecutor` →
  `Pito::Mcp::Executor` (markdown back to the model; never persists). The model
  ENDS with `pito_render_command` (Flow A: the command runs through the
  unmodified Router and the pending event CONVERTS into its first native
  message — indistinguishable from typing it) or `pito_respond` (Flow B: typed
  blocks). Caps (8 iterations / 150k tokens) and failures finalize with copy.
- **Blocks, never markup.** `Ai::Blocks` validates/clamps the model's typed
  blocks (text / kv_table / table / media / sparkline / chart / score / ttb /
  suggestion); failures degrade to text. `Event::Ai::BlockRenderer` is the ONE
  place blocks meet ViewComponents — entity media resolves server-side by id
  (the model never supplies URLs), charts render through the kwargs-pure braille
  visualizers.
- **Suggestions + apply.** An answer carrying suggestion blocks gets a reply
  handle; `#<handle> apply [n]` (reply verb `apply`, target `ai_message`) runs
  suggestion n through the normal pipeline — its own confirmations still fire.
  The source message stays live for further applies.
- **The AI thread accent.** `data-accent="ai"` (purple→pito-blue gradient) on
  the chatbox bar while typing `ai …` (`pito--ai-accent`), the turn's echo, and
  the `:ai` answer.

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
| `ai`                     | `status:, blocks:, prompt:, reply_handle:` — typed blocks (see "AI assistant")                                                  |

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
