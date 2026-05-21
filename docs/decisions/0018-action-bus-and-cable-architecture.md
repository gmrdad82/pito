# ADR 0018 — Action bus + cable architecture: registry, trigger, channel grammar

## Status

Proposed — locked 2026-05-21 in response to the FB-126 / FB-178 /
FB-126→FB-180 spaghetti surfacing during /settings Beta 4 closeout.
Gates every cross-stack action work for /games, /channels, MCP, and CLI
from this point forward.

## Context

/settings ships a confirmation flow for `[reindex]` (FB-126) wired
directly from a Stimulus controller to a Rails POST endpoint. The
`:command` palette (FB-178) ships an alternate path that re-implements
the same brand-aware copy, the same confirmation step, the same
endpoint, and a near-duplicate of the same fetch shape. MCP will need a
third copy when `reindex_records` lands; the `pito` CLI a fourth when
`pito reindex meilisearch` lands.

Four (likely five) parallel paths to the same Rails action, each with
its own copy / i18n key / confirmation contract / response handling, is
the spaghetti this ADR forecloses. /games + /channels are much bigger
surfaces — `[ delete ]`, `[ sync ]`, `[ unstar ]`, `[ rename ]`, bundle
member ops, video bulk ops — and the cost of one-off-wiring per action
× per consumer (web click, leader menu, palette, MCP, CLI) scales
quadratically. Locking the architecture now means every new action
touches one canonical definition and the consumers fall out for free.

A second concern surfaces at the same time: cable broadcasts are
spreading without a single naming + ownership rule. The Top Status Bar
(TST) listens for global sync / sidekiq stats; panel-scoped reindex
flows broadcast to sub-panel channels; future progress streams will
multiply the surface. ADR 0017 declared the `pito:<screen>:<panel>`
grammar; this ADR pins the operational table of channels in use today,
fixes the macro for jobs to broadcast to a panel, and locks the
TST-global vs panel-scoped split so the two never collide.

Three concerns this ADR addresses together:

1. **Action fragmentation** — palette vs click vs leader-menu vs
   MCP vs CLI all re-implementing the same trigger contract.
2. **Confirmation contract drift** — each consumer reading its own
   copy / i18n keys / danger flag.
3. **Cable channel ownership** — TST-global vs panel-scoped vs
   sub-panel-scoped, with Sidekiq middleware coverage rules.

## Decision

A three-layer architecture: **Action** (Ruby definition), **Trigger**
(JS dispatcher + Rails dispatcher), **Cable** (channel grammar +
broadcast macro). Each layer is a single canonical surface; every
consumer routes through it.

### Layer 1 — Action registry

`Pito::ActionRegistry` is the canonical source of every user-triggerable
action in pito. Lives under `app/services/pito/action_registry.rb` and
loads at Rails boot. Each entry is a `Pito::Action` struct with:

```ruby
Pito::Action = Struct.new(
  :name,         # Symbol — :reindex_meilisearch, :revoke_session, ...
  :path,         # Proc resolving to a Rails route, or symbol named route
  :method,       # :post (default), :patch, :delete
  :confirmation, # nil (no confirm) or { title:, message:, danger: bool }
  :i18n_key,     # String — "tui.commands.reindex_meilisearch"
  :cable_panel,  # nil or String — canonical panel channel this action affects
  :scopes,       # Array<Symbol> — :web, :palette, :leader, :mcp, :cli
  keyword_init: true
)
```

Definitions live in `app/services/pito/actions/*.rb`, one file per
action or one file per logical group (e.g.
`app/services/pito/actions/reindex.rb` declares both
`:reindex_meilisearch` and `:reindex_voyage`). The registry indexes by
`name`.

Example:

```ruby
Pito::Action.define(:reindex_meilisearch,
  path:         -> { settings_stack_meilisearch_reindex_path },
  method:       :post,
  confirmation: { title: "reindex Meilisearch?",
                  message: "this rebuilds the search index. it may take a few minutes.",
                  danger:  true },
  i18n_key:     "tui.commands.reindex_meilisearch",
  cable_panel:  "pito:settings:stack:meilisearch",
  scopes:       %i[web palette leader mcp cli])
```

The registry is **the** source of truth for: which actions exist; what
path each one POSTs to; whether each one requires confirmation and what
the copy is; which panel each one cable-broadcasts to; which surfaces
the action is exposed on (`scopes` controls palette visibility, leader
menu inclusion, MCP tool exposure, CLI subcommand listing).

The registry serializes a JS-readable subset (name, path, method,
confirmation, i18n_key) into a `<meta name="pito-actions"
content="...JSON...">` tag in the layout. The browser reads this once
at first paint; later updates re-emit the meta tag via a turbo-frame
refresh of the head shell.

