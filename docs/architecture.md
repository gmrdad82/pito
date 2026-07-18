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

- **Ontology is config.** Every tool (dispatch "tools", known as verbs pre-2.0;
  distinct from MCP tools) is declared ONCE in `config/pito/tools.yml`
  — a per-tool `mcp:` block promotes a read-only chat tool to an MCP tool, and a
  top-level `mcp_readers:` block declares the two readers with no backing
  dispatch tool (`pito_conversations`, `pito_messages`). No Ruby tool tables.
  `Pito::Dispatch::Schema` validates the blocks (read-only allowlist, unique
  tool names, template placeholders ⊆ params); the add-a-tool proof pins the
  config-only contract.
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

The `ai` chat tool runs an agentic loop against a configurable LLM provider.
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
  handle; `#<handle> apply [n]` (reply tool `apply`, target `ai_message`) runs
  suggestion n through the normal pipeline — its own confirmations still fire.
  The source message stays live for further applies.
- **The AI thread accent.** `data-accent="ai"` (purple→pito-blue gradient) on
  the chatbox bar while typing `ai …` (`pito--ai-accent`), the turn's echo, and
  the `:ai` answer.

## Local AI stack (3.0.0)

PITO embeds text and maps free-text chat with two self-hosted `llama.cpp`
sidecars — no cloud API key, no per-token cost, nothing leaves the box. This
retired Voyage AI (the previous embeddings vendor) end to end. It is unrelated
to the AI assistant's cloud providers above (`config/pito/ai_providers.yml`) —
that loop still calls out to whichever provider `/config ai` selected; this
stack is entirely local infrastructure the assistant doesn't touch.

### Sidecars

- **`embedder`** — `llama.cpp:server` serving `embeddinggemma-300m` (Q8 GGUF,
  ~350MB) over the OpenAI-compatible `/v1/embeddings` endpoint.
  `Pito::Embedding::Client` (`app/services/pito/embedding/client.rb`) is the
  sole HTTP wrapper: `ENV["PITO_EMBEDDER_URL"]` (`http://embedder:8081` in
  `docker-compose.yml`, `http://127.0.0.1:8091` for host-Puma dev via
  `docker-compose.dev.yml`). Model + dimension are LOCKED at 768
  (`Pito::Embedding::Client::DIMENSIONS`) to match the pgvector columns below
  — changing either needs a coordinated re-embed + column migration.
- **`nlmapper`** — a second `llama.cpp:server` holding `Qwen/Qwen3-0.6B-GGUF:
Q8_0` (`--ctx-size 2048`) over `/v1/chat/completions`.
  `Pito::Nl::CompletionClient` (`app/services/pito/nl/completion_client.rb`)
  is its sole wrapper: `ENV["PITO_NLMAPPER_URL"]` (`http://nlmapper:8082`
  prod, `http://127.0.0.1:8092` dev). It calls the CHAT endpoint, not the raw
  `/completion` one, so Qwen3's own chat template applies; `chat_template_
kwargs: { enable_thinking: false }` plus a trailing `/no_think` prompt suffix
  (belt-and-suspenders, two mechanisms) suppress its `<think>` reasoning
  preamble, which was otherwise strangled mid-think by the GBNF grammar.
- Both are CPU-only (no GPU assumed), 1GB memory-capped, and each own a
  dedicated model-cache volume (`embedder_models` / `nlmapper_models`, dev and
  prod scoped separately by compose project) — no coupling between the two.
  No host port in production — `web`/`pito-mcp` reach them over the compose
  network only; dev publishes 8091/8092 for the host-Puma app.
- **Forgiving vs strict, mirrored on both clients (K2 data honesty).**
  `Client#embed` and `CompletionClient#chat` never raise — an unconfigured
  URL, non-2xx, malformed body, or network error all degrade to nil (or an
  array of nils): a sidecar hiccup degrades a feature, it never crashes a
  turn. `Client#embed_batch` is the STRICT counterpart the catalog indexers
  use: it raises `Pito::Embedding::Client::Error` naming the real cause,
  which `Game::EmbeddingIndexer`/`Video::EmbeddingIndexer` convert to
  `Pito::Error::EmbeddingNil` so a job records a visible, retryable failure
  instead of a silent zero.

