# Pito UX Defaults

Per-feature UX defaults the user has explicitly chosen. Future feature specs
that touch any of these surfaces must bake the default in without re-asking.
Append-only — entries get added; existing entries do not get overwritten or
removed.

The architect-spec subagent consults this file when drafting any UI-touching
spec.

## Dashboard

### Chart `[ ] sync` checkboxes default to ACTIVE on all sync-capable charts

When the dashboard renders, every sync-capable chart's `[ ] sync` checkbox
starts checked (`[x]`). The user opts out per chart, not in. Applies to the
existing dashboard and any new sync-capable chart added later. "Sync-capable" =
line/time-series charts that share an x-axis index for crosshair sync;
non-sync-capable charts (e.g., bar charts like `top videos`) do not get a
`[ ] sync` checkbox at all.

**Note on terminology:** this rule is about the `[ ] sync` checkbox that
controls crosshair synchronization between charts (shared hover index across
charts in the same sync group). It is NOT about chart visibility / hiding. There
is no per-chart visibility toggle on the dashboard.

**Why:** the user's mental model is "all charts hover together by default, let
me uncouple the ones I don't want synced." Default-off would require re-checking
every chart on every visit.

**How to apply:** any spec that adds, restyles, or modifies dashboard charts
must state explicitly that `[ ] sync` defaults to active for sync-capable
charts. The implementer enforces this via Stimulus initial state and the
localStorage seeding logic.

### Dashboard chart sync state persists in localStorage

Sync-capable dashboard charts have `data-chart-id` slugs and are wired as
`chart-sync` Stimulus targets. The `chart_sync_controller.js` reads/writes
`localStorage["pito_dashboard_charts_synced"]` (JSON array of chart-id slugs
that are currently synced / checked). On first visit (key absent), all
sync-capable chart-ids are written. On subsequent visits, the controller
restores the user's last state. Any combination is permitted. The "default
ACTIVE" rule (entry above) governs the first-visit seed; this rule governs
persistence after the first interaction.

**Style:** the `[ ] sync` checkbox uses the design-system bracketed style via
`CheckboxComponent` (`<label class="md-check">` with hidden native input, `[ ]`
/ `[x]` / `[-]` rendered by `.md-check-indicator::before`). Native
`<input type="checkbox">` is NEVER used directly on the dashboard — always go
through `CheckboxComponent`.

**Why:** the user wants per-browser memory of which charts they keep synced.
localStorage is the simplest mechanism and survives refresh + revisit.
Per-device only is acceptable (no server-side preference yet).

**How to apply:** any spec that adds, modifies, or restyles a sync-capable
dashboard chart must include the `data-chart-id` attribute, the
`data-chart-sync-target="chart"` attribute on the container, and a
`CheckboxComponent` wired with `data-chart-sync-target="checkbox"`,
`data-chart-id="<slug>"`, and `data-action="change->chart-sync#toggle"`. The
localStorage key name (`pito_dashboard_charts_synced`) and JSON shape (array of
slugs that ARE synced) are stable: do not bikeshed.

## Dialogs and confirmations

### Never use JavaScript alert / confirm / prompt

No `window.alert`, `window.confirm`, `window.prompt`, no `data-turbo-confirm`,
no `confirm:` link helper. Period. Across the Rails app, terminal app, MCP —
every Pito surface.

**Why:** the user wants consistent, professional UX. JS dialogs break flow,
can't be styled, can't be tested cleanly, can't carry context (lists,
breakdowns, skip warnings). The action confirmation page framework
(`shared/_action_screen.html.erb` + `DeletionsController` shape, Alpha-era) is
the canonical pattern. The terminal app has its own in-TUI confirmation step.
MCP has a `confirm: bool` parameter on destructive tools.

**How to apply:** when scoping any feature with a destructive or significant
user action, route it through the action confirmation framework. Migrate any
leftover Alpha-era `data-turbo-confirm` instances opportunistically when
touching the surrounding feature.

## Bulk operations

### Single-record actions are bulk operations with one ID

Do not design separate single-record and bulk-record actions. Every destructive
or significant operation accepts a list of IDs (1 or N) and uses the same
controller, view, job, and confirmation page.

**URL/route shape (Rails):** `/<action>s/:type/:ids` with comma-separated IDs.
Examples: `/deletions/channel/123`, `/syncs/channel/1,2,3`.