### Layer 2 — Trigger dispatcher

**JS side — `Pito.dispatchAction(name, payload = {})`.** Lives in
`app/javascript/pito/action.js`. The single entry point every JS
consumer (Stimulus controllers, palette, leader menu) uses to fire an
action. Flow:

1. Reads the action definition from the serialized `<meta
   name="pito-actions">` registry (cached at module load).
2. If `confirmation` is present, mounts (or shows) the
   `Tui::ConfirmationDialogComponent` instance for that action, wiring
   the title / message / danger flag from the registry. The dialog
   resolves via `[ confirm ] / [ cancel ]` to either continue or
   abort.
3. On continue, builds a Turbo-form POST against `action.path` with the
   CSRF token from `meta[name=csrf-token]` and any `payload` body. The
   form is Turbo-driven (no `data-turbo="false"`); the response is
   expected to be `204 No Content` — cable handles the UI update.
4. On `204`, the dispatcher resolves its promise (cable will populate
   the panel asynchronously). On non-`204` (e.g. `409 Conflict`,
   `422 Unprocessable`), the dispatcher reads the response body
   (a JSON envelope `{ kind: "error", payload: { message:, code: } }`)
   and surfaces it through the same indicator slot the cable would
   have updated. **No HTML error pages reach the user inside a
   panel-scoped flow.**

Every JS-side consumer routes through this one function:

- `[reindex]` Stimulus action — `click → Pito.dispatchAction(:reindex_meilisearch)`
- `:command` palette enter — `Pito.dispatchAction(palette.selected_action)`
- Leader-menu shortcut — `Pito.dispatchAction(leader.bound_action)`
- Future MCP-web bridge — same call

No consumer crafts its own `fetch` / `turbo:submit`; no consumer
embeds its own copy or confirmation step. The 4-deep duplication
forecloses.

**Rails side — `Pito::ActionDispatcher`.** Lives in
`app/services/pito/action_dispatcher.rb`. Used by MCP and CLI (which
do not have a browser to mount the JS dialog), and by any server-side
call site that needs to invoke an action with the same contract.
Signature:

```ruby
Pito::ActionDispatcher.call(name, user:, confirm: false, payload: {})
```

