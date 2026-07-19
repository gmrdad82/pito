# Changelog

All notable changes to PITO are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/); the project aims for
[Semantic Versioning](https://semver.org/).

## [3.7.0] — 2026-07-20

### Added

- **The flock answers the cable** — every received message now rolls a
  fresh, independent reaction per butterfly: a push of random strength, a
  lean toward a random point, a crosswise tilt, a full-field leap to a
  new destination, or sitting this one out entirely — random per
  butterfly, random per payload, random in everything (owner's spec,
  verbatim). The trigger is the real per-payload cable event
  (`turbo:before-stream-render`), retiring the old DOM-mutation impulse
  that startled every body identically on any re-render. The plan-maker
  is a pure module (`fx/impulse.js`) proven with seeded randomness the
  same way the flight model is; strength and duration ranges are fx.yml
  knobs; reduced motion sits perfectly still.

### Changed

- **The fx pay half rent** — the night sky samples a coarser grid
  (`cell 16→22` via new fx.yml sky knobs: ~47% fewer per-frame hash
  calls, proportionally fewer, brighter-feeling stars); the butterfly
  ring trails shorten (14→8 samples) and trade their per-sample radial
  gradients for cheap alpha-falloff circles — from ~160 gradient
  allocations a frame to at most two per body (the body glow and disk
  keep theirs; the soul stays). Plasma mirrors pitomd's tuned shader
  byte-for-byte (25→12 fbm-octave units, 52% — the port citation and a
  text-pin test hold the budget in both repos). Op-count budgets are
  pinned by counting-Proxy tests; the long-running sky presence test
  finally gets the generous timeout it always needed.

## [3.6.0] — 2026-07-19

### Added

- **The AI suggestion line grows a visible accept affordance** — the
  stage-into-chatbox icon is gone; the line keeps one copy icon and gains
  a "shift+u to accept" chip (the house kbd shimmer plus copy-driven hint
  text) that stages that line's own command on click or tap — the same
  target the Shift+U key and the `apply`/`use`/`accept` reply words have
  always clicked, now something you can see.
- **The @ai palette entry names its answering model** — "… — answered by
  %{model}." interpolated server-side into the autocomplete description,
  with the model painted orange in both the web popup and the TUI's
  completion row (an additive `model` field on the wire; old clients read
  the plain sentence). No model configured → a clean sentence with no
  placeholder residue.
- **Zero-downtime deploys** — the web container becomes two blue/green
  slots behind the existing Caddy, which health-checks `/up` on both and
  routes to whichever is alive. A deploy pulls the new image into the
  idle slot, waits for it to pass health (migrations run there while the
  old slot still serves — the additive-migration rule makes that safe),
  then drains the old slot; a failed health check aborts with the live
  slot untouched. `pito update`/autoupdate flip instead of bouncing; a
  one-time idempotent migration moves existing single-slot installs over
  on their next update — the last restart that ever drops a request.
- **@ai replies wherever list, show, and analyze took you** — every
  message those three tools mint now answers to `#handle @ai <question>`:
  the reply anchors on that exact message and the model receives its REAL
  content — a clean projection of the persisted payload (intro text,
  table cells, card fields; chrome never) through the same projection the
  MCP tools already read — behind a one-line "the owner is replying to
  this message" preamble. Config-declared like every reply tool: the
  targets are YAML lines on the `@ai` entry, nothing else changed.
- **The @ai option knows who answers — and vanishes when nobody would** —
  wherever @ai is offered (the chat palette, the reply vocabularies) the
  option itself now reads `@ai(claude-sonnet-5)`: the ACTIVE model baked
  in server-side, painted orange, display-only (tab still inserts plain
  `@ai` — you're not passing a parameter). And when no provider/model/key
  is configured, @ai simply isn't offered anywhere: a declared
  `enabled_if: ai_configured` condition on the tools.yml entry, resolved
  by one readiness check and honored generically by every presenting
  surface — no hardcoded tool checks. Typing it blind still gets the
  polite not-configured answer. (The short-lived "— answered by %{model}"
  description suffix retired in favor of the label — one mention, not two.)
- **List intros name their channel(s); single-channel lists drop the
  column** — `list vids`/`list games` intros carry the result set's
  channel handle(s) as reference tokens, and when the WHOLE result set
  lives on one channel the channel column vanishes: from the table, from
  the `with`/`without` vocabulary and footer, and from `sort` — the
  intro's reference already says it, and a 19-row column of the same
  truncated handle said nothing. Multi-channel sets keep the column
  exactly as before; later pages inherit page 1's decision.

### Fixed

- **Schedule refuses vids YouTube would refuse** — YouTube rejects
  `publishAt` for any video that has ever been published; a mass schedule
  over previously-public vids sailed through pito's confirmation and died
  minutes later as `invalidPublishAt` watchdog errors (2026-07-19, live).
  The rule now lives in pito: stage-time and confirm-time guards name the
  already-public vid with honest copy, single and mass alike — and the
  wire format was proven correct all along (a new spec pins the exact
  UTC RFC3339 `publishAt` through the real single and mass paths).

## [3.5.0] — 2026-07-19

### Added

- **Pushes wear a real title** — the phone notification's bold line was
  empty because the FCM contract never carried one. Notifications grew a
  nullable `title` column; every source with a clear identity stamps a
  copy-driven title ("Unpublished vids", and friends), the FCM payload
  sends it as `data.title` (omitted entirely when a notification has
  none), and pito-android maps it with a "PITO" fallback for old servers.
- **Answers estimate their cost when the provider won't say** — OpenCode
  Zen bills per token but never reports a per-call cost, so its answers
  wore a bare model badge. When the provider reports nothing, the badge
  now shows a computed estimate — the loop's tracked tokens against the
  per-1M pricing the provider's own `/models` metadata publishes — worn
  with a leading `~` ("~$0.03") so an estimate never masquerades as a
  receipt. A provider-reported cost still wins, unmarked, exactly as
  before; models with no pricing anywhere still show nothing. Unknown is
  still not free — it's just no longer mute when the rate card is public.

### Changed

- **One date shape everywhere** — the message-timestamp rule is now THE
  house rule, extracted into `Pito::Formatter::HouseDate` and worn by
  every stamp on every surface: today collapses to bare `12:04`, this
  year reads `19 Jul 12:04`, any other year `5 Jun '25 12:04`; date-only
  values never collapse (`19 Jul`). `SyncStamp` delegates to it (detail
  cards, schedule confirmations, the `publish_at` column — the
  `DD-MM-YYYY` era ends), the @ai kv-table typed dates follow, chart
  prior-year ticks restyle to `Jun '25` (month-only — five day-bearing
  ticks don't fit a 42-cell canvas), release labels drop their US order
  ("October 15, 2026" → "15 Oct '26"), and month-granularity badges and
  period labels drop the year when it's this year's.
- **AI tables truncate smart, not blunt** — the kv key column's flat
  20ch cap (born in 3.4.0, visually inert in practice) is replaced by a
  container-driven track: full natural-width keys whenever the row has
  room, a proportional cap with a 20ch floor only when space tightens.
  Wide tables get per-column roles: the leading `#id` column, numeric
  columns, and date columns are content-sized and never truncate; prose
  columns carry the squeeze, wrapping at comfortable widths and
  tightening only under many-column or narrow-container pressure.
- **AI table columns align by what they hold** — pito's table law grows
  from numbers-only to three families: a column of numbers ("7,709",
  "2.2K", "93%"), of `#id`s, or of dates right-aligns, heading cell
  included; prose keeps reading left.

### Fixed

- **Notifications reach the phone clean** — the private-reminder dedup
  marker (`<!-- pito:private_reminder:… -->`) and raw markup leaked into
  the FCM push body and the TUI's `/notifications.json` verbatim; both
  seams now render through one shared plain-text pass — the same strip
  the Slack/Discord lanes always had — while the marker keeps doing its
  dedup job in the persisted record.
- **Digest webhooks preview clean on the lockscreen** — the achievements
  and upcoming-releases digests put their fenced, pipe-aligned table in
  the previewed surface, so phone shades rendered raw backticks and a
  mid-title cut. The previewed line is now a plain copy-driven summary
  ("3 unlocked: First Light, Not Alone, +1 more"); the aligned table
  rides in an embed/attachment field, which no shade renders — the rich
  in-app block survives untouched on both Discord and Slack.

## [3.4.0] — 2026-07-18

### Added

- **Schedule the whole week in one line** — `schedule 5 tomorrow, 6 friday,
7 27-07-2026 18:00` stages every pair behind ONE confirmation card, and the
  batch is all-or-nothing: one bad segment (a past time, a missing vid, two
  publishes crowding the same hour) rejects the lot with the offender named.
  A new house rule backs it at the model layer: no two publishes on the same
  channel within 60 minutes of each other — and imports/syncs from YouTube
  are deliberately exempt, so a Studio-side pile-up still mirrors in freely.
  Works as a hashtag reply on vid lists and search results too.
- **Update many at once** — `update game footage 5 2, 6 3, 9 4.5` applies row
  by row and reports once ("2 applied, 1 skipped — #6: no such game"); vid
  description/tags get the same comma form behind a single confirmation.
  Valid rows never wait for invalid ones.
- **Suggestions you can actually grab** — the copy snippet grew a second
  icon: stage the command straight into the chatbox, cursor parked, Enter
  still yours. Shift+U stages the latest AI suggestion from anywhere, and
  replying `apply` (or `use`, `accept`) to an AI answer does the same —
  staging, never running.

### Changed

- **The AI closes with ONE suggestion, not a volley** — at most one
  ready-to-run command per answer (a mass command counts as one), zero when
  there's nothing actionable. Its tables also grew up: long labels truncate
  instead of crushing the values, dates render in pito's own
  `DD-MM-YYYY HH:MM` (the model's raw date strings never reach the screen
  again), and a leading `#id` in a row is now tappable like every other id
  column when the row carries its command.
- **The AI model picker works from a phone** — the ctrl+f / ctrl+x hints are
  now tappable, and the reasoning effort is always visible: a cycler when
  the provider supports it, an honest dim line when it manages reasoning
  itself.

### Removed

- **The `footage` tool retires** — `update game footage <id> <hours>` has
  been the only setter for a while; the standalone tool, its card-reply
  action, and its help entries are gone (and the showcase no longer suggests
  the long-dead `footage update` form — a live bug on its way out).

## [3.3.1] — 2026-07-18

### Changed

- **Slash-command chrome stops offering itself for sharing** — every
  slash-dispatching tool (`/config`, `/jobs`, `/notifications`, and friends)
  now opts out of the universal `share` / `unshare` reply actions: a
  credentials table or a queue-status readout is chrome, not a shareable
  artifact. One `universal_reply: false` per tool in tools.yml — the
  mechanism that always existed, now applied across the slash surface.
- **No actions, no hashtag** — a message now mints and renders its `#handle`
  only when at least one reply action is actually available (its own reply
  target's actions, or a universal action that applies to its tool and
  kind). The rule is general, not special-cased: old messages whose actions
  have since gone away simply come back chipless on re-render, because
  payloads are data and rendering applies current rules. This also retires
  the stale display-only handle on legacy theme-diff cards.

## [3.3.0] — 2026-07-18

### Added

- **Phone notifications, no extra apps** — every pito notification now also
  lands on your phone as a real push, with the pito icon, tap-to-open into
  your conversation, delivered even when the app has been closed for days.
  The Android shell registers its device silently the first time you open it
  with a session (one Android 13+ permission ask, native-side), and the
  server fans pushes out beside the existing Slack/Discord webhooks. Dead
  tokens self-prune the moment FCM reports a device gone; an instance with
  no Firebase credentials configured simply skips the lane. Requires
  pito-android with push wiring and a `PITO_FCM_CREDENTIALS_PATH` pointing
  at a Firebase service-account key.

## [3.2.1] — 2026-07-18

### Fixed

- **`/config embeddings` stops calling itself a credentials panel** — the
  status table's title now reads "Embeddings status" instead of the
  "Embeddings credentials" fallback it inherited from the credential
  providers (it never held a credential; it's a read-only health readout).
- **The embeddings panel stops counting its own echo** — the conversation
  events row read N/N+1 on every single run, because the echo of the very
  command you just typed was already on the scrollback with its embedding
  still pending. Counts now cover only completed turns (that's the moment
  the embed pass is scheduled), so a healthy box reads N/N — and a genuinely
  stuck event still shows, which is the whole point of the row.
- **A single-result card knows what it's showing** — replying
  `link to 56,55,54,50` on a search (or list) card that displays exactly one
  game used to bounce off the usage hint, as if the card hadn't just told
  you which game it meant. When no source id is typed and the card shows
  exactly one row, that row now implies the source — link and unlink, games
  and vids, search and list cards alike. A typed id still wins, and a
  many-row card still asks you to say which one.

## [3.2.0] — 2026-07-18

### Added

- **Conversations join the semantic search party** — `search conversations
about <text>` works, routing to the same meaning-search the `like` keyword
  already ran for conversations (there is no seed to name, so for this noun
  the two keywords are honest synonyms). Bare conversation queries stay
  literal — exact recall ("find where I said X") is that noun's default job.
- **pito mumbles confusion in ten languages** — the didn't-understand
  dictionary grows Italian, French, German, Japanese, Chinese, Korean,
  Dutch, and Portuguese variants alongside the English deck and the
  long-standing Spanish "Lo siento". Same odds, same shrug, more passports.
- **The README and the site finally brag about it** — semantic search gets
  a headline section with real production captures: a keyword-less query, a
  vibe query, ranked Match bars, and the pager.

### Fixed

- **An unrecognized filter is never silently dropped again** — "list games
  with hard bosses" used to render the FULL, unfiltered library as if the
  filter had applied (the worst kind of success); "show games with hard
  bosses" died in a usage hint. Both — and their vids twins — now hand the
  original sentence to the natural-language gate, which routes it where it
  belonged all along (a semantic search). Asking a list for a column it
  already shows (`with title`) stays a list.
- **The fuzzy did-you-mean stops reaching** — a 4-character token now needs
  to be one edit away before a suggestion is offered: "hard" no longer
  earns "Did you mean `hack`?" (the production logs' repeat offender),
  while genuine near-misses ("fpss" → `fps`, "actoin" → `action`) still
  get their nudge.

## [3.1.2] — 2026-07-18

### Changed

- **Semantic Match bars are scored relative to the top hit** — the `about`
  bar used to anchor its 100 at cosine similarity 1.0, which a short query
  against a long game description structurally cannot reach, so the
  library's best answer to "brutal but worth every second" rendered a sad
  score of 16. Now the first result always reads 100 and the rest scale to
  how far above the honesty floor they sit relative to it — a close second
  reads in the 90s, a genuinely distant one stays low. 100 means "the best
  you've got for this query"; the nothing-close floor keeps that claim
  honest, and the ranking itself is untouched.

- **A bare search goes straight to the vectors** — "search games forcing
  skillful play", "search games with a good story", "search games
  requireing patience" (typo and all): a query with no `like`/`for`/`about`
  keyword now rides the same semantic path as `about`, because natural
  phrasings are an open set no connector vocabulary could enumerate — and
  the embedder shrugs at typos where a substring match never would. This
  supersedes 3.0.0's "bare means exact": `for` is now the one explicitly
  literal path ("search games for hades" when you want games actually
  titled that), and conversations keep their own grammar untouched. The
  result card's footer still tells you which engine answered.

## [3.1.1] — 2026-07-17

### Added

- **Search learns a third keyword: `about`** — free-text, qualitative search
  over the trait-infused embeddings 3.1.0 taught the vectors: "search games
  about brutal but worth every second" finds the right game — or vid — by
  feel, with no title or seed required. It's honest about a miss, too:
  nothing genuinely close returns nothing, never a page padded out with weak
  matches just to fill it.
- **The `like` path closes its genre loophole** — every match now has to
  clear the blended-score relevance floor, not just the genre-less seeds
  that used to lean on it alone; sharing a genre with the seed no longer
  buys a result a free pass. `search vids like` honors the same contract:
  neighbors below the similarity floor (which always rendered zero-length
  score bars) are dropped instead of padding the page.
- **The natural-language mapper learns the `about` shape** — qualitative,
  vibe-first phrasing ("something brutal but worth every second," not a
  title or a named game) now maps to `search … about …` instead of getting
  squeezed into `like` or `for`.
- **`search vids` pages exactly like `search games`** — the vids library was
  about to outgrow a single page, so `like`/`for`/`about` now fetch the same
  deep ranking games do and page it with the same `list_cursor` mechanism: a
  `search vids` result with more than a page of matches now offers `next`/
  `more` just like `search games` always has. `sort`/`order`/`analyze` still
  don't apply to a ranking — re-sorting or re-analyzing it wouldn't mean
  anything.

## [3.1.0] — 2026-07-17

### Added

- **Games gain a trait vocabulary — and semantic search can feel it** — a
  single declared YAML (`config/pito/traits.yml`, 3 scales + 24 tags:
  difficulty from `easy` to `brutal`, story from `bad` to `emotional`, pace
  from `relaxing` to `chaotic`, tags from `war` and `roguelike` to
  `worth_it`, `awful`, `parry_windows`, and `frame_tight_jumps`) now
  describes every game qualitatively. Traits live in a `games.traits`
  `jsonb` column (GIN-indexed) with per-trait provenance: `derived` values
  are computed from IGDB facts, `classified` values come from a
  Claude-with-web-search session, and `owner` values are yours — **an
  owner-sourced trait permanently outranks every classifier** and is never
  overwritten by any automated pass. `Game::Traits::Vocabulary` is the
  config-backed registry, `Game::Traits::Apply` the single legal writer
  (validates against the vocabulary, enforces owner-wins, enqueues the
  re-embed), `Game::Traits::Derive` the deterministic IGDB mapper.
- **The classify round-trip** — `rake pito:traits:export` writes the whole
  library as a commented, human-editable YAML (one `overrides:` block per
  game for your verdicts; `"!tag"` pins a trait absent forever);
  `rake pito:traits:import` validates everything before applying anything
  and reports honest counts; `rake pito:traits:derive` is the idempotent
  heal that recomputes every derived trait from stored IGDB facts.
- **Traits ride into the vectors** — a game's embedding text gains a
  `traits:` phrase built from its trait words, so "something brutal but
  worth every second" lands near the games you tagged that way. Games
  without traits produce byte-identical embed text (no mass re-embed on
  deploy); classifying a game changes its digest, and the 02:00 nightly
  re-embeds it unprompted. Ten new difficulty/relaxing/worth-it corpus
  phrasings on `search` teach the NL router the same vocabulary.
- **The nightly derives before it embeds** — `NightlyReindexJob` now runs a
  traits-derive pass first (per-game rescue-and-warn), then the corpus
  sync, then the re-embed sweeps, so fresh traits ride into that same
  night's vectors — sequential by construction, no timing to tune. The new
  `rake pito:nightly` alias chains derive → NL sync → reindex for on-demand
  runs.
- **Four game traits flip from Claude's judgment to synced IGDB fact** —
  `multiplayer`, `single_player`, `hyped`, and `family_friendly` used to
  ship as `source: classified` (a Claude judgment call) purely because
  pito didn't sync IGDB's `game_modes`, `hypes`, and `age_ratings`. All
  three now sync (`Game::Igdb::Client::GAME_FIELDS`, new `games.game_modes`
  / `games.hypes` / `games.age_ratings` columns), so `Game::Traits::Derive`
  computes the four tags deterministically on every IGDB sync:
  `multiplayer`/`single_player` from IGDB's game modes ("Multiplayer" /
  "Co-operative" count as multiplayer, "Single player" as single-player),
  `hyped` from IGDB's pre-release follow count clearing a tunable
  threshold, and `family_friendly` from an ESRB E/E10+ or PEGI 3/7 age
  rating (both threshold and rating sets are named, tunable constants on
  `Game::Traits::Derive`). Existing games pick up the new columns — and the
  four derived tags — on their next IGDB re-sync (`bin/rails
pito:games:resync_release_dates` sweeps every game with an `igdb_id`).

## [3.0.3] — 2026-07-17

### Fixed

- **The chatbox pointer stops stuttering during heavy streams** — the fx
  layer sampled the pointer on every DOM mutation; it now only records
  positions and lets the frame clock drive the work, so a busy scrollback
  no longer fights the cursor.
- **Analyze joins the soft-fail lane** — when the NL mapper picks `analyze`
  with a subject pito can't resolve locally, the reply now carries the
  did-you-mean fallback instead of a dead-end error (games, videos,
  channels, and linked lookups already had no local dead-ends).
- **The NL mapper gets 30 seconds, not 10** — cold-start completions on the
  2-vCPU box could exceed the old cap and surface as fake "huh" responses;
  the wider cap carries incident provenance so a real timeout is still
  logged as one.
- **Over-long embedding requests are char-budgeted** — chunked embeds are
  grouped into sub-batches capped at 2,000 characters per request, fixing
  the last five braille-dense conversation events that timed out the
  sidecar on the production box.

## [3.0.2] — 2026-07-17

### Fixed

- **Dense conversations embed too** — eleven conversation events (markdown
  tables full of pipes, digits, and ids) still failed to embed after 3.0.1's
  chunk-and-pool: table-heavy text tokenizes about four times worse than
  prose, so a chunk sized for ~300 English tokens landed at ~1,589 and the
  sidecar refused it. Chunking is now density-adaptive — when the embedder
  answers "too large", the input is re-chunked at half the budget and
  retried, down to a floor sized for the worst density observed. Prose-sized
  inputs keep the exact fast path; only the dense stragglers pay the retry.

## [3.0.1] — 2026-07-17

### Fixed

- **The digest gate now re-embeds a row with a NULL vector** — `Game::EmbeddingIndexer`,
  `Video::EmbeddingIndexer`, and `Pito::Embedding::EventIndexer` used to skip
  re-embedding whenever the text digest matched the stored one, even if the
  embedding column itself was empty. Every 2.x → 3.0.0 upgrader hit this
  automatically: the 1024→768-dim column promotion left `summary_embedding`
  NULL on every existing row while `embedded_digest` carried over unchanged,
  so the first post-upgrade `pito rake pito:embeddings:reindex` silently
  no-opped — dead similarity search and recommendations until a manual
  `FORCE=1` sweep. The gate now skips only when the digest matches AND a
  vector is already present. 3.0.1 also changes the embedding prompt itself
  (every input is now wrapped in a task-specific prefix before it reaches
  the embedder, putting every vector in a new space) and salts every digest
  with that prompt (`Pito::Embedding::Client::VECTOR_SPACE`), so a stored
  vector's digest now identifies which prompt space produced it, not just
  its source text — a same-text row embedded under the old prompt no longer
  looks unchanged. **The first `pito rake pito:embeddings:reindex` after
  upgrading to 3.0.1 — or simply the next 02:00 nightly reindex — re-embeds
  every game, video, conversation event, and NL-corpus row automatically**;
  no `FORCE=1`, no manual steps, and any future prompt change self-heals the
  same way.
- **Large conversations no longer permanently fail to embed** — the local
  embedder sidecar rejects any single input over its ~512-token physical
  batch with an HTTP 500; at 3.0.0 this silently dropped 23 of 189
  conversation events. `Pito::Embedding::Client` now chunks over-budget text
  on whitespace boundaries, embeds each chunk, and pools the vectors
  (element-wise mean, L2-normalized) — content is never truncated, and a
  single short input still returns byte-identical results to before.
- **The nightly reindex actually runs again** — `NightlyReindexJob` had been
  enqueued by nothing since 2026-06-09 (a promised chat trigger never
  shipped), and even a manual run only ever covered games and videos, never
  conversation events, so a failed event embed was permanent. It's back on
  the recurring schedule (02:00 UTC, both environments) and now sweeps
  never-embedded events too; the manual `pito:embeddings:reindex` sweep also
  correctly reports a still-nil event embed as `failed` instead of the
  misleadingly benign `skipped`.
- **Chat edits keep their embeddings current** — adding or removing a game's
  platform and editing a video's description or tags used to change the
  exact fields the embedder indexes without ever re-embedding, so the
  stored vector silently drifted from the visible text. Both paths now
  enqueue the matching re-embed job (digest-gated, so a same-turn double
  enqueue is harmless).
- **`find` no longer dead-ends every time** — `find vids about tekken` (the
  tool's own documented example) always returned "not implemented": the
  tool declared a chat-recognized verb with no handler behind it, which
  also meant the natural-language gate could never see a "find …" input
  either, since the verb had already claimed it. The `find:` chat
  recognition is gone (the tool's `nl_examples:` stay, feeding the NL
  corpus); "find …" now falls through to the natural-language router, which
  typically resolves it to `search` or `list` with a did-you-mean.
- Rake task `pito:images:regenerate` no longer tries to build a phantom
  `:lg` avatar variant (channel avatars only ever define `:sm`/`:xs`).

- **The MCP container stops fighting itself at boot** — `config/puma.rb`
  gated the in-Puma SolidQueue supervisor on the mere _presence_ of
  `SOLID_QUEUE_IN_PUMA`, and compose passes the literal string `"false"` to
  `pito-mcp` — which is truthy in Ruby. The MCP Puma booted a job supervisor
  it was explicitly configured never to run; its thread crash-raced the slim
  boot and died as the `NameError`/`NoMethodError` pair AppSignal kept
  reporting. The gate now compares against `"true"`.
- **`analyze @handle` works** — `analyze @yourhandle` used to answer
  "Analyze what?", dropping the handle on the floor; a leading `@handle` now
  resolves to the channel through the same exact+fuzzy lookup
  `show channel` uses.

### Added

- **`pito:images:purge_orphans`** — a new rake task that finds
  `ActiveStorage::VariantRecord`s whose variation digest no longer matches
  any currently-defined named variant (leftovers from 3.0.0's cover-art
  resize and the removed `:lg` avatar). Dry-run by default (prints what it
  would purge); pass `PURGE=1` to actually delete the orphaned variant
  blobs and records.
- **`/config embeddings`** — a new status block showing embedder
  reachability plus embedded/total counts for games, vids, conversation
  events, and NL router examples, closing a gap since 3.0.0 shipped local
  AI with zero operator visibility beyond `logger.warn` lines. The NL
  router also now logs one decision line per call (score, matched tool,
  nearest phrase, branch) so a low-confidence miss is debuggable after the
  fact instead of just a silent "huh?".
- **pito-tui: the conversation-search hit picker actually opens** — Shift+J
  was built against a JSON contract the server had already replaced before
  the picker shipped, so it could never decode a real hit and never opened.
  It now reads the real list-card payload (`table_rows` with
  `anchor_event_id` / `conversation_uuid`), jumps in-conversation on a
  same-thread hit, and submits `/resume <uuid>` for a hit in another
  conversation. The dead `/config voyage` command palette entry (removed
  from the server in 3.0.0) is gone from the tui too.
- pitomd's marketing site retexted its last few "Voyage" comments to "local
  AI" (source comments only — the built site never named Voyage, so nothing
  visitor-facing changes).

- **Verb-first free text finally reaches the language brain** — "show me my
  tekken vids" used to be captured by the `show` handler on its first word
  alone and die with a literal `can't find a video called "me my tekken
vids"`; the NL gate was only reachable when the first word matched no
  command at all. A handler that recognizes its verb but can't act on a
  free-text body now soft-fails back into the full NL pipeline (router →
  mapper → auto-run / did-you-mean), while numeric misses (`show game 99999`)
  and follow-up replies keep their crisp errors. Typo'd leading verbs
  ("impory", "seach") get snapped to the intended command before scoring,
  and `ls draft vids` filters like the private list it always meant.
- **Pure-read tools may auto-run** — the NL gate used to conflate
  "read-only" with "MCP-exposed", so `search`, `analyze`, `at-a-glance`,
  `breakdowns`, `channels`, `linked`, and `help` could never auto-run at any
  confidence. tools.yml now carries an explicit per-tool `read_only:`
  declaration the gate honors (write-capable tools remain confirm-only,
  pinned by a guard spec that fails if the auto-runnable set ever widens).
- **The NL corpus keeps itself in sync** — tools.yml phrase edits used to
  reach a populated production table never (the only sync path fired on an
  empty table). `pito rake pito:nl:sync` pushes edits on demand, the 02:00
  nightly heals drift automatically, and ten thin tools gained fresh
  owner-voice phrasings.
- **CI validates the compose stacks and the copy dictionary** — both
  docker-compose files now trigger CI and get `config -q` validated, and
  `rake pito:copy:audit` runs on every build (all were release-gate claims
  that nothing actually enforced).

### Changed

- **Every embedding speaks EmbeddingGemma's trained dialect** — the model
  was trained with task prompts; raw text is out-of-distribution. Every
  vector (games, vids, conversation events, NL corpus) now carries the
  documented sentence-similarity prompt at the wire, invisibly to callers.
  A measured A/B on the routing surface: more genuine reads clear the
  auto-run bar while the noise ceiling _drops_. Confidence thresholds were
  recalibrated on live prefixed measurements (`suggest` 0.75 → 0.72, with
  the calibration fixture restructured into honest tiers).
- **The command mapper picks its examples per utterance** — the qwen mapper
  used to receive all few-shot exemplars on every call, which made it
  brittle: adding any exemplar reshuffled unrelated compositions. It now
  embeds the exemplar pool once (cache invalidated on tools.yml change),
  retrieval-picks the eight nearest for each utterance, and falls back to
  the full static prompt if the embedder is unreachable. Together with a
  re-tuned repeat penalty (1.3 → 1.1, digit-safety re-verified live),
  indirect phrasings compose measurably better — and a new live-gated
  calibration harness guards every future grammar or exemplar edit.
- **Score columns tell the truth** — game "like" results are a ten-signal
  blend and now say **Match**; vid and conversation results are pure
  semantic similarity and now say **Similarity**, rescaled against measured
  practical bands (an unrelated vid pair used to display ~88/100 because
  raw cosine never goes near zero; it now reads ~19, and true garbage
  clamps to 0).
- **`docs/footage.md` left the repo** — the footage reference lives with
  the terminal client now; the in-app behavior (per-game manual
  `footage_hours`) is unchanged.

## [3.0.0] — 2026-07-16

### Added

- **Local AI replaces Voyage AI** — two CPU-only [llama.cpp](https://github.com/ggml-org/llama.cpp)
  sidecars ship in both compose files: `embedder` (embeddinggemma-300m, Q8,
  768-dim, the OpenAI-compatible `/v1/embeddings` API) and `nlmapper`
  (Qwen3-0.6B, Q8, grammar-constrained to PITO's own command set). No
  signup, no API key, nothing leaves your machine — see the README's "Local
  AI" section for the ports, env vars, and troubleshooting curls.
  `Pito::Embedding::Client` (`app/services/pito/embedding/client.rb`) is the
  single HTTP seam every caller goes through, with the same two contracts
  the Voyage client grew up on: forgiving `#embed` (nil on any failure,
  never raises) and strict `#embed_batch` (raises, naming the real cause,
  for bulk/reindex jobs that want a visible failure).
- **Talk to PITO in your own words** — chat input that matches no tool now
  routes through an embedding router (`Pito::Nl::Router`, a cheap
  cosine-nearest lookup against every tool's `nl_examples:`) and, when
  nothing trained is close enough, a grammar-constrained mapper
  (`Pito::Nl::Mapper`) asks the `nlmapper` sidecar to compose a real PITO
  command, then proves it by round-tripping through the actual chat parser
  — LLM output that doesn't parse to a known tool never reaches you.
  Read-only mappings at confidence ≥ 0.90 auto-run immediately with an
  attribution line ("Ran `<command>`."); everything else — lower
  confidence, or any write-capable tool, regardless of confidence — asks
  "Did you mean `<command>`?" first. Thresholds, lexical synonyms, and the
  few-shot worked examples all live in `config/pito/tools.yml`'s `nl:`
  block; a held-out calibration corpus (`spec/fixtures/nl_calibration.yml`)
  measures the thresholds empirically instead of guessing them.
- **`search conversations like <text>` / `search conversations for <text>`**
  (bare = `for`) — semantic (`like`, cosine-nearest over a new
  `events.embedding` column) and exact-substring (`for`/bare) search over
  your own scrollback, grouped into one hit per conversation and ranked by
  best match. Clicking a hit row jumps the scrollback straight to that
  message with a brief highlight flash. Declared in `config/pito/tools.yml`
  under the existing `search` tool (`search_nouns: [games, conversations]`);
  handled by `Pito::Chat::Handlers::SearchConversations`. Only allowlisted,
  owner-searchable event kinds get embedded, over a partial HNSW index.
- **Title lookups** — `show game <title>`, `show vid <title>`, and
  `show game for vid <title>` resolve free text through one shared
  exact-first ladder (`lib/pito/title_resolve.rb` + `lib/pito/title_match.rb`):
  an exact (including IGDB `alternative_names`) or prefix match wins
  outright, then anchored token-run scoring, then an acronym-of-initials
  tier ("mk2" → "Mortal Kombat 2"). Every tier breaks ties toward the
  shortest title, so "mortal kombat" always finds "Mortal Kombat" over
  "Mortal Kombat 2".
- **Link suggestions after a video sync** — a freshly-synced, still-unlinked
  video gets up to 5 numeral-aware game-link nudges ("Mortal Kombat 2:
  Was it really that good?" correctly favors a library "Mortal Kombat 2"
  over "Mortal Kombat"), scored by the same token-run matcher the title
  ladder uses, with embedding cosine similarity as a tiebreak only
  (`app/services/video/game_link_suggester.rb`). Offered once per video —
  `videos.link_suggested_at` — as ready-to-run `link` commands in a
  notification, never an auto-link.
- **Viewport-driven paging** — pagers for notifications, `/resume`, and the
  games-import search sidebar now accept a client-sent page size (pito-tui
  sends its actual visible row count via `limit=`), clamped to each tool's
  configured `max_page_size` in `config/pito/tools.yml`; a limit-less
  caller (browsers, older builds) sees identical behavior to before.
- **An F9 FPS overlay on every surface** — a top-left chip, hidden until
  toggled, readable in every environment (not just development); its
  sampler only runs while the chip is visible, so an untoggled chip costs
  nothing. The DEVELOPMENT ribbon at the bottom goes back to being a plain
  wordmark now that the fps meter that briefly lived inside it (2.1.0) has
  its own home.
- **MCP tool descriptions got a rewrite** — every remote-AI tool exposed
  over `/mcp` now carries intent framing (when to reach for this tool vs. a
  sibling) plus worked "owner asks this → the tool call that answers it"
  example utterances, so a connected AI assistant picks the right tool on
  the first try instead of guessing from a bare noun.
- **AppSignal now hears about broken embedding batches** — a strict
  `embed_batch` failure (a sidecar down mid-sweep, a malformed response) is
  reported to AppSignal as an incident; the forgiving `embed` path (search-
  like matching, link-suggestion tiebreaks) stays log-only, since a sidecar
  hiccup there is designed degradation, not an incident.
- **Search results are first-class, config-driven lists** — every search
  result (games, conversations, vids) renders through the same list-card
  mechanism as `list games`/`list vids`, with a display mode set by the
  `like`/`for` grammar split: `like` (similarity) adds a **Score** column, a
  0–100 gradient bar rendered from a structured `{ score: }` cell at display
  time — never HTML baked into the stored payload; `for` (mentions) adds an
  **Occurrences** count (conversations) or matches across multiple lexical
  fields (games, vids), with no score bar at all.
- **`search vids like <title>` / `search vids for <text>`** — vids join
  games and conversations as a searchable noun for the first time. `like`
  resolves a seed vid and ranks its nearest embedding neighbors (same shape
  as games' `like`, seed leading at a 100 score); `for` matches title,
  description, and tags. Because a search result is a single-page similarity
  ranking, its card carries a dedicated `video_search` reply target: every
  per-vid reply still works (`show`/`rm`/`schedule`/`publish`/`unlist`/`link`/
  `unlink`/`glance`/`game`/`shinies` and column `with`/`without`), but the
  pager (`next`/`more`) and `sort`/`order` are deliberately absent — they'd
  paginate or re-order a ranking that only makes sense as the one page it was
  returned as. That result card has its own `#<handle> --help` page listing
  exactly those replies, and `search vids for`/`search vids like` now appear
  in the Ctrl+K command palette next to the games and conversations forms.
- **Conversation search drops its snippet for a resume shortcut** — the hit
  card's second column is now mode-dependent: `for`/bare shows an
  **occurrence count**, sorted most-mentioned-first (ties break on recency);
  `like` shows the same **Score** bar every other search result gets. The
  conversation name itself is now the click affordance — clicking it fills
  the chatbox with `/resume <uuid>` (or `/resume <uuid> <event_id>` for a
  `for` hit, so the click both switches conversations and jumps straight to
  the matched message) and submits immediately.
- **`/resume <uuid>`** and **`/resume <uuid> <event_id>`** — switch straight
  to a conversation by uuid, optionally landing on one message via a
  `#event_<id>` anchor jump (the same smooth-scroll-and-flash a
  conversation-search hit click triggers). `/resume <name>` keeps its
  existing exact-title behavior.
- **`search games for <title>` now matches genres, developer, and
  publisher** too, on top of the existing title/summary/alternative_names/
  platforms/themes/player_perspectives fields — "capcom" or "beat 'em up"
  now finds a game via its detail card even when neither word is in the
  title.

### Changed

- **Scheduled Slack/Discord notifications arrive as one digest, not a flood** —
  the two recurring jobs that used to fan a separate webhook out per item now
  each send a single grouped message: one **Upcoming releases** digest (blue
  accent) and one **Achievements** digest (gold accent), each a monospace
  two-column table (days-until │ game title; achievement │ who earned it),
  sorted soonest-first / by unlock order. In-app notifications, their
  per-event records, the real-time single-achievement webhook, and the job
  schedules are all unchanged — only the scheduled webhook fan-out is
  collapsed. Delivery is best-effort: a webhook outage is logged, never raised.
- **Scroll pills stop counting past ten** — the ctrl+home / ctrl+end
  pills now read "10+ msgs before/after" once more than ten messages sit
  out of view; counts one through ten stay exact. Same short form in the
  TUI.
- **Game and vid embeddings retired Voyage AI for good** — every live
  path that (re)embeds a game or vid (IGDB sync, game import, the nightly
  reindex fan-out, the video library sync, and the chat `reindex`
  confirmation) now calls the local-embedder indexers end to end; the
  Voyage AI indexer/client/stats files and their two bulk/reindex jobs
  are gone, renamed live per-record jobs are `GameEmbedIndexJob` /
  `VideoEmbedIndexJob`.
- **The rest of Voyage AI is decommissioned** — the `voyage` gem is gone
  from the Gemfile; `app/services/voyage/*`, both Voyage indexer files, and
  `lib/pito/stack/voyage.rb` are deleted; the `/config voyage` credential
  surface (its accessors, its input-masking rule, its usage-dashboard tile)
  is gone along with it. `app_settings.voyage_api_key` is dropped for good
  (an owner-ruled, deliberately destructive migration — see
  `db/migrate/20260715170000_*`). The retired 1024-dim `summary_embedding`
  columns on `games`/`videos` are dropped and the 768-dim `_v2` columns
  promoted to the canonical column and index names in the same migration
  chain (`db/migrate/20260715180000_*`) — no straggler "finalize" step left
  waiting on a manual go-ahead.
- **`search games for <title>` is now an exact match, and bare defaults to
  it** — `search games for tekken` (or the bare `search games tekken`) now
  returns only games actually titled Tekken-something (matched against
  title and IGDB `alternative_names`), never a genre/theme neighbor; `search
games like <title>` keeps its unchanged similarity ranking. Previously a
  bare query behaved like `like`.
- **Breaking for self-hosters: the first boot after `pito update` downloads
  new AI weights** — `pito up` now pulls the `embedder` and `nlmapper`
  sidecars' GGUF weights (~850MB combined) from Hugging Face into their own
  per-sidecar volumes (`embedder_models` / `nlmapper_models`) before either
  reports healthy; budget a few extra
  minutes on a slow connection (both healthchecks' `start_period: 10m`
  covers it). New `PITO_EMBEDDER_URL` / `PITO_NLMAPPER_URL` env vars point
  the app at the sidecars — the compose files set both for you, no `.env`
  edit needed. Run the chat `reindex` command once after upgrading
  (`reindex game <id>` / `reindex vid <id>`, or `pito rake
pito:embeddings:reindex` for a full games+videos+events sweep) so your
  library re-embeds at the new 768-dim width; until then, similarity search
  and search-like results ride whatever finished re-embedding. The Voyage
  API key setting is simply gone — no action needed, the column drop above
  is automatic.
- **Similar-games card shows 4 covers, 20% bigger** — was 5 covers at
  180×240; the strip variant grows to 432×576 (displayed 216×288) so 4
  covers fill one clean desktop row and wrap to a tidy 2×2 on mobile with no
  orphaned third card. Existing covers regenerate at the new size
  automatically on your next `pito update` — a one-off backfill enqueued on
  deploy (derived from each cover's stored master image), so there is no
  manual step and no CSS/HTML upscaling.

### Fixed

- **Backfilled achievement tiers land in the right order** — when a channel
  or vid is first tracked with history behind it, a metric can clear several
  milestone tiers in one shot (connect a channel already past its tier-3 subs
  mark and tiers 1–3 all unlock at once). Those lower tiers were always
  created, but they shared a single unlock timestamp, so the per-metric
  timeline (ordered by `unlocked_at`) couldn't sort them. They're now stamped
  one second apart — the top tier at the unlock moment, each lower tier a
  second earlier — so the history reads tier-1-oldest up to the highest tier
  newest. Single-tier unlocks are unchanged.
- **Embedding failures now say why** — when the local embedder can't
  produce a vector for a game or vid (a sidecar hiccup, a malformed
  response, a missing key), the recorded error carries the real cause
  instead of a bare "returned nil", so an incident names its culprit on
  sight.

## [2.4.0] — 2026-07-14

### Added

- **Your shinies, your ambitions** — the achievement ladders moved out of
  the code and into `config/pito/shinies.yml`: every scope × metric ceiling
  and the channel-subs award metals are data now, shipped with the same
  defaults as before (nothing changes unless you say so). Self-hosters
  mount their own copy over the baked one to reshape every ladder; a broken
  file refuses to boot with a message naming exactly what's wrong. See
  README → "Customizing your shinies".

## [2.3.2] — 2026-07-14

### Fixed

- **The wall stopped ghosting under the plasma** — when the living
  background changed moods mid-jank (several `ls games` cover walls loading
  at once), the outgoing wall could freeze at a visible tint and haunt the
  screen for five seconds. Retired moods now drop to invisible the moment
  they leave the mix.

## [2.3.1] — 2026-07-14

### Fixed

- **pito-tui can delete conversations again** — a body-less DELETE carries
  no Content-Type, so the JSON CSRF carve-out never matched it and the
  server refused the tui's `dd` behind a disguised 404. DELETE now also
  recognizes API clients by their JSON Accept header — safe because no
  browser primitive can send a cross-site DELETE (forms can't produce the
  verb, fetch forces a preflight we never approve, and the lax session
  cookie stays home regardless). Found by AppSignal four minutes into its
  first production hour.

## [2.3.0] — 2026-07-14

### Added

- **AppSignal, wired but optional** — APM, error tracking, and log
  forwarding for the whole production stack (web requests, SolidQueue jobs,
  the recurring fleet, and the MCP Puma). Activation is double-gated: the
  app must run in production AND find `APPSIGNAL_PUSH_API_KEY` in its
  environment (set it in the install dir's `.env`; compose passes it
  through). Without a key — every other self-host — nothing changes, at
  all. Logs keep flowing to Docker's STDOUT either way.
- **`/up`** — the liveness route production.rb always believed in finally
  exists (200 when booted), ready for uptime monitors.
- **The sync runs twice a day now** — channels and vids refresh at 01:00
  AND 13:00 UTC (new uploads show up by lunch, not tomorrow); the IGDB
  upcoming-games refresh stays a nightly affair.

- **Warm analytics, faster fills** — a twice-daily warmup pass now
  pre-fills every connected channel's glance, analyze, and breakdown
  caches with the exact production fill code, so those turns land on warm
  data instead of paying YouTube round-trips while you watch. Cold turns
  got faster too: per-metric fills run six at a time (was three) and cold
  fetches fan out eight wide (was four), with the connection pool sized to
  match — tuned per environment, so development runs wider still on a big
  machine while production stays fitted to its 2-vCPU box.

### Changed

- **The recurring fleet stopped fetching what it already had** — the
  achievements passes now read the video stats, subscriber counts, and
  lifetime analytics the sync and snapshot passes persisted an hour
  earlier, falling back to the API only when a pass failed (stale data
  heals itself; failed fetches never write fake zeros). Steady state: two
  lifetime-report calls a day instead of three-plus, and zero redundant
  videos.list / channels.list sweeps.
- **Fleet failures report without breaking ranks** — when one channel's
  refresh dies inside a recurring pass, the error now lands in AppSignal as
  an incident while the isolation holds exactly as before: siblings keep
  running, nothing partial is written, and keyless installs report nowhere.

## [2.2.0] — 2026-07-14

### Added

- **`ls private vids`** — the fourth visibility filter: vids that are
  private and not scheduled — uploaded, processed, and going nowhere until
  you act. Scheduled vids stay out; the filter survives paging and speaks
  MCP.
- **The night watchman** — at 01:45 every night (right after the sync),
  PITO counts your private vids older than a day and, if any exist, nags
  you once — the bell, Slack, and Discord all carry the same line, drawn
  from a fresh 50-variant dictionary. One reminder per day, silence when
  the shelf is clear.

## [2.1.3] — 2026-07-14

### Fixed

- The conversations sidebar paints above its dimming overlay again — the
  living background's stacking rules had quietly trapped it underneath.

### Changed

- The cable writes now: every payload sends a bright red dot traveling the
  cable's stroke end to end with a blue-to-purple ink trail chasing it,
  then evaporating.

## [2.1.2] — 2026-07-13

### Fixed

- **The app can't get trapped on a dead conversation anymore** — deleting
  the conversation you're standing in used to strand the Android shell on
  the native error screen (Hotwire never renders an HTTP error's body).
  PITO now serves its own graceful not_found page as a success to the
  native shell, so the app renders it like any visit; browsers keep the
  honest 404. No app update needed — every installed APK is fixed.

## [2.1.1] — 2026-07-13

### Fixed

- **`--web` is a command, not a suggestion** — the orchestrator now runs
  the first web search itself on `@ai --web` turns and hands the model the
  results, so no model can skip the web again (DeepSeek's tool forcing is
  unreliable; ours isn't).
- The AI now spells the product **PITO** — all caps, always.

## [2.1.0] — 2026-07-13

### Changed

- **The AI model picker's header slimmed to title + Esc** — the active-model
  summary is gone from the top row; the ● on the active row already says it.

### Added

- **The AI model picker's state is readable as JSON** — `GET /settings/ai`
  returns exactly what the `/config ai` overlay renders (providers, keys
  present, live catalogs, active pick, effort, favorites, recents, and —
  given `?conversation=` — that conversation's ✨ model trail), session-gated;
  the web overlay and the JSON now render one shared assembly, so terminal
  clients get pixel-parity pickers that can never drift.

- **A live FPS meter rides the DEVELOPMENT ribbon** — page frame rate now,
  the fx engine's own clock alongside it once the living background lands;
  the perf yardstick for fx iteration.

- **The shelf mood** — game lists and channel libraries float their actual
  covers at hashed depths behind the conversation, swaying with the
  butterfly.
- **The butterfly flock** — every effect chases an autonomous attractor that
  flies in eased legs of uneven tempo (darting, cruising, drifting), startles
  when pito events land, leans toward your mouse without obeying it — and a
  whole flock of them wears visible bodies over the resting sky: thin
  brand-colored rings trailing fading echoes, never touching, never over a
  mood (they fade as a mood rises). The lens and halftone moods anchor up to
  three focus circles to the flock — more on a desktop, one on a phone, each
  a different size — and the cover wall sizes its tiles by how much art it
  has: a thin shelf means bigger covers, never doubled ones.
- **A readable conversation over any mood** — a page-toned veil band exactly
  as wide as the message column, surfaces at 92% of their own color, one soft
  halo on every text, and a global mood-intensity cap; water calmed to a pond
  (rare soft drops, high damping — all fx.yml knobs).
- **One white ink, two colored gleams** — every special token now rests on
  the same foreground white as plain text: keybindings are bold with the
  theme's blue band sweeping through, clickable #id / @handle tokens are bold
  with the theme's purple band, and subjects, references, and #handles are
  simply bold — no shimmer, no chips, no backgrounds.
- **The verdict sheet closed the roster** — `aurora` (2-4 blurred hue
  areas breathing on the flock) wears every analyze moment; `trails` (the
  pitomd ring-cascade: each butterfly drags a stack of luminous purple/blue
  circles, bright head to swelling tail) joins lists, analyze, and channel;
  plasma serves walls and only walls; AI wears the globs alone; and the
  fluid smoke, comet, film grain, scanlines, and coins were shown the door.
- **Two new moods from the owner's verdict sheet** — `glow` (dreamy
  spotlights punching light through the cover, one per butterfly, staggered
  sizes) joins water, duotone, and lens on single-cover moments; `globs`
  (the gooey metaball field, blobs riding the flock) leads the AI pool. The
  cover wall gained collision-free placement (tiles never overlap, sizes
  roam between a floor and a ceiling, film grain on top), plasma became the
  wall's 50/50 partner and its thin-shelf understudy, the flock re-rolls
  3-6 members on every mood pick, and the idle rings finally wear pitomd's
  luminous rotating gradients instead of thin hoops.
- **The mood map is law, not luck** — fx.yml now states cover cardinality on
  both sides: every effect declares whether it wears one cover, many, or
  none, and every context declares what it carries. The locked trio (water,
  duotone — né halftone — and lens) belongs to single-cover moments only
  (show/analyze of one game or vid); cover walls belong to `ls games`,
  `ls vids`, and `show channel`; putting a single-cover mood on a list is a
  boot error in the owner's own words, not a silent skip.
- **Messages now command the background** — when a game, list, vid, channel,
  AI, or analytics message holds the viewport, a mood picked from its
  YAML-declared pool crossfades in over the sky (halftone dots, water
  ripples, a chromatic lens, or drifting smoke — cover-fed where the message
  carries art), chosen per message and remembered per message; scrolling
  glides between moods, never strobes, and nothing ever paints over a
  message body. Moods are keyed by their ART, not the message: `show vid 2`
  then `analyze vid 2` flow through one uninterrupted ripple field, and a
  game sharing its linked vid's cover keeps the water alive rather than
  restarting it — neighbours only, and never the same effect twice in a row
  when the art changes and the pool offers an alternative.
- **The ffprobe snippet moved out** — `footage snippet` (and its `footage
game <id>` alias) left pito entirely; probing your recordings now lives in
  pito-tui's ctrl+f flow, where the files actually are. `footage update
<id> <hours>` stays.
- **The scrollback never scrolls for you anymore** — the follow-the-newest
  feature is gone (an AI answer's tool iterations kept yanking the view
  mid-read). Reloading or resuming a conversation still lands on the
  newest message, and sending a command still shows it arrive; everything
  else is yours, with ctrl+home / ctrl+end as the ferries.
- **The scroll pills speak once, plainly** — "3 msgs before ctrl+home ▲" /
  "3 msgs after ctrl+end ▼": one clear string on both web and TUI (the
  50-variant dictionary is retired), white words, and the pills now kiss the
  conversation scrollbar — top pill at the top, bottom pill riding the chat
  dock.
- **Shinies are engraved, not shadowed** — chip text is a deep shade of its
  own material sitting in a carve (dark recess above, material-tinted lip
  below); gold engraves warm, stone engraves cool.
- **Pull-to-refresh is a soft swap** — the bottom pull now rides a Turbo
  replace-visit instead of a full reload, so the Android app never flashes
  its boot screen on a refresh.
- **The sky is on** — a natural star field now breathes under the whole app:
  the TUI sky's exact math (deterministic star identity, real stellar color
  classes, a rarity ladder from dust to brilliants, per-star breathing, two
  parallax drift layers) on one fixed canvas that never fights the content —
  30fps-capped, DPR-capped, pausing when hidden, still under reduced motion,
  and fully alive on mobile.
- **Messages know their mood** — eligible messages (`:system`, `:enhanced`,
  `:ai`) now carry a server-derived fx context (game, shelf, vid, channel,
  AI, analyze — with the cover art paths that mood needs) stamped at the
  persist door and re-derived when a follow-up replaces content; the JSON
  mirror carries it to every client. The living background reads this,
  never guesses.
- **The fx registry** — `config/pito/fx.yml` declares the living background's
  ontology (engine knobs, effects and their capabilities, context → weighted
  effect pools), schema-validated with did-you-mean hints and an
  add-an-effect proof: a new effect or context remap is a YAML edit, never a
  conditional. Groundwork for 2.1.0's message-mood backgrounds.

### Fixed

- **No more dead strip under the chatbox in production** — the chat dock
  reserved the development ribbon's 32px in every environment; production now
  hugs the viewport with a tight 12px while development keeps its ribbon room.
- **The "below: N hidden" pill stops covering the context meter** — its
  anchor is now measured from the chat dock's real top edge (and re-measured
  as the dock grows), instead of a desktop-tuned 116px constant that
  overlapped the meter on phones.

### Changed

- **The install banner switches to the app** — on Android the banner's action
  is now an intent link: if the PITO app is installed it opens straight into
  it, and if not the same tap falls back to downloading the newest APK.

## [2.0.1] — 2026-07-12

### Changed

- **The Android install banner is a gold shiny** — the install invite now
  wears the achievement system's gold award material (fill, travelling gleam,
  breathing halo) stretched into a full-column banner, with the smartphone
  glyph, a bracketed "[ Get the APK ↓ ]" action, roomier edges, 16px, and a
  breath of space below the top edge. Built on a new generic ShinyChipComponent
  so anything can wear a material without inline styling; the link keeps
  resolving to the newest published APK release.
- **Slack notifications stop underlining code** — the notifier posts its
  Block Kit text verbatim, so a bare `ghcr.io/…` image ref inside a code chip
  no longer renders as a barely-visible auto-link; explicit links still work.

## [2.0.0] — 2026-07-12

### Added

- **The `@ai` verb — ask PITO's assistant anything** — `@ai what should I play
next?` (any casing: `@AI`, `@Ai`, `@aI`) runs an agentic loop against your
  configured provider: the model reads your library through PITO's own
  read-only tools, then either answers by running ONE real pito command (its
  native card appears, exactly as if you typed it) or composes its own reply.
  The pending message narrates which tool it is reading; provider switches via
  `/config ai` apply on the very next question; loop/token caps and provider
  failures land as clean messages, never a stuck spinner.
- **Talk WITH the assistant, not just at it** — every AI answer is replyable
  (`shift+r`): `#a7 @ai and what about tekken?` continues that thread, and the
  replied-to exchange (your question plus that exact answer) is guaranteed
  into the model's context even when it has scrolled far out of the recent
  window. `apply [n]` still runs a suggested command.
- **AI answers stream in as they're written** — on providers that support it,
  the assistant's blocks no longer land in one paint at the end: each
  paragraph, chart, or gauge appears in the pending message the moment the
  model finishes writing it, and kv/table blocks go further — their rows fill
  in ONE BY ONE while the table is still being composed (charts and gauges
  always land whole; a half heart means nothing). The final message is still
  persisted atomically, so an interrupted stream simply falls back to the
  one-shot behavior.
- **`/config` autocompletes by namespace** — typing `/config ` now offers the
  three groups (AI · Sources · Profile), each expanding in place to its
  members on Tab; typing a fragment still completes providers directly. The
  final commands are unchanged.
- **`with`/`without` suggestions know the card** — replying on an analytics
  card, `with` offers only metrics it doesn't already show and `without` only
  those it does; either vanishes from the palette when it has nothing to
  offer.
- **Select all stays inside the message** — long-press a word, hit Select
  all, and the selection covers exactly that message (flash-free); dragging
  across messages still works natively.
- **The sidebar hugs the conversation** — on desktop the panel's left edge
  now sits on the conversation column's right edge instead of floating at the
  far side of an ultrawide.
- **A heavy fill can't block your next command** — command dispatch rides its
  own worker lane, so analytics crunching never delays the reply to whatever
  you type next.
- **Small models get more room** — the AI loop allows 16 round-trips (tokens
  still capped) and its instructions teach batching tool calls and committing
  early; bare `pito_analyze` now really does analyze all channels, and asking
  a channel's games when none are linked answers in words instead of silence.
- **The `/resume` list and notifications panel page themselves** — both
  sidebars load 50 rows and fetch the next 50 through the same generic pager
  the moment the dotted shimmer at the bottom scrolls into view — a
  hundreds-long conversation history no longer arrives in one giant paint.
- **The `show vid` / `show game` pickers page and search server-side** — the
  picker sidebars ride that same 50-row pager, and the JSON feed behind them
  (`/videos/picker.json`, `/games/picker.json`) accepts `q=` (the same
  title match as the web's picker search) so a terminal client's search is
  exact-parity with the browser — filtered results page too, instead of
  arriving as one capped dump.
- **Spinner verbs travel with the event** — thinking indicators on the JSON
  stream and backfill now carry their word pools (`words` while spinning, the
  past-tense `word` once resolved) rendered from the server's CURRENT copy at
  send time, so a client binary older than the deployed dictionaries can
  never show stale verbs.
- **AI conversations wear a sparkle** — `/resume` rows whose thread contains
  AI answers append the house sparkles glyph after the name, its fill
  shimmering in the AI accent pair on the global angle; the ✨ model chip on
  every AI answer now renders that same centralized badge.
- **Model catalogs refresh themselves nightly** — a 01:30 scheduled job
  re-fetches every reachable provider's model list (and the pricing mirror
  behind computed chip costs) once a night, replacing ad-hoc daytime
  re-fetches.
- **Effort is per model** — the picker's effort cycler now binds
  low/medium/high to the CHOSEN model (a `provider/model → effort` map), so
  switching models restores each one's own setting and models without
  reasoning control simply never carry one.
- **The picker knows this conversation** — a leading "Conversation" group
  lists the models this conversation's answers were actually written by
  (newest first), so hopping back to "whatever wrote that last answer" is one
  keystroke. Appears only once AI messages exist.
- **The AI's content vocabulary is declared, not hardcoded** — a new
  `config/pito/content.yml` is the single ontology of everything the
  assistant may compose: paragraphs (with **bold**, _italic_, and a limited
  color palette — default, cyan, red, green), kv-tables, tables, media,
  sparklines, area/bar/heatmap charts, the new **heart chart** (a braille
  heart filled to a 0–100 sentiment score with a likes/dislikes legend),
  score bars, effort gauges, and suggestions. Each block carries an
  explanatory "what it is / when to use it / exact data shape" the model
  reads; global content rules ban emoji outright (kaomoji welcome — the
  terminal look survives). The tool document, validation caps, and system
  prompt rules all generate from the YAML — changing what the model may say
  is a YAML edit plus support code, and presentation never leaks to it.
  While it works, the tool-activity line ("Crunching the numbers… ·
  pito_analyze") now shimmers like the Thinking block, opening with one of
  fifty handshake quips ("Somewhere, a GPU sweats…") the instant you ask.
- **AI answers, dressed by feedback** — the surface settles on a static
  pure-purple tint while the left bar keeps the purple→pito-blue sweep, now
  height-aware (a one-line chatbox bar and a tall answer each flow at their
  own pace); the pending message wears the plain :system dress until the
  answer lands; the ✨ model badge sits in a translucent corner chip; the
  reply handle renders through the standard meta line with its clickable
  `shift+r`. Typed kv-values (price/date/number/score) right-align through
  the house formatters — prices wear the same coins as `show game` — rows
  can carry a click-to-run command, and stray `**bold**` markers are
  unwrapped in cells (styling belongs to paragraphs). Suggestions only
  appear when you ask for them, and the `apply` reply is gone — AI answers
  reply with `@ai <text>` (and now `share`, like any card).
- **`/config` un-spilled** — the nine AI providers no longer clutter the
  config surface: `/config ai` is the ONLY AI entry, now scriptable as
  kwargs (`provider=… api_key=… model=… effort=…`, documented in its
  `--help`); per-provider slash commands are gone.
- **Every answer knows what it cost** — the ✨ chip now shows the message's
  price beside the model: the house coin and a two-decimal amount with its
  currency ($0.01 — symbols attach, ISO codes take a space), taken from the
  provider's own reported cost for the answer — a receipt, never an
  estimate. Free models proudly show $0.00; providers that don't report a
  cost show nothing rather than a made-up number.
- **verbs are tools now** — the dispatch ontology file is
  `config/pito/tools.yml` (top-level `tools:`), and the whole codebase
  speaks "tool" for chat commands: parser, handlers, registry, matrix,
  reply bindings, segments, pager, help groups, guard suites, copy
  ("Unknown command"), and the suggestions wire protocol. MCP tools keep
  their name — on any collision the MCP side wears the mcp prefix. Old
  persisted rows keep reading via a back-compat key.
- **Nine AI providers, one picker** — the `/config ai` dialog now spans every
  provider in the registry: OpenCode Zen, OpenRouter, Hugging Face, DeepSeek,
  OpenAI, Anthropic, Qwen, GLM (Z.ai), and Gemini. Favorites (`ctrl+f`) and
  recents float your models to the top; each provider gets an inline
  paste-your-key row (`/config <provider> api_key=…` works from text too, key
  masked); an effort cycler appears for providers that support reasoning
  control. Keyless providers list nothing but a hint that models load once a
  key is added (no placeholder rows, no doomed requests); a `pinned` badge
  only ever marks the curated fallback when a keyed provider's live catalog
  fetch fails.
- **Charts and gauges untied from their data sources** — the big ticked area
  chart, and the time-to-beat gauge (now generic ordered levels + a current
  tracker — game footage is just its preset) accept plain values from any
  caller; the AI's `area` chart blocks render the full ticked chart with
  y-values, date axis, and target line.
- **`/config ai` — AI provider foundation** — the first piece of the AI chat
  groundwork: an AI provider registry (`config/pito/ai_providers.yml`, starting
  with OpenCode Zen), a live model catalog (fetched from the provider, cached a
  day, pinned fallbacks when offline), and a picker overlay opened by
  `/config ai` — paste your API key once (stored encrypted in the install's
  settings, never shown again), then search and pick the active model with
  ↑/↓ + enter; `ctrl+x` clears the stored key, and the dialog always shows
  whether a key is on file. Also reachable from the Ctrl+K palette, and
  scriptable as `/config ai api_key=… model=…` (key masked in the echo like
  every credential).
- **The `update` verb — one typed surface for metadata writes** —
  `update game footage|price|platform <id> <value>` writes locally at once;
  `update vid description|tags <id> <value>` stages a confirmation whose _yes_
  pushes exactly that one field to YouTube (nothing else in the snippet is
  touched, publish state untouched). These are the commands the AI suggests —
  and only you can run. The old typed `footage update` / `price set` /
  `platform set` forms now point you at their `update` equivalent; replying on
  cards (`#g3 price 20`) works exactly as before. The footage tally snippet
  gained a per-game entry: `footage game <id>`.
- **Share opt-out per verb** — a verb can now declare `universal_reply: false`
  in verbs.yml and every message it emits stops offering share/unshare|revoke
  (no handle, no palette entries; a typed `#handle share` is politely refused).
  `sync`'s status messages are the first to use it. A HOW-TO comment block in
  verbs.yml documents the switch.

### Changed

- **Sparklines come alive** — the glance tiles' sparklines drop their flat
  single-color fill for the same red→amber→yellow→green health ramp the big
  area charts wear, so a good week visibly glows green at its peaks.
- **Bar charts punch as hard as the heatmap** — every filled segment is
  clamped into the heatmap's neon band (bright, chroma-floored, hue kept),
  so a brand-blue or purple bar glows exactly as loud as a red or green one
  on any theme; the dim remainder cells also keep more of their own hue
  instead of sinking into the dotted paper.
- **Subjects wear pink, references shimmer cyan** — the highlighted SUBJECT
  of a line (a game title, a metric name) now rests on each theme's own
  synthesized pink instead of orange, and REFERENCE tokens (`#id`s and
  values inside AI answers) get their shimmer back on their cyan base; both
  sweeps are now derived mathematically from the base color itself, so the
  pair stays coherent on every one of the 18 themes.
- **`/config` overview regrouped** — three sections now: AI (ai, tavily),
  Sources (google, voyage, igdb), and Profile (webhook, nickname, sound,
  timezone).
- **Older messages show their day, not just a time** — a scrollback message
  from another day now reads `6 Jul 11:04` (and `2 Jan '25 11:04` once the
  year differs) instead of a bare `11:04` that made a five-day-old
  conversation look like it happened this morning. Today's messages keep the
  clean time-only prefix.
- **`search games like <title>` returns relevance, not the library** — the
  seed game itself now heads the results (its title being the closest match),
  followed only by games that actually share a genre with it, ranked by the
  recommendation blend — three results instead of fifty-one on a 66-game
  library. A seed with no genres on record falls back to a similarity floor.
- **Bottom pull-to-refresh, redone** — the ASCII gauge is gone. Pulling up from
  the very bottom of the conversation now floats in the Lucide refresh arrows —
  no tile, no border, just the glyph on a purple→pito-blue gradient stroke —
  tracking the finger 1:1, the arrows winding up with the drag while their
  gradient counter-rotates against them; crossing ~30% of the screen height
  fires the reload on the spot, and letting go earlier just drops it back out.
  The conversation itself no longer moves during the pull.
- **AI answers dress like PITO** — the `:ai` message opens with its timestamp
  inline in the first line (wrapped text returns to the left margin) and sits
  on a purple→pito-blue gradient surface in the accent bar's exact colors,
  cycling every ~10 rows so long answers sweep purple→blue→purple instead of
  stretching one fade thin. A ✨ badge (inline Lucide sparkles on the same
  gradient stroke) pins the answering model's name to the bottom-right corner.
  Any markdown pipe-table the model leaks into prose is extracted into a real
  table block — rendered on the shared grid in the kv-table palette (cyan
  leading column, dim values), the same look `show game` details wear. While
  the loop runs, the pending message narrates each tool read with a line from
  the copy dictionary ("crunching the numbers… · pito_analyze") instead of a
  bare arrow.
- **The AI model picker speaks the palette's language** — bold title row with a
  tappable Esc hint, yellow section titles for favorites/recents and every
  provider, the Ctrl+K-style underlined search, and keybinding-styled footer
  hints. Esc now always dismisses it (nothing can swallow the key while the
  picker is open); Esc while pasting an API key backs out to the list first.
- **Universal reply actions no longer override verbs** — a reply token a
  message's verb declares itself always routes to the verb; share/revoke only
  apply where nothing else claims the token.
- **Code comments no longer cite internal plan documents** — references to
  untracked working docs (task numbers, phase codes, decision datestamps) are
  gone from the tracked sources; the constraints they explained remain, written
  to stand alone.

## [1.6.0] — 2026-07-10

### Added

- **`publish_at` video column** — a scheduled video's go-live time is now its own
  first-class column (`list vids with publish_at`), sortable (`sort by publish_at`)
  and shown as a named "Publish at" field on `show vid`, instead of being buried in
  the visibility label. Visibility keeps its four scopes (public / unlisted /
  scheduled / private); the exact timestamp is now visible without opening the vid.
- **Richer MCP tools** — the `pito_list` MCP tool now advertises, per noun, exactly
  which extra columns, filters, and sort keys it accepts (read straight from the
  chatbox grammar, so the two can't drift), gains a `filter` argument, and rejects
  unknown columns/nouns with a helpful error instead of silently ignoring them. The
  `filter` argument documents the real values it accepts (`upcoming`, `rpg`, `ps5`,
  `xsx`, …) rather than bare category names. An AI client can now pull a
  scheduled-video slate (with publish times) in one call instead of fetching each
  video separately. Every tool now declares its read-only nature explicitly in
  config (a required per-tool flag, schema-enforced): nine pure-read tools carry
  `readOnlyHint: true`, while the four analytics tools (`analyze`, `glance`,
  `breakdowns`, `channels_of_game`) declare `false` — their first call for a
  period computes and caches (and may query the YouTube Analytics API), which
  their descriptions state openly — so a strict client may ask before calling
  them. No tool can modify library data either way.
- **One game-filter vocabulary** — the genre / platform tokens `list games`
  understands now come from the same config vocabulary that `--help`, the MCP
  tools, and `find` read (a guard keeps them in lockstep), which adds a batch of
  new working tokens (`sony`, `psn`, `microsoft`, `windows`, `xsx`, `xss`,
  `series x`, `series s`, `xb1`, `xbone`, `nintendo`, `iphone`, `ipad`, `mobile`,
  …) including two-word forms (`list games series x`). `arcade` is gone, matching
  the v1.4.0 platform drop — and Arcade is now stripped from imported platform
  data too (a migration scrubs previously imported rows), so the word no longer
  exists anywhere in PITO.
- **Filters and columns in `--help`** — `list games --help` / `list vids --help`
  now list the available filters (e.g. `upcoming`, `scheduled`) alongside the
  columns, and both are generated from the same source the table and MCP use, so a
  new column or filter shows up everywhere at once. `show vid #id --help`,
  `show vids --help`, `list vids --help`, `game --help` / `games --help`, and
  `search --help` now render (previously some alias, id, segment-verb, and
  query-verb forms showed nothing). `/jobs --help`, `/games --help`, and
  `/rename --help` now show their full command pages (subcommands / arguments)
  instead of a bare generic page.

### Changed

- **Chatbox autocomplete keys** — when the suggestion palette is open, **Tab**
  accepts the highlighted suggestion and **Enter** always submits the chatbox as
  typed. Enter no longer silently completes a half-typed verb, so what you see is
  what you send.

### Fixed

- **Stale scheduled times** — a video that already went live no longer shows its
  old go-live timestamp in `list vids with publish_at`: past times render as "—"
  and sort with the unscheduled bucket, so the schedule slate only ever shows
  genuinely upcoming publishes (the `show vid` field already behaved this way).
- **`--help` always helps** — a chat command carrying `--help` whose noun can't be
  parsed (e.g. `link #3 to game #5 --help`) now renders the verb's help page
  instead of falling through to the command itself.
- **Blank filter labels** — `list games --help` no longer renders empty token
  cells for the genre / platform filter rows.
- **IGDB release days** — a game's release date now records the real day from
  IGDB's timestamp instead of defaulting to the first of the month, so countdowns
  and the "upcoming" slate are accurate and already-released games stop being
  counted as upcoming. A missing-date sentinel (epoch 0) degrades to month
  precision instead of fabricating day 1.
- **First real score for a new game** — a game whose score moves from 0 (unknown)
  to its first real value is no longer blocked by the score-drift guard; the guard
  still catches suspicious large swings between two real scores.

## [1.5.0] — 2026-07-09

### Added

- **Connect an AI chat (MCP)** — PITO now speaks the Model Context Protocol at
  `/mcp`, so an AI assistant (claude.ai on your phone, ChatGPT, or any MCP client)
  can READ your PITO over a one-time connection: list and show your games, videos,
  and channels; pull analytics, breakdowns, at-a-glance snapshots, similar games,
  channel coverage, and shinies; and read your past conversations. Thirteen typed
  tools in all, declared entirely in `config/pito/verbs.yml` — no new plumbing per
  tool. It is strictly **read-only**: nothing it can call imports, edits, publishes,
  deletes, links, schedules, or changes anything, and MCP calls never write to your
  scrollback or show up in the resume sidebar. Auth is standard OAuth 2.1 (PKCE +
  dynamic registration) with a single TOTP approval per client — authenticate once,
  then it refreshes silently. Served by a dedicated container so a slow model
  tool-loop can never slow the web app, the APK, or the TUI. See the README
  "Connect an AI chat (MCP)" section to attach a client.

### Fixed

- **Pull-to-refresh, reworked** — pulling up now fills the arrow/disc gauge with a
  smooth pito-blue gradient (no more one-row-at-a-time stepping), the disc is
  reachable with a modest pull instead of dragging to mid-screen, and a downward
  pull no longer parks the scrollback with a blank gap below the content. Release
  with the disc filled to refresh. (Mobile / Hotwire Native.)

## [1.4.4] — 2026-07-08

### Added

- **Multiple ids at once** — `list`, `analyze`, `at-a-glance`, and `breakdowns` now
  take several ids together (comma and/or space, optional `#`): `list videos 2, #4, 7`
  lists exactly those in the order you typed; `analyze videos 2,3,4` /
  `at-a-glance videos 2,3,4` / `breakdowns games 5,6` evaluate them as ONE combined
  card. A single id still works everywhere.
- **Slate, filtered by channel** — `schedule <id> slate only @handle1, @handle2`
  scopes the schedule to just those channels (the union); without `only` you still
  get the full slate.

### Fixed

- **Pull-to-refresh no longer over-runs into blank space** — the reveal now tracks
  your finger 1:1, capped at the arrow block's own height, so the arrows show from
  the first movement and there's no dead gap below them.

## [1.4.3] — 2026-07-08

### Changed

- **Schedule slate, rebuilt** — `schedule <id> slate` is now one combined list of
  everything scheduled (id · title · channel · go-live), sorted by go-live, with no
  week/rest split. The go-live reads in human form — "in 3 hours", "tomorrow at
  noon", "in 2 days", "on 1st of March" — so near vs far is obvious at a glance.
  The `with` / `without` / `sort` column options are unchanged.
- **Taller pull-to-refresh reveal** — three arrows above the shrug line and six
  below it before the arming circle, for a more deliberate pull.

### Fixed

- **No more dead space at the bottom of the scrollback** — the pull-to-refresh hint
  was cloned into the scrollback on the first pull and left there; as a flex block
  it kept its height even while invisible, leaving a permanent gap above the chatbox
  (and a bare tap could even spawn one). It is now removed on release and recreated
  only during an actual pull.

## [1.4.2] — 2026-07-08

### Changed

- **Cleaner `show vid` and `show channel` cards** — on the video card the last-sync
  time now sits directly under visibility, and tags moved out of the key/value table
  into their own hairline-separated section beneath the description (labelled and
  wrapped, just like the description). On the channel card the description likewise
  moved out of the key/value table into a hairline-separated section below it,
  matching the video card.

## [1.4.1] — 2026-07-08

### Fixed

- **Reply verbs work on every card again** — replying `game` to a `show vid` card
  (and `channels` / `similar` / `vids` on a game card, `games` / `vids` / `shinies`
  on a channel card, `at-a-glance` on any of them) returned "Unknown action". The
  detail-card handlers carried a hand-maintained allowlist that had drifted from
  `verbs.yml`, silently rejecting verbs the config declared as available. Reply
  availability is now driven entirely by `verbs.yml` — every follow-up handler gates
  on the same config matrix, so a verb that's declared for a card just works, and a
  new segment verb needs zero handler changes. A build-failing guard keeps any
  hardcoded verb list from creeping back in.

## [1.4.0] — 2026-07-07

### Added

- **Fuzzy channel handles** — `show channel fighter` now resolves `@fighterpro`.
  Resolution falls back to a pg_trgm similarity match when no exact handle matches,
  on both the typed `show channel <handle>` path and channel-card replies.
- **`search games like <title>`** — a similarity search that lists the games most
  like a seed game (via the recommendation engine). It renders as a normal list
  card, so `#id` show/link/analyze replies, `sort`/`with` column tweaks, and
  `more`/`next` paging all work on the results.
- **`more` to page a list** — reply `more` (a synonym of `next`) to go past the
  first 50 rows of any list.
- **Pull-to-refresh, redesigned** — deliberately stiffer to trigger, with a taller
  five-row ASCII reveal (arrows → shrug → arrows → a circle that arms the reload),
  and now available in mobile web browsers, not just the app shell.
- **Bare `import <title>`** — games are the only importable thing, so `import tekken`
  now works exactly like `import game tekken` (and bare `import` opens the sidebar).

### Fixed

- **`vids` works wherever `videos` does** — `show channel @h with vids` and a `vids`
  reply on a channel card are now recognized (they were silently unknown before).
- **`@`-less channel lookup** is locked with a regression test —
  `show channel gmrdad82` resolves without the leading `@`.
- **The pager keeps your sort and columns** — re-sorting or adding/removing columns
  as a reply to an already-shown list now carries into `more`/`next` instead of
  reverting; a video-list sort reply no longer dropped pagination entirely.
- **Arcade-only games no longer clutter import search** — IGDB carries a separate,
  arcade-only entry for many titles (e.g. a second "Tekken 7" for the 2015 arcade
  cabinet) that collides by name with the console/PC release and can't be told
  apart in the sidebar. Import search now keeps only games on a platform you play
  (PlayStation / Xbox / Switch / Steam), so the arcade duplicate drops out.

## [1.3.2] — 2026-07-07

### Fixed

- **One channel's outage no longer blanks a whole breakdown** — analytics
  fetches are now isolated per subject: if YouTube fails for one channel or
  video (the Subscribed chart was hitting this — the API 5xx's the
  subscribedStatus dimension for some channels), the rest still aggregate
  and render. A failed subject contributes nothing and is not cached, so it
  refetches and recovers on its own; genuine bugs still surface rather than
  being silently zeroed.
- **Empty charts say so** — a metric with genuinely no data shows a centered
  "No data yet." over the paper instead of a blank canvas that read as broken.

## [1.3.1] — 2026-07-06

### Fixed

- **The shinies actually ripple** — the gleam stagger was being reset by an
  animation shorthand; with longhands, every chip runs its own of twenty
  phase offsets.

## [1.3.0] — 2026-07-06

### Fixed

- **"Spans 1 games" no more** — the channel games intro pluralizes its
  count-bound nouns ("1 game" / "23 games") across all fifty variants.

### Added

- **Shinies became materials** — achievements were redesigned end to end.
  Progression badges are filled natural-stone chips (Wood through Opal),
  positional on each metric's own ladder, with a travelling gleam and their
  own embedded typeface — fully independent of the app theme. The metals
  are reserved: Silver, Gold, and Diamond are channel awards at 100K, 1M,
  and 10M subs. Ladders are now per scope at monetized-channel scale (a
  vid's ceiling is far below its game's, which sits below the channel's) —
  no more 10M-comments fantasies. The shinies message lays out full-width
  lanes: a material rail (every step a tick in its stone, the next one
  pulsing) with the obtained chips flowing left to right; detail cards cap
  their compact strips at three per row. Replying `shinies` now also works
  on channel messages.
- **Games grid data for text clients** — `channel_games` messages carry
  structured `games` rows (`id`/`title`/`vids`) beside the rendered grid,
  so cover-less clients can draw the list themselves.

## [1.2.1] — 2026-07-06

### Added

- **The JSON surface grew a mini status** — `GET /chat/:uuid.json` and
  `/resume.json` now carry `me` (nickname identity) and
  `notifications.unread`; the conversation object carries the context
  meter (`pct`/`count`/`threshold`, the exact web-meter math). Every web
  meter tick also sends a `conversation.update` message on the JSON
  cable with fresh context and unread numbers — terminal and native
  clients render live without polling.
- **Error events always ship readable text to JSON clients** — payloads
  that carry only an i18n `message_key` get the server-rendered `text`
  added in the JSON projection (cable mirror and backfill alike), so
  non-browser clients never invent copy. Stored payloads are untouched;
  the web keeps re-rendering keys with current translations.

### Fixed

- **Channel list `next` keeps your table setup** — paging a sorted or
  `with`-customized channel list no longer resets the added columns, and
  counter sorts keep working past page 1.

## [1.2.0] — 2026-07-06

### Added

- **A channel's games, as a cover grid** — `show channel @handle full` now
  slots a games message between the detail card and the vids table: every
  game linked to the channel's videos as a cover card with its `#id` and
  that channel's vid count, alphabetized, five per row. Also reachable as
  `show channel @handle with games`, free-chat `games channel @handle`, and
  by replying `games` to any channel message. Replying `show <id>` on the
  grid opens the game.
- **Every show segment is a reply verb now** — replying `at-a-glance`,
  `videos`, `similar`, `channels`, `game`, or `games` on a show or list
  message emits that segment for the entity, exactly like the typed form.

### Changed

- **`vids` reads naturally everywhere** — the game segment `linked-videos`
  is now `videos` (aliases `vids`, `linked-vids`): `show game #3 with vids`,
  `vids game #3`. The vid segment `linked-game` is now just `game`:
  `show vid #10 with game`, `game vid #10`. The two-word `linked` forms and
  all reply wiring keep working unchanged.

## [1.1.5] — 2026-07-06

### Fixed

- **The top y-tick no longer gets clipped** — chart surfaces carry real
  headroom now. The tick labels are centred on their data rows, so the top
  one always extended half a line above the plot, and the swipe wrapper was
  silently clipping it on every device. The surface grew 8px taller; widths
  are untouched.

## [1.1.4] — 2026-07-06

### Changed

- **Breakdown bars always sum to exactly 100** — the braille bar charts
  (Age, Geography, Gender, Devices, Subscribed) keep their glyphs, but the
  cell math is normalized with three simple rules: every positive slice
  shows at least one cell; if the rounded cells overshoot the axis, the
  biggest bar gives cells back until they fit; if they undershoot, the
  biggest bar absorbs the slack. Segments tile sequentially — each bar
  starts where the previous ended — so a full breakdown always closes the
  axis on the last paper column instead of drifting a cell short or long.
- **Chart surfaces span their column** — the metric surface reaches the
  column edge on every device; a glyph canvas wider than its home (area
  charts on narrow phones) swipes horizontally instead of inflating the
  page. Desktop's 450px columns fit the full canvas outright. The dotted
  paper fills the whole surface, edge to edge.
- **Lifetime windows start at your first video** — no more 2005 epoch on
  lifetime charts; the window floors at the earliest published video, and
  ticks from prior years render as short `Mar'26` forms.
- **Copy sentences start with a capital letter** — a sweep across every
  dictionary (~370 variants): chart captions no longer open with the
  lowercase "lifetime" token, sync/theme/footer/upcoming lines got reworded
  so interpolated tokens sit mid-sentence, and the pull-to-refresh hints,
  delete confirmations, and typo notices are capitalized. Literal command
  syntax, chrome tokens, and echoes of your own input stay as-is. A new
  spec guard keeps the rule enforced.

## [1.1.3] — 2026-07-05

### Changed

- **The shimmer band became a gradient** — subject and reference tokens (and
  the mini status' green nickname) now sweep one blue→purple gradient band,
  wider than the old single-color slice, so the pass actually reads in both
  theme families.

### Fixed

- **Charts follow their container everywhere** — the braille canvas is a
  fixed 42 glyph cells, and any home narrower than that (the glance grid's
  halves in a half-screen desktop window, phone columns) had rows bleeding
  past the cell edge. Chart cells are size containers now: the glyphs derive
  their size from the real available width, and the locked 450px desktop
  layout renders pixel-identically.
- **Channel sort replies work again** — making counter columns
  visibility-gated (1.1.2) broke `#handle sort views`: the reply handler
  never passed the stamped selection, so every counter sort silently
  no-opped. It passes it now, and a `with likes` selection survives the sort.

## [1.1.2] — 2026-07-05

### Added

- **The mini status listens to the version heartbeat** — the `@version`
  suffix now has a dedicated cable listener: every 5-minute push writes the
  server's running version straight into the bar, live, no reload needed.
  The yellow nudge still announces the skew and owns the actual reload.

### Changed

- **Chart shimmer reads on light themes too** — the sweep band across every
  chart (area, bar, heart, sparkline, score, TTB) is now plain white on all
  themes; `fg-default` was dark on light themes, which erased the effect.
- **Text shimmer banding went blue→purple** — subject and reference tokens
  keep their text color but sweep in the brand pair instead of
  orange→yellow, on light and dark alike.
- **`help` is no longer a reply verb** — every handle offered it and most
  targets answered "no help page available"; the row is gone from reply
  palettes and help pages app-wide. `--help` (the flag) remains the help
  surface everywhere.
- **The pull-hint shrug became fifty shrugs** — the kaomoji beside the line
  is now its own 50-variant dictionary, sampled independently of the fifty
  texts: 2,500 combinations, déjà vu rare.

### Fixed

- **Thinking kaomoji stopped clipping on phones** — the indicator hangs its
  glyph left of the text column, which walked past the narrow mobile inset;
  the page now carries a few extra pixels on the left, scrollback and chatbox
  shifting together.
- **Charts stay on the paper on phones** — the 42-cell braille canvas was
  wider than a phone viewport, so dots walked off the right edge (heatmap
  most visibly). Chart glyphs now scale down on narrow viewports to fit
  exactly; desktop and the 450px column are untouched, and the heatmap's
  seven day-bands keep their even 6-cell split at every scale.

## [1.1.1] — 2026-07-05

### Added

- **The pull-to-refresh gesture got a face** — a shrug (¯\\\_(ツ)\_/¯) and one
  of fifty short ironic lines fade in as you pull, turning yellow the moment
  releasing would reload.
- **The refresh nudge is heartbeat-driven now** — the server pushes its
  version to every open tab every five minutes, so an update can never again
  slip past unannounced (1.1.0 did exactly that: the one-shot reconnect check
  missed the update's churn). The reconnect check stays as a fast path.

### Fixed

- **Pull-to-refresh reloads the styles too** — the Android WebView re-served
  the cached document on reload, keeping the old CSS alive across a server
  update while the scrollback content looked fresh. HTML now goes out
  `no-store` (assets stay fingerprinted and long-cached), so every reload —
  gesture, nudge tap, or key combo — actually wears the new build.
- **Ampersand bundles reach the import sidebar** — IGDB joins some two-title
  bundles with " & " ("Yakuza Kiwami 3 & Dark Ties") instead of " + "; the
  combo detector now accepts both spaced joiners, while unspaced ampersands
  ("Game&Watch …") stay filtered.
- **`ls channels` finally honors `without`** — the counter columns
  (subs/views/vids) were part of the immovable base table, so the footer
  offered levers that moved nothing. Now only identity (avatar · handle ·
  title) is fixed: the default table looks identical, but `#handle without
views` slims it, `with likes` widens it, and sort follows whatever is
  visible — matching how games and vids lists have always worked.

## [1.1.0] — 2026-07-05

### Added

- **The palette answers from the first letter** — free chat verbs finally get
  what slash commands always had: typing `l` offers `link`/`list`/`login`…,
  `analy` narrows to `analyze`, and the palette is alias-aware — `ls` matches,
  stays `ls` when accepted, and Enter on any complete verb or alias sends
  immediately. One row per verb (never `list` AND `ls`), arguments continue
  after each space exactly as before.
- **Bottom pull-to-refresh in the Android app** — pito lives at the bottom of
  the scrollback, so the refresh gesture does too (Slack-style): overscroll
  past the last message and release. App-only; browsers keep their reload
  buttons. Top pull-to-refresh stays off — it fights scrolling the history.
- **The refresh nudge is tappable** — yellow is the action class, so the
  nudge acts like one: tap or click anywhere on it to reload. Touch devices
  are told "Tap here" instead of a key combo they don't have.
- `breakdown` now works as an alias for `breakdowns`.

### Changed

- **Chart shimmers switch to fg-default** — the sweeping diagonal band across
  every chart (area, sparkline, bar, heart, heatmap, score bar, and TTB) now
  uses `var(--fg-default)` instead of the pito-blue `var(--brand-pito)`, for a
  cleaner look that follows the theme text colour.

### Fixed

- **Bar charts total 100% now** — a breakdown with more than five segments
  (say, Geography's long tail of countries) rolls everything past the top
  four into an "Other" bar instead of silently dropping it; five or fewer
  segments stay fully discrete. Age breakdowns also stopped inflating their
  kept buckets to fake a 100 — the shares are honest and the tail is named.

## [1.0.1] — 2026-07-05

### Added

- **The refresh nudge** — when the server updates under an open tab (the
  autoupdater's specialty), the cable reconnect now checks `GET /version`
  against the page's build and, on a mismatch, drops a yellow, reply-less
  notice into the scrollback: fresh CSS/JS arrived, reload to wear it. Copy
  comes from a new 50-variant dictionary and names the right key combo for
  your OS (⌘R on Macs, Ctrl+R/F5 elsewhere). Ephemeral by design — never
  persisted, gone with the reload it asks for.
- **The mini-status shimmers** — the authenticated `■ nickname` now wears the
  house green↔yellow sweep (the same recipe as rising trend numbers), so the
  little square finally looks as alive as the channel it represents.

## [1.0.0] — 2026-07-04

### Added

- **A coverage floor** — the suite now measures itself (SimpleCov, `.rb` files
  only — services, models, controllers, jobs, and ViewComponent classes; ERB
  and JS deliberately excluded) and CI fails below the floor, mirroring
  pito-tui's Go coverage gate. Opt-in locally (`COVERAGE=1 bundle exec rspec
&& bundle exec rake coverage:floor`), always-on in CI, enforced on the
  MERGED result after `parallel_rspec` so per-process slices can't false-fail.
- **A JSON client surface** — the scrollback always persisted structured
  `jsonb` events (never HTML), and now non-browser clients can drink straight
  from it: `POST /session {otp}` (TOTP-only JSON login minting the same
  session cookie), `GET /chat/:uuid.json` (the backfill), JSON `POST /chat` →
  `201 {uuid, turn_id}`, `GET /resume.json` (the conversation picker), and a
  live `Pito::JsonChannel` mirroring every persisted event append/replace as
  `{type, event}` from the Broadcaster's choke points. Auth-gated end to end
  (guests get explicit 401s; the cable rejects them outright — strictly
  tighter than the old consumer-less ChatChannel it replaces), with a
  media-type-keyed CSRF carve-out for JSON bodies. Web-only verbs (sidebars,
  navigations) answer terminal clients with a printable `web_only` refusal.
  Built for [`pito-tui`](https://github.com/gmrdad82/pito-tui) — the
  Go/Bubble Tea terminal client — and whatever window comes after it.

- **Caddy direct HTTPS** — a `caddy` compose profile (dormant by default) plus
  `pito caddy`, which writes a `Caddyfile` for your domain and enables the
  profile in `.env`. An alternative to the cloudflared tunnel for hosts with a
  public IP: automatic Let's Encrypt, WebSockets included, survives
  `pito update`. The installer now offers the choice (tunnel stays the
  default); the existing cloudflared flow is untouched.
- **`pito hetzner`** — provision a Hetzner Cloud box ready to run PITO from
  your laptop: `provision` idempotently creates the SSH key (prefers a
  dedicated `~/.ssh/pito-hetzner.pub`), a 22/80/443 firewall, and the server
  (CX23 / ubuntu-26.04 / fsn1 defaults, all overridable) with cloud-init that
  installs Docker, adds 2G swap, and disables password SSH; `info` reports
  status + IP. Needs the `hcloud` CLI; the API token is never stored.
- **`pito autoupdate`** — your server pulls new releases itself; CI holds ZERO
  deploy credentials. A 15-minute systemd timer checks for a newer release
  tag, waits until its multi-arch image is actually live on GHCR, and applies
  it with the same `pito update` you'd run by hand — which now carries a
  single-updater `flock`, so the timer and a manual update can never race.
  Dedicated `log/autoupdate.log` (logrotate weekly), optional Slack ping via
  `SLACK_WEBHOOK` in `.env`, `--check` dry-run, `--uninstall` to remove.
- **Android client prep** — the Rails side of the upcoming
  [pito-android](https://github.com/gmrdad82/pito-android) Hotwire Native
  shell: a public path-configuration endpoint
  (`/configurations/android_v1.json`), a `hotwire_native_app?` helper, and a
  dismissible conversation-width "get the APK" banner shown only to Android
  browser visitors (never inside the app; dismissal persists per browser).

### Changed

- **README: "Android app" grew into "Beyond the browser"** — the clients
  section now covers `pito-android` AND `pito-tui` (the Go/Bubble Tea terminal
  client) and points to the [pitomd.com](https://pitomd.com) showcase; the
  whole PITO family cross-references itself across every repo.
- **The lists answer back properly.** `ls games` gains `views`/`likes` columns
  (summed across a game's linked vids — 0 when nothing is linked) in
  `with`/`without` and `sort`; `ls channels` joins the with/without mechanism
  with an addable `likes` column (a channel's likes are the sum of its vids').
  The sums are MATERIALIZED into each entity's own stats rows at the three
  daily stats passes (and on link edits) — lists read a single row, never
  re-summing videos at render;
  the vids `comms` column is gone (comment counts stay on `show vid`);
  `duration` is the one word for video length everywhere (heading, footer,
  sort — `length` still quietly accepted); and `ls games` no longer pretends
  sorting by platform icons means something.
- **The argument palette actually opens now — everywhere.** Typing
  `#handle with ␣` (or `sort ␣`, `show ␣`, metric args) pops the option
  palette, and so do chat verbs' own arguments (`list ␣` → channels/games/
  vids, `show game 5 with ␣` → segments). The server had the menus all
  along; client gates discarded them for argument positions — one for
  hashtag replies, one for free chat input. `price ␣` also gained its
  enumerable openers (`set`/`unset`). Fresh-token rule throughout: palette
  at a trailing space, Enter still sends mid-token.
- **`help` and `--help` list alphabetically** — verbs within each group and
  every man-page section's rows (kwargs, options, segments) now sort
  alphabetically (`--help` counts as "help", `#id` as "id"), so long listings
  scan predictably.
- README: the features grid is a single-column flow (the two-column table
  rendered unevenly), the exposure section covers both HTTPS mechanisms, and
  new sections document CI auto-deploy and the Android app.

### Fixed

- **The transition-built chatbox lost its ghost 10px** — arriving in a
  conversation via the start-screen transformation left the chatbox 10px
  taller than a reload: the morph still injected the legacy
  `#pito-chatbox-filter` line, which no page renders since the channel/period
  meta moved into the hint slot — an empty div whose margin-top haunted the
  box. The injection (and its dead start-screen template) are gone; the morph
  keeps only the hidden channel/period inputs.
- **The start-screen palette owns Enter now** — typing a partial verb (say
  `/resu`) popped the palette with a highlighted row, but Enter submitted the
  raw partial and the backend shrugged. The start screen (and the 404 page —
  same component) now wires the palette keydown in the same order as the
  conversation chatbox, so Enter accepts the highlighted row; every
  non-palette Enter (login included) passes through untouched.
- **Android path-configuration drift** — `/configurations/android_v1.json` now
  matches the shell's bundled config byte for byte (adds `fallback_uri`, turns
  `pull_to_refresh` OFF — the gesture fights the live scrollback — and clears
  the back stack on root patterns). The app disk-caches this document over its
  bundled copy on every launch, so the divergence was silently overriding the
  shell's intended behavior. Served with `Cache-Control: public, max-age=3600`.
- `pito --help` no longer truncates after `self-update` — the usage printer
  followed a hardcoded line range and silently dropped `service`,
  `cloudflared`, `link`, and `version`.
- **Start-screen transition lands at the conversation width** — the first
  message's chatbox animation expanded to full viewport width and morphed
  into a legacy 50px-padded layout, leaving the chatbox wider than the
  conversation column until a reload. It now lands exactly at the centered
  964px column and builds the same DOM the server renders (same classes,
  paddings, and controllers). Applies equally to `/` and the 404 start
  screen.
- Slack release notices no longer show literal `*` around the headline — the
  bold span wrapped a trailing code span, which Slack's mrkdwn refuses to
  close.
- **The IGDB nightly stopped crying wolf.** The "checked 60, updated 49"
  notification was mostly cover-art churn: the freshness gate compared the
  attachment's age against an `igdb_synced_at` stamped seconds earlier, so
  every cover was re-downloaded nightly, and CDN re-encodes re-attached
  unchanged art — each attach touching the game. Covers are now keyed on
  IGDB's immutable image id (blob metadata): unchanged covers cost zero
  network and zero writes, a genuinely new cover still attaches and busts
  caches. The notification itself now reports only what it's for — **release
  dates that actually moved** (game-level or per-platform); rating drift and
  cover refreshes keep writing (and busting caches) without making noise.

## [0.9.5] — 2026-07-03

**YAML love** — every verb, alias, kwarg, segment, and reply lives once in
`config/pito/verbs.yml`; generic code executes it, guard suites keep it honest,
and adding a verb is an edit, not an engineering project.

### Added

- **Segment verbs** — every enhanced card is now its own verb, defined purely
  in `verbs.yml`: `at-a-glance` (`glance`, `overview`), `videos` (`vids`),
  `linked-game`, `similar` (`similars`), `linked-videos` (`linked-vids`),
  `channels` (`handles`), `breakdowns` (`lifetime`, `life`) — plus the
  two-word `linked game #vid` / `linked vids #game` forms where the noun names
  what you get. All served by one generic handler; byte-identical to the
  parent verbs' `only` forms.
- **`without <segments>`** on `show` and `analyze` — everything minus the
  named segments, alias-aware (`similars`), documented in `--help`, with the
  selector-conflict copy now naming all four selectors.
- **Options footers on show/analyze** — the first card states which segments
  `with` can add and `without` can drop, through one noun-agnostic 50-variant
  dictionary shared with the list surfaces (`pito.copy.options_footer.*`).
- **The palette now actually suggests arguments** — reply verbs offer their
  real options (columns, sort keys, metrics, the list's own row ids) and chat
  verbs their kwargs; two client gates that silently closed the palette are
  open.
- **Config-driven dispatch** — every verb (chat, slash, and hashtag-reply) is
  now declared once in `config/pito/verbs.yml`: aliases, kwargs and their
  resolution paths, segments, reply availability per message type, auth tiers,
  page sizes, and dispatch targets. A generic Router executes from the config
  through one uniform handler contract; the hand-written grammar tables,
  per-handler reply matrices, and if/else dispatchers are gone. A
  schema-integrity suite validates every key and reference (unknown keys are
  rejected with did-you-mean hints), a help-sync guard fails CI when help copy
  drifts from the config, and an add-a-verb proof demonstrates that a new verb
  defined purely in YAML parses, autosuggests, documents itself, and dispatches
  with zero engine changes.
- **Sharing is declaratively scoped** — `verbs.yml`'s `universal_reply:` block
  now says exactly where the universal reply verbs apply: `share`/`revoke`
  (alias `unshare`) carry `kinds: [system, enhanced]` — thinking, echo, error,
  and confirmation messages are never shareable — and a per-target `except:`
  list is available for finer opt-outs. Both keys are schema-validated
  (typos rejected with did-you-mean).
- **Capped lists state their totals** — "50 rows out of 233"-style lines (a
  50-variant dictionary) on every capped ls page and `next` batch.
- **The `#` palette lists every live reply handle** (scrollback order,
  uncapped — consumption keeps the set small).

- **Segment selection on `show` and `analyze`** — multi-message verbs now take
  `full` (everything), `with <segments>` (add to the default), and
  `only <segments>` (exactly the named). Bare `show` renders just the detail
  card; bare `analyze` just the plain-numbers card. Segments have dash-case
  names (`at-a-glance`, `similar`, `linked-videos`, `channels`, `numbers`,
  `breakdowns`, …), documented per verb in `--help`.
- **ls lists cap at 50 with a `next` verb** — `ls vids` / `ls games` /
  `ls channels` show the first 50 rows (the value lives in
  `config/pito/verbs.yml`, the seed of the config-driven dispatch system); a
  capped list says more rows exist, and `#<handle> next` appends the next
  batch as a fresh message with identical filters, sort, and columns.
- **Every message tells you what it can do** — a universal `#<handle> help`
  reply verb renders that message type's option page, and every live reply
  handle's meta line carries a dim `help` cue.
- **List footers describe their real options** — each list ends with which
  columns `with`/`without` can add or drop and which keys `sort` accepts,
  derived per surface (so `ls channels` no longer implies columns it lacks).
- **Chat argument palette** — chat verbs now autosuggest their arguments
  (segment names, nouns, subcommands, live game titles, …), and typing `#`
  lists the live reply handles in scrollback order.

### Changed

- Palette listings are alphabetical (slash commands, verb arguments, config
  keys); `show channel` gained its missing `--help` page; `analyze` joined the
  main `help` output; vid/game refs read `#id` across all help pages.

### Fixed

- **The mini status bar keeps one row** — the presence square and nickname no
  longer wrap apart on narrow panels.
- **Nightly IGDB sync no longer reports every game as updated** — the sync
  re-stamped each game's `updated_at` unconditionally (a bookkeeping timestamp
  and an as-is release-date rewrite), so the "checked 60, updated 60"
  notification fired with nothing actually changed. Bookkeeping now writes
  touch-free and release dates only persist when they differ; the notification
  counts genuine changes again.
- **Charts fit the 450px column again** — every braille plot (analyze charts,
  the game channels distribution, at-a-glance sparklines) shrinks from 45 to
  42 cells. Braille glyphs render from a scoped fallback face whose advance
  (≈10.25px at the 14px base) is 22% wider than the mono `1ch`, so 45-cell
  plots overflowed the locked two-column width by ~23px.

## [0.9.0] — 2026-07-02

**cache the cache** — a dedicated caching, code-optimization, and
request-rewriting release. Same product, a fraction of the requests.

### Added

- **Layered cache architecture** on top of the analytics primitives (L0):
  **L0.5** per-metric cell data (selection-free — any `with`/`without`
  combination composes from the same cached cells), **L1** rendered
  message fragments (handle chrome extracted to a serve-time meta slot, so
  hashtag retirement never invalidates a fragment), and **L2** whole-scrollback
  snapshots (a conversation reload is one cache read, uniform for 2 or
  100 messages).
- **Share pages cached** — the public `/share/:uuid` scrollback serves from a
  content-addressed SolidCache entry; revocation stays gated by the Share row.
- **IGDB search cache** — repeat sidebar searches answer instantly for a day;
  error envelopes are never cached.
- **`rake pito:bench`** — a strictly READONLY benchmark harness (in-process
  network kill switch + read-only DB session): replay/component/Copy/fold
  timings, cache-temperature inventory, and dry request-plan counters, with
  diffable JSON snapshots under `tmp/bench/`.
- **`CacheSweepJob`** (daily 04:00) — sweeps expired analytics cache/primitive
  rows and `api_requests` audit rows older than 90 days.
- **Automatic recovery after reauth** — the moment a dead YouTube grant is
  reauthenticated, PITO requeues every failed job and immediately re-runs the
  scheduled passes the flag had been skipping (channel + video sync per
  channel, stats, achievements) — no more waiting for the next nightly.

### Changed

- **The glance (`show …`) folds from the shared primitives** instead of firing
  ~10 dedicated YouTube requests every time: 2 requests cold, **zero warm**, at
  any level — and it now shares rows with `analyze` (the double-fetch is gone).
- **TTL policy in one place** (`Window#expires_at_for`): finalized periods
  (ended ≥ 1 week ago) stay frozen forever; **lifetime data holds 24h** (was
  hourly); live windows hold 4h. Retention rows joined the same policy (their
  hardcoded 1h TTL was a second policy point — removed).
- **Batched + parallel external requests**: per-video scalars fetch ≤200 videos
  per request via the Top-videos report; un-batchable per-video reports (daily,
  breakdowns — API has no video dimension there) fetch 4-wide concurrent; the
  IGDB nightly refresh bulk-fetches every awaited game in ⌈N/500⌉×2 requests
  (was 2×N).
- **Analyze finalize composes from per-metric stashes** — the last metric to
  land no longer re-aggregates every metric (which refetched likes and probed
  every report at the message window); repeat analyzes within the TTL make
  **zero** requests end-to-end.
- **Likes hearts** fold from the scalars primitive (were raw uncached HTTP).
- The `daily` report now carries `likes` (glance sparkline); pre-0.9.0 warm
  rows refetch once via `require_keys`.
- Copy-widget **"Copied!" feedback no longer reflows its host row** — it
  overlays the icon instead of occupying flex space (the footage-snippet
  layout-jump bug).

### Removed

- **`/compact`** — the placeholder command and its whole stack (handler, no-op
  job, confirmation branch, copy, grammar row, specs). The context bar stays.

## [0.8.5] — 2026-07-02

A broad follow-up to **analtics**: a full `show channel` surface, sharper `sync`
and `analyze` reply flows, named conversations, a faster/cleaner notifications
panel, a self-hosted typeface, and an exhaustive dispatcher-recognition spec net
that hardens every verb/keyword combination across the slash, hashtag, and chat
stacks. (Bespoke analytics view components close out the tag.)

### What PITO does that no one else does — not even Studio

As of this tag, the full set of things that exist here and nowhere else — not in
YouTube Studio, not in TubeBuddy, not in vidIQ:

- **Cross-channel game coverage** — `show game` shows how a game's coverage is
  distributed across _your_ channels (vids + views + lifetime watch-time) next to
  the top-5 channels it best fits. Nobody else has a cross-channel game view.
- **Games ↔ videos, explicitly linked** — `link` / `unlink`, never guessed from
  titles; the graph everything else runs on.
- **Per-platform release dates — PlayStation, Switch, Xbox, and Steam** — grouped
  by date with logos, countdowns that name the platform, and nightly re-syncs
  until a date is concrete.
- **Analytics at the game level** — avg % viewed, retention, and avg view duration
  aggregated across a game's linked vids (Studio: one video at a time).
- **Day-of-week heatmap** — computed from your daily views; the API has no such
  dimension.
- **Footage hours per game** — your recorded backlog on the time-to-beat bar.
- **Game price, tracked** — coins on the card; budget a slate before promising it.
- **A calendar that finds the gap** — `schedule … slate` across every channel.
- **Any message is a shareable link** — `share` mints a public URL to that exact
  reply, chart included.
- **Conversations are snapshots** — old conversations keep their numbers as they
  were.
- **Happily mobile** — the chatbox works on a phone.
- **Similar games + Shinies** — Voyage-powered recommendations and lifetime
  achievement badges, because this is a gaming tool that knows it.
- **And the whole thing is one chatbox** — terminal-style, keyboard-first; you
  type, it answers.

### Added

- **Shareable links are clickable + one-click copy** — the `share` reply now renders
  the public link as a real clickable link (opens in a new tab, action-styled) with
  a copy-to-clipboard icon right beside it, so you can open or grab it instantly.

- **`analyze` retention chart** — the `:enhanced` analyze card's audience-retention
  metric (lifetime, per-video) now renders as a real **area chart** — same reveal
  animation and shimmer as the Views chart — instead of a placeholder, filled by its
  own dedicated background request. Its caption is a distinct witty line reporting the
  average retention and how it benchmarks.

- **`analyze` day-of-week heatmap** — the `:enhanced` analyze card now leads with a
  **day-of-week heatmap**: seven equal-width, full-height braille bars (Mon→Sun),
  each tinted on the green→red health ramp by that weekday's average views over the
  channel's lifetime (busiest weekday green, quietest red), with the shared pito-blue
  shimmer swept over it. The caption calls out your busiest posting day. Works on
  vid, channel, and game scopes.

- **`analyze` comments chart** — comments moved from a plain scalar to a real **area
  chart** in the `:enhanced` card (last metric), on vid, channel, and game.

- **Per-platform release dates — PlayStation, Switch, Xbox, and Steam** — a game's
  upcoming release is now tracked **per platform** instead of as one blurry date.
  `show game` shows a release date per platform, grouped by date: platforms sharing
  a date collapse to one line with all their logos, and platforms with different
  dates each get their own line with their own logo (e.g. **PlayStation + Steam**
  on July 31, **Switch** in Q3). The release countdown now fires **one reminder per
  distinct date, naming which platform is releasing** ("… on PlayStation + Steam in
  3 days"). Xbox joins as a first-class platform (logo + grouping, catching Xbox One
  / Series X|S / 360). No other tool tracks per-platform release dates for a
  creator's slate. **Backfill:** existing games pick up per-platform dates on their
  next IGDB sync — to refresh everything now, run
  `Game.find_each { |g| GameIgdbSync.perform_later(g.id) }` from the console.

- **Missing-image placeholders you can click to sync** — every entity image
  (channel banner & avatar, video thumbnail, game cover — every size and every
  card) now falls back to a muted click-to-sync placeholder when nothing is
  attached, instead of a bare `?` or a "No cover" line. It's a rectangle for
  banners / thumbnails / covers, a circle for avatars, showing a centered
  **"No image." + sync** (auto-hidden on boxes too small to read, like tiny
  avatars). The **whole box is clickable**: one click types the exact sync
  command for that entity and runs it (a real Enter keypress) — so you go from
  "there's no art here" to fetching it in one tap. A new `Pito::ImageRender`
  service owns the image-or-placeholder decision, so no card hand-rolls it.
- **Direct `sync game #id` and `sync channel @handle`** — game sync used to be
  reply-only and `sync channel` only took the shift+tab scope. Now both work as
  direct id/handle commands (mirroring `show game #id` / `show channel @handle`),
  which is what the new image placeholders click to run. `sync channel @handle`
  scopes to that one channel (overriding the shift+tab scope); `sync vid #id`
  is unchanged.

- **`show game` channel coverage + recommendation** — the channel-matches card is now
  two columns: the left shows this game's coverage **distribution across your channels**
  (offset bars weighted by linked videos, views, and lifetime watch-time), the right shows the top-5 channel
  **recommendation** (avatar + fit score) — the same channels, side by side. The
  distribution streams in progressively (a no-data canvas until the numbers land);
  the recommendation renders instantly. No other tool shows cross-channel game coverage.

- **Auto-purge of unnamed conversations** — a nightly job deletes conversations
  that you never named (still on the default `Unnamed N` title) once they've had no
  activity for **30 days**; anything you actually titled — even a name that starts
  with "Unnamed" — is kept and only ever deleted by you. It deletes one at a time
  through the same path as the sidebar `dd` shortcut (no bulk lock), and the
  `/resume` sidebar now shows an ironic heads-up under "n rename · dd delete".

- **Image masters + on-demand variants** — the channel banner & avatar, video
  thumbnail, and game cover art now store the **original, unprocessed** source image
  as the master, with the display sizes derived as named ActiveStorage variants
  (banner 450×253 · avatar 120/60 · thumbnail 450×253 · cover 450w detail + 180×240
  strip — the strip is now 1:1 with its display, no browser downscale). Re-syncing a
  channel / vid / game fetches a fresh master; **`rake pito:images:regenerate`**
  re-derives every variant from the masters (run after a re-sync, or when sizes
  change — safe in the Docker CLI / production).

- **`analyze` fills metric-by-metric** — the `analyze` `:system` and `:enhanced`
  cards now render every metric cell up front in a loading state, then **fan out one
  dedicated background request per metric** (each its own YouTube call), swapping each
  chart / heart / bar / scalar in **independently** as it lands. A failing or
  empty metric shows its no-data placeholder without blocking the rest; the card's
  thinking block holds until **every** metric is in. (`:system` uses your shift+space
  period; `:enhanced` is lifetime.)

- **Progressive at-a-glance analytics** — the `show vid` / `show game` /
  `show channel` glance now renders **all metric cells up front in a loading
  state** (dotted-paper canvas + metric name + a small dots-loader), then **fans
  out one dedicated background job per metric**. Each metric makes its **own
  YouTube request** for just that metric (scalar + day-series) and **swaps its own
  cell in independently** the moment it lands — so a slow or failing metric never
  blocks the rest (a failed one shows a dash, the others still fill). The card's
  thinking block stays up until **every** metric has landed, then the whole message
  persists in its filled state. All glance metrics are **lifetime/all-time** (the
  intro copy now says so). A metric whose request **fails, is quota-limited, or
  comes back with no data** keeps its dotted-paper no-data canvas and shows **n/a**
  in place of a value — the others still fill, and that state persists on refresh.

- **Channel banner on `show channel`** — PITO now caches its own copy of the
  YouTube channel banner during sync: it fetches the **original 2560×1440** banner
  (the raw URL serves only a 512×288 default) and downscales it to 374×210 — the
  same 16:9 box as a video thumbnail (both 16:9, so nothing is cropped), served
  from our host, never hotlinked. On the `show channel` card the banner takes the
  top-left spot, and the **avatar always lives in the kv-table** (above the handle)
  as a small **120×120 variant** shown at 60px (a real ActiveStorage variant, not a
  CSS-scaled full image). A channel with **no banner** leaves the top-left spot
  empty (the avatar is never shown on the left). The banner and avatar are
  **re-saved on sync only when the image actually changed** (digest-gated), and the
  small avatar variant is derived from the attached avatar — so it shows even on a
  channel that hasn't re-synced since.
- **`show game` split into three reply-able cards** — the recommendations now
  arrive as separate `:enhanced` messages — **similar games**, **linked videos**
  (when any), and **channel matches** — in that order under the detail card, each
  with its own thinking block. Each is context-repliable: reply `show #<id>` on
  similar games → `show game`, on linked videos → `show vid` (plus `unlink #<id>`
  to unlink that video from the game), and `show @<handle>` on channels →
  `show channel`.
- **Thinking blocks on `sync` results** — every `sync` outcome (`sync channel`,
  `sync channel videos`, `sync vid`, `sync videos`, `sync game`) now shows a
  **thinking indicator** while it runs and resolves into a witty, shimmered intro
  line (50-variant `sync.intro` copy + a new `syncing` thinking dictionary) — so
  async results no longer pop in unannounced.
- **Analytics likes HEARTS** — the `analyze` `:system` grid renders the **Likes vs
  Dislikes** metric as braille **hearts** filled bottom→top to the lifetime
  approval score (likes/(likes+dislikes)%): vid/game shows a **subject heart**
  (red) beside the **channel-average heart** (purple); channel shows one. The
  hollow rim above the fill reads as the remaining dislikes. The hearts reuse the
  exact area-chart container chrome (so they flow identically in portrait and
  landscape), carry a thumbs-up/down legend, and a witty 50-variant caption.
- **Analytics area charts — Views, Watched Hours, Subs, Avg View Duration, and Avg Retention** — the `analyze`
  `:system` grid now shows **five** Studio-style **braille area charts** side-by-side at **channel / video / game**
  level, each a ~thumbnail-wide 16:9 widget with a **subscriber-aware red→green
  health gradient**, discrete tick values, a pito-blue shimmer with a distinct
  per-metric phase offset so the five never pulse in sync, its **own** bottom-up
  reveal animation (independent of the `/config` fx effect), and a witty caption.
  Views / Watched Hours / Subs captions carry a filled **trend triangle** (▲/▼/–)
  vs the prior window.
  **Avg View Duration** uses adaptive bucketing (daily ≤30 days, weekly 31–90, monthly
  > 90) with per-bucket Σ(estimated_minutes_watched×60)/Σ(views); ticks and caption
  > values show **M:SS**; health target is 2:00 (120 s). No trend triangle.
  > **Avg Retention** is always **lifetime** (the shift+space period window is
  > ignored); the x-axis shows video-position percentages (0%→100%) rather than day
  > indices; vid level = the video's own audience-retention curve; game/channel =
  > **views-weighted average** across linked/all videos fetched and cached per-video
  > in `AnalyticsPrimitive` (report: "retention"); caption shows **M:SS (XX.X%)**
  > plus a cyan "lifetime" reference token; health target is 50%. No trend triangle.
  > The five chart metrics are ordered first in the `:system` grid
  > (`views, watched_hours, subs, avg_view_duration, avg_viewed_pct`); remaining
  > scalars keep the `0`/`1` scaffold display until each is built.
- **Glance sparklines** — the `show vid` / `show game` / `show channel`
  `:enhanced` glance now renders a **2-row braille mini-series above the scalar**
  for its four time-series metrics (**views, watched hours, net subs, likes**),
  fetched as day-series alongside the period totals (new
  `Pito::Analytics::GlanceSeries`; `likes` added to the daily report). The scalars
  are unchanged; metrics with no series stay scalar-only. The sparkline is a flat
  **fg-default** line (no health gradient) under the shared pito-blue chart-viz
  shimmer, chart-width, with no ticks/legend/caption/axis — and an empty or
  all-zero series still floors a minimal baseline row so the cell always shows a
  line.
- **Analytics bar breakdowns** — the `analyze` grid renders share-of-audience
  metrics as braille **horizontal bar groups** (new
  `Pito::Analytics::Metric::BarChartComponent` + `Pito::Analytics::Breakdown`):
  **Subscribed** (subscribed vs not — `:system`) and **Devices**, **Geography**
  (top 5 countries), **Gender**, and **Age** (top 5 buckets) in `:enhanced`. Each
  is 1–5 group-centered bars (full braille fill in the bar's colour + the heart's
  dim "missing" remainder, a minimum sliver so tiny shares still show), on the
  same canvas/dotted-paper/reveal/pito-blue-shimmer as the area chart, with a
  legend (label + %) below. Shares aggregate from per-video dimension primitives
  (views-summed for subscribed/devices/geography; `viewerPercentage`-renormalised
  for gender/age) and are persisted so a `with`/`without` reply re-renders without
  re-fetching.
- **`show channel`** — a full channel surface: a `:system` detail card (with
  last-sync time and a trimmed linked-game card), an `:enhanced` repliable vids
  list, and an `:enhanced` channel analytics glance. Channels now carry a
  `description` synced from the YouTube snippet.
- **Named conversations** — `/new <name>` opens a titled conversation and
  `/resume <name>` jumps straight to it. A miss offers a clicky "create it"
  affordance plus up to five fuzzy-matched suggestions to resume instead.
- **`/rename`** — rename the current conversation from the chatbox.
- **`sync` targets specific vids** — `sync vid|vids|video|videos #id[,#id…]`
  syncs exactly those videos (ids win); bare `sync vids` obeys the shift+tab
  channel scope (mirroring `analyze`).
- **`show` replies route by card** — replying to a `:system` card runs `sync`
  for that entity; replying to an `:enhanced` glance runs `analyze` — for vids,
  games, and channels alike.
- **`analyze` as a reply everywhere** — reply `analyze` to a `list vids` /
  `list games` / `list channels` to analyze that whole listed scope, or to a
  `show vid` / `show game` / `show channel` card to analyze that single entity
  (with `--help` + autosuggest coverage).
- **`list games upcoming` splits in two** — a `:system` card of games releasing
  within 30 days and an `:enhanced` card of the later/TBA ones; always both, each
  with its own subject-token intro (and an ironic empty-state line when a bucket
  is empty).
- **Mobile-tappable chatbox hints** — `shift+tab` / `shift+space` / `m` are
  clickable on touch (simulate the keypress) instead of being swallowed by the
  chatbox.
- **`show first|last`** selectors — `show last game`, `show first rpg game`,
  `show last published vid`, `show last vid` (= last published), etc. resolve to
  the earliest/latest entity (games by release date, vids by publish date) within
  the shift+tab channel scope.
- **Contextual command showcase** — when the chatbox is empty and idle, it cycles
  conversation-aware command suggestions (comet-revealed), regenerated after every
  turn from that turn's real entities (real `#ids`, always-valid forms). Rule-based,
  no Voyage; pauses on focus/typing, clears on input.
- **`/authenticate`** is now an alias for `/login`; while logged out, the slash
  suggestions surface only `/login`, and the other verbs explain that login is
  required.
- **`/notifications`** is now the canonical notifications command (the one shown
  in the slash palette); **`/notifs`** remains as an alias.
- **`/logout`** gains **`/exit`** and **`/quit`** aliases.
- **`list … with <cols> sort by <col>`** combine cleanly, with `sort` / `sorted`
  / `order` / `ordered` (and an optional `by`) all accepted.
- **Game platforms** — `platform set` / `platform unset` add and remove a game's
  platforms.
- **Paginated notifications panel** — loads 50 at a time and fetches more as you
  scroll (or press ↓ at the bottom), with a shimmering-dot loader and a playful
  "end of the list" marker (a new reusable copy dictionary). Replaces the old
  load-everything panel.
- **Async conversation deletion** — `dd` in the /resume sidebar hands the
  (potentially slow) cascade to a background job while the row shows a
  shimmering-dots placeholder; the state is persisted, so reopening the sidebar
  mid-delete still shows the dots.
- **Chatbox history recall** — oh-my-zsh-style prefix recall: type a prefix and
  walk previous matching commands.
- **Self-hosted DejaVu Sans Mono** — the terminal typeface (plus a braille face)
  is now bundled and subset, replacing Iosevka; source-misaligned ASCII art fixed.
- **`vid` category column** in `list vids`.
- **Scrollback jump pills** — a long conversation now shows small, centered
  navigation pills above and below the scrollback telling you how many messages
  are off-screen (`N messages above` / `below`, from a 50-variant copy
  dictionary), each with a clickable yellow **`ctrl+home`** / **`ctrl+end`** token
  that jumps to the start / end. The pills appear only when there's something to
  scroll to, hide while the sidebar or command palette is open, and reuse the
  exact off-screen-counting the `/share` page already used (extracted into a
  reusable, specced `Pito::Conversation::ScrollbackCount` service).

### Changed

- **Retention on channel and game** — the `:enhanced` retention chart is no longer
  video-only. It now renders for channels and games too, computed by views-weighting
  each of the scope's videos' retention curves (a channel is its videos; a game is
  its linked videos across channels).

- **`analyze` averages come straight from YouTube** — the average-view-duration and
  average-percentage-viewed charts (and the at-a-glance average-view-duration
  sparkline) now **pull YouTube's own per-day averages** and views-weight them across
  a multi-video scope, instead of deriving them from watch-minutes ÷ views or the
  retention curve. The numbers now match YouTube Studio exactly rather than drifting.

- **Chart cells are framed** — every analytics chart (at-a-glance and `analyze`,
  incl. the empty no-data canvas) now has a dashed border in the graph-paper dot
  color, so the two side-by-side 450px columns read as distinct despite the small gap.

- **`list games` drops the `release date` and `year` columns** — with releases now
  tracked per platform, a single sortable release/year column no longer makes sense.
  Both are gone from the `list games` table, the `with`/`without` column options, and
  their sort tokens (`list --help` updated). The `list released | upcoming | tba`
  status filter is unchanged.

- **Shimmer system overhaul** — one consistent set of shimmers, all sharing a single
  diagonal angle (135°) and speed (5s) as Tailwind tokens, all 20-step staggered:
  - **action** (pito-blue + purple) is now the _only_ clickable shimmer — keys, table
    links, clickable tokens, `/resume` suggestions, `#id` links, shift+r.
  - **subject** and **reference** (decorative identifiers) read as normal foreground
    text with an orange→yellow sheen.
  - **network** activity (thinking block, IGDB search/import, notification "load more")
    shares one inverted shimmer (purple + pito-blue).
  - all **charts + score bar + time-to-beat** share one `--chart-shimmer` (pito-blue).
  - **`#reply` handles** and the **notification count** are now plain muted text (the
    reply action lives on shift+r; open notifications with ctrl+/).
  - achievement/shinies badges keep their per-tier colours but use the global speed/angle.
- **Context bar** — no longer shimmers. It keeps its green→red gradient and now counts
  only distinct backend messages (`:system`/`:enhanced`/`:confirmation` — follow-up
  re-renders don't add); each increment lights an **orange "lit-fuse" comet** that grows
  the fill from the old position to the new one, then settles.
- **`/themes`: click or tap to apply** — clicking (or tapping, on mobile) a theme in
  the themes sidebar now applies it immediately, the same as pressing Enter on it. The
  live preview stays desktop-only via the ↑/↓ keys.
- **Wider detail layout (450px columns)** — `show game` / `show channel` / `show vid`
  now use two **450px** columns (left media + right content), and the conversation
  column is sized to fit them exactly (964px on desktop). The banner / thumbnail /
  cover boxes render at their native 450px variant size (no more browser downscale).
  The `list`/recommendation **cover strips** and **channel matches** show the **top 5**
  (by score) on one row, with a tightened gap so they fit the narrower column.
- **Single-line chatbox** — the chatbox is shorter, with the textarea vertically
  centered; the `c to chat` hint (and the shift+tab / shift+space cyclers) now sit
  inline, right-aligned on the textarea's line, with symmetric left/right padding.
  The conversation name moved out of the chatbox to above the context bar (left of
  the `xx%`), shown only when the conversation is named.
- **Rake tasks drop the `tools` namespace** — every `pito:tools:*` task is now
  `pito:*` (e.g. `pito:totp`, `pito:clean`, `pito:games:*`, `pito:images:*`).
- **Normal text cursor in every input** — the chatbox, the ctrl+k command-palette
  search, the sidebar search boxes, and the conversation-rename field now use the
  browser's normal native caret. The bespoke JS caret/cursor machinery was already
  retired; the interim CSS block caret (`caret-shape: block`) is now removed too —
  one ordinary blinking caret everywhere.

- **`show game` channel matches show just the @handle** — each matched channel now
  shows its avatar, clickable **@handle**, and score bar, without the channel
  name/title line (the @handle identifies it). The `list channels` view still shows
  the title.

- **Inline chat suggestions removed; palettes stay** — the inline free-chat
  typeahead "ghost" (and the `tab` completion shortcut + its chatbox hint) is gone.
  Typing a natural-language message no longer ghost-completes verbs or arguments.
  The `/slash` command palette and the `#hashtag` reply-verb palette (arrow-key
  navigable, Enter to accept) are unchanged and remain the only suggestion
  surfaces. `tab` no longer completes anything (it still stays inside the chatbox
  rather than moving focus).
- **shift+tab / shift+space are contextual now** — the channel cycler (shift+tab)
  shows only while you're typing `list vids`/`list games`, and the period cycler
  (shift+space) only while typing `analyze`; otherwise the row shows `c to chat`
  (when unfocused) or nothing. The keystrokes are live only when their
  hint is showing, and the channel/period are **sent only when their cycler is
  visible** — so no other verb picks up a stale channel or period (`list games`
  with `@all` = all games; with `@handle` = games having a vid on that channel;
  `list vids @handle` = that channel's vids). The meta row is a single row on
  desktop and mobile with the middot separators removed.
- **`c to chat` hint** — the chatbox focus shortcut is **`c`** (yellow, clickable)
  and the caption reads **`c to chat`** (new `Pito::Copy` caption, replacing the old
  `chat` label) and shows on the **start screen, 404, `/chat`, and `/share`**. The
  meta line is a **single row on desktop and mobile** again (no more stacking). On
  `/chat` it still swaps with the shift+tab/shift+space cyclers by focus; the other
  surfaces show it always.
- **Native block caret replaces the custom JS cursor** — the bespoke
  caret/comet-trail JavaScript (mirror-based pixel math, ghost trail, showcase
  comet) is gone everywhere — the chatbox textarea **and every search/rename input,
  including the ctrl+k command palette and the sidebar IGDB search**; the browser's
  native caret is styled as a phasing block via CSS (`caret-shape: block`). Idle
  conversation hints now rotate through the input's `placeholder` every ~10s. This
  removes a class of caret bugs (the caret dropping 1–2px on hover, sitting under
  the placeholder on reload, and the broken caret on the `/share` page).
- **Analyze `:enhanced` is always lifetime** — the enhanced analyze card no longer
  follows the shift+space period (its audience-composition bars + retention are
  all lifetime anyway), so it shows the all-time picture and its intro copy says so
  (a dedicated 50-variant lifetime dictionary). The `:system` card keeps the
  shift+space period. (Sets up a 1-day-TTL cache for the enhanced card in 0.9.0.)
- **Notification badge** in the mini-status is a compact cyan-shimmer **`N*`**
  (was `N notifs`) and is **clickable** — click it (or `ctrl+/`) to toggle the
  notifications sidebar. The /resume sidebar shortcut labels are trimmed to
  `n rename` / `dd delete`.
- **`/config` credentials** dual-route to the right provider and mask secrets at
  the source.
- **Slash palette** triggers argument completion on a trailing space and sends on
  Enter at the verb stage.
- **`list channels`** is ordered by most-recently-published vid.
- **No more entity guessing in free chat** — `show`, `rm`/`delete`, and `list` no
  longer silently assume "game" when the second word isn't a recognised entity. In
  free chat the second token _is_ the entity: a bare id (`show 123`, `rm 5`), a
  bare verb (`show`, `rm`), or an unknown word (`show foo`, `list foobar`) now gets
  a clear "I don't get it" nudge instead of a surprise game lookup. Explicit nouns
  (`show game 12`, `rm vid 5`, `list vids`) and `list`'s filter shortcuts
  (`list rpg`, `list upcoming`) are unchanged; reply (`#<handle>`) flows keep their
  context. `analyze` already worked this way (it suggests options).
- **Mini-status shows the build** — the nickname now carries a muted suffix:
  `gmrdad82@<tag>` on a Docker production image, `gmrdad82@localhost` (or your
  configured host) in development.
- **Analytics widgets own their reveal** — charts/bars animate with their own
  choreography (the Views bottom-up wipe, the score/TTB `=` left→right comet
  wipe); they always play. Message prose renders instantly (see Removed).
- **Mobile chatbox meta line** stacks each shortcut chip key-over-caption (2 rows
  per pair) with an ellipsised conversation name, instead of overflowing.
- **PITO logo broken-neon reveal** — on the start screen and the 404 page the
  block-logo flickers in glyph-by-glyph at random, like a faulty neon sign warming
  up, then settles (with the odd rare flicker). Its own animation, always plays.

### Removed

- **Internal dead-code sweep** — removed a batch of unreferenced code with no
  user-facing effect: several orphaned jobs/services/components (`VideoPublish`,
  `SyncVideoJob`, the unused recommendation-scoring and local-search-query objects,
  the pre-real-analytics `Channel` mock cluster, the `Pito::Transitions` module, and
  more), a fully-orphaned copy dictionary, a never-rendered `/config` help line,
  dead CSS rules, the vendored `xterm.js` bundle + its addons, and a second pass
  of never-called helper modules (safe-iteration, yes/no, slug, git-revision,
  formatter, and game message-builder utilities). Behaviour is unchanged.

- **Unwired auth scaffolding** — removed never-called auth helpers: the
  session-token-rotation concern (written for in-app TOTP-enroll / backup-code
  flows that never shipped — enrollment stays the `pito:totp` rake task), the
  exponential login-backoff calculator (superseded by the live
  10-failures-per-5-minutes throttle), the duplicate TOTP-enroller service, and
  the session cookie's unused re-verify helper, and the QR-code gems
  (`rqrcode` + its two dependencies) that only the never-built in-app
  enrollment view would have used. Login, throttle, and logout are untouched.

- **Message & theme-change reveal animations** — the per-glyph text reveals
  (typewriter, scramble, and the word-jump comet), plus the theme-change diff
  morph, are gone. Chat messages and theme switches now render **instantly**. The
  widget/chrome reveals stay and always play: chart sweeps (area/bar/metric),
  the context-bar dynamite fuse, the PITO logo flicker, the desktop sidebar
  slide, and shimmers — none of them respect the OS "reduce motion" setting any
  more, they always animate.
- **`/config motion` and `/config fx`** — with the content reveals gone, the
  animation on/off toggle and the reveal-style picker no longer have anything to
  configure. Both commands (and their `--help`, autosuggest, grammar, and the
  stored `fx_enabled` / `fx_effect` settings) are removed; the stored rows are
  deleted by a migration. **`/config sound` is unchanged.**

### Changed

- **Detail cards show Stats and Shinies as aligned rows** — on `show channel` /
  `show vid` / `show game`, the Stats line (`365 Views · 17👍 · 2💬`) and the Shinies
  badges are now key/value rows (label on the left, value on the right) instead of
  stacked headings; the Shinies badges wrap freely in their column.

- **Analytics chart columns keep a clean gap** — the at-a-glance, `analyze`, and
  per-game channel-distribution chart panels now each fill exactly one 450px column,
  so the two columns no longer touch or overlap. The channel recommendation column
  stays panel-free.

- **Share pages are simpler and unfold with one key** — a public `/share/:uuid` page
  is now a minimal read-only view: no auth mini-status, no scroll-nav, no command
  palette. The reduced chatbox is prefilled with **unfold**; press **`c`** to focus
  it, then **Enter** opens the full conversation (the hint swaps "c to chat" →
  "Enter to unfold", and the Enter affordance is a real link so it works without JS).
  Shared messages also no longer show their reply `#hashtag` (they're read-only).

- **Charts sit on a surface panel, not a dashed frame** — the at-a-glance and
  `analyze` metric cells now lift onto a surface background (chart + caption
  together) instead of the dashed border.

- **Copy affordance shimmers in the action colour** — the copy icon (share link +
  footage snippet) now uses the shared copy widget with the pito-blue↔purple action
  shimmer instead of a flat cyan, via one core component so both stay in sync.

- **Replies no longer elevate a message's background** — the "this was just changed
  by your reply" surface lift (`payload[:surface]`) was removed. A message keeps the
  background it was rendered with; follow-up replies don't re-tint the original.

- **Sharp images on phones and hiDPI screens (@2×)** — every image variant now
  renders at twice its on-screen size (game covers 900×1200, similar-strip
  cards 360×480, banners and video thumbnails 900×506, avatars 240/120/70),
  so retina displays — every phone — get crisp art instead of a soft 1×
  upscale. Channel avatars also fix a real bug: the roster sync fetched
  YouTube's **88×88** `default` thumbnail as the master; it now takes the
  800×800 `high` size. Masters were already large elsewhere (IGDB `t_1080p`
  covers, 2560×1440 banner originals, `maxres` thumbnails). Variants
  regenerate lazily on first view — no migration, no backfill; a `sync
channels` after deploy refreshes the avatar masters.

- **Awaited games refresh nightly, until the date is real** — the nightly IGDB
  pass no longer skips a game synced within the last 7 days: any game still
  awaited re-syncs every night, and every sync rewrites the release dates when
  IGDB changed them — so a slipped date or a newly-dated platform lands by
  morning. "Awaited" means no **fixed clear date** yet: TBA, a future date, or
  a bare year/quarter/month (a "Q3" game keeps refreshing after July 1 — as
  release approaches it will get a concrete day, and only a day-precision date
  in the past settles it), on the game or **on any platform**. A title already
  out on one platform keeps refreshing while another platform's date is open;
  only fully-released games rest.

- **All help copy flows through the copy engine** — the `--help` man-page trees
  (chat verbs, hashtag targets, share verbs) were the last strings read with raw
  `I18n.t`; `Pito::Copy` gained a Hash-aware `subtree` and a soft-miss
  `render_soft` API (both specced) and the help builders now use them, so every
  user-facing string is served by `Pito::Copy`. The trees also moved out of the
  dictionary namespace into their own (`pito.chat_help.*` / `pito.hashtag_help.*`
  / `pito.share_help.*`, in `config/locales/pito/help/`), so the copy audit now
  counts only real 1-or-50 dictionary keys (660 → 367). No visible change.

- **Internal refactors from the code-quality audit** — no visible change: the
  three detail cards (channel / vid / game) now share one two-column card shell
  plus shared sync-stamp and top-Shinies helpers instead of three hand-rolled
  copies; the system message's data grid is one component instead of a
  triplicated template block; the `Pito::Game` helper namespace was renamed
  `Pito::Games` so it can no longer be confused with the `Game` record; analyze
  markers are symbolized once at the read boundary; and a handful of duplicate
  copy variants were replaced with fresh lines (the 1-or-50 pools stay at 50).

### Fixed

- **Footage snippet command is readable again** — the `footage` command block was
  being shrunk to ~40% (an ASCII-fit scale meant for wide art) and gained a
  horizontal scrollbar. It now renders full-size and wraps to fit, readable on
  mobile too.

- **Thinking ASCII + scroll-nav polish** — the resolved thinking face (`( •_•)>⌐■-■`)
  now uses the same dim colour as its "…for 1.06s" text; the bottom scroll-nav pill
  drops its bottom border to match the top pill.

- **Unresolved messages can't be shared** — the `share` reply is now offered (and
  accepted) only once a message has finished loading (its thinking indicator
  resolved). Sharing an in-flight message (e.g. an `analyze` card mid-render) is
  refused with a clear message, and the reply menu hides `share` until it's ready.

- **Chart health colour is consistent across metrics** — on a small channel, the
  Watched-hours and Subs area charts rendered green from the baseline up (while
  Views, avg-view-duration and avg-%-viewed showed the expected red baseline). Their
  daily targets are fractional (< 1), and the plot's `1.0` y-scale floor was dragging
  the green anchor down to the baseline. The gradient anchor now uses the target's
  own scale, so an empty/under-target chart reads red at the baseline for every metric.

- **`analyze` subscribers no longer read zero** — the daily analytics query wasn't
  requesting subscriber gains/losses, so the subs chart and net-subs total could
  read 0; the daily query now pulls them and the subs numbers are correct.

- **At-a-glance avg view duration comes from YouTube, sparkline included** — the
  glance sparkline for avg view duration was still derived from watch-minutes ÷
  views per day (a rounded estimate that could disagree with the number right
  beside it, badly on low-view days). It now pulls YouTube's own per-day
  `averageViewDuration` — matching the scalar and the `analyze` chart. A channel
  or vid reads YouTube's value directly; a game extrapolates it from its linked
  vids (views-weighted).

- **Game likes show one heart, not two** — the `analyze` likes for a game showed both
  a vids heart and a channel heart. A game spans channels, so the channel heart was
  meaningless; a game now shows a single heart from its linked videos. (Channel shows
  one channel heart; a video still shows two — its own plus its channel's.)

- **Conversation scrollbar is clearly visible** — the scrollback's edge-fade
  gradient was masking the scrollbar itself; the fade was removed from the
  conversation scrollback so the slim themed scrollbar is fully visible.

- **`footage snippet` command is readable** — the copyable shell one-liner was
  rendering at the tiny browser "monospace" default; it's now pinned to the 14px
  base, with a copy icon replacing the "Copy" text.

- **Release countdown no longer fires a month early** — a game with a concrete
  date on one platform and a quarter (e.g. "Q3") on another used to store the
  quarter's _start_ as its release date, so the countdown could announce "in 0 days"
  weeks before the real launch. Countdowns now come from the per-platform dates and
  only fire for **day-precision** releases — never counting down to a quarter or a
  year.

- **Analytics grids are always two columns** — the `analyze` message and every
  at-a-glance grid (show vid / game / channel) now lay out as a fixed 2×450px grid on
  desktop (stacked on mobile), so the braille charts sit side by side instead of
  collapsing to a single full-width stack. Every glance metric (including net subs at
  +0/-0) now carries a sparkline with a baseline floor, and a pending metric's loading
  comet rides in the caption row rather than floating over the chart canvas.
- **Less shimmer, more signal** — only actionable, thinking, network, and subject text
  shimmers now. Channel `@handles`, video/game `#ids`, scope chips, and table column
  headings are plain text; the subject shimmer is a single orange band and the (now
  reserved) reference shimmer a single yellow band.
- **Footage value never hides behind a bracket** — on the time-to-beat bar the inline
  footage value is offset past its tick (left or right of the pillar by where it sits),
  so a `0h` value at the far-left no longer overlaps the `[`.
- **Channel recommendation rows line up** — in `show game` the right-column avatars now
  match the left column's bars row-for-row: each tiny avatar is a 1px-ringed circle
  sized to one bar's height (its `:xs` variant regenerated to match).
- **Context bar meets the chatbox** — the conversation context meter now sits flush
  against the chatbox with no gap.
- **Chatbox lines up with the messages** — the chatbox / slash palette left border now
  aligns with the scrollback messages' left border on desktop (a residual column
  padding had pushed it 5px to the right).
- **Scroll-nav pills are created/removed, not shown/hidden** — the top/bottom "N more
  above/below" pills are now added to and removed from the DOM as you scroll (a stale
  `hidden`-class rule could never actually hide them, so the bottom pill lingered at the
  very bottom). They read correctly too: right singular/plural noun and verb ("1 more
  message remains", "3 more messages remain"), both pills gone at the extremes and on a
  short all-visible conversation, and the bottom pill sits flush against the context bar.
- **Scroll-nav pills breathe** — a little more horizontal padding on both pills.
- **Chatbox padding is tighter and even** — less left/right padding, and the gap from the
  left edge to the text now matches the gap on the right (the accent bar + gap had made
  the left side wider).
- **Cleaner game-import messages** — importing a game now shows a single thinking block
  (leftover ones from a previous version's extra messages are gone). The status message
  reads _"<game> is importing…"_ (present tense, no `#id`) with the timestamp on the same
  row as the copy; the done message also puts its timestamp inline, its `#id` is now
  **clickable** (opens the game via `show game #id`), and the redundant "Type `show game`
  to see it in full" line was removed.
- **Anniversary / GOTY editions are importable** — IGDB tags some standalone releases
  (e.g. _Rayman: 30th Anniversary Edition_) as "bundles", which the game search filtered
  out. Bundle rows whose name says **GOTY / Game of the Year / Anniversary** now pass the
  filter alongside true combo bundles, so you can import them.
- **Footage value is readable on the time-to-beat bar** — the generic footage tick
  color was bleeding onto the inline value chip (fg-on-fg = invisible); the chip now
  keeps its inverted, legible colors.
- **Score value sits tight to the pillar** — the inline score-bar value chip is
  nudged 2px toward its marker.
- **No gap above the score bar** — removed a stale top margin (left over from when the
  score floated above the bar) in `show game` and the similar-games cards.
- **Conversation autocomplete** — the `:conversations` slot (used by reply/resume
  completion) resolves again; a new `Pito::Conversation` namespace had shadowed the
  top-level `::Conversation` model in the grammar resolver.
- **Channel banner refreshes on `sync channels`** — the banner (and avatar) were
  only fetched on OAuth connect, so a synced-but-not-reconnected channel never got
  one. Sync now refreshes both, digest-gated (no work when the image is unchanged).
- **Conversation column is centered on desktop** — the scrollback + chatbox now sit
  in a fixed-width, centered column (sized to fit a 6-cover message row) on wider
  screens; mobile stays full-width.
- **Score bar reads at the extremes** — the marker no longer clips off the track at
  0 or 100 (its position is clamped to 1–99 while the shown number stays the real
  score), and the score value now sits inline on the bar beside the marker (left for
  low scores, right for high) instead of floating above with a ▼.
- **Footage shows on the time-to-beat bar** — the footage value renders inline on
  the bar (**`0h`** when there's none — footage is never shown as a dash).
- **Resolved thinking blocks get a glyph** — a small random ASCII flourish marks a
  finished "thought for …" where the spinner was.
- **Fainter chart paper for hearts & bars** — the dotted background grid behind the
  heart and bar charts is lighter so the data stands out.
- **Full bars no longer overflow** — a 100% horizontal bar leaves a cell of
  headroom instead of spilling past the chart edge.
- **Readable chart axis labels** — Y-tick value chips paint over the braille in the
  message's own background colour with a hair of padding.
- **Tiny values still show on sparklines** — any non-zero point now renders at least
  the smallest braille bump instead of reading as a flat line.
- **Channel card polish** — the 'Avatar' label is vertically centered to the avatar,
  and the @handle is a clickable token that runs `show channel @handle` on click
  (same affordance as the #id tokens in show vid/game).
- **Visible conversation scrollbar** — the scrollback shows a thin, theme-colored
  scrollbar instead of hiding it.

- **Shiny badges fit three-up on mobile** — the compact achievement badges on the
  `show channel` / `show vid` / `show game` cards were locked to an 11rem min-width
  (only two fit per row). The compact form now has a **fixed slim width** and
  **truncates** (ellipsis) when a face is too long, so **three fit per row on
  mobile**. The shinies-command badges (the extended form, with dates) are
  unchanged.
- **`share` links use the host you're actually on** — the minted `/share/:uuid`
  URL now uses the request origin (scheme + host + port, e.g.
  `https://dev.pitomd.com`) instead of the static configured host (which read as
  `http://localhost:3027` behind a tunnel). Threaded from the request through the
  async dispatch job.
- **Bare `show channel` reads as a channel, not a game** — `show channel` with no
  `@handle` (and no channel scope) now asks _which channel_ instead of falling
  through to the game picker; with a shift+tab channel scope set, it shows that
  channel directly.
- **`share` is hidden on confirmation prompts** — the reply menu on an ephemeral
  confirm/cancel message (e.g. a delete confirmation) no longer offers
  `share`/`revoke`/`unshare`; sharing a throwaway prompt made no sense.
- **Owner-set game platforms survive an IGDB re-sync** (no longer overwritten).
- **`/connect`** no longer shows a no-handle confirmation when already connected.
- **Channel avatar filenames are channel-unique** so the CDN can't serve a stale
  cached image across channels.
- **Follow-up parity** — delete/publish aliases, implicit `price <id> <amount>`,
  footage reply parity, and repliable publish/unlist/schedule on a video card,
  with the schedule id-less reply bug fixed.
- **Chat-verb suggestions no longer crash** on a bare complete verb — typing
  `list` / `ls` (or any verb) used to raise "negative array size" and drop the
  suggestion; fixed.
- **Targeted sync copy** — syncing a specific vid now reads `Sync #25?` /
  `Syncing #25 from YouTube…` instead of the misleading `#25 vids`.
- **Clearing the chatbox now persists** — emptying a saved draft (backspace to
  blank) is saved to the conversation, so a cleared chatbox no longer reappears
  with stale text after a refresh.

### Reliability

- **Exhaustive dispatcher-recognition specs** — a fast, DB-free spec net asserts
  the system's understanding of every verb × every keyword combination (with and
  without args, plus unknown inputs) across the slash, hashtag, and chat stacks.

## [0.8.0] — 2026-06-26

The **analtics** release — a chat-first `analyze` verb over the YouTube Analytics
API: per-video primitives cached (completed periods frozen forever), aggregated
across any scope, and rendered as metrics you refine with `with` / `without`.

### Added

- **`analyze` verb** (synonyms `analytics`, `stats`) — both as a chat verb
  (man-style `--help` + autosuggest) and via a `#<handle>` reply. Targets
  channels, vids, or games (id lists + synonyms accepted); scope resolves from the
  shift+tab channel filter and runs over the shift+space period. Each run fans out
  into atomic per-video / per-channel requests.
- **Analytics primitives store + completed-period freeze.** Per-video raw reports
  are cached in Postgres keyed by `(subject, report, date-range)` —
  entity-agnostic, so a video fetched for one scope warms every later scope that
  shares it (a channel analysis warms a later game analysis, no extra YouTube
  calls). A period whose end-date is ≥ 7 days past is **frozen permanently**
  (YouTube finalizes metrics in ~2–3 days); live periods carry a 1h TTL.
- **Two messages per analyze — `:system` + `:enhanced`** — each its own 50-variant
  copy dictionary. Every ordered metric renders as a "data-pulled" scaffold cell
  through one generic component (bespoke per-metric components come in a later
  pass). The per-message thinking indicator spans the message's full fan-out.
- **Refine with `with` / `without`.** Chat `analyze … with X,Y` / `without X,Y`
  whitelists or excludes metrics; replying `with` / `without` to an analyze message
  **mutates it in place** (re-rendered from the persisted scaffold, no re-fetch),
  while replying to a `show vid` / `show game` analytics glance emits a fresh
  analyze pair.
- **`show vid` / `show game` analytics glance is repliable** and now renders
  through the shared analytics component, with a witty nudge toward `analyze`.
- **ASCII art fits narrow screens.** A scale-to-fit controller uniformly shrinks
  the start-screen logo and in-message art (e.g. `/connect`) to fit mobile widths
  — alignment preserved, still live themed text — with desktop untouched.
- **`link` accepts multiple vids in one chat command** (`link game 1 with vid
15,14`), matching the reply path.

### Changed

- **"Comms" → "Comments" everywhere user-facing**, pluralized (1 comment / N
  comments). `comms` is still accepted as an input alias (with/without + columns).
- **IGDB import sidebar** renders at the single 14px base size (no font-size drift).

### Fixed

- **Shinies pluralize at a count of 1** — "1 Like" / "1 Sub" / "1 View" /
  "1 Comment", not "1 Likes" — across every metric.
- **Compact counts round down, never up** (`2,259` → `2.2K`), so a displayed count
  never overstates the real number.
- **A new `:system` / `:confirmation` message retires all prior live `#<handle>`
  replies** uniformly — typed verbs and replies-that-append alike — so stale reply
  affordances don't linger. Repeatable verbs (link/unlink) and in-place mutations
  are exempt.

## [0.7.6] — 2026-06-25

The **golden tape** release — the README now _moves_, and game prices read as coins.

### Added

- **CLI casts in the README** (recorded with [VHS](https://github.com/charmbracelet/vhs),
  themed in PITO's own synthwave palette):
  - **Operating PITO** — `pito --help` → `version` → `logs` → `rake` → `backup`, live.
  - **Install** — `curl | sh` showing the version picker → fetch (the "one line" proof).
  - **`pito update`** — the interactive stable/edge version picker switching the stack.
- **`Pito::Coin` — price as coin tiers.** Game prices now read at a glance as
  spinning gold coins instead of a bare `€`: 1 coin (≤ €9.99, budget) up to 5
  (> €79.99, premium/collector), thresholds at `9.99 / 29.99 / 59.99 / 79.99`.
  Price has three meanings: **unset** (`nil`) renders `—`, an **explicit 0** renders
  a Mario-style **star** + `0.00` (deliberately free — "genuine value", its own state,
  settable via `price set <id> 0`), and **> 0** renders the coins + the number
  (`🪙🪙🪙 59.99`). `Pito::Coin` owns the tier; `Pito::Formatter::Price` owns the number
  and the nil-vs-0 distinction (`unpriced?` / `free?`); `Pito::Games::PriceGlyphs`
  renders. Shows in the game list Price column, the game detail card (`:system`), and
  the linked-game card (`show vid` `:enhanced`).
- **`price` verb in `shift+r` replies.** Reply to a `list games` message with
  `#<handle> price set <id> <amount>` (or `price set <id> 0` for free) — previously
  only `show game` replies could set price.
- **Linked games in `list vids with games`.** The Game column now shows
  `#<id> <title>`, with `#<id>` a clickable cyan shimmer token (like the vid `#` id)
  that opens `show game #<id>`.

### Fixed

- **A not-found reply no longer consumes the `#<handle>`.** Replying to a
  `list games` / `list vids` / a `show game` linked-vids `:enhanced` list with a bad
  id (`#<handle> show 999`) returned the friendly "Don't have 999." but silently
  consumed the source's reply handle, so you couldn't retry without repeating the
  whole command. The not-found now keeps the list repliable (`Chat::Result::Ok` gained
  a `consume:` flag, set `false` for not-founds and forwarded by `ChatResultAdapter`).

## [0.7.5] — 2026-06-24

The **papercuts** release — chat/slash autosuggest + reply-shortcut fixes.

### Fixed

- **`/config` now submits cleanly.** The slash palette kept offering credential
  keys even while you typed a value or after you'd supplied them all, so Enter
  re-selected a key instead of sending. It now suggests nothing while you type a
  value and excludes keys already set — once they're all in, the palette closes and
  Enter submits. (No more dummy token to dismiss it.)
- **`sync` autosuggest.** Typing `sync channels ` now ghost-suggests `with`, then
  `with ` suggests `vids` — matching how `list … with` already completes.
- **`shift+r` (reply) works without focusing the chatbox first.** It's a global
  shortcut again: when the box isn't focused (and you're not typing in another
  field), `shift+r` focuses it and starts the reply.
- **`import` help is no longer truncated.** The hint read `import game <title>`, and
  `<title>` was parsed as an HTML tag — eating the rest of the line. Now `[title]`.

## [0.7.4] — 2026-06-24

The **safety-net & self-service** release: hands-off restorable backups, version
channels you pick at install/update time, and `pito` as a real PATH command.

### Added

- **Version channels (stable / edge).** Install and `pito update` are now
  interactive — pick a **stable** release (image tag _and_ CLI/scripts pinned to the
  same `vX.Y.Z` git tag, fully reproducible) or **edge** (`:latest` image + CLI from
  `main`). Available releases are listed live from the GitHub API. Non-interactive
  flags: `--version vX.Y.Z` / `--edge`. `.env` records `PITO_TAG` + `PITO_REF`.
- **`pito --version`** — shows the running version + channel (e.g.
  `pito 0.7.3 (stable)`), read from the image's OCI labels + `.env`.
- **Scheduled backups.** `pito backup-schedule` installs a daily systemd timer
  (`pito-backup.timer`, 03:00) that runs `pito backup` and self-prunes to the
  newest **7** — rolling, hands-off backups on the host. Also offered during
  install. Retention + location tune via `PITO_BACKUP_KEEP` / `PITO_BACKUP_DIR`.
- **`pito restore <dir>`** — restore a backup over the live stack (DB + assets),
  with a confirmation prompt (it's destructive) and a service restart after.
- **`pito backup --list`** — list existing backups with their artifact sizes.
- **`pito` on your `PATH`.** The installer now symlinks the CLI to
  `/usr/local/bin/pito`, so it runs as a bare `pito` from anywhere (the CLI
  resolves the symlink back to its install dir). `pito link` / `--link-only`
  (re)adds it, `pito update` keeps it current; `./pito` from the install dir
  still works if the symlink step is skipped.

### Changed

- **`pito backup` now prunes** to the newest `PITO_BACKUP_KEEP` (default 7) after
  each run, and honors `PITO_BACKUP_DIR`. The asset archive already captured
  rendered variants (same disk root); that's now documented.
- **README tour thumbnail** — the hero now uses the real "Inception Wednesday"
  tour-video thumbnail, pre-sized to its display width (no browser downscaling).

## [0.7.3] — 2026-06-24

The **less-is-more** release. The published image goes on a serious diet —
**870 MB → 365 MB (−58 %)** — without giving up a single feature, backups move out
of the container onto the host where they actually survive, and the installer
finally finishes the job (services enabled, tunnel running) on its own.

### Added

- **`pito backup`** — a host-side, durable backup. Writes `./backups/<timestamp>/`
  on the host: `database.sql.gz` (via `pg_dump` run inside the Postgres container —
  version-matched, pgvector embeddings included) and `active_storage.tar.gz` (your
  avatars/thumbnails/covers). Restore is a documented one-liner. Replaces the old
  in-container task, which quietly wrote backups _inside_ the ephemeral web
  container — i.e. straight into the void on the next recreate.
- **Hands-off self-host.** The installer now **enables + starts** the `pito` systemd
  service itself (no more "here's the command to run"), and **configures + runs
  cloudflared as a service** — tunnel config lands in `~/.cloudflared/config.yml`,
  an existing tunnel is reused, and the tunnel comes up on boot with no manual
  `cloudflared tunnel run`. Re-running the installer is idempotent: it keeps your
  master key, Postgres volume (channels/videos/games/`/config` keys), and TOTP.
  `pito update` is systemd-aware too — it pulls, restarts via the service (`sudo
systemctl restart pito`) so the unit stays the owner, and prunes the old image.
- **Dev tabs are unmistakable.** In development the favicon turns **red** and a
  full-width **DEVELOPMENT** banner pins to the bottom (label from `Pito::Copy`), so
  a dev tab is never confused for production.

### Changed

- **Image rebuilt on Alpine/musl: 870 MB → 365 MB.** `ruby:3.4-alpine`; the runtime
  stage carries only shared libraries (`vips`, `libpq`); the build toolchain and
  `-dev` headers live in the discarded build stage. Native gems (nokogiri, pg, ffi,
  ruby-vips) and Thruster run on musl; the POSIX-sh entrypoint replaces the bash one.

### Removed

- **From the runtime image:** the build-only **Tailwind CLI** (~114 MB; CSS is
  precompiled at build time), the shipped **bootsnap cache** (rebuilt lazily — first
  boot is a touch slower, the only tradeoff), gem documentation, **`postgresql-client`**
  (backup is host-side now), **`curl`**, the C toolchain, and **bash/zsh** (busybox
  `sh` is the shell).
- **In-container backup** — `Pito::Tools::Backup` + the `pito:tools:backup` rake task,
  superseded by `pito backup`.

### Fixed

- **The DEVELOPMENT banner reaches both edges** — dropped a dead `scrollbar-gutter:
stable` that reserved a permanent ~6 px strip down the right of every page (the
  window never scrolls; only the inner scrollback does).

## [0.7.2] — 2026-06-24

The **polish, prose & paper-cuts** release. PITO gets its proper name (uppercase,
at last), a README that actually moves, a guide for extending it — and a fistful of
fixes for the ways it used to quietly eat your message or refuse to install.

### Added

- **`docs/extending.md`** — concrete, code-grounded guides for the four common
  extensions: a new **theme**, a new **language**, a new **message-content type**,
  and a new reveal **fx**. Dual-audience (human contributors and AI agents alike).
- **README revamp** — the origin story (the name is a Spanish nursery rhyme), the
  "why it exists" pitch, **animated GIFs** of the chat / linkage / scheduling /
  themes, a **collapsible 19-theme gallery**, and a Sponsor section. Install docs gain
  the `--host` / `--dir .` flags for a non-interactive, in-place install.

### Changed

- **pito → PITO.** The product name is now written PITO in all prose and user-facing
  copy. Code identifiers stay lowercase — the `Pito::` namespace, the `pito` CLI,
  `bin/pito`, `pito.copy.*` i18n keys, URLs, and paths are unchanged.
- **Leaner image.** `.dockerignore` now excludes `node_modules`, `docs/` (incl. the
  ~14 MB media gallery), `spec/`, and the dev `public/pito-storage` blobs — roughly
  60 MB off a local build, ~17 MB off the published image.

### Fixed

- **The chatbox no longer eats your message.** Removing the `/up` route in 0.7.0 left
  the cable-health monitor pinging a now-404 endpoint, so ~60 s into every session it
  falsely flagged the WebSocket "offline" — after which hitting Enter reloaded the
  page (restoring a previous view) instead of sending. The brittle HTTP poll is gone;
  submission always POSTs over HTTP regardless of cable state.
- **The Docker install actually installs.** Two fresh-install crashes fixed: an unset
  `RAILS_MASTER_KEY` was injected as a blank string and corrupted credential
  generation (dropped from compose — the mounted master key is the source of truth);
  and the compose `:ro` mount auto-created `config/credentials.yml.enc` as a
  read-only **directory** before it existed, crashing the generator (bootstrap now
  uses a plain `docker run`).
- **Shinies messages are no longer falsely repliable** — they carried a `#handle`
  reply target nothing consumed; the dead handle (and its `shift+r` affordance) is
  gone.

## [0.7.1] — 2026-06-23

The **polish** release on top of 0.7.0: PITO now keeps your pictures, talks back
when you say hello, ships its arm64 image without the emulation tax, and stops
pinging Slack five times for one green push.

### Fixed

- **Active Storage blobs now persist.** The production image runs as a non-root
  user, but the Active Storage `:local` root (`/var/lib/pito-assets`, backed by
  the persistent `rails_storage` volume) was never created in the image — so a
  freshly-attached Docker volume came up root-owned and the first avatar / cover
  art / video thumbnail upload (and its vips variants) failed with `EACCES`. The
  `Dockerfile` now creates that directory owned by the runtime user **before**
  dropping privileges, so the volume is seeded writable and your media survives
  container recreate, rebuild, and `docker compose pull`. (Postgres data already
  persisted via its own volume.)

### Added

- **Greetings & farewells.** `hi` / `hello` / `hola` / `hey` / `yo` / `good
morning` … and `bye` / `goodbye` / `hasta luego` / `ciao` / `later` … now get a
  witty reply (one of 50 variants each) instead of an error — matched as
  whole-input phrases in the chat parser, isolated from the verb grammar.
- **Witty fallback for nonsense.** Input PITO genuinely can't parse ("boo!", "I'm
  hungry") no longer errors; it returns a `:system` reply from 50 variants, always
  nudging toward `help`. Errors are now reserved for _recognised_ verbs with bad
  arguments.

### Changed

- **Release builds arm64 on a native runner.** Multi-arch publishing moved off
  QEMU emulation onto native per-arch runners (`ubuntu-24.04` for amd64,
  `ubuntu-24.04-arm` for arm64) with a digest-merge step — far faster, same
  `linux/amd64 + linux/arm64` result, so Apple Silicon / Raspberry Pi self-hosters
  keep a native image.
- **Slack CI notifications de-spammed + randomized.** One push used to fire ~5
  green pings (CI ×2 + JS + Docs + Release). Now exactly one green "heartbeat"
  (the CI `rails` job); every other workflow notifies only on failure. The
  Deadpan Butler also picks from a pool of lines so it stops repeating itself.

## [0.7.0] — 2026-06-23

The **local-first self-host** release. PITO stops being "clone the repo and pray"
and becomes "one command, on your own machine." No cloud, no Kamal, no monthly
anything — your laptop, your data, still.

### Added

- **Docker self-host in one command.** `curl … script/install.sh | sh` lands a tiny
  `./pito` install (compose file + CLI), generates your _own_ secrets
  non-interactively (no editor, no host Ruby), pulls a **prebuilt multi-arch image**
  from `ghcr.io/gmrdad82/pito`, enrolls your TOTP login, and offers a Cloudflare
  tunnel + a systemd unit for reboot-persistence. No git clone.
- **`pito` operator CLI** — one self-contained script (no repo, no Ruby) for the
  Docker stack: `up`/`down`, `totp`, `console`, `logs`, `rake`, `clean`, `install`,
  `update`, `service`, `cloudflared`.
- **`/jobs` slash command** — your window into SolidQueue: `status` (workers, state
  counts, recent failures), `requeue <id|all>`, `run <key>` (run a recurring task
  now), `pause` / `resume`. Its subcommands autocomplete in the command palette.
- **Background jobs actually run in production** — the Docker stack runs the
  SolidQueue supervisor inside Puma (`SOLID_QUEUE_IN_PUMA`), so chat-triggered jobs
  and the recurring schedule (nightly sync, achievements, release countdowns) fire on
  a single self-host box without a separate worker process.
- **`pito:tools:clean`** — clears the `tmp/` scratch (keeping `tmp/storage`, `tmp/pids`,
  and `.keep`) and truncates dev `log/*.log`. Safe for blobs: dev Active Storage lives
  under `public/pito-storage`, not `tmp/`.
- **`PITO_APP_BASE_URL`** — set your public host once; it wires Host Authorization,
  URL helpers, and asset delivery. Pairs with a Cloudflare Tunnel for remote access.
- **Dev conveniences** — `PITO_DEV_JOBS=1 bin/dev` to run the recurring scheduler
  locally, and a development-only `/login 123456` dummy code (override with
  `PITO_DEV_TOTP_CODE`, disable with `…=off`) so you can sign in without an
  authenticator. Both are impossible outside development.
- **Release pipeline** — `.github/workflows/release.yml` builds + pushes the
  multi-arch image to GHCR on a **version-tag push only** (never per-commit); a new
  CI `scripts` job shellchecks every shell script.

### Changed

- **Explicit environments**: Docker runs **production**, native `bin/dev` runs
  **development** — documented end to end.
- **Recurring jobs are off under `bin/dev`** by default, so a dev box never quietly
  hits YouTube/Discord on a cron.
- **Leaner, tidier container**: production image drops test-group gems
  (`BUNDLE_WITHOUT="development test"`); compose caps container log growth via the
  json-file driver and mounts each owner's own secrets over the baked-in copies.
- **Fixed the stock `bin/` scripts**: `bin/setup` no longer waits on a phantom
  `redis` (and uses the right compose stack); `bin/test` works again (added the
  missing `bin/test-prepare`). `bin/boot` is now a thin shim forwarding to `pito`.
- **The `shift+r` reply hint now shows on every addressable message** (not just the
  most recent), so any message with a `#handle` is one click from a reply.
- Agent/working docs moved from `tmp/docs` to a gitignored `docs/claude/`.

### Fixed

- **Authenticated 404s no longer 500.** The not-found page rendered the start screen
  with `channels: nil`, blowing up `@channels.any?`; channels now coerce to `[]`.
  (Also explains the occasional dropped chat turn — a request that 500s never finishes.)
- **The game picker no longer hijacks the chatbox.** With a picker sidebar open, its
  keyboard nav stole Enter — injecting `show`/`rm game #id` over whatever you were
  typing. It now ignores keys while focus is in a field outside the picker.

### Removed

- **Kamal** (`config/deploy.yml`, `.kamal/`, `bin/kamal`) — PITO is local-only; there
  was never a cloud-deploy story to maintain.
- The stock **`/up` health route** — single-owner tool, not a load balancer.
- **Action Mailer, Action Mailbox, and Action Text** — all unused (notifications ride
  Slack/Discord webhooks).
- The **`jbuilder`** and **`bcrypt`** gems — neither was used.

## [0.6.0] — 2026-06-23

The **it-has-to-look-good** release. PITO grows a trophy cabinet (shinies),
learns to shimmer, trails a comet behind your cursor, and surfaces analytics at a
glance — because if you're going to stare at your numbers all day, they ought to
look good doing it.

### Added

- **Shinies** — lifetime achievements across **subs, subs gained, views, watch time, likes,
  and comms** (subs is channel-only; subs gained is per video/game), on a 22-step tier ladder
  (1 → 10M) color-coded by tier. Unlocked by a
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
- **Smarter `list` parsing** — `list` with no noun lists the **games** library, and filter terms
  are matched against a known vocabulary (genre aliases like `rpg`/`fps`, platform synonyms like
  `ps5`/`switch`, and `upcoming`); any token that isn't recognized vocabulary is treated as filler
  and **silently dropped** instead of rejected. So `list rpg ps5 please` lists games filtered to the
  **Role-playing** genre on **PlayStation 5**, ignoring `please` — no "didn't understand" error.
  When an unrecognized token (≥4 chars) is within two edits of a real genre/platform/`upcoming`/noun
  term, `list` offers that correction (`list rpgg` → _"Did you mean `rpg`?"_) instead of listing.
  Noun routing runs through one shared vocabulary: `games`/`game`/`gamez` → games,
  `channels`/`channel` → channels, `videos`/`video`/`vids`/`vid` → videos.
- **Message intros shimmer their subject** — the subject of an intro (the video / game title, or
  the `count` + noun in list intros like "11 games" / "6 channels") now carries a pito-blue→purple
  shimmer, and channel `@handle` references in intros shimmer cyan. Titles stay HTML-escaped.
- **Every message types out, each with its own thinking indicator** — response messages now
  reveal via the typewriter (including the detail / list / analytics / shinies HTML cards, not just
  plain text), and each message carries its **own** thinking indicator that resolves when _that_
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
  (`ctrl+arrow`, `Home`/`End`, or a far click) the trail draws a **continuous morphing comet** (3–5
  stretched segments that tile edge-to-edge, no gaps) — full height at both ends, pinching thin
  through the middle — that streaks from the old caret position to the new one and retracts toward
  the cursor. The caret and its trail are **pito-blue**. Respects
  `/config motion` + reduced-motion (solid block, no trail/blink when off).
- **`/config` autosuggest** — typing `/config ` shows a **browsable list** of providers, and
  `/config <provider> ` lists that provider's setting/credential key names (secrets masked) —
  navigate with ↑/↓ + Enter (the suggestion now layers _below_ the block cursor — above the
  type-fx and trail layers — fixing a case where the cursor was hidden while a suggestion showed).
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
- **Thinking indicator now cycles its verb** every 5s (`Executing…` → `Computing…` → …)
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
- **Notifications panel** sorts unread-first then read (each newest-first), applied server-side
  when the panel opens (marking a row read/unread updates it in place without re-sorting — see
  _Notifications read-state_ below).
- **Analytics now follow the shift+space interval.** The glance figures on `show video` /
  `show game` are computed for whatever window you've selected (7d / 28d / 3m / 1y /
  lifetime), default **7d**, persisted per conversation — change it with shift+space and it
  sticks across reloads. The default lives on the conversation, not in the analytics layer.
- **Analytics table** — each metric is a label/value pair (label left, value right-aligned) that
  flows in a flex-wrap row, auto-filling as many columns as the width allows, in canonical order
  Views, Watched hours, Avg view duration, Avg viewed %, Subs, Likes, Comms. **Subs shows
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
- **Similar-games line** drops the middot — now just `#id Game Title` (shimmer id + a thin flex
  gap + title).
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
  keeps the two-column layout. (PITO's first responsive breakpoint.)
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
- **Command-palette commands are clickable** — clicking a `ctrl+k` palette row selects it and
  prefills the command into the chatbox (same as arrow-to-it + Enter — press Enter to run), and the
  command token (e.g. `/connect`) shimmers cyan.
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
- With the **ctrl+k palette open over a sidebar**, arrow/Enter keys now drive only the palette
  — the conversation list, notifications, the game/video pickers, and the IGDB import-results picker
  all bail while the palette is open (no more dual cursor).
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
- **Conversation rename shortcut** moved from `` ` `` to `n` (and `ctrl+`` ` ```→`ctrl+n`).
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
