# Beta6 — Gaps: lock contracts (doc-blocks) + comprehensive specs (Rails + JS)

Live progress log for the post-Beta hardening pass. Tick each phase as it lands.

## Context

The Beta reboot merged to `main` (PR #56). Two gaps to close before new features:

1. **Contracts aren't locked in.** Base classes lack top-level doc-blocks stating
   their contract, so subclass authors reverse-engineer expectations. Principle:
   **document the contract on the base; document specifics on the classes that
   extend it.**
2. **Spec coverage gaps + thin spots** (Rails ~67% line ratio; 52 unspecced
   services, 36 jobs, 11 models, missing edge cases). JS: 3/31 controllers tested.

## Decisions

- **Interleave per area** (doc-blocks + specs together, per phase).
- **Comprehensive / multi-phase.**
- **All testable JS** (skip browser-only animation: `home_transition`, `logout`,
  `audio` playback, `type_fx` frames, `terminal_caret` visual wrap — pure logic only).
- **Sonnet-dispatched, per-area commits** (escalate to Opus on repeated failure);
  on-branch sequential (no worktrees — stale-base bug); commit + push per area;
  PR CI green throughout.

## Branch / merge

Work on **`beta6-gaps`** off `main` (squash-only, protected); per-area commits;
PR; squash-merge at the end.

## Conventions to reuse

- **Doc-block exemplars:** `lib/pito/slash/parser.rb`, `lib/pito/grammar/normalizer.rb`,
  `app/services/pito/action.rb` + `action_dispatcher.rb`,
  `app/services/pito/notifications/formatter/templates/base.rb`.
- **RSpec:** FactoryBot + `spec/models/factories_spec.rb`; TOTP helper in
  `spec/requests/resume_spec.rb`; `WebMock`; `have_broadcasted_to`; grammar
  registry setup in `rails_helper`. `render_inline` + Nokogiri (not Capybara).
  Run `bundle exec rspec` (never `bin/rspec`).
- **Vitest:** `vitest.config.js` (jsdom + aliases) + the Stimulus-Application mount
  pattern in `spec/javascript/history_controller.test.js`. Run `npm test`.

## Per-phase Definition of Done

- [ ] Doc-blocks: base states the contract (responsibilities, required overrides,
      inputs/outputs, invariants); subclasses state specifics; no base-level
      contract duplicated across subclasses.
- [ ] New specs + deepened thin specs with the area's edge cases/scenarios.
- [ ] `bundle exec rspec` green · `npm test` green · `bin/rubocop` clean ·
      `node --check` changed JS.
- [ ] Commit + push; PR CI (`rails`, `js`, `prettier`) green before next phase.

## Phases

### [x] Phase A — Language core: lex / grammar / parse / autocomplete

- Doc-blocks: `Lex::Lexer` (token types, URL/@/string/whitespace, `preceded_by_space`),
  `Grammar::Registry` (dual specs+vocabularies store, boot), `Grammar::Vocabulary`
  (resolution canonical→synonym→dynamic→nil, fillers, members), `Grammar::HandlerDsl`.
  Verify Parser/Normalizer/Spec/Slot/Token (already good).
- Rails specs (deepen): lexer (multi-space, tab, NBSP, trailing space, space-join
  regression); normalizer (`when:` slots, introducers, repeatable, fillers);
  autocomplete `Engine` (multi-word ghost, cursor start/mid/end, provider+kv,
  no-match); slash `Dispatcher` `--help` (subcommand, `-h`, mid-arg, unknown, case).
- JS: `autosuggest_controller`.

### [x] Phase B — Command dispatch: handlers + action bus

- Doc-blocks: `Slash::Handler` base + subclasses (config/help/disconnect) + chat/
  hashtag handler bases/subclasses.
- Rails specs: config (getter/setter/toggle + provider `--help`), disconnect, help;
  chat/hashtag dispatch edges; `ActionDispatcher`/`ActionRegistry`.
- JS: `command_palette`, `chat_form`, `rename`, `draft`.

### [x] Phase C — Stream / broadcast / events + sidebar JS

- Doc-blocks: `Stream::Broadcaster`, `Stream::EventRenderer`.
- Rails specs: broadcaster (emit/replace/auth/settings/global + `have_broadcasted_to`),
  event_renderer (each kind, unknown raises); cross-instance broadcast assertions.
- JS: `resume`, `notifications_nav`, `scrollback`, `dots`/`done_dispatch`/`turn_complete`.

### [x] Phase D — Notifications: delivery + formatter + model + jobs

- Doc-blocks: `DeliveryChannel::Base` (override contract + 2xx/429+5xx/4xx semantics),
  `Formatter::Templates::Base` (title/body/url; payload-only), `Notifications::Source`.
- Rails specs: delivery channels (404/timeout/429/5xx/4xx/malformed, WebMock);
  each formatter template; `Builder`/`Scheduler`; `Notification` model; jobs
  `NotificationDeliver` + deepen `CleanupNotificationsJob`.
- JS: `chatbox_hints`.

### [x] Phase E — Auth / session

- Doc-blocks: `auth/*` base/contract; `Current`.
- Rails specs: `TotpVerifier` (valid/format/replay/drift/seed-missing), `TotpEnroller`,
  `SessionCookie`, `ChatLogin` (throttle), `backoff_calculator`; login/logout/OAuth
  request edges.
- JS: `auth.js`, `cable_health`.

### [x] Phase F — Domain models + sync jobs

- Doc-blocks: `ApplicationRecord`/`ApplicationJob` brief; `Current`.
- Rails specs: `YoutubeConnection`, `Video`, `Genre`, `Company`, join tables,
  `Current`; jobs `ChannelInfoJob`, `ChannelAnalyticsSync`, `VideoAnalyticsSync`,
  `BulkSync`, `BulkDelete`, `GameIgdbSync`, `VideoPublish`, `ConfirmationDispatch`;
  deepen `SyncChannelStatsJob`.

### [x] Phase G — Component base + remaining services + remaining JS

- Doc-blocks: `ApplicationComponent` (component conventions) + key event components
  (system/error/echo).
- Rails specs: `recommendation/*`, `search/engine`, `schedule`, remaining formatters
  (`ttb_hours`, `webhook_url_mask`), `external_api_tracker/*`, `git_revision`,
  `hashtag/handlers/reply`; any component still without a spec.
- JS: `settings.js`, `ready.js`, `expand_controller`, `thinking`, `platform_key`,
  `clipboard`, `turbo_actions`; pure-logic only for `type_fx`/`terminal_caret`/`audio`.
  Skip `home_transition`/`logout` choreography (E2E-only).

## Final

- [ ] PR CI all green → squash-merge → delete `beta6-gaps`.

## Risks / notes

- No git worktrees for agents (stale-base bug); on-branch sequential, verify HEAD,
  never reset/force-push.
- Some services may be genuine no-ops/stubs — confirm behavior before specing; skip
  - note rather than testing emptiness.
- JS tests stay logic-focused; browser-only animation/layout is out of unit scope.
- Phases independent / re-orderable; A→G is roughly highest-risk core first.