The dispatcher reads the registry, validates `confirm == true` when
`confirmation` is present (returns a `requires_confirmation` envelope
otherwise — the two-step `confirm` flag pattern from CLAUDE.md "Hard
rules"), then invokes the action's controller path via internal
routing (or directly calls the underlying service / job for MCP /
CLI consumers that want to skip the controller layer).

### Layer 3 — Cable channel grammar

The canonical channel table — every broadcast in pito belongs to
exactly one of these patterns:

| Channel pattern | Scope | Who subscribes | Who broadcasts | Payload kind examples |
|---|---|---|---|---|
| `pito:status_bar` | Global | TST on every authenticated screen | Sidekiq middleware (start + finish, every job, always) | `data` (sidekiq counters), `data` (sync_state) |
| `pito:<screen>:<panel>` | Panel | Panel ViewComponent via `turbo_stream_from` or Stimulus | Action's controller or job (opt-in via `broadcasts_to_panel` macro) | `idle`, `indeterminate`, `progress`, `complete`, `error`, `data` |
| `pito:<screen>:<panel>:<sub_panel>` | Sub-panel | Sub-panel ViewComponent | Same as panel, narrower channel | Same kinds, narrower target |

Examples in use today:

- `pito:status_bar` — TST live data; payloads carry `sync_state`
  (`"syncing"` / `"idle"`), `workers` count, full `sidekiq` counters
  object (`{ b, e, r, s, d }`), and `clock` (ISO timestamp).
- `pito:settings:notifications` — notifications panel toggle saves.
- `pito:settings:security` — sessions table updates (revoke).
- `pito:settings:stack:meilisearch` — Meilisearch sub-panel reindex
  progress.
- `pito:settings:stack:voyage` — Voyage sub-panel reindex progress.

Per the ADR 0017 envelope, every payload carries `{ kind, payload, ts }`.

**Sidekiq middleware coverage rule.** The
`StatusBarBroadcastMiddleware` (mounted in
`config/initializers/sidekiq.rb`) broadcasts to `pito:status_bar` on
job START and END for **every** Sidekiq job, always — no opt-in, no
opt-out. The TST's sync indicator and busy counter reflect the live
queue state at all times.

**Panel-scoped opt-in macro.** Job classes that want to broadcast to a
panel beyond the global TST update declare it via:

```ruby
class MeilisearchReindexJob
  include Sidekiq::Job
  broadcasts_to_panel "pito:settings:stack:meilisearch"
  # ...
end
```

The macro wires panel-scoped `kind: indeterminate` on `before_perform`,
`kind: progress` via job-emitted broadcasts, `kind: complete` on
`after_perform`, `kind: error` on retry exhaustion. The macro reads
the canonical channel name from `Pito::ActionRegistry` when the action
that triggered the job links to a `cable_panel` — preferring registry
lookup over a hard-coded literal so renames stay coherent.

Controllers similarly broadcast via:

```ruby
Pito::CableBroadcaster.call(
  "pito:settings:stack:meilisearch",
  kind: :indeterminate,
  payload: { label: "queued" }
)
```

`Pito::CableBroadcaster` enforces the envelope (`{ kind, payload, ts }`)
so consumers can't broadcast raw shapes.

### Cross-stack consumers

Every consumer reads from `Pito::ActionRegistry`. The fork point is
**where**, not **what**:

| Consumer | Reads | Renders |
|---|---|---|
| Web HTML link | `Pito::ActionRegistry[:reindex_meilisearch]` | `Tui::ActionLinkComponent.new(name: :reindex_meilisearch)` — renders `[reindex]` with the registry's `i18n_key` for label, Stimulus action `pito-action#dispatch`, data attribute carrying the action name |
| Palette command | `Pito::ActionRegistry.for_scope(:palette, screen:)` | Each action renders as a palette row; selecting fires `Pito.dispatchAction(name)` |
| Leader menu | `Pito::ActionRegistry.for_scope(:leader, screen:)` | Each action's bound key fires `Pito.dispatchAction(name)` |
| MCP tool | `Pito::ActionRegistry[:reindex_meilisearch]` | `reindex_records` MCP tool reads the registry's `confirmation` contract; respects `confirm: bool` arg per CLAUDE.md "Hard rules"; invokes `Pito::ActionDispatcher.call(name, user:, confirm: true)` |
| CLI subcommand | `Pito::ActionRegistry[:reindex_meilisearch]` | `pito reindex meilisearch` reads the registry; in-TUI confirmation overlay mirrors the JS dialog; invokes `Pito::ActionDispatcher` via the Rails JSON endpoint |

The registry is the seam. The brand-cap test, the i18n-key-presence
test, the cable-channel-naming test, all run once against the registry
and cover all five consumers.

### Spec contract

Every action registered in `Pito::ActionRegistry` MUST satisfy:

- `i18n_key` resolves to a non-empty string in `config/locales/`.
- If the action's `i18n_key` resolves to a label containing a brand
  name (Meilisearch, Voyage AI, Postgres, Redis, Slack, Discord,
  YouTube), the brand is capitalized per the "Brand names always
  capitalized" rule.
- `confirmation` is either `nil` or has all three keys (`title:`,
  `message:`, `danger:`); `danger` is `true` for any destructive
  action.
- `cable_panel` is either `nil` or matches the
  `pito:<screen>:<panel>[:<sub_panel>]` grammar.
- `scopes` is a non-empty array; every symbol in it is one of
  `%i[web palette leader mcp cli]`.

A single spec (`spec/services/pito/action_registry_spec.rb`) runs
these checks across every registered action — adding a new action
without satisfying the contract fails CI.

### Confirmation dialog as canonical component

`Tui::ConfirmationDialogComponent` (FB-124) is the single confirmation
surface. The JS dispatcher mounts it; the palette renders it via the
same component; the MCP and CLI surfaces use their stack's equivalent
(MCP returns `requires_confirmation` envelope, CLI overlays an in-TUI
confirmation). No surface re-implements the confirmation step.

## Consequences

### Easier

- **One i18n surface.** Every consumer reads the same `i18n_key`. A
  copy change in `en.yml` lands everywhere simultaneously.
- **One confirmation contract.** Edit the registry entry, every
  consumer's confirmation step updates.
- **MCP / CLI parity is automatic.** Adding an action to the registry
  with `scopes: %i[mcp cli]` exposes it on those surfaces without
  per-consumer code. Removing a surface is a `scopes` edit.
- **Brand-cap spec covers all consumers.** Currently every consumer
  needs its own brand-cap test; with the registry, one spec covers
  the lot.
- **Cable channel naming auditable.** Every action's `cable_panel`
  field shows up in the registry; drift detection is a single grep.
- **Sub-panel jobs broadcast to TST globally PLUS panel-specifically
  without manual wiring** — `broadcasts_to_panel` macro + Sidekiq
  middleware coverage rule mean adding a job is one line, not two
  broadcast call sites.

### Accepted costs

- **One more layer of indirection.** Reading the registry adds a step
  vs. inlining a `fetch` in a Stimulus controller. The trade is
  explicit; the spaghetti cost of NOT having the layer is documented
  in the Context section above.
- **Must remember to register.** A new action that bypasses the
  registry to wire its own POST in a Stimulus controller defeats the
  contract. Code review + the dispatch checklist (CLAUDE.md gate 5
  variant) catches this; the spec contract above fails CI if the
  registry omits an action that other surfaces already reference.
- **JS payload size grows linearly with action count.** The serialized
  registry meta tag carries every action's path + confirmation copy.
  At current scale (~20 actions across /settings + planned /games +
  /channels) this is negligible. If it ever crosses ~200 actions, the
  serialization moves to a per-screen lazy fetch.

## Migration plan

Refactor in this order. Each step lands as its own dispatch with the
spec contract green before the next step starts:

1. **`[reindex]` (Meilisearch + Voyage) — POC.** Currently the most
   spaghetti'd path (FB-126 + FB-178 + FB-180 + FB-153 + FB-154 + FB-155
   + FB-171 all touched the same flow). Migrate to registry first;
   verify the JS dispatcher + Rails dispatcher + cable broadcaster +
   `ConfirmationDialogComponent` integration end-to-end.
