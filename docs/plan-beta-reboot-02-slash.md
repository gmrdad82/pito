# pito — Slash Core Plan (Plan 2)

> Status: draft. Comes after `plan-beta-reboot-01-ui.md` (Plan 1).
> Builds the shared dispatch foundation plus the slash-command system end-to-end.
> Tasks are atomic (≤5 min each). Check off as you go. Re-open scope
> only after a phase commit lands.

## Sign-off

- [x] Drafted — 2026-05-27
- [x] Audited — 2026-05-27

## North star

Plan 1 left a static visual chassis at `/`, `/start`, `/_ui/palettes`, `/_ui/sidebar`. Plan 2 turns the chatbox at `/` into a working pipe for **slash commands**: typing `/help` and pressing Enter produces an echoed user event in the scrollback, a real assistant response listing the registered slash commands, and a persisted record of the exchange that survives a page refresh.

Plan 2 also lays down the **shared foundation** that Plan 3 (Chat) will reuse: the lexer, the persistence model (Conversation/Turn/Event), the Action Cable channel, the broadcast pipeline, the single `POST /chat` controller, the form wiring around `Pito::Shell::ChatboxComponent`. Everything below the parser/registry split.

Data is **fake but the flow is real**. Handlers return hardcoded payloads. No DB queries against domain models, no YouTube API, no IGDB, no Voyage. But every step from keystroke to scrollback uses the production pipeline: Stimulus submits via Turbo → controller → lexer → slash parser → registry → handler → result → broadcaster → Turbo Stream over Action Cable → ScrollbackComponent re-renders from persisted Event records.

## Supersedes from Plan 0

| Plan 0 reference | Plan 0 says | Plan 2 supersedes with |
|---|---|---|
| P12 | Command router + handler registry under `lib/pito/command/...` with `Pito::Command::Router/Invocation/Registry/Handler` | Replaced by `lib/pito/lex/`, `lib/pito/slash/`, and `lib/pito/stream/` with the namespaces `Pito::Lex`, `Pito::Slash::Parser/Invocation/Registry/Handler/Result`. Handlers live under `app/services/pito/slash/handlers/`. |
| P12.5–P12.11 | First seven handlers (Help, Channels::Stats, Videos::Show, Videos::Publish, Videos::Schedule, Games::ByGenre, Videos::ByGenre) | Replaced by a single example handler `Pito::Slash::Handlers::Help` end-to-end. Domain handlers (publish/schedule/etc.) move to later plans. |
| P12.14 | Form on terminal page POSTs to `/commands` | Replaced by single `POST /chat` endpoint. Controller does a leading-`/` check and dispatches to Slash or Chat. Plan 2 wires the Slash branch; Plan 3 wires the Chat branch. |
| P13 | `Pito::TerminalChannel` streaming from `"pito:terminal:#{session_id}"` + `Pito::Stream::Broadcaster` + `Pito::Stream::Echo` + `Pito::Stream::Spinner` | Replaced by `Pito::ChatChannel` streaming from `"pito:conversation:#{conversation_id}"` + `Pito::Stream::Broadcaster` emitting persisted Event records. Echo and Spinner are out of scope; replaced by the Event persistence model (which gives us the same effect plus refresh-survivability). |

P0–P11 and P14–P19 of Plan 0 are unaffected. Plan 1's component inventory is unaffected. Plan 2 wires forms and Stimulus around the existing chatbox; it does not change the chatbox's visual contract.

## Locked decisions

Carry forward from Plan 0 + Plan 1:

| Topic | Decision |
|---|---|
| UI stack | Turbo + Stimulus + importmap-rails (zero node) |
| CSS | tailwindcss-rails |
| Components | view_component |
| Jobs | SolidQueue |
| Cache | SolidCache |
| Cable | SolidCable |
| Brand | `pito` lowercase except sentence start |
| i18n | All copy in `config/locales/pito/<area>/en.yml` |
| License | AGPL-3.0 |

New for Plan 2:

