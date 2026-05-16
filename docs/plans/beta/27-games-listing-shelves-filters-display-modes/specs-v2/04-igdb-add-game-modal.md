# 04 — IGDB add-game modal polish

> Phase 27 v2 spec. Tightens the global IGDB add-game modal: shorter copy,
> auto-search (no explicit `[search]` button), bracketed-muted `[cancel]`,
> horizontal-overflow audit, and an eager IGDB-title fetch so the breadcrumb
> shows the real title instead of `Untitled game` immediately after submit.

---

## Goal

When the user opens the IGDB add-game modal (via `[+]` on `/games` or the
`i` keypress), they see a tighter, less chatty surface: one input that
searches on its own as the user types past 5 chars OR hits Enter, with
existing result rows showing `[add]` / `[update]` per the current pattern.
On submit, the resulting game's breadcrumb shows the IGDB-fetched title
immediately (not the `Untitled game` default attribute that the model
applies when title is blank).

---

## Scope in

- Modal copy + control polish (no behavior change to the underlying search
  endpoint).
- Stimulus controller behavior: debounce-search at 5+ characters; Enter
  also triggers a search; drop the explicit `[search]` button entirely.
- CSS overflow audit on the modal — the modal currently overflows
  horizontally in some viewports (the inline `max-width: 720px` was added
  as a polish hack; revisit the cascade so the modal sizes correctly
  without the inline override).
- Eager IGDB title fetch on the add flow: when the user clicks `[add]` for
  an IGDB result, the `Game.create` call uses the title from the modal's
  search-result row (which already came from IGDB) as a synchronous seed
  for the new `Game#title`. The async `GameIgdbSync` job still runs and
  overwrites with the canonical IGDB record, but the breadcrumb during
  the in-flight window shows the real title rather than `Untitled game`.
- `[cancel]` button uses `BracketedMutedLinkComponent` (the muted
  bracketed-button pattern, e.g. from session-revoke modal). Confirm the
  component name and slot shape at implementation time.

## Scope out

- The keyboard `i` keypress wiring (already routes to the modal — no
  change).
- IGDB API client / `GamesController#search` behavior. Both are upstream.
- The `[update]` overwrite-confirmation modal chain (separate confirm
  modal, untouched).
- Restyling the result-row layout itself (rows render via
  `_search_results.html.erb` — leave the row structure).

---

## Files to change

- `app/views/shared/_igdb_search_modal.html.erb` (existing)
  - Title copy: `add a game from igdb` → `add a game`.
  - Drop the `placeholder="search igdb…"` subtitle hint inside the input
    (the title carries the context now; the placeholder becomes
    `search…` or empty per the implementation decision below).
  - Drop the `<button class="bracketed">[search]</button>` element
    entirely.
  - Replace the `<button>[cancel]</button>` in `.modal-footer` with
    `<%= render(BracketedMutedLinkComponent.new(label: "cancel",
    href: "#", data: { action: "click->igdb-search-modal#close" })) %>`
    (verify the muted-component supports `data-action` passthrough; if
    not, wrap in a span with the action).
  - Remove the inline `style="max-width: 720px;"` hack and reconcile the
    CSS cascade (see CSS audit below).

- `app/javascript/controllers/igdb_search_modal_controller.js`
  - Replace the existing `input` action's behavior (likely debounce on
    every keystroke) with a guard: only fire `#search` when the input
    value's length is ≥ 5 OR when the user pressed Enter.
  - Add an Enter handler: `data-action="input->...#search keydown.enter->...#search"`.
  - Drop the `submit` action handler if the only invoker was the
    `[search]` button.
  - Debounce window: 250 ms (audit existing; keep if already debounced).

- `app/assets/tailwind/application.css` (CSS audit)
  - The current modal width is constrained by `.confirm-modal {
    max-width: 420px }` (defined in the cascade later than `.pane-dialog`).
    Reconcile: either (a) bump `.pane-dialog { max-width: 720px }` and
    drop the inline override, OR (b) introduce a `.pane-dialog--wide`
    modifier the modal opts into. Architect lean: (b) — explicit modifier,
    so other confirm modals keep their 420px cap.
  - Verify the inner `width: min(720px, 92vw)` is still necessary; if the
    outer `<dialog>` now sizes correctly, the inner can drop the inline
    width.

