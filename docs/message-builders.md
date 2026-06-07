# Plan: Pito::MessageBuilder — decouple message chrome from content

> Status: Drafted (not audited). Branch `themes`, current branch, no tags. Don't
> start a phase before the Audited line is stamped.

## Sign-off
- [x] Drafted
- [x] Audited — approved by the user for execution; every builder + refactor ships with specs.

## North star

Every chat / slash / hashtag / follow-up message is produced by a
`Pito::MessageBuilder::*` builder — one per message type — that returns a
string-keyed payload Hash. Handlers and jobs ONLY: resolve the domain object,
call the builder, and emit an event with the correct chrome `kind`. Zero inline
payload construction anywhere. Chrome (the border/wrapper) stays a pure function
of the event `kind` (`Event::{System,Enhanced,Confirmation,Error}`); content is
a pure function of the builder. The two never mix.

## Locked decisions

| Topic | Decision |
| --- | --- |
| Namespace | All builders live under `Pito::MessageBuilder::<Domain>::<Name>` (e.g. `Game::Detail`, `Channel::List`). |
| Shape | Each builder is a module with `module_function`; public `.call(...) -> Hash` returning a string-keyed payload. |
| Chrome vs content | Builders set ONLY content + flags (`body`, `html`, `table_rows`, `sections`, `text`) + follow-up stamping. They NEVER choose the `kind`/border — the caller does. |
| Follow-up stamping | `Pito::FollowUp.make_followupable!` lives INSIDE the builder for follow-up-able messages (handlers stop calling it directly). |
| Existing builders | Migrate `Game::DetailMessage`, `Game::EnhancedMessage`, `Game::DeleteConfirmation` INTO the namespace (rename + repoint). |
| Copy | All user-facing strings stay `Pito::Copy` (unchanged). |
| Helpers | `MessageBuilder::Helpers` provides `render_component(c)` + `html_payload(body:, **extra)` to kill duplication. |
| Verify | Per phase: `bundle exec rspec` (NOT bin/rspec) + `bin/rubocop` + `bin/rails zeitwerk:check` + `rake pito:copy:audit` 0-below. |

## Phase index
- P0 — MessageBuilder namespace + shared helpers
- P1 — Migrate the 3 existing builders into the namespace
- P2 — List message builders (games, channels)
- P3 — Confirmation builders (delete reuse, resync, reindex, disconnect)
- P4 — Theme list message builder
- P5 — Enhanced recommendations mutation builder
- P6 — Text / Error message helpers + sweep remaining inline payloads
- P7 — Gate (no inline payloads) + finalize

---

## P0 — MessageBuilder namespace + shared helpers
- [x] T0.1 Create `app/services/pito/message_builder.rb` declaring the `Pito::MessageBuilder` module + doc-block. complexity: [low]
- [x] T0.2 Add `Pito::MessageBuilder::Helpers#render_component(component)` wrapping `ApplicationController.renderer.render(component, layout: false)`. complexity: [low]
- [x] T0.3 Add `Helpers#html_payload(body:, **extra)` returning `{ "body" => body, "html" => true }.merge(extra.stringify_keys)`. complexity: [low]
- [x] T0.4 Run `bin/rails zeitwerk:check` + `bin/rubocop`. complexity: [manual]
- [x] T0.5 Commit: `Add Pito::MessageBuilder namespace + shared helpers`. complexity: [manual]

## P1 — Migrate the 3 existing builders into the namespace
- [x] T1.1 Move `Pito::Game::DetailMessage` → `Pito::MessageBuilder::Game::Detail` (file + module). complexity: [low]
- [x] T1.2 Move `Pito::Game::EnhancedMessage` → `Pito::MessageBuilder::Game::Enhanced`. complexity: [low]
- [x] T1.3 Move `Pito::Game::DeleteConfirmation` → `Pito::MessageBuilder::Game::DeleteConfirmation`. complexity: [low]
- [x] T1.4 Repoint callers: `chat/handlers/show.rb`, `chat/handlers/list.rb`, `chat/handlers/delete.rb`, `follow_up/handlers/game_detail.rb`, `follow_up/handlers/game_list.rb`, `jobs/game_import_job.rb`. complexity: [high]
- [x] T1.5 Rename the moved specs + update constant references. complexity: [low]
- [x] T1.6 Run `bundle exec rspec` + `bin/rails zeitwerk:check`. complexity: [manual]
- [x] T1.7 Commit: `Move Game detail/enhanced/delete-confirm builders under Pito::MessageBuilder`. complexity: [manual]

## P2 — List message builders (games, channels)
- [ ] T2.1 Create `Pito::MessageBuilder::Game::List` (intro + id/title `table_rows` + `make_followupable!(game_list)`). complexity: [low]
- [ ] T2.2 Create `Pito::MessageBuilder::Channel::List` (intro + `Channel::ListComponent` html via helper). complexity: [low]
- [ ] T2.3 Reduce `Chat::Handlers::List#call` games branch to call the builder. complexity: [low]
- [ ] T2.4 Reduce `Chat::Handlers::List#list_channels` to call the builder. complexity: [low]
- [ ] T2.5 Update `spec/services/pito/chat/handlers/list_spec.rb` + add the two builder specs. complexity: [low]
- [ ] T2.6 Run `bundle exec rspec`. complexity: [manual]
- [ ] T2.7 Commit: `Extract Game::List + Channel::List message builders`. complexity: [manual]