| Topic | Decision |
|---|---|
| Endpoint | Single `POST /chat`. Controller inspects the input; leading `/` → Slash dispatcher, otherwise → Chat dispatcher (Plan 3 wires Chat). |
| Code layout | Infrastructure (parsers, registries, value objects, base classes) lives under `lib/pito/`. Concrete handlers (the domain work) live under `app/services/pito/<system>/handlers/`. |
| Persistence | Three models: `Conversation` (top-level container), `Turn` (one user input + its responses), `Event` (one renderable thing in scrollback). Events store **structured payloads** (`kind`, `payload`, `position`), never rendered HTML. Re-render through ViewComponents on every read. |
| Locale-key payloads | Payloads reference **i18n keys + interpolation args**, never rendered strings. `{ kind: :ok, message_key: "pito.slash.help.intro", message_args: {} }` not `{ message: "Available commands…" }`. |
| Broadcast | `Pito::Stream::Broadcaster.new(conversation:).emit(event)` — persists the Event, then broadcasts a Turbo Stream `append` of the rendered ViewComponent to `"pito:conversation:#{conversation.id}"`. |
| Cable channel name | `"pito:conversation:#{conversation.id}"`. One stream per conversation, matching the "per-conversation" decision from question 12. |
| Conversation lookup | A `current_conversation` helper on `ApplicationController`. Plan 2 hardcodes "the single conversation" (find-or-create one). Multi-conversation routing is deferred. |
| Parser invariants | `Pito::Lex` produces tokens with no knowledge of slash or chat. `Pito::Slash::Parser` consumes tokens; never imports `Pito::Chat`. (Plan 3 will mirror this from the other side.) |
| Form submission | Stimulus controller on the chatbox captures Enter, prevents default, submits the form via Turbo. Stays simple — no autocomplete, no palette, no history navigation in Plan 2. |
| Confirmation primitive | `Pito::Slash::Result::NeedsConfirmation` is defined and serialized as an Event of kind `:confirmation_prompt`. **No actual confirmation handler is built** — just the structural support so domain handlers in later plans can return it. |
| Unknown command | A slash verb with no matching handler produces an Event of kind `:error` with `message_key: "pito.slash.errors.unknown_verb"` and `message_args: { verb: <verb> }`. Renders through `Pito::Event::ErrorComponent`. |
| Tests | RSpec request specs for the controller, RSpec lib specs for lexer + parser + registry, RSpec service specs for handlers. Component specs deferred per Plan 0 P3 + P18.6. |

## Cross-plan invariants

| Invariant | Rationale |
|---|---|
| `lib/pito/slash/**` does NOT `require` or reference `Pito::Chat::*`. | Parallel expansion without coupling. Plan 3 mirrors this from its side. |
| `lib/pito/chat/**` (Plan 3) does NOT `require` or reference `Pito::Slash::*`. | Same. |
| Both systems share **only** `Pito::Lex` and `Pito::Stream::*`. Nothing else. | Minimum shared surface. |
| Every handler returns a `Result` value object; the controller never reads handler internals. | Uniform dispatch contract. |
| Events store structured payloads, never HTML. | Refresh-survives, theme-survives, locale-survives. |
| Re-rendering an Event from its payload must always produce the current "now" (timestamps re-resolve, "5m ago" recomputes). | Date/time relevance survives time. |

## Complexity hints

Same as Plan 0 and Plan 1:

| Hint | When |
|---|---|
| `[manual]` | You, by hand — branches, commits, visual review, design choices |
| `[low]` | YAML, renames, file audits, locale entries, gemfile edits, single-file Ruby classes, value objects, small controllers, ERB tweaks |
| `[medium]` | Multi-file work: lexer + parser pair, controller + channel + broadcaster, persistence layer |
| `[high]` | Architectural calls: turn model, payload schema, invariants |

## Module map

```
lib/pito/
├── lex/
│   ├── lexer.rb            # String -> [Token]
│   └── token.rb            # value object: { type:, value:, position: }
├── slash/
│   ├── parser.rb           # [Token] -> Invocation
│   ├── invocation.rb       # value object: { verb:, args:, kwargs:, raw: }
│   ├── registry.rb         # verb -> handler class
│   ├── handler.rb          # abstract base
│   ├── result.rb           # Result::Ok / Result::Error / Result::NeedsConfirmation
│   └── dispatcher.rb       # orchestrates parse -> registry lookup -> handler call
└── stream/
    ├── broadcaster.rb      # persist + broadcast
    └── event_payload.rb    # payload validation / coercion

app/
├── channels/
│   └── pito/
│       └── chat_channel.rb
├── controllers/
│   └── chat_controller.rb
├── models/
│   ├── conversation.rb
│   ├── turn.rb
│   └── event.rb
├── services/
│   └── pito/
│       └── slash/
│           └── handlers/
│               └── help.rb
└── components/
    └── pito/
        └── event/
            ├── echo_component.{rb,html.erb}        # user echo (orange border, reuses UserMessageComponent)
            ├── error_component.{rb,html.erb}       # error events
            └── confirmation_prompt_component.{rb,html.erb}  # NeedsConfirmation events (visual only)
```

Plan 1's components (`Pito::Event::UserMessageComponent`, `Pito::Event::AssistantTextComponent`, `Pito::Shell::ChatboxComponent`, etc.) are reused. Plan 2 adds `EchoComponent`, `ErrorComponent`, and `ConfirmationPromptComponent` to the Event family.

## Phase index

