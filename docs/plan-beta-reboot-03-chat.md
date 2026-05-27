# pito — Chat Core Plan (Plan 3)

> Status: draft. Comes after `plan-beta-reboot-02-slash.md` (Plan 2).
> Builds the chat-message system on top of Plan 2's shared foundation.
> Tasks are atomic (≤5 min each). Check off as you go. Re-open scope
> only after a phase commit lands.

## Sign-off

- [x] Drafted — 2026-05-27
- [x] Audited — 2026-05-27

## North star

Plan 2 wired the slash-command branch of `POST /chat`. Plan 3 wires the **other branch** — the free-text branch — and adds the **refinement turn model** that distinguishes chat from slash. After Plan 3, typing `list` (or any other recognized chat verb) in the chatbox produces a real broadcasted response. Typing `hello` (or any unrecognized free text) produces a real "didn't understand" error event in the scrollback.

The shared foundation (Conversation/Turn/Event, `Pito::Lex`, `Pito::Stream::*`, `ChatController`, Stimulus form, Cable channel) was built in Plan 2 and is reused as-is. Plan 3 adds only the chat-specific layer: `Pito::Chat::Parser/Message/Registry/Handler/Result/Dispatcher`, the example handler `Pito::Chat::Handlers::List`, the unknown-input handler, and the turn model that supports refinements vs new topics.

**Data is fake. Flow is real.** The example `list` handler returns hardcoded video-list-shaped data — no DB queries against domain models, no YouTube API. But every step from keystroke to scrollback uses the production pipeline established in Plan 2.

## Supersedes from Plan 0 and Plan 2

Plan 2 already superseded Plan 0's P12 and P13. Plan 3 supersedes nothing further from Plan 0 (its scope is entirely additive). It does extend two pieces from Plan 2:

| Plan 2 reference | Plan 2 says | Plan 3 extends with |
|---|---|---|
| S7.2 | "Otherwise, return 204 No Content for now (Plan 3 will wire the Chat branch)." | Wires the Chat branch: input not starting with `/` dispatches via `Pito::Chat::Dispatcher`. |
| S7.3 | Materializes Slash's `Result::Ok/Error/NeedsConfirmation` into Events within one Turn. | Adds materialization of Chat's `Result::Ok/Error/Refine`. The `Refine` variant attaches Events to the **existing** open Turn instead of creating a new one. |

## Locked decisions

Carry forward from Plan 0 + Plan 1 + Plan 2:

| Topic | Decision |
|---|---|
| UI stack | Turbo + Stimulus + importmap-rails |
| Components | view_component |
| Endpoint | Single `POST /chat` |
| Persistence | Conversation/Turn/Event (built in Plan 2 S1) |
| Broadcasting | `Pito::Stream::Broadcaster` (built in Plan 2 S3) |
| Stimulus form | `pito--chat-form` controller (built in Plan 2 S7) |
| Lexer | `Pito::Lex::Lexer` (built in Plan 2 S2) |
| i18n | All copy in `config/locales/pito/<area>/en.yml` |

New for Plan 3:

| Topic | Decision |
|---|---|
| Chat verbs | A small fixed set of recognized opening words: `list`, `show`, `find`. Plan 3 implements only `list` end-to-end; `show` and `find` are reserved (parser recognizes them but dispatcher returns "no handler yet"). |
| New-turn vs refinement | The parser classifies the message as **new** if it starts with a recognized verb, **refinement** otherwise (and a Turn is already open in this conversation). When no Turn is open and the message isn't a recognized verb, it's classified **unknown** and produces an error event. |
| Refinement target | Refinements attach to the most recent Turn in the conversation. They produce additional Events on that Turn — Plan 3 keeps it simple by **appending** new Events (Plan 4+ may add replace-the-result-block semantics; out of scope here). |
| Open turn lifetime | A Turn is "open" if `Turn.last_for(conversation)` exists and was created in the last 30 minutes. Beyond that, refinements become unknown-input errors. Configurable later; hardcoded for Plan 3. |
| Result types | `Pito::Chat::Result::Ok(events:)`, `Pito::Chat::Result::Error(message_key:, message_args:)`, `Pito::Chat::Result::Refine(events:)`. `Ok` opens a new turn; `Refine` extends the current one. Distinct from Slash's Result types — different namespace, no cross-import. |
| Unknown handler | A dedicated handler `Pito::Chat::Handlers::Unknown` returns `Result::Error(message_key: "pito.chat.errors.unknown_input", message_args: { input: <raw> })`. Invoked by the dispatcher when no verb matches AND the input doesn't qualify as a refinement. |
| Example handler scope | `Pito::Chat::Handlers::List` returns one `assistant_text` event with hardcoded fake content (a short string mentioning what would normally be listed). No DB, no domain models, no real list of videos. Just enough to prove the end-to-end pipeline works. |
| Refinement example | None in Plan 3 beyond the structural support. The `Refine` Result type is defined and wired, but no handler returns it. A demo fixture handler `Pito::Chat::Handlers::RefineDemo` (similar to Plan 2's `EchoConfirm`) exists as the canonical example. |
| Tests | RSpec lib specs for the chat parser and dispatcher; RSpec service specs for the example handlers; RSpec request specs extending Plan 2's `chat_spec.rb` with the chat branch. |

## Cross-plan invariants (reinforced)

| Invariant | Rationale |
|---|---|
| `lib/pito/chat/**` does NOT `require` or reference `Pito::Slash::*`. | Parallel expansion. (Plan 2 mirrored this from its side.) |
| `app/services/pito/chat/handlers/**` does NOT reference `Pito::Slash::*`. | Same. |
| Both systems share **only** `Pito::Lex` and `Pito::Stream::*`. | Minimum shared surface. |
| Chat handlers never mutate domain data (no AR writes, no API calls that change state). Slash owns mutation. | Conceptual cleanliness — chat reads, slash writes. (Plan 3's `List` handler doesn't even read; later chat handlers will read but never write.) |
| Events stored by chat handlers use the same `Event::KINDS` from Plan 2. No new kinds in Plan 3. | Consistent rendering pipeline. |

## Model recommendations

Same as previous plans:

| Hint | Suggested model | When |
|---|---|---|
| `[manual]` | you, by hand | branches, commits, visual review, design choices |
| `[flash]` | DeepSeek V4 Flash / Gemini 2.0 Flash / GPT-4o-mini | YAML, renames, file audits, locale entries |
| `[haiku]` | Claude Haiku 3.5 | Single-file Ruby classes, value objects, small handlers |
| `[sonnet]` | Claude Sonnet 4 | Multi-file work: parser, dispatcher, controller integration |
| `[pro]` | DeepSeek V4 Pro / Claude Opus 4 | Architectural calls (rare — most decisions inherited from Plan 2) |

## Module map

```
lib/pito/
└── chat/
    ├── parser.rb           # [Token] -> Message
    ├── message.rb          # value object: { verb:, body_tokens:, kind:, raw: }
    ├── registry.rb         # verb -> handler class
    ├── handler.rb          # abstract base
    ├── result.rb           # Result::Ok / Result::Error / Result::Refine
    └── dispatcher.rb       # orchestrates parse -> classify -> registry lookup -> handler call

app/services/pito/chat/handlers/
├── list.rb                 # the example handler (fake data)
├── unknown.rb              # fallback for unrecognized input
└── refine_demo.rb          # DEMO — proves Refine round-trips
```

Plan 2's `Pito::Lex`, `Pito::Stream::Broadcaster`, models, controller, components, channel, and Stimulus controller are reused without modification beyond the S7 controller extension noted above.

## Phase index

- C0 — Pre-flight (verify Plan 2 lands)
- C1 — Chat parser + message value object
- C2 — Chat registry + handler base + result types
- C3 — Chat dispatcher (with new-turn vs refinement classification)
- C4 — ChatController extension (wire the Chat branch)
- C5 — Example handler: `Pito::Chat::Handlers::List` end-to-end
- C6 — Unknown-input handler
- C7 — Refinement primitive (structural only)
- C8 — i18n keys for Plan 3
- C9 — AGENTS.md additions
- C10 — Verification & cleanup

---

## C0 — Pre-flight

> Verify Plan 2 finished. Don't start C1 until every box here is checked.

- [ ] T0.1 Confirm every Plan 2 phase (S0–S14) is checked off. model: [manual]
- [ ] T0.2 `bin/dev` boots; `/` renders persisted events; typing `/help` works end-to-end; refresh persists. model: [manual]
- [ ] T0.3 `Pito::Slash::Dispatcher`, `Pito::Stream::Broadcaster`, `Conversation.singleton` all callable from console without error. model: [manual]
- [ ] T0.4 Create branch `plan-03-chat` from `plan-02-slash` (or main, post-Plan-2 merge). model: [manual]
- [ ] T0.5 Tag the current state as `v0.2.1-pre-chat`. model: [manual]

## C1 — Chat parser + message value object

> Tokens → ChatMessage. Classifies as new-turn vs refinement vs unknown.

- [ ] T1.1 Create `lib/pito/chat/message.rb`. Frozen value object with `verb:` (symbol or nil), `body_tokens:` (array of `Pito::Lex::Token`), `kind:` (`:new_turn` or `:refinement` or `:unknown`), `raw:` (original input string). model: [haiku]
- [ ] T1.2 Create `lib/pito/chat/parser.rb`. Class method `Pito::Chat::Parser.call(tokens, raw:, conversation:) -> Message`. The `conversation` arg is needed to decide refinement-eligibility (i.e. whether an open Turn exists). model: [sonnet]
- [ ] T1.3 Parser rule: if `tokens.first.type == :slash`, raise `Pito::Chat::Parser::NotAChatMessage`. (Slash messages must not reach the Chat parser.) model: [haiku]
- [ ] T1.4 Parser rule: take the first `:word` token's value as the candidate verb (symbol). If it's in the recognized verb set (`%i[list show find]`), classify as `:new_turn` with that verb. The remaining tokens become `body_tokens`. model: [sonnet]
- [ ] T1.5 Parser rule: if the candidate verb isn't recognized, check refinement eligibility — does `Turn.last_for(conversation)` exist and is it less than 30 minutes old? If yes, classify as `:refinement` with `verb: nil` and all tokens (minus EOF) as `body_tokens`. If no, classify as `:unknown` with `verb: nil`. model: [sonnet]
- [ ] T1.6 Add `Turn.last_for(conversation)` class method returning the most recent Turn in the conversation, or nil. Already implicit in `Conversation#turns` ordering but add a named method for clarity. model: [haiku]
- [ ] T1.7 Recognized-verb set lives in `Pito::Chat::Parser::RECOGNIZED_VERBS = %i[list show find].freeze` at the top of the parser file. Constant kept here (not in Registry) so the parser can classify independently of registration state. model: [haiku]
- [ ] T1.8 RSpec spec `spec/lib/pito/chat/parser_spec.rb`: `list videos` → `Message(verb: :list, kind: :new_turn)`; `more stuff` after a recent turn → `Message(verb: nil, kind: :refinement)`; `more stuff` with no recent turn → `Message(verb: nil, kind: :unknown)`; `/help` raises `NotAChatMessage`. model: [sonnet]
- [ ] T1.9 Verify in console: `Pito::Chat::Parser.call(Pito::Lex::Lexer.call("list videos"), raw: "list videos", conversation: Conversation.singleton)` returns the expected Message. model: [manual]
- [ ] T1.10 Commit: `[skipci] C1: chat parser + message value object`. model: [manual]

## C2 — Chat registry + handler base + result types

> Distinct from Slash's equivalents. No cross-import.

- [ ] T2.1 Create `lib/pito/chat/result.rb`. Three immutable subclasses: `Pito::Chat::Result::Ok(events:)`, `Pito::Chat::Result::Error(message_key:, message_args:)`, `Pito::Chat::Result::Refine(events:)`. Each is its own class, NOT a reuse of `Pito::Slash::Result::*`. model: [sonnet]
- [ ] T2.2 In `Result::Ok` and `Result::Refine`, `events:` is an array of `{ kind:, payload: }` hashes (same shape Plan 2 uses). model: [haiku]
- [ ] T2.3 Create `lib/pito/chat/handler.rb`. Abstract base class. Initialized with `message:` and `conversation:` kwargs. Instance method `call -> Result`. Class attribute `verb`. Class attribute `description_key`. model: [sonnet]
- [ ] T2.4 Create `lib/pito/chat/registry.rb`. Singleton-style class with `register(handler_class)`, `lookup(verb) -> handler_class | nil`, `size -> integer`. model: [haiku]
- [ ] T2.5 Extend `config/initializers/pito.rb` to also call `Pito::Chat::Registry.register_all!` at boot. model: [haiku]
- [ ] T2.6 Implement `Pito::Chat::Registry.register_all!` to register every handler under `Pito::Chat::Handlers::*`. model: [haiku]
- [ ] T2.7 RSpec spec for `Pito::Chat::Registry`: registering a handler, looking up, unknown verb returns nil. model: [haiku]
- [ ] T2.8 Confirm no cross-import: `git grep -n "Pito::Slash" lib/pito/chat` returns zero. model: [manual]
- [ ] T2.9 Commit: `[skipci] C2: chat registry + handler base + result types`. model: [manual]

## C3 — Chat dispatcher

> Glue layer. Classifies the message, looks up the handler, invokes it, returns the result.

- [ ] T3.1 Create `lib/pito/chat/dispatcher.rb`. Class method `Pito::Chat::Dispatcher.call(input:, conversation:) -> Result`. model: [sonnet]
- [ ] T3.2 Dispatcher flow: (1) tokenize via `Pito::Lex::Lexer.call(input)`; (2) parse via `Pito::Chat::Parser.call(tokens, raw: input, conversation: conversation)`; (3) branch on `message.kind`. model: [sonnet]
- [ ] T3.3 Branch `:new_turn`: look up handler via `Pito::Chat::Registry.lookup(message.verb)`. If nil, return `Result::Error(message_key: "pito.chat.errors.verb_not_implemented", message_args: { verb: message.verb })`. Else instantiate handler and call it. model: [sonnet]
- [ ] T3.4 Branch `:refinement`: dispatch to a fixed handler `Pito::Chat::Handlers::RefineDemo` for Plan 3 (since no real refinement-capable handler exists). Future plans replace this with proper routing to the current turn's originating handler. model: [sonnet]
- [ ] T3.5 Branch `:unknown`: dispatch to `Pito::Chat::Handlers::Unknown`. model: [haiku]
- [ ] T3.6 Wrap step (2)'s `NotAChatMessage` exception: should never happen (controller routes leading-`/` to Slash), but if it does, return `Result::Error(message_key: "pito.chat.errors.misrouted_slash", message_args: { raw: input })`. model: [haiku]
- [ ] T3.7 RSpec spec for the dispatcher: returns Ok for `list ...`, Error for `madeup ...` as new_turn (verb_not_implemented after we register only `:list`), Refine for refinement input, Error for unknown input with no open turn. model: [sonnet]
- [ ] T3.8 Commit: `[skipci] C3: chat dispatcher`. model: [manual]

## C4 — ChatController extension

> Wire the Chat branch. Materialize Chat Results into Events. Handle the Refine variant by attaching to the existing Turn.

- [ ] T4.1 Edit `ChatController#create` (from Plan 2 S7.2) to dispatch via `Pito::Chat::Dispatcher.call(input: params[:input], conversation: current_conversation)` when the input doesn't start with `/`. model: [sonnet]
- [ ] T4.2 Materialize the Result: always create an `echo` Event first (same as Slash branch); then for `Result::Ok`, create a new Turn and attach `result.events` to it; for `Result::Error`, attach to a new Turn the echo + one `error` Event; for `Result::Refine`, attach the echo + `result.events` to the **most recent existing Turn** (no new Turn created). model: [sonnet]
- [ ] T4.3 Extract Turn creation/lookup into a helper `current_or_new_turn(conversation:, input_text:, input_kind:, attach_to_existing:)` on `ChatController`. The flag is set by the result type. model: [sonnet]
- [ ] T4.4 Each Event creation still goes through `Pito::Stream::Broadcaster` so the broadcast pipeline is unchanged. model: [manual]
- [ ] T4.5 RSpec request spec extension: POST `/chat` with input `list videos` returns 204; creates exactly one new Turn; creates an echo Event + at least one assistant_text Event; broadcasts to the conversation stream. model: [sonnet]
- [ ] T4.6 RSpec request spec extension: POST `/chat` with input `madeup verb` (and no existing recent turn) returns 204; creates a Turn; creates echo + error Event with `payload[:message_key] == "pito.chat.errors.unknown_input"`. model: [haiku]
- [ ] T4.7 RSpec request spec extension: with a recent existing Turn present, POST `/chat` with input `refinement text` returns 204; does NOT create a new Turn; adds echo + new Events to the existing Turn. model: [sonnet]
- [ ] T4.8 Commit: `[skipci] C4: chat controller branch + turn attachment logic`. model: [manual]

## C5 — Example handler: `Pito::Chat::Handlers::List` end-to-end

> The one chat handler this plan wires fully. Returns hardcoded fake data, no DB.

- [ ] T5.1 Create `app/services/pito/chat/handlers/list.rb`. Class `Pito::Chat::Handlers::List < Pito::Chat::Handler`. `self.verb = :list`. `self.description_key = "pito.chat.list.descriptions.list"`. model: [haiku]
- [ ] T5.2 `#call` returns `Pito::Chat::Result::Ok.new(events: [...])`. The events array contains one `assistant_text` event with payload `{ message_key: "pito.chat.list.fake_response", message_args: { count: 5, sample_title: "Sample video title" } }`. model: [haiku]
- [ ] T5.3 Mark the handler clearly: `# FAKE DATA — returns hardcoded placeholder content. Real list logic arrives in a domain plan.` at the top of the file. model: [haiku]
- [ ] T5.4 Register `List` in `Pito::Chat::Registry.register_all!`. model: [haiku]
- [ ] T5.5 Verify in console: `Pito::Chat::Dispatcher.call(input: "list videos", conversation: Conversation.singleton)` returns `Result::Ok` with one assistant_text event. model: [manual]
- [ ] T5.6 RSpec service spec for `Pito::Chat::Handlers::List`: returns Ok with one event whose payload references the expected i18n key. model: [haiku]
- [ ] T5.7 Smoke test: type `list videos` in the chatbox at `/`. See echo (orange border) + assistant text response. Refresh. Same content reappears. model: [manual]
- [ ] T5.8 Commit: `[skipci] C5: /list handler end-to-end (fake data)`. model: [manual]

## C6 — Unknown-input handler

> "didn't understand" path. Real flow, error event in the scrollback.

- [ ] T6.1 Create `app/services/pito/chat/handlers/unknown.rb`. Class `Pito::Chat::Handlers::Unknown < Pito::Chat::Handler`. No `verb` attribute (not registered against any verb — invoked directly by the dispatcher's `:unknown` branch). model: [haiku]
- [ ] T6.2 `#call` returns `Pito::Chat::Result::Error.new(message_key: "pito.chat.errors.unknown_input", message_args: { input: message.raw })`. model: [haiku]
- [ ] T6.3 In `Pito::Chat::Dispatcher`, the `:unknown` branch instantiates and calls this handler (no registry lookup). model: [haiku]
- [ ] T6.4 RSpec service spec: returns Error with the expected message_key and message_args. model: [haiku]
- [ ] T6.5 Smoke test: type `hello` in the chatbox. See echo + red-bordered error: "Didn't understand 'hello'. Try /help for available commands." model: [manual]
- [ ] T6.6 Smoke test: type `madeup verb here` (recognized chat verb pattern but unregistered verb — `madeup` isn't in `RECOGNIZED_VERBS`). Since `madeup` isn't recognized AND there's no open turn, it routes to Unknown. See the same error. model: [manual]
- [ ] T6.7 Commit: `[skipci] C6: unknown-input handler`. model: [manual]

## C7 — Refinement primitive (structural only)

> No real refinement-capable handler yet. Just prove the Refine result type round-trips.

- [ ] T7.1 Create `app/services/pito/chat/handlers/refine_demo.rb`. Class `Pito::Chat::Handlers::RefineDemo < Pito::Chat::Handler`. No `verb` attribute (invoked directly by dispatcher's `:refinement` branch). model: [haiku]
- [ ] T7.2 `#call` returns `Pito::Chat::Result::Refine.new(events: [{ kind: :assistant_text, payload: { message_key: "pito.chat.refine_demo.acknowledged", message_args: { input: message.raw } } }])`. model: [haiku]
- [ ] T7.3 Mark the handler: `# DEMO — Proves the Refine result type round-trips. Replace with proper routing when real refinement-capable handlers exist.` model: [haiku]
- [ ] T7.4 RSpec service spec for `RefineDemo`: returns `Result::Refine` with one assistant_text event. model: [haiku]
- [ ] T7.5 RSpec request spec: with an existing recent Turn (e.g. previous `list videos` request), POST `/chat` with input `add ctr` results in events appended to the existing Turn, not a new Turn. model: [sonnet]
- [ ] T7.6 Smoke test: type `list videos`. Then type `add ctr`. Observe: only one Turn exists in the DB for both messages; both echo events + both response events appear in the scrollback. model: [manual]
- [ ] T7.7 Smoke test: wait > 30 minutes (or temporarily lower the threshold) after `list videos`, then type `add ctr`. Observe: it now routes to Unknown (no open turn), producing an error event. Restore threshold after. model: [manual]
- [ ] T7.8 Commit: `[skipci] C7: refinement primitive (structural)`. model: [manual]

## C8 — i18n keys for Plan 3

> Every user-facing string added by Plan 3.

- [ ] T8.1 Create `config/locales/pito/chat/en.yml`. Add keys: `pito.chat.list.descriptions.list`, `pito.chat.list.fake_response`, `pito.chat.errors.unknown_input`, `pito.chat.errors.verb_not_implemented`, `pito.chat.errors.misrouted_slash`, `pito.chat.refine_demo.acknowledged`. model: [haiku]
- [ ] T8.2 Suggested copy: `list.descriptions.list: "List items (videos, games, playlists)"`; `list.fake_response: "[FAKE] Would list %{count} items here. Example: %{sample_title}"`; `errors.unknown_input: "Didn't understand %{input}. Try /help for available commands."`; `errors.verb_not_implemented: "The chat verb %{verb} isn't wired yet."`; `errors.misrouted_slash: "Internal: slash command %{raw} reached the chat parser."`; `refine_demo.acknowledged: "[DEMO refinement] Received: %{input}"`. model: [haiku]
- [ ] T8.3 Audit every file added/modified in Plan 3 — no inline user-facing strings. model: [sonnet]
- [ ] T8.4 Boot `bin/dev`, exercise `list videos`, `hello`, `madeup`, `add ctr` (after a recent turn). No `translation missing` placeholders. model: [manual]
- [ ] T8.5 Commit: `[skipci] C8: i18n keys for chat core`. model: [manual]

## C9 — AGENTS.md additions

> Document the conventions Plan 3 introduces.

- [ ] T9.1 Add section `## Chat conventions` to AGENTS.md describing: `Pito::Chat::*` namespace, handlers under `app/services/pito/chat/handlers/`, every handler returns a `Pito::Chat::Result`, registry registered in `config/initializers/pito.rb`, recognized verbs declared in parser constant `RECOGNIZED_VERBS`. model: [sonnet]
- [ ] T9.2 Add section `## Turn lifecycle` describing: how the parser classifies new-turn vs refinement vs unknown, the 30-minute open-turn threshold, how the controller attaches Events to existing vs new Turns based on the Result type. model: [sonnet]
- [ ] T9.3 Add section `## Chat vs Slash` summarizing the isolation invariants: no cross-import, no shared Result types, shared only via `Pito::Lex` and `Pito::Stream::*`, chat reads (eventually) and slash writes. model: [haiku]
- [ ] T9.4 Commit: `[skipci] C9: AGENTS.md chat + turn lifecycle conventions`. model: [manual]

## C10 — Verification & cleanup

> Final pass. Confirm Plan 3 delivered what it promised.

- [ ] T10.1 `bundle exec rspec` is green across all specs added by Plan 3 (lib, service, request). model: [manual]
- [ ] T10.2 `bin/dev` boots cleanly; visit `/`; type `/help` (still works from Plan 2). model: [manual]
- [ ] T10.3 Type `list videos` → echo + fake list response appears via Cable. Refresh `/` → events persist. model: [manual]
- [ ] T10.4 Type `hello` → echo + red error event ("Didn't understand 'hello'"). model: [manual]
- [ ] T10.5 With the previous Turn still open (within 30 min), type `add ctr` → events appended to the existing Turn (no new Turn row). model: [manual]
- [ ] T10.6 `git grep -n "Pito::Slash" lib/pito/chat app/services/pito/chat` — should return zero hits (isolation invariant). model: [manual]
- [ ] T10.7 `git grep -n "Pito::Chat" lib/pito/slash app/services/pito/slash` — should return zero hits (the other direction). model: [manual]
- [ ] T10.8 `git grep -nE '"[A-Z][a-z][^"]*"' app/services/pito/chat lib/pito/chat` — every match is an i18n key, an inline-comment string, or a non-user-facing string. model: [manual]
- [ ] T10.9 Tag: `git tag v0.3.0-chat-core`. model: [manual]
- [ ] T10.10 Commit: `[skipci] C10: chat core verification`. model: [manual]

---

## Open follow-ups (later plans)

These are explicitly NOT in Plan 3:

- Real chat handlers that hit the DB: list videos, list games, top videos by metric, etc.
- The full chat grammar described in earlier brainstorming: `with FIELD, FIELD`, `top N`, `latest N`, period overrides, filter keywords (`shorts`, `longform`, etc.). Plan 3 ships a stub verb only.
- Phrase dictionary for fuzzy modifier matching ("watched mostly by men", "on mobile").
- Embedding fallback via Voyage for unmatched remainders.
- Optional LLM fallback for genuinely novel inputs.
- The `new topic` keyword (or button) to explicitly close the current Turn.
- Replace-vs-append refinement semantics: refinements that rewrite the previous result block (e.g., add a column to the same table) instead of appending new events.
- TAB channel cycling + SHIFT+TAB period cycling (Stimulus + state).
- Channel/period context being sent with each message and converted to absolute timestamps server-side.
- Multi-conversation routing (per-tab conversations, session picker, rename, fork).
- Ctrl+K / Ctrl+P command palette UI.
- Autocomplete or suggestions while typing.
- Syntax highlighting of recognized tokens.
- Sessions persisted across devices (mobile → desktop continuity).
- Authentication (`/authenticate`) and OAuth (`/connect`) — covered by Plan 0 P14, surfaced in a later plan.
- Localization beyond English.

## How to use this plan

Same as previous plans:

1. Pick the next unchecked task in phase order.
2. Read the `model:` hint; pick the cheapest model that fits.
3. Dispatch as a sub-agent (in OpenCode, Claude Code, etc.) OR do by hand.
4. Verify (read the diff, run `bin/dev`, exercise the affected flow).
5. Check the box. Move on.
6. Commit at the end of each phase using the suggested `[skipci]` title.
7. If a task feels bigger than 5 minutes, split it.
