# 01f — Game Show/Edit Per-Platform Ownership

> Depends on `01a` (data model). Adds the per-platform ownership editor to a
> game's show and edit screens. Read view shows ownership state on the show
> page; edit view exposes a checklist of release platforms (sourced from IGDB),
> with optional per-row metadata (acquired_at, store, notes) per `01a`'s v1
> column set.

---

## Goal

Surface per-platform ownership in the UI:

- `Game#show` reads per-platform ownership state plainly (e.g., "Owned on: PS5,
  Steam") with each platform linking to its filtered
  `/games?filters=<slug>,owned` view.
- `Game#edit` presents a checklist of platforms the game is released on
  (IGDB-sourced) so the user can tick the ones they own. Per-row optional
  metadata: `acquired_at`, `store` (free-text), `notes`.

Single submit; no JS confirm; destructive un-tick (un-owning) is part of the
same form submit because it's not destructive in the project-rule sense (it
edits a metadata row, doesn't delete a top-level record).

---

## Files touched

Controllers:

- `app/controllers/games/platform_ownerships_controller.rb`

Routes:

- `config/routes.rb` —
  ```ruby
  resources :games, param: :slug do
    resource :platform_ownerships, only: %i[edit update], module: :games
  end
  ```

Models:

- `app/models/game.rb` (accepts nested attributes for ownerships via the
  `accepts_nested_attributes_for :game_platform_ownerships` declaration with
  `allow_destroy: true`)

Views:

- `app/views/games/show.html.erb` (read view of ownership)
- `app/views/games/edit.html.erb` (entry point to ownership editor)
- `app/views/games/platform_ownerships/edit.html.erb` (the editor form)
- `app/views/games/_owned_platforms_list.html.erb` (partial used on show)

Components:

- `app/components/games/platform_ownership_editor_component.{rb,html.erb}`
- `app/components/games/owned_platforms_chip_list_component.{rb,html.erb}`

Specs:

- `spec/requests/games/platform_ownerships_spec.rb`
- `spec/system/games_platform_ownerships_spec.rb`
- `spec/components/games/platform_ownership_editor_component_spec.rb`
- `spec/components/games/owned_platforms_chip_list_component_spec.rb`
- `spec/views/games/show_spec.rb`
- `spec/views/games/platform_ownerships/edit_spec.rb`

---

## Controller decomposition

### `Games::PlatformOwnershipsController`

- `before_action :load_game` (`Game.friendly.find(params[:game_slug])`)
- `#edit` — renders the editor; builds in-memory `GamePlatformOwnership` records
  for each release-platform not yet owned (so the form shows every platform as a
  row).
- `#update` — accepts nested attributes; permitted params:
  ```
  game: {
    game_platform_ownerships_attributes: [
      { id, platform_id, _own ("yes"|"no"), acquired_at, store, notes, _destroy }
    ]
  }
  ```
  The controller transforms `_own: "yes"|"no"` (yes/no boundary per project
  rule) into either a present row (yes) or a destroy marker (no) before
  persisting. On success: redirect to `Game#show`. On failure: re-render `#edit`
  with errors.

---

## Component decomposition

### `Games::PlatformOwnershipEditorComponent`

Inputs:

- `game: Game`
- `form: ActionView::Helpers::FormBuilder`

Renders:

- A checklist of every platform the game is released on (from IGDB).
- For each platform: a checkbox `_own` (`"yes"` / `"no"` per project rule), plus
  optional fields `acquired_at`, `store`, `notes` (collapsed/expanded by default
  — open for v1; spec-leveled collapsibility is a follow-up).
- Submit button `[save]`. No cancel-via-confirm; cancel is a plain link back to
  `Game#show`.

### `Games::OwnedPlatformsChipListComponent`

Inputs:

- `game: Game`

Renders the list of owned platforms as bracketed chips on the show page, each
linking to `/games?filters=<slug>,owned`. When empty, renders muted "(not owned
on any platform)" placeholder.

---

## yes / no boundary

- Form's `_own` field uses `"yes"` / `"no"` string per project rule.
- Controller converts to Boolean before persisting (presence vs. destroy).
- No `true` / `false` / `0` / `1` accepted from the form.

---

## Friendly URL preservation

- `/games/:slug/platform_ownerships/edit` — slug-based.
- Redirect after update goes to `/games/:slug`, not `/games/:id`.

---

## No JS confirm

- Un-ticking an owned platform is a form-state change, not a destructive
  top-level deletion. The form submit applies in one POST.
- If the user wants to delete the Game itself, that's via the existing
  `/deletions/game/:ids` flow — not changed here.

---

## Spec pyramid

### Request — `spec/requests/games/platform_ownerships_spec.rb`