- S0 — Pre-flight (verify Plan 1 lands)
- S1 — Persistence: Conversation, Turn, Event models + migration
- S2 — Shared lexer (`Pito::Lex`)
- S3 — Stream pipeline: ChatChannel + Broadcaster
- S4 — Slash parser + invocation
- S5 — Slash registry + handler base + result types
- S6 — Slash dispatcher
- S7 — ChatController + form wiring + Stimulus submit
- S8 — Scrollback re-render from persisted Events
- S9 — Example handler: `Pito::Slash::Handlers::Help` end-to-end
- S10 — Error path: unknown verb event
- S11 — Confirmation primitive (structural only)
- S12 — i18n keys for Plan 2
- S13 — AGENTS.md additions
- S14 — Verification & cleanup

---

## S0 — Pre-flight

> Verify Plan 1 finished. Don't start S1 until every box here is checked.

- [x] T0.1 Confirm every Plan 1 phase (U0–U11) is checked off. complexity: [manual]
- [x] T0.2 `bin/dev` starts cleanly; `/` renders the chat shell with hardcoded sample events; `/start` renders the start screen. complexity: [manual]
- [x] T0.3 `Pito::Shell::ChatboxComponent`, `Pito::Event::UserMessageComponent`, `Pito::Event::AssistantTextComponent` exist and render without error from console. complexity: [manual]
- [x] T0.4 Create branch `plan-02-slash` from `plan-01-ui` (or main, post-Plan-1 merge). complexity: [manual]
- [x] T0.5 Tag the current state as `v0.1.1-pre-slash`. complexity: [manual]

## S1 — Persistence: Conversation, Turn, Event

> Build the three tables that hold every interaction. Payloads are structured JSON; no HTML stored.

- [x] T1.1 Generate migration `add_conversations_turns_events.rb`. Tables: `conversations`, `turns`, `events`. complexity: [medium]
- [x] T1.2 In the migration, `conversations` has: `id`, `title` (string, nullable), `created_at`, `updated_at`. No user_id (single-user app). complexity: [low]
- [x] T1.3 In the migration, `turns` has: `id`, `conversation_id` (FK, not null, indexed), `position` (integer, not null), `input_kind` (string, not null — `"slash"` or `"chat"`), `input_text` (string, not null), `created_at`, `updated_at`. Unique index on `(conversation_id, position)`. complexity: [low]
- [x] T1.4 In the migration, `events` has: `id`, `conversation_id` (FK, not null, indexed), `turn_id` (FK, not null, indexed), `position` (integer, not null), `kind` (string, not null), `payload` (jsonb, not null, default `{}`), `created_at`, `updated_at`. Unique index on `(conversation_id, position)`. complexity: [low]
- [x] T1.5 `bin/rails db:migrate`. Verify schema landed. complexity: [manual]
- [x] T1.6 Create `app/models/conversation.rb`: `has_many :turns, -> { order(:position) }`, `has_many :events, -> { order(:position) }`. Add `Conversation.singleton` class method that finds the first conversation or creates one (Plan 2 single-conversation assumption). complexity: [medium]
- [x] T1.7 Create `app/models/turn.rb`: `belongs_to :conversation`, `has_many :events, -> { order(:position) }`. Validations: `input_kind` in `%w[slash chat]`, `position` presence, `input_text` presence. complexity: [low]
- [x] T1.8 Create `app/models/event.rb`: `belongs_to :conversation`, `belongs_to :turn`. Validations: `kind` presence, `position` presence. Add `KINDS` constant listing supported kinds: `%w[echo assistant_text error confirmation_prompt]`. complexity: [low]
- [x] T1.9 Add a class method `Event.next_position_for(conversation)` returning `conversation.events.maximum(:position).to_i + 1`. complexity: [low]
- [x] T1.10 Add a class method `Turn.next_position_for(conversation)` returning `conversation.turns.maximum(:position).to_i + 1`. complexity: [low]
- [x] T1.11 RSpec model specs: `Conversation.singleton` returns the same record across calls; `Event.next_position_for` increments; `Turn` validates `input_kind` inclusion. complexity: [low]
- [x] T1.12 Commit: `[skipci] S1: conversation/turn/event persistence`. complexity: [manual]

## S2 — Shared lexer (`Pito::Lex`)

> One tokenizer. Knows nothing about slash or chat. Produces a flat token stream.