**MCP shape:** `bulk_<action>_<resource>(ids: [int], confirm: bool)`. The
`confirm` flag is required for the action to fire. Without `confirm: true`, the
tool returns a preview (counts, skip warnings, message). With `confirm: true`,
the tool creates the BulkOperation and enqueues the job.

**Terminal shape:** the bulk picker (existing) selects 1 or N records via
space-toggle; the action triggers the in-TUI confirmation; on `y`, the action
calls the bulk MCP/JSON API with `confirm: true`.

**Why:** one mental model across surfaces; code reuse; confirmation is a
feature, not friction; future actions inherit the pattern.

**How to apply:** when designing any new MCP tool for a destructive or
sync-style action, the architect-spec must use the bulk shape with
`confirm: bool`. Do not introduce single-record tool variants.

## Boolean values

### External boolean values are "yes" / "no" — never true/false/1/0

Boolean fields are stored internally as `Boolean` (Postgres `boolean` columns,
Ruby `true`/`false`, Rust `bool`), but every value crossing a project boundary
is communicated as the string `"yes"` or `"no"`.

**Where this applies:**

- URL query params (filter chips, etc.) — `?starred=yes&connected=no`. Absence
  of the param is the "no filter" semantic; presence with `"yes"` filters.
- JSON API request and response bodies —
  `{ "star": "yes", "connected": "no", "syncing": "yes" }`. Strings, not
  booleans.
- MCP tool input schemas — `enum: ["yes", "no"]` for any boolean-ish field.
- MCP tool outputs — same yes/no strings.
- Rust client (`pito` CLI at `extras/cli/`) — `#[serde(with = "yes_no")]` on
  `bool` fields so JSON serialization/deserialization handles the conversion
  automatically. Internal Rust types stay `bool`.

**Why:** human-readable wire format. The UI already renders boolean fields as
`yes` / `no` in tables; the user wants this to be the canonical
externally-visible form everywhere, including shareable URLs.

**How to apply:**

- Conversion happens at the boundary via small helpers (e.g.,
  `YesNo.to_yes_no(bool)` and `YesNo.from_yes_no(string)` in Ruby; the `yes_no`
  serde module in Rust).
- Any new boolean field added later — `email_verified`, `archived`, anything —
  follows the same rule from day one. No new field is exposed as `true`/`false`
  on the wire.
- Strict on input: the only accepted external values are `"yes"` and `"no"`.
  Anything else (`true`, `1`, `on`, etc.) is rejected with a clear error. No
  permissive coercion.

**What stays internal:**

- Database columns: `Boolean`.
- Ruby model attributes: `true`/`false`.
- Rails console, Rake tasks, background jobs that operate on models: standard
  Ruby boolean.
- Rust struct fields after deserialization: `bool`.
- View rendering (ERB / Ratatui): the existing `channel.star? ? "yes" : "no"`
  patterns stay; they're just the display layer of the same convention.

## Bracket conventions

Two distinct bracket conventions exist in Pito's design language:

### Action labels: `[label]` (no inner spaces)

Clickable / actionable elements use brackets flush against the label: `[view]`,
`[sync]`, `[delete]`, `[cancel]`, `[edit]`, `[save]`, `[back]`, `[link]`,
`[open]`. Zero inner spaces. Implemented via `BracketedLinkComponent`.

### Checkbox markers: `[ ]` / `[x]` / `[-]` (inner space is the glyph)

Checkboxes keep an intentional inner character: empty `[ ]`, checked `[x]`,
indeterminate / disabled `[-]`. When labelled, label follows the closing bracket
separated by a single space: `[ ] starred`, `[x] connected`. Implemented via
`CheckboxComponent` (or its visual-only static cousin for filter chips).

**Never use `[ word ]` (action label with inner spaces).** That style was used
in early scaffolding; everywhere it remains it should be tightened to `[word]`.

This convention applies in:

- Web ERB views (rendered through `BracketedLinkComponent` /
  `CheckboxComponent`)
- `pito` CLI (`extras/cli/`) — TUI labels follow the same rule
- Manual test playbooks under `docs/orchestration/playbooks/` — playbook steps
  reference UI actions using the same bracket form the user sees on screen
- Architectural decisions, specs, README files — any prose that quotes UI labels