## P3 — Confirmation builders (delete reuse, resync, reindex, disconnect)
- [ ] T3.1 Replace the inline rm/delete confirmation in `follow_up/handlers/game_detail.rb` with `MessageBuilder::Game::DeleteConfirmation`. complexity: [low]
- [ ] T3.2 Create `Pito::MessageBuilder::Game::ResyncConfirmation`; use it in game_detail resync. complexity: [low]
- [ ] T3.3 Create `Pito::MessageBuilder::Game::ReindexConfirmation`; use it in `follow_up/handlers/game_enhanced.rb` reindex. complexity: [low]
- [ ] T3.4 Create `Pito::MessageBuilder::Channel::DisconnectConfirmation`; use it in `slash/handlers/disconnect.rb`. complexity: [low]
- [ ] T3.5 Update the four handlers' specs. complexity: [low]
- [ ] T3.6 Run `bundle exec rspec`. complexity: [manual]
- [ ] T3.7 Commit: `Extract resync/reindex/disconnect confirmation builders; reuse delete-confirm`. complexity: [manual]

## P4 — Theme list message builder
- [ ] T4.1 Create `Pito::MessageBuilder::Theme::List` (body + Dark/Light `sections` + marker value2 + `make_followupable!(theme_list)`). complexity: [low]
- [ ] T4.2 Reduce `Slash::Handlers::Theme#list_themes` to call the builder. complexity: [low]
- [ ] T4.3 Update `spec/services/pito/slash/handlers/theme_spec.rb`. complexity: [low]
- [ ] T4.4 Run `bundle exec rspec`. complexity: [manual]
- [ ] T4.5 Commit: `Extract Theme::List message builder`. complexity: [manual]

## P5 — Enhanced recommendations mutation builder
- [ ] T5.1 Extract the game_enhanced `similar`/`channel` segment rebuild (score-bar segments + `rebuild_enhanced_payload`) into `Pito::MessageBuilder::Game::EnhancedSegments`. complexity: [high]
- [ ] T5.2 Reduce the game_enhanced handler mutations to call the builder. complexity: [low]
- [ ] T5.3 Update `spec/services/pito/follow_up/handlers/game_enhanced_spec.rb`. complexity: [low]
- [ ] T5.4 Run `bundle exec rspec`. complexity: [manual]
- [ ] T5.5 Commit: `Extract Game::EnhancedSegments mutation builder`. complexity: [manual]

## P6 — Text / Error message helpers + sweep remaining inline payloads
- [ ] T6.1 Add `Pito::MessageBuilder::Text.call(key_or_text, **args)` → `{ "text" => resolved }`. complexity: [low]
- [ ] T6.2 Add `Pito::MessageBuilder::Error.call(message_key:, message_args: {})` → error payload. complexity: [low]
- [ ] T6.3 Replace inline `{ text: Pito::Copy.render(...) }` / error payloads across chat/slash/follow-up handlers with the helpers. complexity: [high]
- [ ] T6.4 Run `bundle exec rspec`. complexity: [manual]
- [ ] T6.5 Commit: `Add Text/Error message helpers; sweep inline text payloads`. complexity: [manual]

## P7 — Gate (no inline payloads) + finalize
- [ ] T7.1 Grep-gate: no `payload:\s*{` / `payload\s*=\s*{` carrying body/html/sections/table_rows outside `app/services/pito/message_builder/`. complexity: [low]
- [ ] T7.2 Verify `jobs/game_import_job.rb` no longer calls `make_followupable!` directly (it lives in the builders). complexity: [low]
- [ ] T7.3 Run full `bundle exec rspec` + `bin/rubocop` + `bin/rails zeitwerk:check` + `rake pito:copy:audit` (0-below). complexity: [manual]
- [ ] T7.4 Add an `## Message builders` note to `AGENTS.md` (chrome=kind, content=`MessageBuilder::*`, one builder per message type). complexity: [low]
- [ ] T7.5 Commit: `Document the MessageBuilder paradigm in AGENTS.md`. complexity: [manual]

## Critical files

Reuse / fold in: `app/services/pito/game/{detail_message,enhanced_message,delete_confirmation}.rb` (→ namespace), `app/components/pito/{game/detail_component,game/enhanced_component,channel/list_component}.*`, `app/services/pito/follow_up.rb` (`make_followupable!`).
Touch: `app/services/pito/chat/handlers/{list,show,delete}.rb`, `app/services/pito/follow_up/handlers/{game_detail,game_list,game_enhanced,confirmation}.rb`, `app/services/pito/slash/handlers/{theme,disconnect}.rb`, `app/jobs/game_import_job.rb`.
New: `app/services/pito/message_builder.rb` + `app/services/pito/message_builder/**` (helpers + Game/Channel/Theme builders).

## Execution notes
Sonnet-first per task; escalate on repeated failure. Plan-runner discipline:
three-state checkboxes per transition; each phase's `Commit:` flips `[x]` before
`git commit`, staging this plan doc alongside the code; plain commit messages
(no `[skipci]`, no co-author); push; CI green. Run on `themes` (no new branch).