- [x] T2.1 Create `lib/pito/lex/token.rb`. Frozen value object with `type:` (symbol), `value:` (string), `position:` (integer — column offset). complexity: [low]
- [x] T2.2 Create `lib/pito/lex/lexer.rb`. Class method `Pito::Lex::Lexer.call(string) -> Array<Token>`. complexity: [medium]
- [x] T2.3 Lexer recognizes the token types: `:slash` (`/`), `:word` (run of `[a-zA-Z][a-zA-Z0-9_-]*`), `:number` (run of digits), `:string` (double-quoted, with `\"` escape), `:colon` (`:`), `:equals` (`=`), `:comma` (`,`), `:at` (`@`), `:dot` (`.`), `:eof`. Skips whitespace. Unknown character → `:unknown` token (caller decides what to do). complexity: [medium]
- [x] T2.4 Lexer is hand-rolled — no Parslet, no Treetop, no regex-only scanner. Walk the string with an index, build tokens, return the array. complexity: [medium]
- [x] T2.5 RSpec spec `spec/lib/pito/lex/lexer_spec.rb` covering each token type, escape handling in strings, position offsets, and the empty-string edge case. complexity: [low]
- [x] T2.6 Verify `Pito::Lex::Lexer.call("/help")` returns `[Token(:slash), Token(:word, "help"), Token(:eof)]`. complexity: [manual]
- [x] T2.7 Verify `Pito::Lex::Lexer.call("/schedule 42 for \"tomorrow at noon\"")` returns the expected six-token stream. complexity: [manual]
- [x] T2.8 Add a comment block at the top of `lexer.rb`: "Pure function. No knowledge of slash or chat. Both Pito::Slash::Parser and Pito::Chat::Parser consume this." complexity: [low]
- [x] T2.9 Commit: `S2: shared lexer Pito::Lex`. complexity: [manual]

## S3 — Stream pipeline: ChatChannel + Broadcaster

> The transport. One channel per conversation. Broadcaster persists the event, then broadcasts the rendered component.

- [x] T3.1 Generate `app/channels/pito/chat_channel.rb` inheriting from `ApplicationCable::Channel`. `subscribed` calls `stream_from "pito:conversation:#{params[:conversation_id]}"`. complexity: [low]
- [x] T3.2 In `ApplicationCable::Connection` (or equivalent), identify by a persistent cookie or, for Plan 2, allow anonymous connections (single-user app — auth wiring comes in Plan 0 P14, already locked). complexity: [medium]
- [x] T3.3 Create `lib/pito/stream/event_payload.rb`. Class method `Pito::Stream::EventPayload.validate!(kind:, payload:)` — raises if `kind` not in `Event::KINDS`. Schema validation deferred (jsonb is permissive enough for Plan 2). complexity: [low]
- [x] T3.4 Create `lib/pito/stream/broadcaster.rb`. Initialize with `conversation:`. Public method `emit(turn:, kind:, payload:)` that: (1) calls `EventPayload.validate!`, (2) creates an Event with `position: Event.next_position_for(conversation)`, (3) renders the right component via `EventRenderer` (T3.5), (4) broadcasts a Turbo Stream `append` to `"pito:conversation:#{conversation.id}"` targeting the scrollback DOM id `pito-scrollback`. complexity: [medium]
- [x] T3.5 Create `lib/pito/stream/event_renderer.rb`. Class method `render(event) -> String (rendered HTML)`. Looks up the component class from a kind-to-component map: `echo -> Pito::Event::EchoComponent`, `assistant_text -> Pito::Event::AssistantTextComponent`, `error -> Pito::Event::ErrorComponent`, `confirmation_prompt -> Pito::Event::ConfirmationPromptComponent`. Renders via `ApplicationController.renderer.render(component_instance, layout: false)`. complexity: [medium]
- [x] T3.6 Updated existing components to accept `payload:` kwarg. AssistantTextComponent resolves i18n keys at render time. complexity: [medium]
- [x] T3.7 Create `Pito::Event::EchoComponent` (rb + erb). Args: `payload:` containing `{ text: <string> }`. Renders via `Pito::Segment::Component` with `border: var(--accent-orange), background: nil`. Content is the text in `text-fg`. (Identical to `UserMessageComponent` but a distinct class — echoes are conceptually different from user messages and Plan 3 may diverge them.) complexity: [low]
- [x] T3.8 Create `Pito::Event::ErrorComponent` (rb + erb). Args: `payload:` containing `{ message_key: <i18n key>, message_args: <hash> }`. Renders via `Pito::Segment::Component` with `border: var(--accent-red), background: nil`. Content is `t(payload[:message_key], **payload[:message_args])` in `text-fg`. complexity: [low]
- [x] T3.9 Create `Pito::Event::ConfirmationPromptComponent` (rb + erb). Args: `payload:` containing `{ prompt_key:, prompt_args:, command_text: }`. Renders via `Pito::Segment::Component` with `border: var(--accent-yellow), background: var(--bg-elevated)`. Content: prompt text in `text-fg`, then command echo in `text-cyan`, then hint line "type /confirm or /cancel" in `text-fg-dim`. No actual handlers in Plan 2 — visual only. complexity: [medium]
- [x] T3.10 RSpec spec for `Pito::Stream::Broadcaster`: persists an Event, increments position, returns the persisted Event. Cable broadcast assertion via `have_broadcasted_to`. complexity: [medium]
- [x] T3.11 Commit: `S3: chat channel + broadcaster + event renderer + new event components`. complexity: [manual]

## S4 — Slash parser + invocation

> Tokens → SlashInvocation. Hand-rolled grammar.