Happy:

- `GET /games/:slug/platform_ownerships/edit` → 200; renders editor with one row
  per release-platform.
- `PUT /games/:slug/platform_ownerships` with `_own: "yes"` for PS5 and Steam →
  creates two ownership rows; redirects to `Game#show`.
- subsequent `PUT` with `_own: "no"` for PS5 destroys that row, keeps Steam.

Sad:

- `PUT` with unknown `platform_id` → 422; renders editor with errors.
- `PUT` with `_own: "true"` (forbidden form value) → 422 (yes/no boundary
  enforced).
- `PUT` with `_own: "1"` → 422.

Edge:

- duplicate `platform_id` rows in submitted attributes → controller
  de-duplicates (or 422 — pick one; architect leans 422 with a clear error
  message).
- empty submit (no `_own: "yes"` anywhere) is valid — un-owns everything.

Flaw:

- a stale `id` (ownership deleted in another tab) is handled gracefully —
  controller catches `RecordNotFound` and renders an actionable error.
- mass-assignment guard — no other Game attributes accepted via this controller.

### System — `spec/system/games_platform_ownerships_spec.rb`

Happy:

- visit `/games/:slug`, click `[edit ownership]`, tick PS5 + Steam, click
  `[save]`. Redirect to show; "Owned on: PS5, Steam" rendered.
- visit `/games/:slug`, click `[edit ownership]`, un-tick PS5, click `[save]`.
  Show page now reads "Owned on: Steam".

Sad:

- form does not use JS confirm.
- form does not show a red destructive button (the form is just an editor).

Edge:

- filling `acquired_at`, `store`, `notes` for a new ownership persists all
  three.
- composes with filter row: after saving PS5 ownership, navigating to
  `/games?filters=ps5,owned` includes the game.

### Component — `spec/components/games/platform_ownership_editor_component_spec.rb`

Happy:

- renders one row per release-platform of the game.
- each row's checkbox is named with `_own` and uses `value="yes"` / unchecked →
  `"no"`.

Sad:

- never emits `data-turbo-confirm`.
- never renders red.

Edge:

- a game with zero release-platforms (no IGDB data) renders an empty editor with
  a muted "(no platforms available)" message.

### Component — `spec/components/games/owned_platforms_chip_list_component_spec.rb`

Happy:

- renders one bracketed chip per owned platform.
- each chip's `href` is `/games?filters=<slug>,owned`.
- alphabetical chip order.

Sad:

- empty ownership renders muted placeholder.

### View — `spec/views/games/show_spec.rb` (additions)

Happy:

- show page renders the owned-platforms chip list.
- show page includes an `[edit ownership]` bracketed link to the editor.

### View — `spec/views/games/platform_ownerships/edit_spec.rb`

Happy:

- form posts to the right path with PATCH method.
- form has no JS confirm.

---

## Manual test recipe

1. Open `/games/:slug` for any game — confirm the show page reads "Owned on:
   <list>" or "(not owned on any platform)".
2. Click `[edit ownership]` — see a checklist of release platforms.
3. Tick PS5 and Steam; fill `acquired_at: 2025-12-25`, `store: PSN` for PS5;
   click `[save]`.
4. Redirect to show page; chips show `[PS5]` `[Steam]`.
5. Re-enter editor; un-tick PS5; click `[save]`.
6. Show page now reads only `[Steam]`.
7. Confirm `/games?filters=ps5,owned` no longer includes this game;
   `?filters=steam,owned` still does.
8. Try POSTing with `_own: "true"` via `curl` — confirm 422 (yes/no boundary
   enforced).

---

## Cross-stack scope

| Surface    | In scope                             |
| ---------- | ------------------------------------ |
| Rails web  | YES — show + edit + ownership editor |
| Rails MCP  | NO — covered by `01g`                |
| `pito` CLI | NO — covered by `01g`                |
| Website    | NO                                   |

---

## Open questions

1. **Edit entry-point UX.** Single page
   (`/games/:slug/platform_ownerships/ edit`) vs. an inline section on
   `/games/:slug/edit`? Architect leans dedicated page so the editor doesn't
   bloat the main game edit form.
2. **`_own` field naming.** Could also be `owned` or `present`. Architect leans
   `_own` to avoid colliding with the model attribute names.
3. **Collapsible per-row metadata** — open by default in v1, collapsible in a
   later polish pass? Architect leans yes, open by default.
4. **Bulk-tick "I own this on all platforms it's released on"** — a quick
   `[own all]` link at the top of the editor? Architect leans defer to
   follow-up; not in the source note.
5. **Show-page chip rendering** — alphabetical (locked) vs. by ownership
   acquisition order? Locked alphabetical.