2. **`[update]` webhook flows (Slack + Discord).** Notifications panel
   `[update]` saves the webhook URL. Confirmation not required;
   straight POST → cable update.
3. **Sessions `[revoke]` (single + bulk).** Confirmation required;
   destructive flag set; broadcasts to `pito:settings:security`.
4. **/games actions (when /games starts).** Star toggle, delete, sync,
   bundle add/remove. Brand-cap test exercises platform names
   (PS5 / Switch 2 / Steam).
5. **/channels actions (when /channels starts).** Star toggle, sync,
   reconnect, disconnect. Brand-cap test exercises YouTube.
6. **MCP scope expansion.** Once the registry covers every web action,
   the MCP tool surface expands to expose `scopes: [:mcp]` actions
   automatically.
7. **CLI parity.** Same automatic expansion as MCP via `scopes: [:cli]`.

Steps 1-3 land inside Beta 4. Steps 4-5 fold into the F4 (/games)
and F5 (/channels) revamp dispatches. Steps 6-7 fold into the MCP /
CLI resumption work.

## Non-goals

- **Does NOT replace Turbo Stream rendering for view updates.** Turbo
  Streams remain the canonical way to swap a DOM fragment. The action
  bus governs the TRIGGER side (how an action is fired); Turbo +
  cable govern the UPDATE side (how the resulting DOM change reaches
  the panel).
- **Does NOT replace Stimulus controllers for keystrokes / cursor /
  scroll / leader-menu state.** Stimulus remains the JS organization
  unit. Stimulus controllers CALL `Pito.dispatchAction(name)` instead
  of crafting their own `fetch` — they don't disappear.
- **Does NOT introduce a new state-management framework.** No Redux,
  no Zustand, no MobX. The registry is read-only at the JS layer; all
  mutation flows through Rails + cable.
- **Does NOT cover non-action UI** (e.g. opening a dialog, focusing a
  panel, switching modes). Those stay in their respective Stimulus
  controllers. The bus is specifically for "user fires an action that
  hits a Rails endpoint and updates state."
- **Does NOT define how leader-menu bindings map to action names.**
  That's a separate locale file
  (`config/locales/keybindings/en.yml`); the binding map references
  registry names but doesn't live in the registry itself.

## Alternatives considered

- **No registry; each consumer crafts its own POST.** Status quo.
  Spaghetti documented in Context. Rejected.
- **Registry but no JS dispatcher (every consumer reads the registry
  directly).** Rejected — the confirmation-dialog mounting + 204
  handling + error envelope parsing wants to be in one place. Without
  the dispatcher, each consumer reimplements the response-handling
  half.
- **One big "command bus" framework like a CQRS layer.** Rejected —
  overkill. The bus is read-only metadata + a thin dispatcher; not a
  command-sourcing / event-replay architecture.
- **Cable broadcasts at the controller layer only, no Sidekiq
  middleware coverage.** Rejected — long-running jobs (reindex, sync)
  need to update the TST sync indicator AND the panel progress bar
  independently. Middleware coverage gives the TST update for free;
  the panel update opts in via `broadcasts_to_panel`.

## Date

2026-05-21

## Related

- ADR 0016 — TUI design system and cable-first architecture
  (declared the direction)
- ADR 0017 — Cable-first architecture spec (channel naming + payload
  envelope; this ADR is the operational complement)
- `docs/architecture.md` — "Turbo-everywhere + cable-per-panel"
  (this ADR's predecessor section) + new "Action bus + cable
  architecture" section (operational summary)
- `CLAUDE.md` — new "Action bus" bullet under "Hard rules"
- FB-126, FB-178, FB-180 — the spaghetti that triggered the lock
- `Tui::ConfirmationDialogComponent` (FB-124) — the canonical
  confirmation surface this bus mounts