- `app/controllers/games_controller.rb#create`
  - The IGDB add-game branch (when `params.dig(:game, :igdb_id)` is
    present) currently does `Game.new(igdb_id:)` → `save` → enqueue
    async sync. v2: accept an optional `params.dig(:game, :title)`
    pre-seed from the modal and pass it into `Game.new`. The title
    column has a default of `"Untitled game"` (per `attribute :title,
    :string, default: "Untitled game"`); explicitly setting it from the
    submitted form prevents the default from sticking during the in-flight
    window. The async `GameIgdbSync` still overwrites with the canonical
    IGDB title on completion.

- `app/views/games/_search_results.html.erb`
  - The existing `[add]` link (or `button_to` POST) must include a
    hidden `title` param carrying the IGDB result row's title. Wire as
    a `button_to` with `params: { game: { igdb_id: ..., title:
    result.title } }`.

- `app/components/bracketed_muted_link_component.rb` — verify the
  component supports `data:` attribute passthrough. If not, this spec
  documents the gap as an open question.

---

## Behavior contracts

### Modal copy

- Dialog title: `add a game` (was: `add a game from igdb`).
- Input placeholder: `search…` (was: `search igdb…`). The "igdb" context
  is implied by the title.
- No `[search]` button anywhere.
- Footer carries ONE control: `[cancel]` rendered via
  `BracketedMutedLinkComponent` (muted styling — same as the muted-link
  pattern on session-revoke).

### Auto-search trigger

- The input fires `#search` (the Turbo Frame fetch to
  `GET /games/search?q=…`) when EITHER:
  - the input value's trimmed length is ≥ 5 characters (debounced 250 ms),
  - OR the user presses Enter at any length ≥ 1 (immediate).
- Below 5 chars and no Enter pressed → no fetch, no result frame change
  (the frame keeps the prior state or its empty initial state).
- The "≥ 5 chars" rule is a guard against firing on every keystroke
  for partial words; the Enter override lets a user explicitly search
  shorter terms (`"DOOM"`).

### Eager title in breadcrumb

- The `_search_results.html.erb` partial submits the IGDB result row's
  title alongside the `igdb_id` on `[add]` click.
- `GamesController#create` accepts `params.dig(:game, :title)` ONLY in
  the IGDB-add branch (no general-create surface — the legacy
  default-create branch ignores `:title` since it preserves the
  `"Untitled game"` default behavior). The IGDB-add branch passes both
  `igdb_id` and `title` to `Game.new`.
- After save: `redirect_to game_path(game), notice: "added; metadata
  loading in background."`. The game's `title` is now the IGDB-pre-seeded
  value, so the breadcrumb `[games] / [Pragmata]` shows the real title.
- The async `GameIgdbSync` runs, fetches the canonical IGDB record, and
  may overwrite the title with the canonical capitalization /
  punctuation. The pre-seed is just the user-visible bridge during the
  in-flight window.

### CSS overflow audit

- Goal: the modal's outer `<dialog>` element does NOT trigger horizontal
  page scroll, regardless of viewport width down to 360 px wide.
- The inner content max-width is 720 px on a wide viewport; below that
  it shrinks to `92vw`.
- The fix is at the `.pane-dialog` or `.confirm-modal` cascade level,
  not the inline `style="max-width: 720px;"` band-aid. Pick:
  - `.pane-dialog--wide { max-width: 720px; }` (preferred), OR
  - bump `.pane-dialog { max-width: 720px; }` and audit other dialogs
    that inherit it.
- The implementation MUST verify in the browser dev tools at 360 px,
  768 px, and 1280 px widths that no horizontal scroll appears on
  `<body>` while the dialog is open.

### `BracketedMutedLinkComponent` reuse

- Existing pattern: session-revoke modal uses
  `BracketedMutedLinkComponent` for its cancel/back link. Reuse the
  same component here.
- Slot: `label: "cancel"`, `href: "#"`, `data: { action:
  "click->igdb-search-modal#close" }`.
- Verify the component's constructor accepts a `data:` hash and forwards
  it to the rendered anchor. If not, this becomes an open question and
  the implementer extends the component (small additive change).

---

## Migrations

None.

---

## ViewComponents

No new components. Confirms one existing component (`BracketedMutedLinkComponent`)
supports the `data:` attribute hash; extend it if not.

---

## Stimulus controllers

- `igdb_search_modal_controller.js` is modified, not added.
- Targets / actions:
  - target: `input` (existing).
  - actions: `input->igdb-search-modal#search`,
    `keydown.enter->igdb-search-modal#search`,
    `click->igdb-search-modal#clickOutside`,
    `keydown->igdb-search-modal#keydown` (Esc → close, existing).
  - `submit` action removed.
- New value: `data-igdb-search-modal-min-chars-value="5"` (default 5,
  declared so a test or a future copy tweak can adjust without editing
  the controller).