- [x] T4.1 Create `lib/pito/slash/invocation.rb`. Frozen value object with `verb:` (symbol), `args:` (array of strings/numbers), `kwargs:` (hash, symbol keys), `raw:` (original input string). complexity: [low]
- [x] T4.2 Create `lib/pito/slash/parser.rb`. Class method `Pito::Slash::Parser.call(tokens, raw:) -> Invocation`. complexity: [medium]
- [x] T4.3 Grammar rule: first token MUST be `:slash`, else raise `Pito::Slash::Parser::NotASlashCommand`. Second token MUST be `:word`, else raise `Pito::Slash::Parser::MissingVerb`. The verb is `tokens[1].value.to_sym`. complexity: [medium]
- [x] T4.4 Grammar rule: remaining tokens collect into `args` (positional) and `kwargs` (when a `:word`/`:colon` or `:word`/`:equals` pattern appears). For Plan 2 keep it simple: bare words/numbers/strings → args; `key=value` or `key:value` → kwargs. complexity: [medium]
- [x] T4.5 RSpec spec `spec/lib/pito/slash/parser_spec.rb`: `/help` → `Invocation(verb: :help, args: [], kwargs: {})`; `/publish 42` → `Invocation(verb: :publish, args: [42], kwargs: {})`; `/schedule 42 when="tomorrow"` → `Invocation(verb: :schedule, args: [42], kwargs: { when: "tomorrow" })`. Errors raise the named exception classes. complexity: [low]
- [x] T4.6 Verify in console: `Pito::Slash::Parser.call(Pito::Lex::Lexer.call("/help"), raw: "/help")` returns the expected Invocation. complexity: [manual]
- [x] T4.7 Commit: `S4: slash parser + invocation value object`. complexity: [manual]

## S5 — Slash registry + handler base + result types

> The dispatch table. Where a verb meets its handler.

- [x] T5.1 Create `lib/pito/slash/result.rb`. Three immutable subclasses: `Pito::Slash::Result::Ok(events:)`, `Pito::Slash::Result::Error(message_key:, message_args:)`, `Pito::Slash::Result::NeedsConfirmation(prompt_key:, prompt_args:, command_text:)`. Each carries the payload shape needed to materialize an Event. complexity: [medium]
- [x] T5.2 In `Result::Ok`, `events:` is an array of `{ kind:, payload: }` hashes (so a single command can produce multiple events). complexity: [low]
- [x] T5.3 Create `lib/pito/slash/handler.rb`. Abstract base class. Initialized with `invocation:` and `conversation:` kwargs. Instance method `call -> Result`. Subclasses override `#call`. Class method `verb` returns the symbol the handler responds to (subclasses set it). complexity: [medium]
- [x] T5.4 Create `lib/pito/slash/registry.rb`. Singleton-style class with `register(handler_class)` and `lookup(verb) -> handler_class | nil`. Internal storage: a hash keyed by `handler_class.verb`. complexity: [low]
- [x] T5.5 Add `Pito::Slash::Registry.register_all!` that explicitly registers every handler under `Pito::Slash::Handlers::*`. Called once at boot from `config/initializers/pito.rb`. complexity: [low]
- [x] T5.6 Create `config/initializers/pito.rb` that runs `Rails.application.config.to_prepare { Pito::Slash::Registry.register_all! }`. complexity: [low]
- [x] T5.7 RSpec spec for `Pito::Slash::Registry`: registering a handler, looking it up, looking up an unknown verb returns nil. complexity: [low]
- [x] T5.8 Commit: `S5: slash registry + handler base + result types`. complexity: [manual]

## S6 — Slash dispatcher

> Glue layer. Parses the input, looks up the handler, invokes it, returns the result. No persistence, no broadcasting — that's the controller's job.

- [x] T6.1 Create `lib/pito/slash/dispatcher.rb`. Class method `Pito::Slash::Dispatcher.call(input:, conversation:) -> Result`. complexity: [medium]
- [x] T6.2 Dispatcher flow: (1) tokenize via `Pito::Lex::Lexer.call(input)`; (2) parse via `Pito::Slash::Parser.call(tokens, raw: input)`; (3) look up handler via `Pito::Slash::Registry.lookup(invocation.verb)`; (4) if nil, return `Result::Error(message_key: "pito.slash.errors.unknown_verb", message_args: { verb: invocation.verb })`; (5) else instantiate the handler with `invocation:` + `conversation:` and call it; (6) return the handler's Result. complexity: [medium]
- [x] T6.3 Wrap step (2) in a rescue: `Pito::Slash::Parser::NotASlashCommand` and `Pito::Slash::Parser::MissingVerb` both become `Result::Error(message_key: "pito.slash.errors.parse_failed", message_args: { raw: input })`. complexity: [low]
- [x] T6.4 RSpec spec for the dispatcher: returns Ok for a registered verb, Error for unknown verb, Error for malformed input. Uses a fixture handler registered in the test. complexity: [medium]
- [x] T6.5 Commit: `S6: slash dispatcher`. complexity: [manual]