### Embedding topology

- **Canonical columns**: `games.summary_embedding` / `videos.summary_embedding`
  / `events.embedding` — all `vector(768)` with an HNSW (`vector_cosine_ops`)
  index (`events.embedding`'s index is partial, `WHERE embedding IS NOT
NULL`, since most event kinds never embed — see EMBEDDABLE_KINDS below).
  Reached through one seam per model, `EMBEDDING_COLUMN` + `#embedding_vector`
  (`Game`/`Video`), so no caller nil-guards or casts a vector by hand.
- **What gets embedded**: `Game::EmbedText.call` / `Video::EmbedText.call`
  build one em-dash-joined string per record (game: title · alt names ·
  genres · developer(s) · publisher(s) · platforms · time-to-beat · rating ·
  summary; video: title · description · tags · category) — the single source
  of truth shared by the per-record indexer and the bulk reindex sweep so the
  two paths can never drift.
- **Digest gating**: `Game::EmbeddingIndexer` / `Video::EmbeddingIndexer` /
  `Pito::Embedding::EventIndexer` each SHA256 the built text into
  `embedded_digest` and no-op when it's unchanged since the last successful
  embed (`force:` bypasses it) — a cover-art-only resync or a stats-only
  re-sync never burns an embedder call. Writes go through `update_column` on
  both the vector and the digest, skipping validations/callbacks so embedding
  never re-triggers a model's own `after_save` chain or rebroadcasts an event.
- **Enqueue points**: `GameEmbedIndexJob` (queue `:search`) from
  `Game::Igdb::SyncGame#call`'s success path and `NightlyReindexJob`;
  `VideoEmbedIndexJob` (queue `:search`) from `Pito::Sync::VideoLibrary#upsert`
  (created or changed) and `NightlyReindexJob`; `EventEmbedJob` (queue
  `:search`) from `Pito::Stream::Broadcaster#complete_turn` — one job per
  finished turn, embedding every embeddable event of it
  (`Pito::Embedding::EventIndexer::EMBEDDABLE_KINDS`: `echo system enhanced ai
system_follow_up enhanced_follow_up` — chrome kinds like
  `thinking`/`confirmation`/`theme_diff` never embed). `NightlyReindexJob`
  fans out one job per game/video (atomic-jobs principle) at 2:00 UTC, ≥1h
  after the nightly sync — both indexers are digest-gated so an unchanged
  catalog costs nothing that night. The chat `reindex <game/video>`
  confirmation (`Pito::Confirmation::Executor#confirm_game_reindex`/
  `#confirm_video_reindex`) instead calls its indexer INLINE with `force:
true` (it already runs inside a worker job) so the "reindexed" outcome text
  is accurate — done, not queued.
- **Manual reindex**: `rake pito:embeddings:reindex` (`FORCE=1`,
  `THROTTLE=<secs>`) sweeps games → videos → events through the same three
  indexers; resumable for free (the digest gate IS the checkpoint), and
  aborts up front when `PITO_EMBEDDER_URL` is unset.
- **Design B (locked, unaffected by 3.0.0)**: channels carry no embedding of
  their own — channel↔game recommendations are computed on demand from video
  vectors.

### NL input flow (chat input the grammar can't classify)

Free-text chat `Pito::Chat::Parser` can't classify at all falls to
`Pito::Chat::Handlers::Unknown`, which gives it ONE shot at the NL gate before
the witty `huh` fallback:

1. **Router** (`Pito::Nl::Router.route`, the CHEAP path) embeds the utterance
   and cosine-searches `nl_examples` — a materialized, digest-synced cache of
   every chat tool's `nl_examples:` corpus in `config/pito/tools.yml`
   (`Router.sync!`: upserts rows keyed by phrase digest, prunes phrases
   removed from the YAML, then embeds only rows still missing a vector — ONE
   batched forgiving `embed` call, never a per-row round trip). `greet`/
   `farewell` are excluded (`ROUTER_EXCLUDED_TOOLS`) — their short literal
   phrases magnetize false positives on garbled input (measured: "asdfghjkl"
   hit `greet` at 0.785). Below the `suggest` threshold (0.75, `tools.yml`'s
   `nl:` block) — or no `nl:` block, or the sidecar's down — the mapper is
   never even consulted; out-of-domain input dies here as the `huh` copy.
2. **Mapper** (`Pito::Nl::Mapper.map`, the EXPENSIVE path) asks the `nlmapper`
   sidecar to rewrite the utterance as one PITO command line, constrained to
   a GBNF grammar (`Pito::Nl::GbnfBuilder`, compiled fresh from `tools.yml` on
   every `Config.data` identity change — a new chat tool "just appears" with
   zero changes to the builder) covering every chat-mappable tool (declares a
   `chat:` block; `@ai` and chitchat excluded). The prompt is a real
   multi-turn few-shot array — one system instruction turn, then EVERY
   `nl.exemplars:` entry (23, disjoint from the router's `nl_examples` and
   from the calibration corpus below) as an alternating user/assistant pair,
   ending on the owner's own utterance as the final open turn — a 0.6B model
   imitates alternating chat turns far better than worked examples buried in
   one system string. `temperature: 0`, `repeat_penalty: 1.3` (vs the 1.0
   default every other caller keeps), `max_tokens: 24` — all three tuned
   against a live finding where unbounded sampling padded digit runs past the
   valid command instead of stopping. The raw completion is round-tripped
   through the REAL chat parser (`Pito::Lex::Lexer` → `KeywordSanitizer` →
   `Pito::Chat::Parser`) — nothing the parser would reject ever reaches the
   owner.
3. **Mismatch retry**: when the router's tool and the mapper's tool disagree,
   ONE retry re-runs the mapper constrained to a SINGLE-tool grammar
   (`GbnfBuilder.call(only: route[:tool])`) — the model then has no legal
   completion for any tool but the router's. Fixes a live finding where "what
   rpgs do I have" routed to `:list` at 0.966 confidence but the unconstrained
   mapper composed "rm games" (a `:delete` command); re-constraining fixes the
   SUGGESTION quality, not just the refusal to auto-run a mismatch.
4. **Canonicalize**: the leading verb token (which may be an alias the mapper
   spelled out, e.g. `ls`) is re-serialized to the parsed canonical tool name,
   so the same string is both displayed and executed.
5. **Auto-run vs did-you-mean**: auto-run (re-enters `Pito::Dispatch::Router`
   directly — the same path `FollowUp::ToolDelegator` and the AI orchestrator
   use — prefixed with an attribution line, `pito.copy.nl.ran`) fires only
   when ALL THREE hold: router confidence ≥ the `auto_run` threshold (0.90),
   router and mapper agree on the tool, and the tool's `mcp.read_only` config
   flag is `true` (never auto-run a write). Otherwise a `did_you_mean`
   confirmation event fires — `#<handle> confirm` re-enters
   `Pito::Confirmation::Executor#confirm_nl_run`, which replays the canonical
   command through `Pito::Dispatch::Router` exactly like a typed one; cancel
   falls through to the generic cancellation copy.
6. A sidecar failure at any step degrades to the `huh` copy — never an error
   surface.

Lexical normalization (`Router#normalize` / `Mapper#normalize`, deliberately
duplicated rather than shared — the two consumers may legitimately diverge
later) downcases, squeezes whitespace, and folds `tools.yml`'s
`nl.synonyms:` (e.g. "clips"/"films" → "vids") onto the corpus's own
vocabulary before either the embed or the prompt is built. Three corpora feed
the stack and must never blur: per-tool `nl_examples:` (the router's
neighbors), top-level `nl.exemplars:` (the mapper's few-shot pairs), and
`spec/fixtures/nl_calibration.yml` (the held-out set that MEASURES, never
trains, the thresholds).

### Search grammar (`search` chat tool)

One tool, three nouns (`search_nouns` vocabulary: `games` default, `vids`,
`conversations`), keyword modes per noun (`about` — 3.1.1 for games/vids,
2026-07-18 owner unlock adds conversations; `like`/`for` everywhere):

- **`search games like <title>`** — unchanged relevance ranking: resolves
  the seed through the title ladder (below), runs
  `Pito::Recommendation::GameSimilarity`, then gates to genuinely relevant
  results (shares a genre with the seed, or a blended-score floor when the
  seed has no genres on record).
- **`search games for <title>`** — exact-name matching: case-insensitive
  substring over `games.title` OR any `games.alternative_names` entry,
  title-ordered. "tekken" returns games actually titled Tekken-something,
  never a genre/theme neighbor (that's what `like` is for).
- **`search games <anything>`** (bare, no keyword — 3.1.2) — routed to the
  same free-text semantic search as `about`: the catch-all, so natural
  phrasings ("search games forcing skillful play") need no connector
  vocabulary at all. Typing `for` is the explicit literal path when
  exactness matters (bare = `for` was the 3.0.0 rule; superseded).
- **`search conversations like <text>`** / **`search conversations about
<text>`** (`Pito::Chat::Handlers::SearchConversations`, delegated from
  `Search#call` rather than registered as its own tool — `search` keeps one
  dispatch slot in `tools.yml`/the registry) — `like` and `about` are
  SYNONYMS for this noun only, both routing to the one semantic path: embed
  the text and cosine-search `events.embedding` (HNSW) over a 200-row
  candidate pool of owner-scoped (`conversations.source == "app"`),
  embeddable-kind events; degrades to the lexical path when the embedder has
  no opinion. Games/vids draw a real line between `like` (seed a title, rank
  its neighbors) and `about` (free-text, no seed); a conversation has no
  title ladder for `like` to seed from in the first place, so there is no gap
  left for `about` to fill — see the handler's class header.
- **`search conversations for <text>`** / bare — `events.payload::text
ILIKE`, the honest fallback with no relevance score (events carry no
  tsvector column). Bare conversations search stays this literal `for` path
  — UNCHANGED by the 2026-07-18 games/vids ruling that made bare mean "the
  vectors catch-all" for those two nouns (their bare path used to be strict
  `for`-style exactness and needed a vibe-search escape hatch; this noun's
  bare path was exact before and after, so there's nothing to unlock). Both
  conversation paths group hits by conversation (anchor = the
  chronologically first hit in the pool), then rank — `like`/`about` by
  nearest cosine distance, `for`/bare by the anchor's recency.
- Both `games` and `vids` paths share one card/pager per noun
  (`Search#build_payload` / `#build_video_payload`), page size 20 — the
  `search` tool's own `concerns.pager` in `tools.yml`, not `list`'s 50. A
  result that exceeds a page stamps the same `list_cursor`/`ranked_ids`
  mechanism `list games`/`list vids` use, read back by the game_list/
  video_search follow-up handlers — `search vids like/for/about` offers the
  exact same `next`/`more` continuation `search games` does. Vids search
  cards deliberately exclude re-sort/re-analyze replies (re-sorting would
  scramble the ranking their pager replays); games search cards ride the
  generic games-list target, which has always allowed them.

Across its nouns, `search` speaks three general modes: `for` matches literal
text (a title, a mention, an exact phrase), `like` ranks results by
embedding similarity to a seed you name (games/vids) or by embedding the
query text directly (conversations, which have no seed), and `about` takes
a free-text, qualitative description and searches by meaning rather than
exact wording — the same semantic space `like` draws its similarity from
(for conversations specifically, `about` and `like` are the identical path,
not independently implemented — see the noun's own bullet above). Keyword
precedence is positional (the keyword typed earliest wins), so a query that
merely _contains_ "about" or "like" mid-sentence is never hijacked; a
games/vids query with no keyword at all rides the `about` path — write
whatever, it goes to the vectors — while a conversations query with no
keyword stays the literal `for` path (conversations' bare behavior is
unchanged by the games/vids bare-catch-all ruling). All modes keep results
honest about a miss: when nothing is genuinely relevant they return nothing,
never a page padded out with weak matches just to fill it.

The GBNF grammar mirrors the clause shape directly: `search`'s `query` slot
compiles to `( "about" | "like" | "for" )? text?` (`GbnfBuilder#search_query_body`) —
the one tool-specific carve-out in an otherwise generic slot compiler.

### Link-suggestion pipeline

`Video::GameLinkSuggester` (`app/services/video/game_link_suggester.rb`)
nudges — never auto-links — a freshly-imported, still-unlinked video toward
the library game it probably belongs to:

- Fires only for a video with no `video_game_links` and a nil
  `link_suggested_at` (the once-only gate).
- Strips `[bracketed]`/`(parenthesized)` noise, tries the lead segment before
  a `:`/`—`/`|` separator first (falling back to the whole title only when
  the lead scores zero overlap), then scores every LIBRARY game (never IGDB)
  by the longest contiguous anchored token run against its title +
  `alternative_names` (`Pito::TitleMatch` — the same DP `Pito::TitleResolve`
  uses below).
- Numeral awareness falls OUT of run-length scoring rather than being a
  special case: "Mortal Kombat 2: Was it really that good?" anchors a
  3-token run onto "Mortal Kombat 2" vs. only 2 for "Mortal Kombat", so the
  numbered title wins outright — no embedding tiebreak needed.
- A unique top scorer wins alone; a genuine tie is broken by embedding cosine
  similarity (the forgiving `#embed` call — a sidecar hiccup just keeps title
  order) and capped at `MAX_SUGGESTIONS` (5).
- Enqueued by `LinkSuggestionJob` from `Pito::Sync::VideoLibrary#upsert`,
  ONLY on the `:created` path (never a resync), right beside that video's own
  `VideoEmbedIndexJob` enqueue. The JOB — never the suggester — stamps
  `link_suggested_at`, and only when it found candidates, so a quiet run (no
  match scored) can retry once a matching game is later imported.
- Surfaces as a `Notification` (turn-less sync/cron context, no live
  scrollback to append to) — `Pito::Notifications::Source::LinkSuggestion`
  renders an HTML list of ranked candidates as ready-to-paste `link vid <id>
to game <id>` commands the owner can confirm or ignore.

### Title resolution (`Pito::TitleResolve`)

The shared exact-first ladder every free-text title lookup composes
(`Game.resolve_by_title` / `Video.resolve_by_title`), so a typed title means
the same thing everywhere. Four tiers, first non-empty tier wins, every tier
breaks its own ties by shortest title:

1. Exact case-insensitive full-name match (title OR, for games, any
   `alternative_names` entry) — wins OUTRIGHT over a same-tier prefix match.
2. Case-insensitive prefix match (the query is the literal lead of the name).
3. Anchored token-run scoring (`Pito::TitleMatch`, shared with
   `Video::GameLinkSuggester` above).
4. Acronym-of-initials ("mk" → Mortal Kombat, "mk2" → Mortal Kombat 2, "kcd"
   → Kingdom Come Deliverance) — TITLE ONLY (alt names already resolve in
   tiers 1-2), with a trailing standalone numeral bound onto the acronym
   whole rather than reduced to a digit-initial.

No match at any tier → nil. Hooked in by `Pito::Chat::Handlers::Show` for a
non-numeric `show game <title>` / `show vid <title>` ref
(`#resolve_id_or_title` — a numeric ref resolves by id first, never through
this ladder) — including the `show game for vid <title>` pivot, which
resolves the named VID through this same ladder and then answers with THAT
vid's linked game — and by `Search#search_like`'s seed resolution.

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

**Config-driven dispatch (0.9.5).** Every tool — chat, slash, and hashtag-reply
— is declared ONCE in `config/pito/tools.yml` (the tool ontology): aliases,
slots/kwargs with named resolver paths (`lib/pito/dispatch/resolvers.rb`),
segments with named guard predicates, per-target reply availability + modes,
the `universal_reply:` set, auth tiers, page sizes, and `dispatch:` targets.
`Pito::Dispatch::Config` loads and freezes it; `Pito::Dispatch::Schema`
validates every key and reference at spec time (unknown keys are rejected with
did-you-mean hints — see `spec/dispatch/schema_integrity_spec.rb`);
`Pito::Dispatch::Matrix` derives the reply matrix; `Pito::Grammar::ConfigSource`
builds the recognition Specs and vocabularies; and `Pito::Dispatch::Router`
executes chat and reply tools through the uniform handler contract
`call(kwargs:, context:) → Result`. There is no Ruby tool table, no per-handler
availability DSL, and no tool→handler conditional: adding a tool is a YAML
entry plus a handler class (proven end-to-end by
`spec/dispatch/add_a_tool_proof_spec.rb`); `spec/dispatch/help_sync_spec.rb`
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

`#<handle> <tool> <rest>` replies to an addressable event are intercepted
**before** async dispatch by `Pito::FollowUp::Router`; availability and modes
come from the tool's `reply:` branch in tools.yml (via `Dispatch::Matrix`),
kwarg/ref extraction from its declared resolver paths (via
`Dispatch::ReplyBinding`), and execution runs through the SAME
`Pito::Dispatch::Router` via `Pito::FollowUp::ToolDelegator` (reply-specific
`call` bodies remain under `lib/pito/follow_up/handlers/`).

### Broadcast pipeline

`Pito::Stream::Broadcaster.new(conversation:)` is the only way to add items to
the scrollback. It: validates the payload, persists an `Event`, renders the
matching ViewComponent, and broadcasts a Turbo Stream `append` to
`"pito:conversation:#{conversation.id}"` targeting `#pito-scrollback`.

### Slash system (`Pito::Slash::*`)

- Infrastructure under `lib/pito/slash/`.
- Handlers under `lib/pito/slash/handlers/`.
- Every handler inherits `Pito::Slash::Handler`, declares `self.verb`, and
  returns a `Result` (`Ok` / `Error` / `NeedsConfirmation`).
- `Pito::Slash::Registry` auto-discovers and registers handlers at boot.
- Tools: `config`, `themes`, `games`, `disconnect`, `notifs`, `help`, and
  **`jobs`** — the operator's window into SolidQueue (`status` / `requeue` /
  `run` / `pause` / `resume`), delegating to `Pito::Jobs::{Status,RequeueFailed,
RunRecurring,PauseResume}` and reading the `SolidQueue::*` models directly.

### Chat system (`Pito::Chat::*`)

- Infrastructure under `lib/pito/chat/`.
- Handlers under `lib/pito/chat/handlers/` — one subclass per tool, each
  declaring `self.verb`. Tools: `list`, `show`, `import`, `sync`, `delete`,
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

## Unified layout (2.0.0 consolidation)

One rule draws the tree: **`lib/` is the chat-OS core — `app/` is the Rails
surfaces plus the YouTube/games adapter.** The 2.0.0 consolidation moved every
core mechanism out of `app/services` so the future extraction of a `pito-core`
engine is a `git mv`, not a rewrite (gem extraction is deliberately deferred
until a second source exists).

- **`lib/pito/`** — the chat OS: dispatch (router/schema/config/matrix/
  finalizer), grammar + lex + the three parsers (chat/hashtag/slash) and their
  handlers, stream (broadcaster/renderer/caches), follow_up, suggestions,
  palettes, copy (the dictionary engine), message_builder, themes, share,
  confirmation, notifications (webhook mechanism), formatter and the other
  leaf utilities, mcp. Knows nothing about YouTube or games.
- **`lib/ai/`** — the AI layer: provider registry, model catalog, wires,
  client, toolset/executor, history, blocks, content registry. Chat-OS-grade;
  `Ai::` namespace.
- **`app/services/`** — the adapter/domain: `channel/`, `game/`, `video/`,
  `google/`, `conversation/`, and the domain-flavored
  `pito/{analytics, auth, games, achievements, recommendation, schedule,
search, stats, sync, showcase, credentials, embedding, nl}`.
- **`app/{components,controllers,jobs,models,views}`** — Rails surfaces;
  `config/pito/` — the ontologies (`tools.yml`, `content.yml`,
  `ai_providers.yml`).
- Specs mirror sources: `spec/lib/**` ↔ `lib/**`, `spec/services/**` ↔
  `app/services/**`. Both roots are zeitwerk-equivalent
  (`config.autoload_lib`), so constants never moved — only files did.

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

## The living background (fx, 2.1.0)

One fixed canvas under the app runs the natural star sky (pito-tui's math:
deterministic fnv star identity, 4 weighted color classes, 4-size rarity
ladder, per-star breathing periods, two parallax drift layers) as the
resting mood. Eligible events (:system/:enhanced/:ai) are stamped at the
single create door (`Event.create_with_position!` → `Pito::Fx::Context`)
with `fx: {context, covers}` — Option B: the event says WHAT it is; the
`config/pito/fx.yml` registry (schema v2, boot-validated by
`Pito::Fx::Registry`) alone maps context → weighted effect pool + knobs.

fx.yml declares cover CARDINALITY on both sides: effects carry `covers:
single|many|none` (needs_cover is gone), contexts are `{covers:, pool:}`
maps, and the registry boot-fails any pool entry whose effect demands what
its context can't carry ("single-cover moods never render lists (owner
law)") — placement is validated, never silently degraded. The owner-locked
map (all eleven moods): water / duotone / lens on the single-cover
contexts (game_detail, vid_detail, and their verbatim analyze twins);
cover_wall + plasma 50/50 on game_list, vid_list, channel, analyze_channel
(plasma also answers thin shelves under the wall's min_covers); globs /
trails (ring-cascades) / aurora on ai; glow EXCLUSIVELY on ai_game — an AI
answer whose media or suggestion blocks name exactly one game derives that
game's cover. Bare analyze (breakdowns) has no entry: the sky answers.
Derive reads each message's own payload markers — replies get no special
rules; channel walls draw art-bearing games only, in SQL. The scrollback
snapshot cache is keyed v2 — bump it whenever event templates change.

Client side (`app/javascript/fx/` + the `pito--fx` Stimulus shell): a pure
context engine (`fx/engine.js`) turns viewport dominance (≥35%, 300ms
hysteresis, clock-matured) into an event-seeded pick and a 700ms crossfade;
WebGL renderers (`fx/renderers/*`: plasma, duotone, water, lens,
fluid_smoke) draw offscreen at `engine.enforcer_alpha`; `cover_wall` mounts
DOM-side. A COVERED mood's identity is effect + covers: a new dominant
message with matching covers keeps the LIVING mood untouched while the new
pool still offers the effect; a different cover rolls fresh, dropping the
living effect when an alternative exists (ANTI-REPEAT; a one-effect pool
repeats honestly). Cover-less moods (`plasma`, `fluid_smoke`) stay
per-message; the cache is NEIGHBOUR-ONLY — only the living mood, never
history — keyed `name:eventId` per owning event.

Everything chases the BUTTERFLY FLOCK, never the pointer — the hand
(mouse on desktop, gyro on phones) reaches every pixel by exactly one
path: it leans the butterflies (randomly-dealt personalities per spawn —
attracted / repelled / tilted / combos; the leader stays attracted), and
the moods follow the butterflies. Nothing reads the device directly; the
sky sways with the leader, the wall's second parallax layer with
butterfly two. `engine.butterflies` is a ceiling; each NEW PICK rolls a
flock of 3..ceiling members
(`fx/attractor.js`: eased legs of uneven tempo — dart/cruise/drift — kicked
to a dart by real events). The leader drives every effect and takes the
mouse's bias; the rest wander chaotic, with tiered safety radii relaxed
over two separation passes then low-pass smoothed into the position every
consumer reads; dart legs hop nearby, never teleport. Ring+trail bodies
draw over the resting sky ONLY, and only after `ring_idle_ms` (8s) of
stillness — activity fades them out — six size tiers, never
adjacent-matching. The sky also tilts with the phone gyro / desktop mouse.

Lens and duotone anchor up to 3 foci to flock members, not one
pointer-glued circle — count scales `min(viewport)/400`, clamped 1..3,
tiered sizes. `cover_wall` tiles scale to a fraction of the viewport's
short side (`size_frac`, boosted `sqrt(max_tiles/count)`, capped
`size_ceiling_frac`), never duplicating art. `duotone` supersamples 2x via
`knobs.dpr` — cells are CANVAS px, so visual dot size is `cell / dpr`.

Readability laws: messages stack above the canvas; a 55% page-color veil
band as wide as the message column; declared surfaces repaint at 92% of
their own color; naked text wears a page-toned halo. Degrades:
reduced-motion → one static frame; missing art or no WebGL2/float → cover
moods drop out pool-wise, the sky answers. Configured in fx.yml ONLY
(owner law — no /config surface); the dev ribbon carries the live FPS
meter (`page fps · fx clock`).