---

## Spec coverage required

### View spec (`spec/views/shared/_igdb_search_modal.html.erb_spec.rb`)

- Title text reads `add a game` (not `add a game from igdb`).
- The input placeholder is `search…` (not `search igdb…`).
- No `<button>` element with text `[search]` is rendered.
- Footer contains exactly one bracketed-muted `[cancel]` element wired
  to the `#close` action.
- No `data-turbo-confirm`, no `confirm:` attribute (CLAUDE.md guard).

### System spec (`spec/system/igdb_add_game_spec.rb` — extend or NEW)

- Opening the modal via `[+]` on `/games`:
  - Type 4 chars → no Turbo Frame fetch (the results frame stays
    unchanged).
  - Type a 5th char → one fetch fires after the 250 ms debounce
    window.
  - Press Enter with 1 char → fetch fires immediately.
  - Press Esc → modal closes.
  - Click `[cancel]` → modal closes (no JS confirm).
- Selecting an `[add]` row in the results:
  - The new game's show page breadcrumb shows the IGDB title (e.g.
    `[games] / [Pragmata]`), not `[games] / [Untitled game]`.
  - The flash notice reads `added; metadata loading in background.`.
  - The async sync job is enqueued (assert via Sidekiq testing API).

### Request spec (`spec/requests/games_spec.rb` — extend)

- `POST /games` with `params[:game] = { igdb_id: 123, title: "Pragmata" }`
  → creates a game with `title: "Pragmata"`, redirects to show,
  enqueues `GameIgdbSync`.
- `POST /games` with only `igdb_id` (no title) → still creates (back-compat),
  title stays as the `"Untitled game"` attribute default.
- Sad: smuggling `params[:game][:notes] = "evil"` does NOT write to
  notes (the create branch only permits `igdb_id` + `title` here).

### Stimulus spec (browser-driven)

- Optional, but if the project's Stimulus controllers have a JS unit
  test pattern (e.g. via `vitest`), cover the min-chars guard and the
  Enter override. If no JS unit test infra exists, the system spec
  above covers the behavior end-to-end.

### Component spec (if `BracketedMutedLinkComponent` is extended)

- `spec/components/bracketed_muted_link_component_spec.rb` —
  verify the `data:` hash is forwarded to the rendered `<a>` element.

### CSS / visual

- No automated spec. Manual verification at 360 / 768 / 1280 px in the
  manual test recipe at the end of this spec set.

---

## Manual test recipe (modal-specific — referenced by spec 04 only)

1. `bin/dev` → open `http://localhost:3000/games`.
2. Click `[+]` → modal opens. Title reads `add a game`. Footer has one
   `[cancel]` link, no `[search]` button. Input placeholder reads
   `search…`.
3. Type 4 chars (`"port"`) → wait 1s → no result rows appear.
4. Type a 5th char (`"al"` to make `"portal"`) → after 250 ms, results
   appear.
5. Backspace down to 3 chars → result frame does NOT clear (stays at the
   last successful result) but does NOT re-fetch.
6. Press Enter with the 3-char value → fetch fires for `"por"`.
7. Click `[add]` on the first result row → redirects to the new game's
   show page; breadcrumb shows the IGDB title (e.g. `[games] /
   [Portal]`), NOT `[games] / [Untitled game]`.
8. Reload the show page once the async sync completes (~1-2s) — title
   may or may not update (depending on the IGDB canonical
   capitalization) but never reverts to `Untitled game`.
9. Re-open the modal at viewport widths 360 / 768 / 1280 px. Confirm no
   horizontal scrollbar appears on `<body>` while the modal is open.
10. Press Esc → modal closes.

---

## Open questions

1. **Min-chars cutoff — 5 vs 4 vs 3?** The user's prompt pinned 5.
   Architect lean: keep 5; 3 or 4 fires too often on common prefixes
   ("the", "wit"). Confirm during spec review.
2. **Does `BracketedMutedLinkComponent` already accept `data:` attribute
   passthrough?** Verify at implementation time. If not, extend the
   component (additive — no risk to existing call sites).
3. **Eager-title behavior on the `[update]` flow** (the overwrite path
   for a game that's already in the library). Architect lean: not
   relevant — `[update]` does not create a new row, so there is no
   `Untitled game` window to bridge. Update flow is untouched.
4. **The legacy "default create empty game" branch in
   `GamesController#create`** (the path that fires when neither
   `igdb_id` nor `title` is present). It's already flagged for the
   polish window; this spec does not touch it. Confirm whether it
   should be deleted as part of v2 — likely yes, but route through a
   separate decision.