## S7 — ChatController + form wiring + Stimulus submit

> The single POST endpoint. Form around the existing chatbox component. Stimulus controller submits on Enter.

- [x] T7.1 Generate `app/controllers/chat_controller.rb` with `#create` action mapped to `POST /chat`. complexity: [low]
- [x] T7.2 In `#create`, read `params[:input]` (string). If `params[:input].to_s.start_with?("/")`, dispatch via `Pito::Slash::Dispatcher`. Otherwise, return 204 No Content for now (Plan 3 will wire the Chat branch). complexity: [medium]
- [x] T7.3 After dispatch returns a `Result`, the controller materializes Events: (a) always create an `echo` Event first with `payload: { text: params[:input] }`; (b) for `Result::Ok`, iterate `result.events` and create each; (c) for `Result::Error`, create one `error` Event with the result's `message_key`/`message_args`; (d) for `Result::NeedsConfirmation`, create one `confirmation_prompt` Event. All persisted within one `Turn` record. complexity: [medium]
- [x] T7.4 Each Event creation goes through `Pito::Stream::Broadcaster.new(conversation: current_conversation).emit(turn:, kind:, payload:)`. The broadcaster persists AND broadcasts. complexity: [medium]
- [x] T7.5 Controller responds with `head :no_content` after dispatch — all visible output arrives via the Cable broadcast. complexity: [low]
- [x] T7.6 Add `current_conversation` helper to `ApplicationController` returning `Conversation.singleton`. (Multi-conversation routing deferred.) complexity: [low]
- [x] T7.7 In `config/routes.rb`, add `post "/chat", to: "chat#create"`. complexity: [low]
- [x] T7.8 Update `app/views/terminal/show.html.erb` to wrap the chatbox in a `form_with url: chat_path, method: :post, data: { controller: "pito--chat-form", turbo: true }`. The form contains a hidden input named `input` populated by Stimulus from the chatbox's editable region. (Plan 1's chatbox is currently a static visual — Plan 2 makes the bar+content area editable via `contenteditable="true"` on the text span, OR replaces the inner text with an `<input type="text">` styled to match. Pick whichever is simpler to style; the input route is recommended for Plan 2.) complexity: [medium]
- [x] T7.9 Create Stimulus controller `app/javascript/controllers/pito/chat_form_controller.js`. Targets: `input` (the text field), `form` (the form element). On Enter keydown (no Shift): `event.preventDefault()`, copy the visible input value into a hidden field, submit the form via `this.formTarget.requestSubmit()`, clear the visible input. complexity: [medium]
- [x] T7.10 Pin Stimulus controller in `config/importmap.rb` and register it in `app/javascript/controllers/index.js` (or equivalent eager-load list). complexity: [low]
- [x] T7.11 Subscribe the `<turbo-cable-stream-source>` element in the terminal layout to `"pito:conversation:#{current_conversation.id}"`. Provide the conversation id from the controller. complexity: [medium]
- [x] T7.12 Add a wrapping `<div id="pito-scrollback">` around the scrollback area in the terminal view (matches the target id used by the broadcaster). complexity: [low]
- [x] T7.13 RSpec request spec `spec/requests/chat_spec.rb`: POST `/chat` with input `/help` returns 204; creates exactly one Turn; creates an echo Event + at least one response Event; broadcasts to the conversation stream. complexity: [medium]
- [x] T7.14 Commit: `[skipci] S7: chat controller + form + stimulus submit`. complexity: [manual]

## S8 — Scrollback re-render from persisted Events

> Page refresh must reproduce every event in order. No HTML stored — components re-render from payloads.

- [ ] T8.1 Update `TerminalController#show` to load `@events = current_conversation.events.includes(:turn).order(:position)`. complexity: [low]
- [ ] T8.2 Replace the hardcoded sample loop in `app/views/terminal/show.html.erb` with iteration over `@events`. For each event, render the component matched by `event.kind` using the same mapping defined in `Pito::Stream::EventRenderer`. complexity: [medium]
- [ ] T8.3 Extract the kind-to-component lookup into a shared method `Pito::Stream::EventRenderer.component_for(event) -> ViewComponent::Base` so both the broadcaster and the view use the same code path. complexity: [medium]
- [ ] T8.4 Keep the hardcoded sample events under `lib/pito/sample/chat_shell.rb` (from Plan 1 U6.2) — but seed them into the DB on first boot rather than rendering inline. Add a Rake task `bin/rails pito:sample:seed` that creates one Conversation + sample Events. complexity: [medium]
- [ ] T8.5 In a dev-only initializer, run the seed once if `Conversation.none?` (so a fresh `db:reset` produces a populated demo state). complexity: [low]
- [ ] T8.6 Smoke test: visit `/`, see sample events. POST `/chat` with `/help` (via the chatbox). See echo + assistant text appended. Refresh `/`. Verify the new events appear in the same order. complexity: [manual]
- [ ] T8.7 Commit: `[skipci] S8: scrollback re-renders from persisted events`. complexity: [manual]

## S9 — Example handler: `Pito::Slash::Handlers::Help` end-to-end

> The one handler this plan wires fully. Returns hardcoded help text by listing the registry.

- [ ] T9.1 Create `app/services/pito/slash/handlers/help.rb`. Class `Pito::Slash::Handlers::Help < Pito::Slash::Handler`. `self.verb = :help`. complexity: [low]
- [ ] T9.2 `#call` returns `Pito::Slash::Result::Ok.new(events: [...])`. The events array contains one `assistant_text` event with payload `{ message_key: "pito.slash.help.intro", message_args: { count: Pito::Slash::Registry.size } }`, followed by one `assistant_text` event per registered handler listing its verb (using `message_key: "pito.slash.help.entry"` and `message_args: { verb: ..., description_key: ... }`). complexity: [medium]
- [ ] T9.3 Add a `self.description_key` class attribute to `Pito::Slash::Handler` so each handler advertises an i18n key for its one-line description. `Help` sets it to `"pito.slash.help.descriptions.help"`. complexity: [low]
- [ ] T9.4 Register `Help` in `Pito::Slash::Registry.register_all!`. complexity: [low]
- [ ] T9.5 Verify in console: `Pito::Slash::Dispatcher.call(input: "/help", conversation: Conversation.singleton)` returns a `Result::Ok` with the expected events. complexity: [manual]
- [ ] T9.6 RSpec service spec for `Pito::Slash::Handlers::Help`: returns Ok; produces N+1 events where N is the registry size. complexity: [low]
- [ ] T9.7 Smoke test: type `/help` in the chatbox at `/`, press Enter. See `/help` echoed (orange border) and the help response appended (no border). Refresh. Same content reappears. complexity: [manual]
- [ ] T9.8 Commit: `[skipci] S9: /help handler end-to-end`. complexity: [manual]

## S10 — Error path: unknown verb event

> Typing `/nope` produces a real error event in the scrollback.

- [ ] T10.1 Confirm `Pito::Slash::Dispatcher` already returns `Result::Error` for unknown verbs (per S6.2). No code change here, just verification. complexity: [manual]
- [ ] T10.2 Verify `ChatController#create` materializes the Error into an `error` Event (per S7.3). No code change here. complexity: [manual]
- [ ] T10.3 Smoke test: type `/nope` in the chatbox. See echo + red-bordered error: "Unknown command: /nope". complexity: [manual]
- [ ] T10.4 RSpec request spec extension: POST `/chat` with input `/nope` creates an error Event with `kind: :error`, `payload[:message_key] == "pito.slash.errors.unknown_verb"`. complexity: [low]
- [ ] T10.5 Smoke test: type a garbled input like `/` (slash with no verb). See echo + error event "Couldn't parse command: /". complexity: [manual]
- [ ] T10.6 Commit: `[skipci] S10: unknown-verb + parse-failed error events`. complexity: [manual]

## S11 — Confirmation primitive (structural only)

> No real confirmation flow yet. Just prove the data type round-trips through the pipeline so future handlers can return it.

- [ ] T11.1 Add a temporary fixture handler `Pito::Slash::Handlers::EchoConfirm` registered under verb `:confirm_demo`. Its `#call` returns `Result::NeedsConfirmation.new(prompt_key: "pito.slash.confirm_demo.prompt", prompt_args: {}, command_text: "/confirm_demo")`. complexity: [low]
- [ ] T11.2 Verify `ChatController#create` materializes a NeedsConfirmation into a `confirmation_prompt` Event with the right payload (per S7.3). complexity: [manual]
- [ ] T11.3 Smoke test: type `/confirm_demo`. See echo + yellow-bordered confirmation_prompt event. (No interaction — that's a later plan.) complexity: [manual]
- [ ] T11.4 RSpec service spec for `EchoConfirm`: returns `Result::NeedsConfirmation` with the expected fields. complexity: [low]
- [ ] T11.5 Mark `EchoConfirm` clearly as `# DEMO — remove once a real confirmation-requiring handler exists` in a top-of-file comment. It stays in tree as the canonical example until then. complexity: [low]
- [ ] T11.6 Commit: `[skipci] S11: confirmation primitive (structural)`. complexity: [manual]

## S12 — i18n keys for Plan 2

> Every user-facing string. No inline strings anywhere.

- [ ] T12.1 Create `config/locales/pito/slash/en.yml`. Add keys: `pito.slash.help.intro`, `pito.slash.help.entry`, `pito.slash.help.descriptions.help`, `pito.slash.errors.unknown_verb`, `pito.slash.errors.parse_failed`, `pito.slash.confirm_demo.prompt`. complexity: [low]
- [ ] T12.2 Suggested copy: `intro: "%{count} commands available."`; `entry: "/%{verb} — %{description}"` with description resolved by interpolating `t(description_key)`; `unknown_verb: "Unknown command: /%{verb}. Type /help for the command list."`; `parse_failed: "Couldn't parse command: %{raw}"`; `confirm_demo.prompt: "Confirm running this demo command?"`. complexity: [low]
- [ ] T12.3 Audit every file added/modified in Plan 2 — no inline user-facing strings. Run `git diff plan-01-ui...HEAD -- '*.rb' '*.erb' | grep -E '\"[A-Z][a-z]'` and resolve each hit. complexity: [medium]
- [ ] T12.4 Boot `bin/dev`, exercise `/help`, `/nope`, `/`, `/confirm_demo`. No `translation missing` placeholders. complexity: [manual]
- [ ] T12.5 Commit: `[skipci] S12: i18n keys for slash core`. complexity: [manual]

## S13 — AGENTS.md additions

> Document the conventions Plan 2 introduces so later plans don't drift.

- [ ] T13.1 Add section `## Dispatch core` to AGENTS.md describing: single `POST /chat` endpoint, leading-`/` branches to Slash, no-leading-`/` branches to Chat (Plan 3), `current_conversation` helper, broadcast via `Pito::Stream::Broadcaster`. complexity: [medium]
- [ ] T13.2 Add section `## Slash conventions` describing: `Pito::Slash::*` namespace, handlers under `app/services/pito/slash/handlers/`, every handler returns a `Result`, registry registered in `config/initializers/pito.rb`, every handler exposes `verb` and `description_key`. complexity: [medium]
- [ ] T13.3 Add section `## Event payload conventions` describing: structured payloads only, i18n keys + args (never rendered strings), `Event::KINDS` enumeration, re-render through ViewComponents on every read. complexity: [medium]
- [ ] T13.4 Add section `## Cross-system invariants` listing the Slash/Chat isolation rules from the Cross-plan invariants table above. complexity: [low]
- [ ] T13.5 Commit: `[skipci] S13: AGENTS.md dispatch + slash + event conventions`. complexity: [manual]

## S14 — Verification & cleanup

> Final pass. Confirm Plan 2 delivered what it promised.

- [ ] T14.1 `bundle exec rspec` is green across model, lib, service, and request specs added by Plan 2. complexity: [manual]
- [ ] T14.2 `bin/dev` boots cleanly; visit `/`; sample events appear. complexity: [manual]
- [ ] T14.3 Type `/help` → echo + help response appears via Cable broadcast. Refresh `/` → same events persist. complexity: [manual]
- [ ] T14.4 Type `/nope` → echo + red error event. complexity: [manual]
- [ ] T14.5 Type `/confirm_demo` → echo + yellow confirmation prompt event. complexity: [manual]
- [ ] T14.6 `git grep -n "Pito::Chat" lib/pito/slash app/services/pito/slash app/controllers/chat_controller.rb` — should return zero hits (the isolation invariant). complexity: [manual]
- [ ] T14.7 `git grep -nE '"[A-Z][a-z][^"]*"' app/services/pito/slash` — every match is an i18n key or a non-user-facing string. complexity: [manual]
- [ ] T14.8 Tag: `git tag v0.2.0-slash-core`. complexity: [manual]
- [ ] T14.9 Commit: `[skipci] S14: slash core verification`. complexity: [manual]

---

## Open follow-ups (Plan 3+ and beyond)

These are explicitly NOT in Plan 2:

- The Chat branch of `ChatController#create` (Plan 3).
- Chat parser, registry, handlers, refinement turn model (Plan 3).
- Real domain handlers: `/publish`, `/schedule`, `/connect`, `/authenticate`, `/config` (later plans, one per domain).
- The actual confirmation flow — a real handler that triggers, accepts `/confirm`/`/cancel`, completes the action. (Later plan.)
- Multi-conversation routing: `current_conversation` becomes per-tab/per-URL; new-session creation; session picker. (Later plan.)
- Ctrl+K (or Ctrl+P) command palette UI (later plan; palette components exist as static visuals from Plan 1).
- Slash command autocomplete / suggestions while typing.
- Syntax highlighting of the input.
- History navigation (↑/↓ through previous inputs).
- Multi-step dialogs with masked input (e.g. `/authenticate` with 6 TOTP boxes).
- Real OAuth flow for `/connect`.
- Per-handler authorization checks.
- Rate limiting on `POST /chat`.
- Localization beyond English.

## How to use this plan

Same as Plan 0 and Plan 1:

1. Pick the next unchecked task in phase order.
2. Read the `complexity:` hint; pick the cheapest model that fits the tier.
3. Dispatch as a sub-agent (in OpenCode, Claude Code, etc.) OR do by hand.
4. Verify (read the diff, run `bin/dev`, exercise the affected flow).
5. Check the box. Move on.
6. Commit at the end of each phase using the suggested `[skipci]` title.
7. If a task feels bigger than 5 minutes, split it.
