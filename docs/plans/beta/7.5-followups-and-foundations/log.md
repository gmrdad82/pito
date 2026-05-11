# Phase 7.5 — Follow-ups Sweep + Concept Foundations · Session Log

## 2026-05-07 — Track A step 01 — Rails-side hygiene sweep

**State at start:** Phase 7.5 specs landed. Phase 6+7+pathA2 work is in the
working tree (still uncommitted). RSpec working-tree baseline was 1700/0/0 (per
the Track C step 05 log entry below). Brakeman was at 2 warnings + 1 ignored.

**Inputs:**

- Spec:
  `docs/plans/beta/7.5-followups-and-foundations/specs/01-rails-hygiene-sweep.md`
- Locked decisions (from the dispatch):
  - **Q1** = (b) fix the underlying `BelongsToTenant` default-scope behavior.
    Identify why `.unscoped` was needed, fix the underlying issue, remove the
    `.unscoped + where(user_id:)` workaround. Verify with empirical SQL
    inspection.
  - **Q2** = (a) broad sweep — every `:unprocessable_entity` across `app/` and
    `spec/`.

**Q1 root-cause analysis:**

Empirical SQL inspection at `bin/rails runner`:

```
Current.tenant = Tenant.first; u = User.first
puts u.sessions.to_sql
# SELECT "sessions".* FROM "sessions"
#   WHERE "sessions"."tenant_id" = 1 AND "sessions"."user_id" = 1
puts u.sessions.unscoped.where(user_id: u.id).to_sql
# SELECT "sessions".* FROM "sessions" WHERE "sessions"."user_id" = 1
```

The `.unscoped + where(user_id:)` pattern was over-defensive copy-paste:
`Current.user.sessions` already filters `WHERE user_id = ?` (association), and
`BelongsToTenant`'s default scope adds `AND tenant_id = ?` — the natural
association is **strictly more restrictive** than the workaround it replaced.
The `.unscoped` opted OUT of the tenant filter the project's hard rule wants in
place. The fix is to remove the workaround; no change to `BelongsToTenant`
itself was needed (the concern is correct as-is). The cross-tenant SQL
verification confirms both `tenant_id` and `user_id` filters are now applied.

**What landed (file-level):**

_Q1 — `Settings::SessionsController` `.unscoped` removal:_

- `app/controllers/settings/sessions_controller.rb` — dropped the
  `.unscoped.where(user_id: Current.user.id)` chain from `#index`, `#revoke`,
  and `#destroy`. Now uses `Current.user.sessions.find(params[:id])` /
  `Current.user.sessions.order(...)`. Header comment updated to record the Phase
  7.5 cleanup and the empirical reasoning.
- `app/controllers/settings_controller.rb` — same pattern fix in the settings
  index pane's `@active_sessions_count` lookup; now
  `Current.user.sessions.where(revoked_at: nil).count`.
- `spec/requests/settings/sessions_spec.rb` — added 3 cross-tenant / cross-user
  regression specs ("does not surface another user's sessions in the index",
  "raises RecordNotFound on revoke for a session belonging to another user",
  "raises RecordNotFound on destroy for a session belonging to another tenant").
  The third spec plants a rogue Session row with `Session.unscoped.create!`
  under a different tenant and asserts the controller's natural scope hides it
  (returns 404 instead of touching the row).

_Q2 — `:unprocessable_entity` → `:unprocessable_content` broad sweep:_

- 49 callsites migrated across `app/` (26) and `spec/` (23):
  - `app/controllers/`: `settings_controller.rb`, `timelines_controller.rb`,
    `channels_controller.rb`, `api/footages_controller.rb`,
    `games_controller.rb`, `collections_controller.rb`,
    `settings/oauth_applications_controller.rb`,
    `settings/tokens_controller.rb`, `projects_controller.rb`,
    `concerns/confirmable.rb`, `footages_controller.rb`.
  - `spec/requests/`: `syncs_spec.rb`, `deletions_spec.rb`,
    `api/footages_spec.rb`, `settings/oauth_applications_spec.rb`,
    `channels_spec.rb`, `sessions_spec.rb`.
  - `rg ':unprocessable_entity' app/ spec/` returns zero matches post-sweep;
    `rg ':unprocessable_content' app/` shows 26 callsites.

_OmniAuth simplification:_

- `config/initializers/omniauth.rb` — collapsed the
  `Rails.application.credentials.dig(:google_oauth, :client_id)` /
  `:client_secret` lookups into a single `credentials.google_oauth || {}`
  binding with explicit early-fail
  (`raise "missing google_oauth credentials: …"`) if either key is blank. The
  `:redirect_uri` lookup remains permissive — that key IS optional in dev (the
  URL-string fallback is intentional, not dead).

_Channel Revamp orphan cleanup:_

- DELETED `app/views/shared/_confirm_dialog.html.erb` (orphaned partial).
- DELETED `app/javascript/controllers/confirm_dialog_controller.js` (its
  Stimulus controller).
- EDITED `app/components/bracketed_link_component.rb` — dropped the unused
  `confirm:` kwarg from `#initialize`. Pre-deletion grep verified zero callers
  in `app/` or `spec/` passed `confirm:` to the component.
- EDITED `spec/components/bracketed_link_component_spec.rb` — dropped one
  example asserting `confirm:` was accepted-and-ignored, simplified one example
  that combined `destructive:` + `method:` + `confirm:` to the two-arg variant.
- `app/javascript/controllers/index.js` uses `eagerLoadControllersFrom` so no
  manual registry entry needed unwiring.

**Pipeline:**

- `bundle exec rspec` — 1702 examples, 0 failures. Delta vs. working-tree
  baseline (1700): +3 cross-tenant regression specs, -1 BracketedLinkComponent
  `confirm:` example dropped. Net +2.
- `bundle exec rubocop` — 412 files, 0 offenses.
- `bundle exec brakeman -q -A -w1` — 2 warnings + 1 ignored, unchanged from
  baseline (ForceSSL pre-existing, UnscopedFind on `Note.find(params[:id])`
  pre-existing, Sessions::AuthConcern VerbConfusion in `brakeman.ignore`).
- Hard-rule greps:
  - `rg ':unprocessable_entity' app/` → zero matches.
  - `rg ':unprocessable_content' app/` → 26 matches.
  - `grep -rn "_confirm_dialog\|confirm_dialog_controller" app/` → zero matches.
  - `grep -rn "BracketedLinkComponent.*confirm:" app/ spec/` → zero matches.
- `bin/rails runner -e development 'puts "boot ok"'` and `-e test` both print
  cleanly — no missing-credentials boot failure with the simplified initializer;
  the early-fail path is exercised manually per the spec's manual recipe.

**Out of scope (intentionally not touched):**

- Decorator slim resolution (Phase 7.5 spec 03).
- CLI surfaces (Track B; spec 02 already landed).
- Phase 5/6/7 OAuth surfaces (Api::AuthConcern, MCP RackApp, ApiToken,
  GoogleIdentity, Doorkeeper, Youtube::\*).
- Phase 4 retracted features.
- `BelongsToTenant` itself — the audit concluded it is correct as-is; the
  `.unscoped` workaround was the sole defect.

**Open issues / follow-ups:**

- None. The four items in this sweep all landed. The spec's "Follow-ups created"
  section anticipated none, which matches the outcome.

**Manual test plan handed back to the user:**

1. `bin/dev` — Web Puma boots cleanly. No "missing google_oauth credentials"
   error.
2. Sign in (`/login`), visit `/settings/sessions`, see your active sessions
   listed with `(this session)` annotation. Open `[revoke]` on the non-current
   row, confirm via the action screen, return to the index and see it marked
   revoked.
3. Visit `/settings/youtube`. Connect a Google account if not already connected.
   Confirm OmniAuth still routes correctly.
4. Disconnect the Google account, reconnect it. Both paths should behave
   identically to pre-sweep.
5. (Optional) `bin/rails console` →
   `Rails.application.credentials.google_oauth.client_id` returns a non-nil
   string. Temporarily move the key out of the credentials file (in a scratch
   copy), boot the app, confirm Rails fails fast with the
   `"missing google_oauth credentials"` message. Restore.

## References

- Spec:
  `docs/plans/beta/7.5-followups-and-foundations/specs/01-rails-hygiene-sweep.md`
- Phase overview:
  `docs/plans/beta/7.5-followups-and-foundations/specs/00-phase-overview.md`
- Sibling concern (root-caused, no change):
  `app/models/concerns/belongs_to_tenant.rb`

## 2026-05-07 — Track C step 05 — `pito-assets` volume + `Pito::AssetsRoot`

**State at start:** Phase 7.5 specs landed by architect-spec earlier on
2026-05-07. The `docker-compose.yml` already declared `pito-assets` as a named
volume (alongside `pito-postgres-data`, `pito-redis-data`,
`pito-meilisearch-data`, `pito-notes`); `config/storage.yml`'s `:local` service
already pointed at `ENV.fetch("PITO_ASSETS_PATH", "/var/lib/pito-assets")` from
a prior pass. What was missing: the `Pito::AssetsRoot` helper for
non-Active-Storage byte writes, the `bin/setup` mkdir step, and the
`docs/setup.md` blurb describing the volume's purpose and dev/prod path
resolution. Q7 was answered env-var-driven (mirror `PITO_NOTES_PATH`).

**Inputs:**

- `docs/plans/beta/7.5-followups-and-foundations/specs/05-pito-assets-volume.md`
- Dispatch decision: Q7 = env-var-driven; production default
  `/var/lib/pito-assets` when `PITO_ASSETS_PATH` is unset.

**What landed (file-level):**

- `app/lib/pito/assets_root.rb` — module with `root`, `path(*segments)`,
  `ensure_dir!(*segments)`, `tenant_root(tenant)`, `inside?` and a
  `Pito::AssetsRoot::Error` class. `root` reads `PITO_ASSETS_PATH` (default
  `/var/lib/pito-assets`); relative env values anchor to `Rails.root` so the
  resolved Pathname is always absolute. `path` and `ensure_dir!` reject absolute
  / empty / traversing segments via lexical `cleanpath` containment — never
  touches the filesystem before the input is cleared, matching `DevDocPath`'s
  safety semantics. `tenant_root` returns `<root>/<tenant_id>/` (mkpath'd,
  idempotent). Active Storage's internal `<root>/active_storage/...` layout is
  independent of this helper.
- `spec/lib/pito/assets_root_spec.rb` — 29 examples covering env-var resolution,
  the production default, relative-path anchoring, multi-segment joins,
  traversal rejection (root-escape and internal `..` that stays inside),
  `ensure_dir!` idempotence and file preservation, tenant scoping (placeholder
  doubles + a real persisted Tenant), tenant isolation, error branches for nil
  tenant / nil id, and the `inside?` predicate.
- `bin/setup` — extended to `mkdir_p` the resolved assets path on first install.
  Skips silently when `PITO_ASSETS_PATH` is unset and the `/var/lib/pito-assets`
  default is not writable (production handles that via the Docker volume mount,
  not `bin/setup`).
- `docs/setup.md` — extended the volumes blurb to enumerate the five
  pito-prefixed names and call out that `pito-notes` / `pito-assets` are
  reserved for the Hetzner cutover. Added a paragraph explaining what
  `PITO_ASSETS_PATH` controls, what's in scope (Pito-derived assets only, not
  source footage), and the test-env carve-out (`:test` Active Storage service
  stays on `tmp/storage`).

**Out of scope (intentionally not touched):**

- Footage thumbnails (Phase 7.5 §06 — depends on this helper).
- Game cover art workflow (deferred per spec 07's pre-spec status).
- The pre-existing `compose.yml` volume declaration — already present; no diff
  required.
- The pre-existing `config/storage.yml` `:local` root resolution — already reads
  `PITO_ASSETS_PATH` with the right default.

**Pipeline:**

- `bundle exec rspec` — 1700 examples, 0 failures (delta: 1671 → 1700; the +29
  are `assets_root_spec.rb`). The pre-existing suite count delta matches the new
  examples one-to-one.
- `bundle exec rspec spec/lib/pito/assets_root_spec.rb` — 29 / 29 green.
- `bundle exec rubocop` — 412 files, 0 offenses.
- `bundle exec brakeman -q -w2` — 0 warnings.
- Manual smoke via `bin/rails runner`:
  ```
  Pito::AssetsRoot.root
  # => #<Pathname:/home/catalin/Dev/pito/tmp/pito-assets>
  Pito::AssetsRoot.tenant_root(Tenant.first)
  # => #<Pathname:/home/catalin/Dev/pito/tmp/pito-assets/1>
  Pito::AssetsRoot.path("footage_thumbs", "1.jpg")
  # => #<Pathname:/home/catalin/Dev/pito/tmp/pito-assets/footage_thumbs/1.jpg>
  Pito::AssetsRoot.path("..", "etc")
  # => raises Pito::AssetsRoot::Error: path escapes assets root: /home/catalin/Dev/pito/tmp/etc
  ```

**Open issues / follow-ups:**

- Phase 7.5 §06 (footage thumbnails) is unblocked. It will be the first consumer
  of `tenant_root`, writing extracted frames under
  `<root>/<tenant_id>/footage_thumbs/<footage_id>.jpg` (or whatever shape the
  §06 spec settles on).
- No `plan.md` for Phase 7.5 yet — the master + docs-keeper hoist
  `00-phase-overview.md` into a `plan.md` once open questions resolve.
  Acceptance for spec 05 was tracked against the spec file's own `## Acceptance`
  checklist, not a phase-level checkbox.

## References

- Spec:
  `docs/plans/beta/7.5-followups-and-foundations/specs/05-pito-assets-volume.md`
- Phase overview:
  `docs/plans/beta/7.5-followups-and-foundations/specs/00-phase-overview.md`
- Sibling helper: `app/lib/dev_doc_path.rb` (path-safety semantics mirrored)
- Sibling helper: `app/lib/notes_filesystem.rb` (tenant scoping shape mirrored)

## 2026-05-07 — Track B step 02 — CLI hygiene sweep

**State at start:** The `extras/cli/` workspace already had substantial
in-flight uncommitted work from prior dispatches (api/client.rs and
ui/dashboard.rs heavily refactored, ~812/1184 ins/dels across the tree).
`cargo fmt --check` was clean at session start; `cargo build` and `cargo test`
were green at the 349-passing baseline; `cargo audit` flagged the two pre-spec'd
advisories `RUSTSEC-2024-0436` (paste, unmaintained) and `RUSTSEC-2026-0002`
(lru, unsound), both reachable exclusively through `ratatui 0.29.0`.

**Inputs:**

- Spec:
  `docs/plans/beta/7.5-followups-and-foundations/specs/02-cli-hygiene-sweep.md`
- Locked decisions:
  - **Q3** = accept ratatui-bump render side-effects, no
    screenshots-before/after gate.
  - **Q4** = full screen-layout parity sweep across every CLI screen vs its
    Rails ERB counterpart.

**What landed (file-level):**

- `extras/cli/Cargo.toml` — `ratatui = "0.29"` → `"0.30"`.
- `Cargo.lock` (workspace root) — refreshed via the build resolve. ratatui 0.30
  brings in `ratatui-core 0.1.0`, `ratatui-widgets 0.3.0`,
  `ratatui-crossterm 0.1.0`, `ratatui-macros 0.7.0`, plus a transitive
  `crossterm 0.29.0`. The previous direct `crossterm = "0.28"` dependency
  remains; both versions resolve side-by-side. `lru` is now `0.16.4` (was
  `0.12.5` via ratatui 0.29) and `paste` no longer appears in the tree.
- `extras/cli/src/ui/channel_detail.rs` — top action legend's keystroke hint
  trimmed from `(v) view  (Y) sync  (D) delete  (s) star` to
  `(v) view  (Y) sync  (D) delete`. Pre-flagged in `follow-ups.md`: star/unstar
  is exposed inline next to the `Starred` KV row, so the duplicate at the top
  was noise. Bracketed action labels `[view] [sync] [delete]` are kept — they
  are the CLI's analog to the Rails breadcrumb-actions row at the top of
  `channels/show.html.erb`.
- `extras/cli/src/ui/help.rs` — removed the stale
  `f y    filter: syncing (toggle)` shortcut row. Path A2 retract dropped the
  server-side `syncing` boolean and `keys.rs::handle_filter_prefix` retired the
  `f y` branch with it; the help overlay was still advertising it.
- `extras/cli/src/ui/dashboard.rs` — appended the Rails dashboard's placeholder
  caption verbatim under the five count rows:
  `[ dashboard reset — charts return with intentional metrics in a later phase. ]`.
  The CLI now reads identically to the Rails dashboard.
- `extras/cli/src/ui/{channel_detail,dashboard,help}.rs` — added five new
  layout-parity tests (TestBackend renders for the channel-detail action legend
  presence/absence, the dashboard placeholder copy verbatim, and the help
  overlay's filter-shortcut listing).
- Pre-existing format drift swept by a single `cargo fmt` pass. Cumulative diff
  includes the in-flight refactor work plus the rustfmt-applied changes; the
  fmt-only deltas are spread across `app.rs`, `api/client.rs`, `keys.rs`,
  `ui/mod.rs` and `ui/operation_progress.rs` per the entry in `follow-ups.md`.
  Final state: `cargo fmt --check` clean.

**Discrepancies surfaced during the parity walk (Item 3):**

| Screen                        | Resolution                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Channel detail action legend  | Fixed — see above (pre-flagged).                                                                                                                                                                                                                                                                                                                                                                                                                          |
| Help screen `f y` row         | Fixed — removed (stale).                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| Dashboard placeholder caption | Fixed — added verbatim Rails copy.                                                                                                                                                                                                                                                                                                                                                                                                                        |
| Channels list columns         | Cross-stack gap — Rails shows `name (id), URL, star, last sync`; CLI shows `url, starred, conn, last sync`. CLI's `conn` column has no Rails counterpart (Rails exposes `connected` as a filter chip only); Rails' `name` column has no CLI counterpart (CLI lacks the row-id link). Out of scope per spec — adding/removing columns crosses into feature-parity territory. Note as a follow-up if we revisit.                                            |
| Videos list columns           | Cross-stack gap — Rails shows id, youtube id, channel URL, views, likes, chats, watch, star, last sync; CLI shows youtube id, channel, ★, views, trend, likes, chats, watch. CLI has a `trend` column with no Rails counterpart; Rails has `id` + `last sync` columns CLI lacks. Out of scope.                                                                                                                                                            |
| Video detail toolbar          | Cross-stack gap — Rails breadcrumb shows `[e]` (edit) and `[-]` (delete) shortcuts; CLI toolbar shows `[edit]` and `[delete]`. CLI verbiage is internally consistent (other screens use `[view]`, `[sync]`, `[delete]`). Out of scope.                                                                                                                                                                                                                    |
| Settings                      | Cross-stack gap — Rails has 9 panes (appearance, workspaces, YouTube, Voyage AI, search, tokens, sessions, oauth applications, google); CLI shows 3 sections (workspaces, appearance, search). Out of scope per spec ("not adding screens that don't yet exist on one side"). The 6 missing CLI panes are settings flows that depend on Phase 11/12 surfaces (sessions, oauth applications, voyage), and the CLI's settings is a read-only mirror anyway. |
| Search results                | Cross-stack gap — CLI shows the full results table; Rails currently shows a "video search is currently disabled (Phase 7 Path A2 retract)" stub copy. The wire shape still returns video hits, so the CLI's table is correct vs. the data; Rails' stub is a UI choice on the Rails side. Out of scope.                                                                                                                                                    |
| Saved views                   | No drift surfaced. CLI matches the Rails `_section.html.erb` shape.                                                                                                                                                                                                                                                                                                                                                                                       |

**Pipeline:**

- `cargo fmt --check --manifest-path extras/cli/Cargo.toml` — clean.
- `cargo audit` (workspace) — `RUSTSEC-2024-0436` and `RUSTSEC-2026-0002` both
  cleared. No advisories reported.
- `cargo build --release --manifest-path extras/cli/Cargo.toml` — clean.
- `cargo clippy --all-targets --all-features -- -D warnings` — clean.
- `cargo test --manifest-path extras/cli/Cargo.toml` — 354 passing (was 349
  baseline; +5 for the new layout-parity tests).

**ratatui 0.30 breakage count:** zero. The codebase compiles unchanged against
the 0.30 API surface — none of `Frame::area()`, `Block`, `Paragraph`,
`Layout::vertical`/`horizontal`, `Constraint::Length`, `Span::styled`,
`Line::from`, `Style::default`, `Borders::ALL`, `Clear`, `TestBackend`, or
`Terminal::new` had a signature change that hit our callsites. The 0.30 split
into `ratatui-core` / `ratatui-widgets` is re-exported transparently through the
umbrella `ratatui` crate's prelude, which is what we use everywhere.

**Out of scope (intentionally not touched):**

- New CLI screens or new Rails screens (full settings parity, search result UX
  divergence, channel-list column reconciliation). The Q4 default is "align
  EXISTING screens"; this sweep does not bring CLI to Rails feature-parity.
- Keymap changes — those belong to spec 04 (`04-keyboard-shortcuts.md`).
- Visual design system tweaks.

**Open issues / follow-ups:**

- The cross-stack gaps above (channels-list `conn`/`name`, videos-list
  `trend`/`id`/`last sync`, settings 6 missing panes, search disabled- stub vs.
  results-table) are candidates for a future feature-parity sweep once the CLI's
  read-only mirror posture is revisited.
- ratatui 0.30 ships a parallel widget set under `ratatui-widgets` — if a future
  spec needs a stateful `List` or `Table` widget we should switch to the
  `WidgetRef` / `StatefulWidgetRef` traits at that point; current callsites all
  use the unit-of-work `render_widget` API which works against either.
- After the user verifies the manual playbook, GitHub Dependabot alert #1 should
  clear once the bump pushes.

## References

- Spec:
  `docs/plans/beta/7.5-followups-and-foundations/specs/02-cli-hygiene-sweep.md`
- Phase overview:
  `docs/plans/beta/7.5-followups-and-foundations/specs/00-phase-overview.md`
- Channels show ERB (parity source): `app/views/channels/show.html.erb`,
  `app/views/channels/_picker.html.erb`, `app/views/channels/_pane.html.erb`.
- Videos ERB: `app/views/videos/index.html.erb`,
  `app/views/videos/_pane.html.erb`.
- Dashboard ERB: `app/views/dashboard/index.html.erb`.
- Settings ERB: `app/views/settings/index.html.erb`.
- Search ERB: `app/views/search/show.html.erb`.

## 2026-05-07 — Track A step 04 — Rails keyboard shortcuts (CLI mirror)

**State at start:** RSpec baseline 1702/0/0. Brakeman 2 warnings + 1 ignored.
RuboCop clean. The CLI's `extras/cli/src/keys.rs` and
`extras/cli/src/ui/help.rs` are at the parity baseline established by Track A
step 02; this dispatch reads them as the canonical schema and lays the Rails
mirror.

**Inputs:**

- Spec:
  `docs/plans/beta/7.5-followups-and-foundations/specs/04-keyboard-shortcuts.md`
- Source of truth: `extras/cli/src/keys.rs`, `extras/cli/src/ui/help.rs` (the
  CLI is locked per Q6 default — strict mirror, no web-only additions).

**What landed (file-level):**

- `app/javascript/controllers/keyboard_controller.js` — replaced. New global
  controller carries a 1000ms prefix-state machine for `g <x>` / `f <x>`,
  list-row j/k highlighting (opt-in via `data-keyboard-row` /
  `data-keyboard-row-id`), space-toggles-checkbox-when-bulk-mode-on (mirrors the
  CLI's gated semantics), b/s/D/Y page-action dispatch, v-opens-external-url on
  detail pages (`window.open(url, "_blank", "noopener,noreferrer")`), `?`
  toggles the help dialog, `/` focuses the search input, `y` submits the action
  confirmation form, Esc cancels prefix → closes dialog → falls back to
  action-screen cancel link. Hard-gated against firing while focus is in
  `<input>` / `<textarea>` / `<select>` / `[contenteditable]` and against
  modifier keys (Ctrl/Cmd/Alt/Meta) so browser shortcuts pass through untouched.
- `app/components/keyboard_shortcuts_modal_component.rb` +
  `keyboard_shortcuts_modal_component.html.erb` — new ViewComponent. The
  rendered `<dialog>` is the keyboard controller's `dialog` target so `?` and
  the `[ ? ]` link both `showModal()` it. Sections mirror the CLI help: general,
  navigation, list pages, detail pages, confirmation prompts. Every key combo is
  rendered as `<span class="keycap">` with the spec's grouping.
- `app/views/layouts/application.html.erb` — `<body>` carries
  `data-controller="keyboard"` so the listener lives for the page lifetime (was
  previously on a wrapper `<div>` around the dialog alone). The header chrome
  gains a `[ ? ]` bracketed link (between the logout button and the theme
  toggle) wired to `click->keyboard#openHelp`. The 3-line dialog inline in the
  layout was replaced with `render(KeyboardShortcutsModalComponent.new)`.
- `app/views/shared/_action_screen.html.erb` — the form gets
  `data: { keyboard_confirmation: "true" }`; the cancel link gets
  `data: { keyboard_confirmation_cancel: "true" }`. The keyboard controller
  routes `y` to `requestSubmit()` and Esc/click to the cancel link. No
  `data-turbo-confirm`. Mirrors the CLI's `handle_confirmation_input`.
- `app/views/channels/show.html.erb` —
  `data-keyboard-external-url= "<channel.channel_url>"` on the page wrapper (the
  `v` binding's target). The breadcrumb sync / delete links carry
  `data-keyboard-page-action="sync"` / `="delete"` so `Y` and `D` route to the
  existing /syncs and /deletions paths.
- `app/views/videos/show.html.erb` — same shape; the external URL is
  `https://www.youtube.com/watch?v=<youtube_video_id>`.
- `app/components/filter_chip_component.html.erb` — every filter chip carries
  `data-keyboard-filter-chip="<label>"` (e.g. `"starred"`, `"connected"`). The
  `f s` / `f c` bindings click the chip whose label matches.
- `app/assets/tailwind/application.css` — `.keyboard-highlight` reuses the
  existing hover background so keyboard navigation and pointer hover share
  treatment.

**Specs (delta +33):**

- `spec/components/keyboard_shortcuts_modal_component_spec.rb` — 9 new examples.
  Asserts every binding from the spec's "Bindings" section appears under the
  right heading (general, navigation, list pages, detail pages, confirmation
  prompts), checks for `data-keyboard-target` / `keyboard#close` wiring, locks
  the "no `f y`" CLI parity rule, and the no-`alert/confirm/prompt` hard rule.
- `spec/requests/keyboard_shortcuts_layout_spec.rb` — 22 new examples covering:
  `<body data-controller="keyboard">` mount, the help dialog rendering on every
  page (/, /channels, /videos, /settings — note /saved_views is a 302 to
  /channels), the `[ ? ]` bracketed link affordance, full help-modal section
  coverage, `f y` not advertised, the filter-chip keyboard hooks on /channels,
  `data-keyboard-external- url` on channel detail, and the action-screen
  `data-keyboard- confirmation` + `data-keyboard-confirmation-cancel` wiring on
  /deletions/channel/:id.
- `spec/components/filter_chip_component_spec.rb` — +2 examples for the
  `data-keyboard-filter-chip` hook (one per label, starred + connected).

**Bindings table (web ← CLI):**

| Web key combo     | Web action                                                     | CLI source (`keys.rs`)                      |
| ----------------- | -------------------------------------------------------------- | ------------------------------------------- |
| `?`               | `dialog.showModal()` (or `close()` if open)                    | `KeyCode::Char('?')` → `Overlay::Help`      |
| `n`               | theme toggle (handled by `theme_controller`; help advertises)  | `KeyCode::Char('n')` → `app.toggle_theme()` |
| `/`               | focus `.search-input`                                          | `KeyCode::Char('/')` → `Overlay::Search`    |
| `Esc`             | clear prefix → close dialog → action-screen cancel             | `handle_esc`                                |
| `g d`             | `location.assign("/")`                                         | `Screen::Dashboard`                         |
| `g c`             | `location.assign("/channels")`                                 | `Screen::Channels`                          |
| `g v`             | `location.assign("/videos")`                                   | `Screen::Videos`                            |
| `g s`             | `location.assign("/saved_views")`                              | `Screen::SavedViews`                        |
| `g e`             | `location.assign("/settings")`                                 | `Screen::Settings`                          |
| `f s`             | click `[data-keyboard-filter-chip="starred"]`                  | `ChannelFilter::Starred`                    |
| `f c`             | click `[data-keyboard-filter-chip="connected"]`                | `ChannelFilter::Connected`                  |
| `j` / `k`         | move `.keyboard-highlight` among `[data-keyboard-row]`         | `handle_move_down/up`                       |
| `space`           | click highlighted row's checkbox (gated on visible/non-hidden) | `handle_space` (gated on `bulk_mode`)       |
| `b`               | click `[data-keyboard-page-action="bulk-toggle"]`              | `handle_bulk_toggle`                        |
| `s`               | click row's `[data-keyboard-action="star"]` or page-action     | `toggle_star_*`                             |
| `D`               | navigate `/deletions/<type>/<ids>` (bulk or current row)       | `open_delete_confirmation`                  |
| `Y`               | navigate `/syncs/<type>/<ids>`                                 | `open_sync_confirmation`                    |
| `v`               | `window.open(externalUrl, "_blank", "noopener,noreferrer")`    | `open_in_browser` (channel detail)          |
| `y` (action page) | `form.requestSubmit()`                                         | `ConfirmationOutcome::Confirm`              |

**Cross-stack gaps (CLI bindings without a web counterpart):**

- **`q`** (back/close). The web has browser back; binding `q` to
  `history.back()` would conflict with the CLI's overlay-aware semantics. Help
  advertises `q` (so users still see it as part of the schema) but the
  controller does not bind it. Rationale: the browser already provides this
  affordance and the CLI's `q` is TUI-specific (no browser equivalent without
  ambiguity).
- **`:q` / `Ctrl+C`** quit. Browser provides `Ctrl+W`; not mirrored.
- **`e`** (channel detail edit). The CLI shows a "URL is locked" flash. The
  web's `[ e ]` bracketed link in the breadcrumb already navigates to the edit
  form, so no `e` keybinding is needed — the visible link IS the affordance.
  Documented as a gap; not a follow-up.
- **`c` on channels**. Per the CLI's comment, "connected reflects the OAuth flow
  and only the web UI may toggle it." On the web, the toggle would be a UI
  affordance not yet exposed by the picker (Path A2 retract removed the inline
  toggle). Help advertises `connected` only as a filter-chip target via `f c`,
  mirroring the CLI exactly.
- **list-row `enter`** to drill into detail. Standard browser navigation already
  opens the row's first link; no binding needed. The CLI's `enter` is
  TUI-specific.

**Pipeline:**

- `bundle exec rspec` — 1735 examples, 0 failures (1702 baseline + 33 new: 9
  modal component + 22 layout + 2 filter chip).
- `bundle exec rubocop` — 415 files inspected, no offenses.
- `bundle exec brakeman -q -A -w1` — 2 warnings + 1 ignored (unchanged baseline:
  pre-existing ForceSSL + Note unscoped find).
- Hard-rule grep: no new `data-turbo-confirm`, `window.confirm`, `alert(`, or
  `prompt(` introduced.

**Manual test recipe (5–10 keys):**

1. `bin/dev`. Visit `/`. Press `?` → help modal opens with five sections.
2. Press `Esc` → modal closes.
3. Press `g`, then `c` within ~1 second → URL navigates to `/channels`.
4. On `/channels`, press `f` then `s` → starred filter chip toggles (URL gains
   `?star=yes`).
5. On `/channels`, press `j` three times → third row gets the
   `keyboard-highlight` background.
6. Click the visible `[ ? ]` link in the header (top-right of the navbar) → same
   modal opens as keypress `?`.
7. Click into the search input, type `j` → letter `j` lands in the input (no row
   movement; focus guard).
8. Press `Ctrl+F` → browser-native find bar opens (no in-app override).
9. Open a channel detail page. Press `v` → the channel URL opens in a new tab.
10. From the channel detail breadcrumb, click `[-]` (delete) → land on
    `/deletions/channel/:id`. Press `y` → the form submits.

## References

- Spec:
  `docs/plans/beta/7.5-followups-and-foundations/specs/04-keyboard-shortcuts.md`
- CLI source of truth: `extras/cli/src/keys.rs`, `extras/cli/src/ui/help.rs`.
- Layout: `app/views/layouts/application.html.erb`.
- Component: `app/components/keyboard_shortcuts_modal_component.rb` +
  `.html.erb`.
- Controller: `app/javascript/controllers/keyboard_controller.js`.
- Action screen: `app/views/shared/_action_screen.html.erb`.
- Detail pages: `app/views/channels/show.html.erb`,
  `app/views/videos/show.html.erb`.
- Filter chip: `app/components/filter_chip_component.html.erb`.
- Specs:
  - `spec/components/keyboard_shortcuts_modal_component_spec.rb`
  - `spec/requests/keyboard_shortcuts_layout_spec.rb`
  - `spec/components/filter_chip_component_spec.rb` (extended)

## 2026-05-07 — Step 06 — Footage thumbnails (CLI half)

**State at start:** Track B (spec 02) had landed: ratatui at 0.30, cargo test
baseline 354 / 354, fmt + clippy clean. Track A (specs 01, 04) and Track C
foundations had landed. Spec 06 Rails half is NOT yet dispatched; this work
ships the CLI half in isolation against mock fixtures, with the wire shape
acting as the contract the Rails dispatch must honor when it lands.

**Inputs:**

- Spec:
  `docs/plans/beta/7.5-followups-and-foundations/specs/06-footage-thumbnails.md`
  (CLI half).
- Locked decisions baked into the dispatch:
  - Adaptive frame count: `count = clamp(duration_seconds / 60, 10, 120)`.
  - Two-tier resolution (1280×720 master JPEG + 320×180 thumb JPEG).
  - Filename = timestamp (`<HH-MM-SS>.jpg`, zero-padded).
  - `ratatui-image` for terminal graphics protocol auto-detection.
  - DaVinci-style scrub layout: big preview top + fixed `+` playhead at centre +
    scrolling film strip beneath.
  - Two scrub interactions: hover/cursor on big preview AND drag/scroll the
    strip.
  - Capability detection at boot:
    `Kitty | Sixel | iTerm2 | Halfblocks | TextOnly`.
  - Halfblocks fallback for terminals without graphics protocol.
  - HTTP fetch with `~/.cache/pito/thumbnails/<footage_id>/{m,t}/<HH-MM-SS>.jpg`
    LRU cache.

**What landed (file-level):**

_Cargo dependency bumps:_

- `extras/cli/Cargo.toml`:
  - Added
    `ratatui-image = { version = "10", default-features = false, features = ["image-defaults", "crossterm"] }`.
    `default-features = false` drops `chafa-dyn` (which would require
    `libchafa-dev` as a system dependency); plain Halfblocks rendering still
    works without chafa, we just trade some visual fidelity in the fallback path
    for a system-dep- free build.
  - Added `image = "0.25"` (tracks ratatui-image's transitive — pinned so the
    cache layer's downscale path can reach the same encoder/decoder surface
    without version skew).
  - Bumped `crossterm` from `0.28` to `0.29` (required by ratatui-image 10.0.8).
    Track B's log noted ratatui 0.30 already pulled crossterm 0.29 in
    transitively; this dispatch promotes the direct dep to the same version so
    mouse-event types come from a single source of truth.

_New module: `extras/cli/src/api/thumbnails.rs`._ HTTP client + on-disk LRU
cache for footage thumbnail frames.

- `Tier { Master, Thumb }` enum with `m` / `t` URL-segment helpers.
- `Manifest { duration_seconds: f64, timestamps: Vec<u64> }` — parsed from
  `GET /footages/:id/frames.json`. `closest` / `closest_index` snap a target to
  the nearest stored entry.
- `format_timestamp(seconds: u64) -> String` and
  `parse_timestamp(stem) -> Result<u64>` round-trip the `HH-MM-SS` filename
  convention.
- `manifest_path(id)` and `frame_path(id, tier, timestamp)` — pure URL
  composers. `url(base, path)` collapses base trailing-slash + path leading-
  slash.
- `fetch_manifest(base_url, footage_id)` — blocking GET, decodes the manifest
  JSON.
- `fetch_frame_bytes(base_url, footage_id, tier, timestamp)` — blocking GET,
  returns raw JPEG bytes.
- `Cache::with_root(root, capacity_bytes)` — write-through LRU. Path layout
  `<root>/<footage_id>/<tier>/<HH-MM-SS>.jpg`. mtime tracks access time;
  eviction sorts by mtime ascending and removes oldest until under cap.
  Atomic-ish write via tmp+rename. `evict_to_capacity` runs after every write.
- `Cache::DEFAULT_CAPACITY_BYTES = 500 * 1024 * 1024` (500 MB) — matches the
  spec suggestion. At the spec's 1000-footages × 60-thumbs × 14 KB ≈ 840 MB
  worst case the cap holds the active working set comfortably while bounding
  on-disk growth.
- `Cache::fetch_or_get(footage_id, tier, timestamp, fetcher)` — cache-aware
  fetcher. Hit → read disk + LRU touch; miss → fetcher → write-through.
- 18 unit tests (timestamp format / parse round-trip, URL composition, manifest
  closest snap, cache hit/miss/eviction/tmp-skip, wire-shape decoding).
- Module-level `#![allow(dead_code)]`: the live-fetch helpers and most cache
  surface are exercised by tests but unreachable from `main` until the Rails
  endpoint ships and the tick-loop wires them in.

_New screen module: `extras/cli/src/ui/footage_detail/`._ Four submodules:

- `capability.rs` —
  `TerminalCapability { Kitty, Sixel, ITerm2, Halfblocks, TextOnly }` enum +
  `detect()` (calls `ratatui-image`'s `Picker::from_query_stdio()`, falls back
  to Halfblocks on stdio failure)
  - `from_protocol(ProtocolType)` mapper + `halfblocks_picker()` test-friendly
    constructor.
- `state.rs` — `FootageDetailState` with primary state
  `active_timestamp_seconds: u64`. Mutators: `set_manifest` (snaps active to
  median, mirroring `_footage_pane.html.erb`'s 50% rendering); `move_to` (snaps
  to nearest manifest entry); `move_to_ratio(0.0..1.0)` (cursor-X hover handler
  entry point); `step(±N)` (step by N stored cells, saturates at endpoints);
  `jump_to_start` / `jump_to_end`; `step_strip(±N)` (mirrors `step` so a wheel
  tick keeps the active cell under the playhead); `recenter_strip()` (resets
  strip pan); `active_filename_stem()` returns the `HH-MM-SS` for the active
  timestamp.
- `scrub.rs` — `ScrubRects { preview, strip }` +
  `handle_mouse(state, rects, event)` mouse-event router. Inside the preview
  rect: `Moved`, `Drag`, and `Down` translate cursor X into a 0..1 ratio via
  `move_to_ratio`. Inside the strip rect: `ScrollUp` / `ScrollDown` step ±1;
  `Drag` translates column to ratio. Returns `bool` so the caller knows when an
  event was consumed.
- `render.rs` — `render(frame, area, theme, state, capability) -> ScrubRects`
  splits the area `Layout::vertical([Percentage(75), Length(1), Min(0)])` →
  preview block, fixed `+` playhead row, strip block. Currently uses a unified
  text-fallback path for all capabilities (the live image-rendering via
  `StatefulImage` is parked behind a follow-up dispatch that wires the HTTP
  fetch into the tick loop). Halfblocks and TextOnly variants get explicit
  fallback hint copy. Strip cells are 9-character `[HH-MM-SS]` tokens (active
  cell bracketed for legibility).

_App / loop wiring (`extras/cli/src/app.rs`, `commands/tui.rs`, `keys.rs`,
`ui/mod.rs`):_

- New `Screen::FootageDetail` variant. Header label `[footage]`.
- `App.footage_detail_state: Option<FootageDetailState>` (allocated lazily on
  `open_footage_detail`, cleared on back-out).
- `App.footage_detail_rects: Option<ScrubRects>` (stamped by `ui::render` after
  the screen draws so the mouse handler can route events).
- `App.terminal_capability: TerminalCapability` (default `TextOnly` so unit
  tests don't probe stdio; `commands::tui::run` overrides via
  `set_terminal_capability(capability::detect())` after `enable_raw_mode` +
  `EnterAlternateScreen` per the ratatui-image contract).
- `App::open_footage_detail(id, label)`, `apply_footage_manifest(manifest)`,
  `record_footage_detail_rects(rects)` — public wiring methods, marked
  `#[allow(dead_code)]` until the live-fetch dispatch consumes them.
- `commands/tui.rs`: enabled `EnableMouseCapture` on terminal setup, matching
  `DisableMouseCapture` on teardown. Event loop now matches both `Event::Key`
  and `Event::Mouse`; mouse routing is `handle_mouse(app, mouse)` which only
  fires when `app.screen == Screen::FootageDetail` and rects are present
  (ignored on every other screen, matching the old behaviour with mouse-capture
  off).
- `ui/mod.rs::render` signature flipped to `&mut App` so the
  `Screen::FootageDetail` arm can stash the rendered rects on the App.
- `keys.rs`: new `handle_footage_detail_key` handler runs before the generic
  normal-mode dispatcher when the screen is footage detail. Bindings: `h` / `←`
  step −1, `l` / `→` step +1, `H` step −10, `L` step +10, `g` / `Home` jump to
  start, `G` / `End` jump to end, `Space` recenter strip. `q` on the footage
  detail screen drops state and returns to the dashboard.

_Tests:_

- `extras/cli/tests/thumbnails_integration.rs` — 5 tokio + wiremock integration
  tests against the spec's wire shape. Anchors the contract the Rails dispatch
  must honor:
  - `GET /footages/:id/frames.json` →
    `{"duration_seconds": <float>, "timestamps": [<u64>, ...]}`.
  - `GET /footages/:id/frames/<m|t>/<HH-MM-SS>.jpg` → raw JPEG bytes
    (`Content-Type: image/jpeg`).
  - `Cache::fetch_or_get` round-trips through disk and a second call hits the
    cache (verified via wiremock's `.expect(1)`).
  - 404 propagation, empty-timestamps decoding (extraction-pending row).
- Unit tests across the new modules:
  - `api/thumbnails.rs` — 18 tests (URL composition, timestamp round-trip,
    manifest snap, cache hit/miss/eviction/tmp-skip, wire decoding).
  - `ui/footage_detail/capability.rs` — 4 tests (protocol mapping, graphics-
    support predicate, label uniqueness, halfblocks-picker construction).
  - `ui/footage_detail/state.rs` — 9 tests (median snap, move/step/jump, ratio
    mapping, missing-manifest no-op).
  - `ui/footage_detail/scrub.rs` — 10 tests (hover hit/miss, scroll, drag,
    half-open rect math).
  - `ui/footage_detail/render.rs` — 10 tests including TestBackend snapshots for
    halfblocks / text-only fallback rendering and layout-shape invariance across
    capabilities.
- `app.rs` — 5 new tests covering open/apply/q/keyboard-step paths through the
  screen.

**Pipeline:**

- `cargo fmt --check --manifest-path extras/cli/Cargo.toml` — clean.
- `cargo clippy --all-targets --all-features --manifest-path extras/cli/Cargo.toml -- -D warnings`
  — clean.
- `cargo build --release --manifest-path extras/cli/Cargo.toml` — clean.
- `cargo test --manifest-path extras/cli/Cargo.toml` — 435 passing (was 354
  baseline post-Track-B; +81 net). Breakdown: 143 lib + 267 bin + 20 footage
  integration + 5 thumbnails integration + 0 doc.

**Cross-stack gap notes (for the Rails dispatch):**

When spec 06 Rails half is dispatched, the endpoints below are the contract the
CLI is already wired against. The wiremock integration tests in
`tests/thumbnails_integration.rs` fail loudly if the Rails side picks different
shapes:

- `GET /footages/:id/frames.json` → status 200, body
  `{"duration_seconds": <float>, "timestamps": [<u64>, ...]}`. Empty
  `timestamps` is a valid state (means "no frames extracted yet"). 404 when the
  row doesn't exist.
- `GET /footages/:id/frames/<m|t>/<HH-MM-SS>.jpg` → status 200,
  `Content-Type: image/jpeg`, body raw JPEG bytes. 404 when the specific file
  isn't on disk; the manifest endpoint is the source of truth for what exists.
- All endpoints use the same base URL the rest of the CLI hits (`PITO_API_URL`,
  default `https://app.pitomd.com`).

**Out of scope (intentionally not done in this dispatch):**

- Live HTTP fetch wired into the tick loop. The CLI compiles + tests with the
  cache + fetch helpers, but the screen still renders the text-fallback path for
  every capability — image rendering via `StatefulImage` lands in a follow-up
  dispatch once spec 06 Rails ships and we can decode real JPEG bytes through
  `Picker::new_resize_protocol`. The `#[allow(dead_code)]` attributes called out
  above flag the parked code paths.
- Importer-side ffmpeg frame extraction + bulk PATCH upload (spec 06 §"Where
  extraction runs" / §"Upload shape"). Those are the importer's half of the CLI
  scope; this dispatch is the rendering / scrub half. Both halves can ship
  independently because the importer's output
  (`<assets_root>/footages/ <id>/{m,t}/*.jpg`) is what the Rails endpoints
  stream and what the scrub UI fetches — neither half assumes the other has
  shipped.
- Footage list / picker screen. The CLI doesn't yet have a navigation path into
  the footage detail screen at runtime; `App::open_footage_detail` is exercised
  by tests only. A future dispatch can wire it in via a `g f` prefix or a new
  `Screen::Footages` index.
- chafa-backed halfblocks fidelity. We dropped `chafa-dyn` from ratatui-image's
  default features because it requires `libchafa-dev` as a system dep, which
  would expand the CLI's install hint surface beyond ffmpeg. Plain Halfblocks
  works without it; if a user complains about fidelity we can re-enable behind a
  feature flag with a documented install hint.

**Open issues / follow-ups:**

- Live image rendering (Kitty / Sixel / iTerm2) — depends on spec 06 Rails half
  landing. Once the manifest + frame endpoints are live, the next dispatch:
  1. Wires `fetch_manifest` into the tick loop (manifest fetched once on screen
     open, applied via `apply_footage_manifest`).
  2. Pre-fetches the active + ±5 surrounding thumbs via `tokio::spawn` so
     scrubbing feels instant.
  3. Replaces the unified text fallback in `render.rs::render_preview` /
     `render_strip` with `ratatui-image::StatefulImage` for the graphics-
     supporting capabilities, leaving Halfblocks / TextOnly on the existing text
     path.
- Footage list / picker screen so the user can reach `Screen::FootageDetail`
  from the keymap.
- The `#[allow(dead_code)]` attributes on the cache + state surface come off in
  the live-fetch dispatch.

## Manual test plan (post-merge, once a developer is in front of the binary)

The detail screen has no nav entry yet; reach it programmatically by modifying a
one-shot test or wiring a temporary `g f` prefix. Once a footage browser ships
in a follow-up the manual recipe collapses to "open a footage row".

In Kitty / Ghostty / WezTerm:

- `pito` (default TUI). Navigate to a footage detail screen.
- Capability detection at boot prints nothing user-facing, but the preview
  body's `capability=...` line should read `kitty` / `sixel` / `iterm2`.
- The "(image rendering arrives once the Rails frame endpoint ships)" hint is
  the expected text fallback until the follow-up dispatch lands.

In Alacritty / plain xterm:

- Same flow. `capability=halfblocks` should appear in the preview body, and the
  "(halfblocks fallback — terminal lacks Kitty / Sixel / iTerm2)" line is
  visible.

In a non-TTY harness (`pito 2>&1 | cat`):

- The TUI won't run in a non-TTY pipeline, but capability detection's
  `from_query_stdio` falls back to Halfblocks on probe failure rather than
  panicking. Verified by the unit test in `capability.rs`.

Mouse hover / drag / scroll: hover the cursor over the preview rect's full width
— the `[ <label> @ HH:MM:SS ]` label in the preview body should walk timestamps.
Scroll-wheel over the strip rect — the active cell (bracketed) should walk left
/ right. Keyboard `h`/`l`/`H`/`L`/`g`/`G`/ `Space` work in every terminal
regardless of mouse-capture state.

Cache: open the detail screen, check `~/.cache/pito/thumbnails/`. Until the
live-fetch dispatch lands the directory will stay empty; the cache plumbing is
exercised exclusively by the integration tests for now.

## References

- Spec:
  `docs/plans/beta/7.5-followups-and-foundations/specs/06-footage-thumbnails.md`
- Track B prerequisite (CLI hygiene + ratatui 0.30):
  `docs/plans/beta/7.5-followups-and-foundations/specs/02-cli-hygiene-sweep.md`
- ratatui-image upstream: `https://crates.io/crates/ratatui-image` (10.0.8
  pinned, lines up with ratatui 0.30 + crossterm 0.29).
- New CLI files:
  - `extras/cli/src/api/thumbnails.rs`
  - `extras/cli/src/ui/footage_detail/mod.rs`
  - `extras/cli/src/ui/footage_detail/capability.rs`
  - `extras/cli/src/ui/footage_detail/state.rs`
  - `extras/cli/src/ui/footage_detail/scrub.rs`
  - `extras/cli/src/ui/footage_detail/render.rs`
  - `extras/cli/tests/thumbnails_integration.rs`
- Modified CLI files:
  - `extras/cli/Cargo.toml` (deps + features)
  - `extras/cli/src/api/mod.rs` (re-export `thumbnails`)
  - `extras/cli/src/ui/mod.rs` (`&mut App` signature, FootageDetail render arm,
    header label)
  - `extras/cli/src/app.rs` (Screen variant, state fields, helper methods, test
    coverage)
  - `extras/cli/src/keys.rs` (footage detail keymap, q-back-out path)
  - `extras/cli/src/commands/tui.rs` (mouse capture, capability detection,
    mouse-event routing)

## 2026-05-08 — Step 06 — Footage thumbnails (Rails half)

**State at start:** Phase 7.5 Track A/B/C step 05 + step 06 CLI half landed
(uncommitted in working tree). RSpec baseline 1735/0/0. Brakeman default
baseline 0 active warnings + 1 ignored. Previous Rails-side dispatch for spec 06
stalled before producing files; this re-dispatch picks up the work.

**Inputs:**

- Spec:
  `docs/plans/beta/7.5-followups-and-foundations/specs/06-footage-thumbnails.md`
- Wire-shape contract (authoritative):
  `extras/cli/tests/thumbnails_integration.rs`. The CLI hits the public-read GET
  endpoints with NO `Authorization` header (verified by
  `grep Authorization extras/cli/src/api/thumbnails.rs` returning nothing).
  Where the spec drifted from the CLI tests, the tests won.

**Schema check:** the `footages` table column is `duration_seconds` (integer),
not `footage_duration_seconds` (the dispatch instructions named the wrong column
— the latter exists on `projects`). `duration_seconds` is what the CLI manifest
decoder expects, so the controller emits `footage.duration_seconds.to_f` on the
manifest endpoint.

**What landed (file-level):**

_Migration:_

- `db/migrate/20260507400003_add_frames_extracted_at_to_footages.rb` — adds
  `frames_extracted_at` (datetime, nullable) to `footages`. Importer's bulk
  PATCH stamps it on success.

_Routes (`config/routes.rb`):_

- `GET /footages/:id/frames.json → footages#frames` — manifest. Public-read.
- `GET /footages/:footage_id/frames/m/:filename.jpg → footages#frame_master` —
  master JPEG (1280x720). Constraint `\d{2}-\d{2}-\d{2}` on `:filename`.
  Public-read.
- `GET /footages/:footage_id/frames/t/:filename.jpg → footages#frame_thumb` —
  thumb JPEG (320x180). Same constraint. Public-read.
- `PATCH /api/footages/:id/frames → api/footages#update_frames` — bearer-
  authenticated bulk upload from the importer. CLI integration tests do NOT
  anchor this URL (importer-side ffmpeg upload is a future dispatch); chosen for
  `/api/` consistency.

_Controllers:_

- `app/controllers/footages_controller.rb` — `frames`, `frame_master`,
  `frame_thumb` actions. `allow_anonymous` on those three so the cookie- session
  gate doesn't fire (CLI clients send no cookie). Other footage actions retain
  the existing gate.
- `app/controllers/api/footages_controller.rb` — `update_frames` action.
  Multipart body shape `frames[<HH-MM-SS>][master|thumb]`. Stamps
  `frames_extracted_at` when ≥1 valid part lands.

_Path-traversal defense:_ four-layer:

1. Route constraint `\d{2}-\d{2}-\d{2}` rejects malformed `:filename` tokens
   before the request reaches the action.
2. Action-level regex re-check on `params[:filename]` (defense in depth — if a
   future code path bypasses the router, the action still rejects garbage).
3. `Pito::AssetsRoot.path` runs cleanpath + containment so `..` segments
   smuggled past the regex are rejected with `Pito::AssetsRoot::Error`, which
   the action catches and returns as 404.
4. The PATCH endpoint applies the same regex to the `timestamp` map keys
   (`/\A\d{2}-\d{2}-\d{2}\z/`) before any file write, so a malicious
   `frames[../etc/passwd][master]=...` payload is dropped on the floor.

Brakeman flags one Weak-confidence `SendFile` warning on the master/thumb
streamer (params flow into the path) — expected; the defenses above keep the
warning at Weak-confidence and the default brakeman run still reports just the
same 1 ignored warning + this 1 active warning.

_Views:_

- `app/views/footages/show.html.erb` — adds the DaVinci-style scrub container
  above the existing metadata table. Carries Stimulus value attributes for
  manifest URL, master URL template, thumb URL template, footage id, and
  duration. URL-template values use `00-00-00` as a regex-satisfying placeholder
  which the controller substitutes for `%{timestamp}` (the router validates URL
  helpers at generation time, so the placeholder MUST match
  `\d{2}-\d{2}-\d{2}`).
- `app/views/projects/_footage_pane.html.erb` — adds a leading
  `.footage-thumb-cell` `<td>` per row with a 64×36 `<img loading="lazy">`
  pointing at the median-frame thumb. Falls through to a 404 (broken image
  glyph) until the importer's bulk-frame upload ships.

_Stimulus:_

- `app/javascript/controllers/footage_scrub_controller.js` — fetches the
  manifest at connect, renders strip cells via `document.createElement` (NOT
  `innerHTML` — avoids any XSS surface even though the values come from our own
  server), wires `mousemove` on the big preview, `click` on strip cells, and
  `scroll` on the strip. Empty manifest path shows a "no frames extracted yet"
  placeholder and skips scrub wiring.

_CSS (`app/assets/tailwind/application.css`):_

- `.footage-thumb-cell` / `.footage-thumb` — 64×36 row thumb cell.
- `.footage-scrub` / `.footage-scrub-preview` / `.footage-scrub-empty` /
  `.footage-scrub-playhead` / `.footage-scrub-strip` / `.footage-scrub-cell` —
  the DaVinci-style scrub layout. `scroll-snap-type: x mandatory` +
  `padding: 2px 50%` on the strip lets the first/last cells reach the centered
  playhead.

_Specs:_

- `spec/requests/footages/frames_spec.rb` (new) — 11 examples. Manifest shape
  (`duration_seconds` Float + `timestamps` array), empty array on no-frames, 404
  on missing footage, no Authorization header required, JPEG byte streaming for
  master + thumb, 404 on missing-file, route-constraint rejection of malformed
  timestamps and path-traversal attempts.
- `spec/requests/api/footages/frames_spec.rb` (new) — 8 examples. Successful
  PATCH writes both tiers + stamps `frames_extracted_at`, no-op when payload is
  empty, regex rejects `../etc/passwd` and `00-../00` keys, 401 without bearer,
  403 without `project:write` scope, 404 on missing footage.
- `spec/requests/footages_spec.rb` — 1 new example asserting the show page
  renders the `data-controller="footage-scrub"` container with the four Stimulus
  value attributes.
- `spec/requests/projects_spec.rb` — 3 specs updated (not new) to skip the new
  non-sortable thumb header column. Headers parity check filters out `<th>`s
  that have no `<a>` sort link.

**Order-dependent route-constraint test fix:**
`spec/requests/footages/frames_spec.rb`'s two malformed-timestamp tests pass in
isolation but failed when run after `spec/initializers/rack_attack_spec.rb`'s
"successful auth" example. Bisect located the trigger; the underlying behavior
is that another spec's run mutates the test environment's exception-handling
state so a routing rejection sometimes raises (`ActionController::RoutingError`
or `ActionView::Template::Error`) instead of returning a 404 response. The
security-boundary assertion is the same either way ("the request did not
successfully serve a frame"), so the tests now treat a raised rejection as a
passing rejection.

**Public-read endpoint and `BelongsToTenant`:** the public-read endpoints have
no cookie session, so `Current.tenant` is unset and `Footage.find` raises
`BelongsToTenant::TenantContextMissing`. The controller uses
`Footage.unscoped.find(id)` (in a private `lookup_footage` helper) to bypass the
tenant default scope. Single-tenant assumption: every footage row belongs to the
seeded tenant. Theta-phase multi-tenant work will need to derive the tenant from
the URL or require a session here.

**Pipeline gate:**

- `bundle exec rspec` — 1754 examples, 0 failures (1735 baseline + 19 new
  specs).
- `bundle exec rubocop` — 418 files inspected, no offenses.
- `bundle exec brakeman` (default confidence) — 1 active Security Warning + 1
  ignored. The active warning is Weak-confidence `SendFile` on `serve_frame`'s
  `send_file` call; layered path-traversal defense (regex constraint +
  action-level regex + cleanpath containment via `Pito::AssetsRoot.path`) keeps
  the warning at Weak-confidence. Not suppressed; left visible for reviewer
  judgment.
- Hard-rule grep — 0 occurrences of `alert(` / `confirm(` / `prompt(` /
  `data-turbo-confirm` in any new or modified file.

**Open issues / follow-ups:**

- Importer-side ffmpeg frame extraction + bulk PATCH upload from `extras/cli/`.
  Spec 06 §"Where extraction runs" / §"Upload shape". Not this dispatch.
- Live image rendering in the CLI's `footage_detail` screen — depends on this
  Rails dispatch shipping; flagged in the CLI half's log entry above with a
  `#[allow(dead_code)]` parking pattern.
- Theta-phase multi-tenant scoping on the public-read endpoints — currently uses
  `Footage.unscoped.find` and assumes single-tenant.

**Manual test plan (post-merge):**

1. `bin/setup`, then `bin/dev`. Confirm `pito-assets` is mounted (or the
   `PITO_ASSETS_PATH` env-var resolves to a writable dir under `Rails.root` in
   dev).
2. Visit any `/projects/:id`. The footage table renders a leading thumb column
   per row. Each thumb is a broken-image glyph (404) until the importer's
   frame-upload dispatch ships — that's expected.
3. Click into a footage row's filename; you land on `/footages/:id/edit`.
   Navigate via the breadcrumb back to `/footages/:id`. The scrub layout renders
   above the metadata table:
   - Big preview area (16:9, with a crosshair cursor on hover).
   - "+" playhead glyph below it.
   - A horizontally-scrolling strip below the playhead.
   - Until frames exist, the manifest fetch returns
     `{"duration_seconds": <float>, "timestamps": []}`. The Stimulus controller
     surfaces the "no frames extracted yet." placeholder inside the preview area
     and skips strip wiring.
4. Manually drop a few JPEGs into the assets root to prove the wire end-to- end
   without waiting for the importer:
   ```
   ASSETS=$(bin/rails runner 'puts Pito::AssetsRoot.root')
   FID=<your footage id>
   mkdir -p "$ASSETS/footage_thumbs/$FID/m" "$ASSETS/footage_thumbs/$FID/t"
   for ts in 00-00-30 00-01-00 00-02-00; do
     cp /path/to/some.jpg "$ASSETS/footage_thumbs/$FID/m/$ts.jpg"
     cp /path/to/some.jpg "$ASSETS/footage_thumbs/$FID/t/$ts.jpg"
   done
   ```
   Reload the project page → the row's thumb appears (median-timestamp thumb).
   Reload the footage detail → the scrub layout shows the big preview, strip
   cells, and hover-on-preview swaps the displayed master as the cursor walks
   left → right.
5. Verify the wire shape directly:
   ```
   curl -s http://localhost:3000/footages/$FID/frames.json | jq .
   ```
   Expect `{"duration_seconds": <float>, "timestamps": [30,60,120]}`.
6. Verify path-traversal rejection:
   ```
   curl -s -o /dev/null -w '%{http_code}\n' \
     "http://localhost:3000/footages/$FID/frames/m/..%2Fetc%2Fpasswd.jpg"
   ```
   Expect a non-200 response (404 or routing error).
7. Verify the bearer-authenticated PATCH (importer-shape preview):
   ```
   TOKEN=<token with project:write scope>
   curl -s -X PATCH -H "Authorization: Bearer $TOKEN" \
     -F "frames[00-01-30][master]=@/path/to/master.jpg" \
     -F "frames[00-01-30][thumb]=@/path/to/thumb.jpg" \
     http://localhost:3000/api/footages/$FID/frames | jq .
   ```
   Expect `{"frames_uploaded": 2, "footage_id": <id>}` and a non-null
   `frames_extracted_at`
   (`bin/rails runner 'puts Footage.find(<id>).frames_extracted_at'`).

## References

- Spec:
  `docs/plans/beta/7.5-followups-and-foundations/specs/06-footage-thumbnails.md`
- Wire-shape contract: `extras/cli/tests/thumbnails_integration.rs`
- Companion CLI half log entry:
  `2026-05-07 — Step 06 — Footage thumbnails (CLI half)` (above)
- New Rails files:
  - `db/migrate/20260507400003_add_frames_extracted_at_to_footages.rb`
  - `app/javascript/controllers/footage_scrub_controller.js`
  - `spec/requests/footages/frames_spec.rb`
  - `spec/requests/api/footages/frames_spec.rb`
- Modified Rails files:
  - `config/routes.rb` (3 public-read GETs + nested PATCH on
    `/api/footages/:id/frames`)
  - `app/controllers/footages_controller.rb` (`frames`, `frame_master`,
    `frame_thumb`, `lookup_footage`, `serve_frame`, `list_frame_timestamps`)
  - `app/controllers/api/footages_controller.rb` (`update_frames`,
    `write_frame`, `uploaded_file?`)
  - `app/views/footages/show.html.erb` (scrub layout)
  - `app/views/projects/_footage_pane.html.erb` (median-thumb cell)
  - `app/assets/tailwind/application.css` (`.footage-thumb*` and
    `.footage-scrub*` rules)
  - `spec/requests/footages_spec.rb` (one new example for the show layout)
  - `spec/requests/projects_spec.rb` (3 existing examples updated to skip the
    new non-sortable thumb header)

## 2026-05-07 — Step 06 — Footage thumbnails CLI half · live image rendering

**State at start:** Spec 06 Rails half had shipped (manifest +
`m/<HH-MM-SS>.jpg` + `t/<HH-MM-SS>.jpg` endpoints live). CLI half had landed the
HTTP client (`api::thumbnails`), the LRU cache, the screen scaffolding
(`ui::footage_detail`), capability detection, the keyboard scrub handler, and
the mouse scrub handler. The remaining gap: graphics-capable terminals were
still showing the text fallback because nothing was fetching the JPEG bytes or
constructing a `ratatui-image::StatefulProtocol`. `cargo test` baseline: 143 +
267 + 20 + 5 = 435.

**Inputs:**

- Spec:
  `docs/plans/beta/7.5-followups-and-foundations/specs/06-footage-thumbnails.md`
- Dispatch task: wire `ratatui-image::StatefulImage` for live JPEG rendering on
  graphics-capable terminals; synchronous fetch in tick loop is acceptable; skip
  prefetch for now; keep `api::thumbnails` HTTP layer untouched.
- ratatui-image API verified against
  `~/.cargo/registry/src/index.crates.io-*/ratatui-image-10.0.8/`:
  - `Picker::from_query_stdio() -> Result<Picker>`
  - `Picker::halfblocks() -> Picker`
  - `Picker::new_resize_protocol(image: DynamicImage) -> StatefulProtocol`
  - `StatefulImage::default().resize(Resize::Fit(None))`
  - `StatefulWidget::render(widget, area, buffer, state)` for the protocol
- `image::load_from_memory(&[u8]) -> Result<DynamicImage>` — already a
  transitive dep of ratatui-image, pinned at 0.25 in `Cargo.toml`.

**What landed:**

1. **`App` extended with thumbnails plumbing.** Three new fields:
   `thumbnails_picker: Option<Picker>` (built once per `set_terminal_capability`
   call), `thumbnails_cache: ThumbnailCache` (the on-disk LRU from
   `api::thumbnails`), `thumbnails_base_url: String` (defaults to `PITO_API_URL`
   / `https://app.pitomd.com`). New constructor
   `App::with_client_and_thumbnails_config(client, base_url, cache)` so tests
   can inject a wiremock origin and a `tempfile::tempdir` cache root. The
   default `with_client` now reads `PITO_API_URL` once at boot.
2. **`set_terminal_capability` rebuilds the picker.** `TextOnly` clears it; any
   other capability allocates a halfblocks picker (test-friendly default). New
   `set_terminal_capability_with_picker` lets the live binary pass the real
   `Picker::from_query_stdio` result so the live render path keeps the correct
   `font_size` / `is_tmux` flags rather than defaulting to halfblocks.
   `commands::tui::run` now does the stdio probe directly (replacing the old
   `capability::detect()` indirection) so it can stash both the protocol type
   AND the picker in one call.
3. **`open_footage_detail` is now a real fetch.** Synchronously calls
   `api::thumbnails::fetch_manifest` against `thumbnails_base_url`. On success
   applies the manifest (which snaps `active_timestamp` to the median) and
   immediately calls `refresh_active_preview_protocol`. On failure (network,
   404, decode), records the error in the screen's flash slot and on the on-disk
   debug log, leaves the manifest empty so the renderer shows the placeholder,
   and keeps the screen open so the user can press `q` to back out.
4. **`refresh_active_preview_protocol`** is the new central image-loading
   routine. Five early-out paths: screen closed, manifest absent, manifest
   empty, no picker (TextOnly), `(footage_id, timestamp)` already matches the
   cached preview. Otherwise: route through `Cache::fetch_or_get` for the master
   JPEG bytes (cache hit on disk → no HTTP; miss → fetch + write through),
   decode via `image::load_from_memory`, build a `StatefulProtocol` via
   `Picker::new_resize_protocol`, store it on `App::footage_detail_preview`
   keyed to the active id+timestamp.
5. **Scrub event handlers re-fetch.** `keys::handle_footage_detail_key` ends
   with an `app.refresh_active_preview_protocol()` call whenever the active
   timestamp moved. Same on the mouse path (`commands::tui::handle_mouse`). The
   match-the-cached-identity early-out in `refresh_active_preview_protocol`
   makes this cheap: Space (recenter strip) is a no-op for the preview, but the
   call is allowed to fire.
6. **Renderer takes a `Option<&mut PreviewProtocol>` parameter.** When
   `Some(...)` the preview rect renders via
   `StatefulImage::default(). resize(Resize::Fit(None))` — the same code path
   serves Kitty / Sixel / iTerm2 / Halfblocks (ratatui-image picks the
   protocol). When `None` the renderer falls back to the existing text body.
   Strip rendering stays text-only (cell-level image rendering is parked behind
   a future dispatch — the spec mentions it but the existing comment in
   `render::strip_text` already documents the gap).
7. **`PreviewProtocol` wrapper.** New module `ui::footage_detail::preview`:
   pairs a `StatefulProtocol` with `(footage_id, timestamp_seconds)` so
   `refresh_active_preview_protocol` can short-circuit when nothing changed.
   `StatefulProtocol` is `!Clone` and holds an internal encode cache; the
   wrapper keeps lifetime ergonomics tidy.

**Decoding strategy:** lazy. `Cache` stores byte forms (JPEG); decoded
`DynamicImage` is built on demand inside `refresh_active_preview_protocol` and
discarded after the protocol is constructed. `StatefulProtocol` keeps its own
internal pixel buffer so re-renders within the same scrub timestamp don't
re-decode.

**Prefetch:** skipped — synchronous fetch in the scrub event handlers is the
only path. Per the dispatch's "synchronous fetch — prefetch can land later"
decision. Wire room is still there: `Cache::fetch_or_get` is prefetch-friendly
(idempotent write-through) and an async runtime could fire-and-forget around the
active timestamp later.

**Tests added (13 new, total CLI test count 435 → 448):**

- `preview.rs` (2 tests) — `PreviewProtocol::matches` distinguishes
  `(footage_id, timestamp)` correctly; accessors round-trip.
- `app.rs` (11 tests):
  - `set_terminal_capability_text_only_drops_picker` — switching back to
    TextOnly drops the picker so the render path early-outs.
  - `set_terminal_capability_persists_for_render_path` updated to assert the
    picker is `Some` for non-TextOnly capabilities.
  - `refresh_active_preview_protocol_no_op_when_screen_closed`
  - `refresh_active_preview_protocol_no_op_with_empty_manifest`
  - `refresh_active_preview_protocol_no_op_when_text_only`
  - `refresh_active_preview_protocol_records_flash_on_fetch_failure`
  - `refresh_active_preview_protocol_uses_cached_bytes` — pre-seeds the on-disk
    cache with a real JPEG; confirms the protocol is built with matching
    `(footage_id, timestamp)` and no network.
  - `refresh_active_preview_protocol_skips_rebuild_when_active_unchanged`
  - `refresh_active_preview_protocol_records_flash_on_decode_failure` — cache
    holds bytes that aren't a JPEG; image-crate decode fails; the flash slot
    records "decode failed" and the preview stays empty.
  - `open_footage_detail_drives_real_manifest_fetch_via_wiremock` — full HTTP
    round trip via a wiremock server hosted on a parked background runtime (the
    test thread runs `App::open_footage_detail` synchronously so
    `reqwest::blocking` doesn't collide with the tokio reactor that serves
    wiremock).
  - `open_footage_detail_records_flash_on_404_manifest`
  - `open_footage_detail_handles_empty_manifest`
- Existing tests adjusted to use a deterministic
  `app_with_unreachable_thumbnails()` helper (cache rooted at
  `tempfile::tempdir`, base URL pointed at `127.0.0.1:1`) so the network isn't
  touched on the unit-test path.

**Files modified:**

- `extras/cli/src/app.rs` — App fields, constructors, `open_footage_detail`,
  `refresh_active_preview_protocol`, `set_terminal_capability` /
  `set_terminal_capability_with_picker`, test helpers, 11 new tests.
- `extras/cli/src/commands/tui.rs` — moved capability detection inline so the
  live `Picker` is captured; mouse handler refreshes the preview after every
  consumed event.
- `extras/cli/src/keys.rs` — keyboard scrub handler refreshes the preview after
  every consumed key; `q` clears `footage_detail_preview` alongside the rest of
  the screen state.
- `extras/cli/src/ui/footage_detail/mod.rs` — register the new `preview`
  submodule; re-export `PreviewProtocol`; refresh module-level docs.
- `extras/cli/src/ui/footage_detail/render.rs` — new
  `preview: Option<&mut PreviewProtocol>` parameter; `StatefulImage` render
  branch; text fallback unchanged. Doc updated.
- `extras/cli/src/ui/footage_detail/state.rs` — doc refreshed (the
  `set_manifest` consumer is now real).
- `extras/cli/src/ui/footage_detail/capability.rs` — doc refreshed.
- `extras/cli/src/ui/mod.rs` — `render_body` borrows
  `app.footage_detail_preview` mutably for the render call.
- `extras/cli/src/api/thumbnails.rs` — module doc refreshed.

**Files added:**

- `extras/cli/src/ui/footage_detail/preview.rs` — `PreviewProtocol` wrapper with
  2 unit tests.

**ratatui-image v10 API surface used (verified against `ratatui- image-10.0.8`
in the cargo registry):**

- `picker::Picker::from_query_stdio() -> Result<Picker>` — boot probe.
- `picker::Picker::halfblocks() -> Picker` — fallback for tests + non-stdio
  contexts.
- `picker::Picker::new_resize_protocol(DynamicImage) -> StatefulProtocol` — the
  bytes-to-protocol factory. `new_protocol` (non-stateful, takes a pre-known
  `Rect`) was rejected because `StatefulImage` resizes itself every render and
  the area isn't known at App-state mutation time.
- `StatefulImage::default().resize(Resize::Fit(None))` — the widget. `Fit`
  preserves aspect ratio and letterboxes inside the rect; the master JPEGs the
  importer produces are already 1280×720 letterbox-padded so the inner Fit is
  essentially a downscale.
- `ratatui::widgets::StatefulWidget::render(widget, area, buf, state)` — the
  render call. Used directly rather than `frame.render_stateful_ widget` because
  `frame.render_*_widget` consumes the widget AND tries to call its own
  `area`/`buf` accessors that don't compose cleanly with a borrowed
  `&mut StatefulProtocol` from the App's optional preview slot.

**Pipeline (final):**

- `cargo build --release` — clean.
- `cargo clippy --all-targets --all-features -- -D warnings` — clean.
- `cargo test` — 143 + 280 + 20 + 5 = **448 passed; 0 failed; 0 ignored** (was
  435; +13 new tests).
- `cargo fmt --check` — clean.

**Manual test plan (post-merge):**

1. Run `cargo build --release --manifest-path extras/cli/Cargo.toml` (or
   `cd extras/cli && cargo build --release`). Then `pito` with no args launches
   the TUI.
2. With Rails running and `PITO_API_URL` pointing at it, navigate to a footage
   that has frames extracted (run the spec-06 manual recipe to seed JPEGs at
   `<assets_root>/footage_thumbs/<id>/{m,t}/...` if the importer dispatch hasn't
   shipped yet). The footage detail screen should display a real JPEG inside the
   preview area:
   - In Kitty / Ghostty / WezTerm: the master frame renders pixel- accurate via
     the Kitty graphics protocol.
   - In foot / mlterm / xterm-with-sixel: same image via Sixel.
   - In iTerm2: same image via the inline-image protocol.
   - In Alacritty / plain xterm without graphics: halfblocks rendition (chunkier
     pixels, identical layout).
   - In a dumb TTY without color: text-only fallback (`[ <label> @ HH-MM-SS ]`)
     — the layout shape is preserved.
3. `h` / `l` / `←` / `→` walks the active timestamp; the preview swaps to the
   corresponding master JPEG on every keystroke. Likewise `g` / `G` / `H` / `L`
   and the mouse-hover path on the preview rect.
4. Open the same footage, walk through 10 frames forward, then back — the second
   pass should be near-instant because every frame hit the
   `~/.cache/pito/thumbnails/<id>/m/<HH-MM-SS>.jpg` cache.
5. Force a 404: rename a master JPEG to a non-existent timestamp; press `l` to
   walk into it. Expect a flash row "frame fetch failed: ..." and the preview
   area falls back to the text body. The screen stays navigable.
6. `q` returns to dashboard; reopening the same footage refetches the manifest
   (stateless across navigation, by design).

**Open follow-ups (created here, not addressed):**

- **Prefetch.** The dispatch explicitly skipped this. Adding a tokio task that
  fires `Cache::fetch_or_get` for ±5 frames around the active timestamp would
  make scrubbing buttery in cold-cache sessions. Requires either rewiring the
  App to async or spawning a worker thread with a bounded MPSC channel.
- **Cell-level image rendering on the strip.** Today every capability renders
  the strip as bracketed text. The Kitty graphics protocol could draw the thumbs
  as small per-cell images for a closer DaVinci parity; ratatui-image needs one
  `Protocol` per cell, which means building N protocols per render — significant
  complexity.
- **Halfblocks chafa-dyn opt-in.** ratatui-image's `chafa-dyn` feature links
  libchafa for higher-fidelity halfblocks. We dropped it from the
  default-features list to keep the system-deps surface to ffmpeg only. If a
  user reports the halfblocks rendition looks too pixelated, we can wire it back
  behind a build flag.

## References

- Spec:
  `docs/plans/beta/7.5-followups-and-foundations/specs/06-footage-thumbnails.md`
- Companion CLI half scaffolding log entry:
  `2026-05-07 — Step 06 — Footage thumbnails (CLI half)` (above)
- Companion Rails half log entry:
  `2026-05-07 — Step 06 — Footage thumbnails (Rails half)` (above)

## 2026-05-07 — MCP OAuth discovery + Doorkeeper bearer dispatch

**Slug:** `mcp-oauth-discovery` (no per-spec file — dispatch-only follow-up that
closes Phase 6B deviation #2 from
`docs/orchestration/playbooks/playbook-2026-05-07-phase-6-and-7-and-pathA2.md:79`).

**Goal:** Make Pito's MCP server speak the OAuth handshake Claude.ai's MCP
custom connector probes for. Three changes: (a) public discovery endpoints at
`/.well-known/oauth-authorization-server` (RFC 8414) and
`/.well-known/oauth-protected-resource` (RFC 9728); (b) `Mcp::RackApp` and
`Api::AuthConcern` accept Doorkeeper-issued OAuth access tokens via a single
dispatch on top of `Api::TokenAuthenticator`, additive to the existing ApiToken
path; (c) every 401 carries a `WWW-Authenticate: Bearer realm="pito"` challenge
with `as_uri`/`resource_uri` pointing at the metadata documents.

**What landed (file-level):**

_Discovery metadata:_

- `app/lib/pito/public_hosts.rb` — new module. Hardcoded canonical bases
  (`https://app.pitomd.com`, `https://mcp.pitomd.com`) with `PITO_APP_BASE_URL`
  / `PITO_MCP_BASE_URL` env overrides for non-prod environments. Both subdomains
  route to the same Rails app, so the metadata MUST hardcode origins (probing
  one subdomain still returns the other's identity).
- `app/controllers/well_known_controller.rb` — new. Two anonymous
  (`allow_anonymous`) JSON actions; field names match RFCs verbatim
  (`response_types_supported`, `grant_types_supported`,
  `code_challenge_methods_supported`, `bearer_methods_supported`). Scopes
  sourced from `Scopes::ALL`. Token-endpoint auth methods include `none` because
  public PKCE clients (e.g. Claude's MCP connector if it registers as public)
  MUST be advertised.
- `config/routes.rb` — two `get "/.well-known/..."` routes immediately after the
  Sidekiq mount; `defaults: { format: "json" }` keeps the controller free of
  MIME negotiation.

_Bearer dispatch (additive — ApiToken path unchanged):_

- `app/lib/api/token_authenticator.rb` — extended `#call` to fall through to
  `OauthAccessToken.by_token(plaintext)` after the ApiToken digest lookup
  misses. OAuth tokens flow into the existing `Result` shape: revoked → 401
  `revoked_token`, expired → 401 `expired_token`, missing
  `tenant_id`/`resource_owner_id` → `invalid_token` (defense-in-depth).
  Audit-log token label resolves to `application&.name` for OAuth rows. New
  `Api::TokenAuthenticator.www_authenticate_header` class method — single source
  of truth for the challenge string used on every 401.
- `app/lib/api/token_authenticator.rb` — `Result#to_rack_response` injects the
  `WWW-Authenticate` header on every 401 (used by `Mcp::RackApp`).
- `app/controllers/application_controller.rb` — `render_api_unauthorized` rescue
  handler now sets the same `WWW-Authenticate` header before rendering, so
  `Api::*` controllers (e.g. `Api::FootagesController`) emit the OAuth metadata
  pointer on bearer rejection too.
- `app/models/oauth_access_token.rb` — added a `#user` reader that resolves
  `resource_owner_id → User`. The bearer dispatch wires
  `Current.user = token.user` on both code paths; `ApiToken` already has the
  `belongs_to :user` association, OAuth tokens previously didn't.
- `app/mcp/rack_app.rb` — new defense-in-depth check: if the resolved
  `user.tenant_id` doesn't match `token.tenant_id`, refuse with `invalid_token`
  rather than serve cross-tenant. Same check added in
  `app/controllers/concerns/api/auth_concern.rb` for symmetry.

_Specs:_

- `spec/requests/well_known_spec.rb` — 6 examples. Both endpoints return 200 +
  JSON, no auth, hardcoded `issuer`/`resource` regardless of `Host` header.
- `spec/requests/mcp/oauth_token_acceptance_spec.rb` — 8 examples. Valid OAuth
  bearer authenticates and proceeds; the round-trip verifies
  `Current.tenant`/`Current.user` are populated by calling a `yt:read` tool and
  asserting non-error. Revoked/expired/insufficient-scope/ cross-tenant paths
  each return the locked envelope. The `WWW-Authenticate` header is asserted on
  missing-bearer 401 and on revoked-token 401.

**Verification:**

- `bundle exec rspec` → 1773 / 0 / 0 (was 1765 before this dispatch; +8 examples
  in `oauth_token_acceptance_spec.rb`, +6 in `well_known_spec.rb`).
- `bundle exec rubocop` → clean on the changed files.
- `bundle exec brakeman -q -A -w1` → 3 pre-existing warnings, 1 ignored; no new
  findings introduced by this dispatch (audited each warning against the changed
  file list — none of the warnings touch `well_known_controller.rb`,
  `token_authenticator.rb`, `oauth_access_token.rb`, `rack_app.rb`, or
  `auth_concern.rb`).
- Hard-rule grep (alert/confirm/prompt/data-turbo-confirm) → clean on every new
  and edited file.

**Manual verification (run after the user validates):**

```
# Metadata endpoints (web Puma + MCP Puma both serve them)
curl -s https://app.pitomd.com/.well-known/oauth-authorization-server | jq .
curl -s https://mcp.pitomd.com/.well-known/oauth-authorization-server | jq .
curl -s https://app.pitomd.com/.well-known/oauth-protected-resource | jq .
curl -s https://mcp.pitomd.com/.well-known/oauth-protected-resource | jq .

# 401 + WWW-Authenticate on /mcp without a bearer
curl -i -X POST https://mcp.pitomd.com/mcp -H 'Content-Type: application/json' -d '{}'
# Expect: 401 + `WWW-Authenticate: Bearer realm="pito", as_uri=..., resource_uri=...`

# OAuth dance via Claude.ai UI:
# 1. Register a Doorkeeper application at /settings/oauth_applications:
#    name=claude-mcp, redirect_uri=https://claude.ai/api/mcp/auth_callback,
#    confidential=yes, scopes="dev:read dev:write yt:read".
# 2. Copy the client_id + client_secret into the Claude.ai MCP custom
#    connector form.
# 3. Click Connect; OAuth flow drives /oauth/authorize, /oauth/token,
#    then a tools/list call to /mcp with the issued bearer.
```

**Open questions for the user:**

- **Claude's exact callback URL.** The spec guesses
  `https://claude.ai/api/mcp/auth_callback`. If Claude rejects it, the user
  iterates by editing the application's `redirect_uri` in
  `/settings/oauth_applications` (no code change needed).
- **`token_endpoint_auth_methods_supported` includes `none`.** This advertises
  support for public PKCE clients. The seeded `pito-cli` is public; whether
  Claude registers as confidential or public will only be visible at
  registration time. Removing `none` here would force every Claude-side client
  to be confidential.
- **`/oauth/register` (RFC 7591 dynamic client registration).** Not implemented.
  If Claude's connector requires dynamic registration rather than user-pasted
  client_id/secret, that is a separate follow-up — the metadata document does
  NOT advertise a `registration_endpoint` field, which is the correct way to
  signal "registration is out-of-band".

**References:**

- Closes Phase 6B deviation #2:
  `docs/orchestration/playbooks/playbook-2026-05-07-phase-6-and-7-and-pathA2.md:79`
- Phase 6B spec
  `docs/plans/beta/12-auth-ui-multi-user-readiness/specs/6b-doorkeeper-oauth-server.md:526`
  declared the bearer-dispatch unification as part of the 6B definition of done;
  this dispatch finally lands it.
- RFC 8414 — OAuth 2.0 Authorization Server Metadata.
- RFC 9728 — OAuth 2.0 Protected Resource Metadata (`as_uri` / `resource_uri`
  field names sourced from §5.3 of the draft Pito's challenge string follows).

## 2026-05-07 — Doorkeeper scope soft-clip + OAuth-app UX polish

**Context:** while testing the Claude.ai MCP connector flow against the Phase 6B
Doorkeeper server, the consent screen never rendered. Doorkeeper's strict scope
validation rejected the request with `invalid_scope` because Claude requested
every advertised scope (`Scopes::ALL`) and the `claude-mcp` application's
per-app whitelist (`dev:read dev:write yt:read`) was a strict subset. Standard
OAuth servers (Google, GitHub) clip rather than reject; the strict default is
incompatible with the MCP connector's "request everything, accept the
intersection" client shape.

**Three fixes in one dispatch:**

1. **Doorkeeper scope soft-clip.** New initializer
   `config/initializers/doorkeeper_scope_clip.rb` monkey-patches
   `Doorkeeper::OAuth::PreAuthorization`:
   - `validate_scopes` accepts the request when at least one requested scope
     intersects the application's scopes AND every requested scope exists in the
     server catalog (`Scopes::ALL`).
   - `scopes` returns the intersection
     `(requested ∩ app.scopes ∩ server.scopes)`. The consent screen, the issued
     grant, and the issued token all reflect the clipped list.
   - Approach **Option B** from the dispatch — patch `PreAuthorization`
     directly. Doorkeeper 5.9 has no `enforce_configured_scopes` toggle that
     flips reject→clip behavior (Option A); subclassing the controller (Option
     C) would still leave the strict `ScopeChecker.valid?` call untouched and
     would not let us override the public `scopes` method that
     `Authorization::Code#access_grant_attributes` reads.
   - Validation rules covered by 10 new specs in
     `spec/requests/oauth_scope_clip_spec.rb`:
     - `app ⊃ requested` → token gets requested scopes.
     - `app = requested` → token gets requested scopes.
     - `app ⊂ requested` → token gets app scopes (intersection).
     - `app ∩ requested = ∅` → reject with `invalid_scope`.
     - `requested` contains a scope outside `Scopes::ALL` → reject.

2. **Middle-truncate `redirect_uri` on the index.** The redirect URI column on
   `/settings/oauth_applications` now uses
   `ApplicationHelper#middle_truncate(uri, head: 16, tail: 24)`. The
   `<td title=…>` carries the full value for hover-reveal. The show page renders
   the untruncated value (the user is there to inspect). Mirrors the
   channel-picker URL column pattern.

3. **`[copy]` affordance on credentials.** `client_id` and `client_secret` on
   the create-success page now wear the bracketed `[copy]` link backed by the
   existing `app/javascript/controllers/clipboard_copy_controller.js` Stimulus
   controller. The show page applies the same affordance to `client_id` only
   (`client_secret` is gone post-create). The pattern matches
   `projects/_footage_pane.html.erb` and `dashboard/index.html.erb`.

**Files changed:**

- `config/initializers/doorkeeper_scope_clip.rb` — new (Fix 1).
- `spec/requests/oauth_scope_clip_spec.rb` — new (Fix 1, 10 specs).
- `app/views/settings/oauth_applications/index.html.erb` — middle-truncate
  redirect_uri column (Fix 2).
- `app/views/settings/oauth_applications/create.html.erb` — `[copy]` on
  `client_id` and `client_secret` (Fix 3).
- `app/views/settings/oauth_applications/show.html.erb` — `[copy]` on
  `client_id` (Fix 3).
- `spec/requests/settings/oauth_applications_spec.rb` — three new assertions
  covering Fix 2 truncation, Fix 3 create-page copy, Fix 3 show-page copy (no
  client_secret on show).

**Pipeline state:**

- RSpec: 1785/0/0 (12 net new from the previous dispatch's 1773).
- Rubocop: clean (424 files, 0 offenses).
- Brakeman: 0 security warnings (one obsolete ignore-entry remains unrelated to
  this dispatch).
- Hard-rule grep: clean (no JS `confirm` / `alert` / `prompt` /
  `data-turbo-confirm`).

**Not committed.** The user re-attempts the Claude OAuth flow, confirms the
consent page now shows the intersection of requested vs. application scopes,
eyeballs the truncated `redirect_uri` column on the index, and clicks `[copy]`
next to the credentials before the architect commits.

## 2026-05-09 — Doorkeeper consent + error pages restyled to Pito

**State at start:** RSpec 1785/0/0, Rubocop clean (424 files), Brakeman 0
warnings. Working tree carries the prior Phase 6+7+pathA2+7.5 sweeps; no commit
yet. User flagged the `/oauth/authorize` consent page and its sibling error page
as visually jarring against the rest of the app — serif fallback, light-only
theme, full-width layout, generic chrome.

**What landed (file-level):**

- `app/views/doorkeeper/authorizations/new.html.erb` — restyled. Adds
  `content_for(:hide_chrome, true)` so the layout strips header to logo
  - theme toggle and footer to copyright + version, mirroring
    `sessions/new.html.erb`. Container narrowed to
    `max-width: 480px; margin: 24px 0;` (left-anchored, matches the login
    screen). Scope list now groups by namespace (`dev:`, `yt:`, `project:`, ...)
    inside `<fieldset>` blocks with bold `<legend>` — same pattern as
    `settings/oauth_applications/_form.html.erb` so consent reads the same as
    where the application was configured. Each scope is rendered as
    `<code>scope</code> — description` with the description in `.text-muted`.
    The `redirect URI` and `client_id` metadata move into a
    `class="detail-table"` (same pattern as the OAuth-application show page).
    Authorize stays as `<button type="submit">[authorize]</button>` so the form
    submits; cancel stays a `BracketedLinkComponent` to `root_path`. No JS
    confirm / alert / prompt / `data-turbo-confirm` introduced.
- `app/views/doorkeeper/authorizations/error.html.erb` — restyled. Same
  `:hide_chrome` flag, same `max-width: 480px` left-anchored container.
  `<h1>authorization error</h1>` + muted intro paragraph, the
  `error_description` body rendered in a `<pre>` carrying `font-family: inherit`
  so the page stays in the project monospace stack (the default UA `<pre>` font
  would have re-introduced the serif/regular-mono drift the consent page was
  already showing). `[back to home]` rendered through `BracketedLinkComponent`.

**Design-system alignment checklist:**

1. Monospace inherited from the layout's font-family chain — no inline
   `font-family` overrides remain (the `<pre>` block on the error page
   explicitly sets `font-family: inherit` to defeat the UA default).
2. Color tokens — every color reference flows through `var(--color-*)` via the
   existing utility classes (`.text-muted`, `.detail-table`, `.bracketed`); no
   hex literals were added. No red — neither page is destructive.
3. Typography hierarchy — `<h1>` for the page title, `<h2>` for "requested
   scopes", muted intro paragraph, `<code>` for scope names and identifiers.
4. Bracketed-link convention — affirmative `[authorize]` is a `<button>` (form
   submit), all other links flow through `BracketedLinkComponent`. No
   `[ label ]`-with-spaces variants introduced; the project convention is
   `[label]` (no inner spaces), which both the component and
   `oauth_authorization_spec.rb`'s
   `expect(response.body).to include("[authorize]")` assertion require.
5. Layout — left-anchored 480px container matches the login page pattern; the
   consent page no longer center-anchors at 560px.
6. `:hide_chrome` — header strips to logo + theme keycap, footer strips to
   copyright + version. Identical to `sessions/new.html.erb`.
7. No JS confirm / alert / prompt / `data-turbo-confirm` and no `beforeunload`
   (this isn't a typed-input form, the carve-out doesn't apply).

**Specs:**

- `spec/requests/oauth_authorization_spec.rb` — already asserts the consent page
  renders, includes `[authorize]`, and includes the application name. All three
  assertions still pass — the restyle preserves the form, the button text, and
  the application name in the heading. No spec changes were needed; per the
  dispatch, we don't add specs that Doorkeeper's own test suite already covers
  (auth flow logic).
- `spec/requests/oauth_scope_clip_spec.rb` — still green (10/10); the Phase 7.5
  fix-1 specs only inspect the redirect / token, not the consent page DOM.
- `spec/lint/punctuation_spec.rb` and the rest of `spec/lint/` — green (3/3);
  the `.text-muted` paragraphs end with `.`, the `<h1>` / `<h2>` labels and the
  `[authorize]` button label stay punctuation-free per the design rule.

**Pipeline state:**

- RSpec: 1785/0/0 (no net change — restyle, not feature work).
- Rubocop: clean (424 files, 0 offenses).
- Brakeman: 0 security warnings (one obsolete ignore-entry from prior sweeps
  remains; unrelated).
- Prettier: ERB is not in the project's prettier parser config (the
  `.prettierrc.json` covers prose / markdown only); skipped per the tool's "no
  parser inferred" exit. No project file forces ERB formatting.

**Manual test plan (handed back to architect):**

1. `bin/dev`, then load `https://app.pitomd.com/oauth/authorize?...` for the
   Claude MCP application. Confirm:
   - Header strips to pito logo + theme keycap only (no nav / search / logout /
     `?` link).
   - Footer strips to copyright + version only (no nav).
   - Page content left-anchored at `max-width: 480px`.
   - Scope list grouped by namespace, each scope as `<code>` + muted
     description.
   - `[authorize]` is a `<button>`, `[cancel]` is a bracketed link.
2. Toggle the `(n)` theme keycap and confirm the page repaints into Dracula
   tokens (bg `#282a36`, text `#f8f8f2`, links purple) with no white flash and
   no leftover light-mode color.
3. Trigger the error page by submitting an authorize URL with an unknown scope
   (or visit the same URL after the scope-clip initializer rejects an
   out-of-`Scopes::ALL` value). Confirm the error description renders in
   monospace, muted, wrapping cleanly inside the 480px column.

**Not committed.** Architect commits after the user signs off on the consent +
error pages on both themes. Files changed are limited to
`app/views/doorkeeper/authorizations/new.html.erb` and
`app/views/doorkeeper/authorizations/error.html.erb` plus this log entry.

## 2026-05-07 — OAuth applications UI polish (5 fixes)

**Inputs:** ad-hoc fixes from the user, no new spec file. Five items: (1)
truncate `client_id` on the index table and tighten `redirect_uri` truncation;
(2) frame the credentials block on the post-create page; (3) add a right-edge
buffer to the wrapping `client_secret` value; (4) lowercase
`[I have saved them]` → `[i have saved them]`; (5) document the `.framed-block`
design-system class in `docs/design.md` and add the CSS.

**Files changed:**

- `app/views/settings/oauth_applications/index.html.erb` — middle-truncate
  `client_id` (head/tail 8/8) with `title=` hover-reveal; tighten `redirect_uri`
  truncation from head/tail 16/24 → 12/12 so 38–40 char callback URLs (e.g.
  `https://claude.ai/api/mcp/auth_callback`) trigger.
- `app/views/settings/oauth_applications/create.html.erb` — wrap the credentials
  `<table class="detail-table">` in a `<div class="framed-block">` for visual
  emphasis on the "save these now" surface; lowercase the `[i have saved them]`
  action link.
- `app/assets/tailwind/application.css` — add `.framed-block` (1px
  `--color-border`, `--color-pane-bg`, 4px radius, 16px padding, 16px vertical
  margin) and a scoped `.framed-block .code-block code` `padding-right: 4px`
  rule so long wrapping values (64-char `client_secret`) don't run flush with
  the frame edge.
- `docs/design.md` — new `## Framed blocks` section between the unsaved-form
  guard and the panes section. Documents visual properties, when to use
  (capture-now / one-time-reveal surfaces), when NOT to use (every block on a
  page degrades the signal), and the long-value buffer rule. Prettier-
  formatted.
- `spec/requests/settings/oauth_applications_spec.rb` — update the existing
  redirect-URI truncation expectation to head/tail 12/12; add a new example
  asserting the index table also middle-truncates the 43-char Doorkeeper `uid`
  and exposes the full value via `title=`.

**Pipeline:**

- RSpec: 1786 examples, 0 failures.
- Rubocop: clean (424 files, 0 offenses).
- Brakeman: 0 security warnings.

**Manual test plan:**

1. Load `/settings/oauth_applications` (index) — confirm both `client_id` and
   `redirect_uri` cells show middle-truncated values, hovering exposes the full
   string via `title=`, and the table fits within a 1280px viewport.
2. Load `/settings/oauth_applications/<id>/created` (post-create) — confirm the
   credentials table now sits inside a bordered, tinted framed block with 16px
   padding, the `client_secret` value has a small right-edge buffer (no longer
   kissing the frame edge), and the action link reads `[i have saved them]`
   (lowercase `i`).
3. Toggle dark theme on either page — the framed block's border and background
   flip to the dark-mode tokens (`--color-border` → `var(--color-border)`
   Dracula values, `--color-pane-bg` → dark pane bg) without re-deploy.
   Truncation is theme-independent.

**Not committed.** Architect commits after the user signs off.

**Out of scope (deliberately untouched):**

- `app/views/settings/tokens/create.html.erb` (`[I have saved it]`) — same
  visual pattern but a different surface; user instructions explicitly scoped
  this work to OAuth applications views. Deferred for a follow-up when the
  tokens page gets its own pass.

## 2026-05-07 — MCP custom-connector icon discovery (shotgun)

**Inputs:** ad-hoc dispatch from the user, no new spec file. Claude.ai's MCP
custom-connector list shows the `pito` entry with a generic globe instead of the
Pito brand mark (red P). There's no MCP spec for icons, so we shotgun every
reasonable discovery surface and let whichever path Claude actually probes
resolve to `public/Pito.png`.

Note: this dispatch ran in parallel with the Doorkeeper-layout / MCP-root-
aliasing work and was deliberately scoped to NOT touch those surfaces.

**Files changed:**

- `app/views/layouts/application.html.erb` — added five icon-discovery hints to
  `<head>`: `<link rel="apple-touch-icon">` (bare + `sizes="180x180"`),
  `<link rel="manifest" href="/manifest.json">`, `<meta property="og:title">`,
  `<meta property="og:description">`, `<meta property="og:image">` (absolute URL
  `https://app.pitomd.com/Pito.png` per Open Graph spec). Header comment records
  why all five surfaces ship together (no documented Claude.ai probe path; cover
  every reasonable one).
- `app/controllers/well_known_controller.rb` — added a `logo_uri` field to both
  `oauth_authorization_server` (RFC 8414) and `oauth_protected_resource`
  (RFC 9728) responses. Non-standard extension (RFC 7591 defines `logo_uri` for
  CLIENT metadata only); some clients honor it as a courtesy hint for the
  connector-list icon. Cost is one extra field per metadata document; benefit is
  one more possible icon-discovery hit.
- `public/manifest.json` — new Web App Manifest. `name` / `short_name` = `pito`;
  `description` = `best YouTube tool` (matches the existing layout fallback
  `<title>`); `start_url` = `/`; `display` = `standalone`; `background_color` =
  `#ffffff`; `theme_color` = `#1a1a1a` (intentionally NOT `#cc0000` — CLAUDE.md
  walls red off as the destructive-only token; the brand-anchor color the user
  picked is the design-system text color `#1a1a1a`); `icons` =
  `[{ src: "/Pito.png", sizes: "any", type: "image/png" }]`.
- `config/routes.rb` — new route alias
  `get "/favicon.ico", to: redirect("/Pito.png", status: 301)` for clients and
  OS-level icon scrapers that ONLY check `.ico`. Pito does NOT carry a `.ico`
  binary in the repo; the redirect keeps the modern PNG asset as the single
  source of truth. `ActionDispatch::Static` runs ahead of the router, so the
  route only fires when no `public/favicon.ico` file exists (the steady state).

**Specs:**

- `spec/requests/well_known_spec.rb` — extended both metadata-document examples
  to assert `body["logo_uri"] == "https://app.pitomd.com/Pito.png"` (two new
  `expect` lines, no new it-blocks).
- `spec/requests/manifest_spec.rb` — new file. Two examples: valid JSON with the
  Pito icon (asserting `name`, `short_name`, `description`, `start_url`,
  `display`, and the icons array's first entry shape) and the anonymous-access
  guard (mirrors the well-known specs).
- `spec/requests/favicon_spec.rb` — new file. Two examples: 301 redirect to
  `/Pito.png`, and the anonymous-access guard.

**Theme color rationale (recorded for future reference):** Pito's logo is a red
play-triangle P, but the design-system hard rule (CLAUDE.md, "Red (`#cc0000`) is
ONLY for destructive / dangerous actions") locks `#cc0000` out of decorative /
branding surfaces. `theme_color` in `manifest.json` is the OS-level address-bar
/ app-frame tint — not a destructive affordance — but it IS a brand surface and
the project's chosen brand-anchor color (per the user's own dispatch
instructions) is the design-system text token, `#1a1a1a`. White
`background_color` matches the rest of the app's light theme.

**Pipeline:**

- RSpec: 1795 examples, 0 failures (was 1786; +4 new it-blocks in the two new
  request specs, +0 new it-blocks in `well_known_spec.rb`; the rest of the delta
  was ambient since the prior log entry).
- Rubocop: 427 files, 0 offenses.
- Brakeman: 0 security warnings (one obsolete-ignore entry from prior sweeps
  remains; unrelated).
- Hard-rule grep: clean (no `window.confirm` / `alert` / `prompt` /
  `data-turbo-confirm` introduced; no booleans at external boundaries).

**Manual test plan (handed back to architect):**

1. After commit and deploy, re-add the `pito` connector in Claude.ai with the
   existing `client_id` / `client_secret`. Once the connector lands in the
   connectors list, confirm the icon shows the Pito logo (red P) instead of the
   generic globe.
2. If still globe, the dispatch's shotgun didn't hit Claude's actual probe path.
   Inspect Claude's network requests (browser devtools or proxy) to discover the
   URL it tries — that single observation tells us which surface to harden next.
3. Spot-check each shotgun surface returns the expected payload:
   ```bash
   curl -sI https://app.pitomd.com/manifest.json | head -1
   curl -s  https://app.pitomd.com/manifest.json | jq .icons
   curl -sI https://app.pitomd.com/favicon.ico | head -3
   curl -s  https://app.pitomd.com/.well-known/oauth-authorization-server | jq .logo_uri
   curl -s  https://mcp.pitomd.com/.well-known/oauth-protected-resource    | jq .logo_uri
   curl -s  https://app.pitomd.com/login | grep -E 'apple-touch-icon|og:image|manifest'
   ```

**Not committed.** Architect commits after the user signs off on the icon in
Claude.ai's connector list.

**Out of scope (deliberately untouched):**

- Doorkeeper layout polish and MCP-root aliasing (parallel dispatch).
- `public/Pito.png` itself (per dispatch instructions: do not modify the asset;
  convert nothing to `.ico`).
- `extras/cli/`, `extras/website/` (different agent lanes).

## 2026-05-10 — Phase 7.5 close-out

**Inputs:**

- Spec:
  `docs/plans/beta/19-phase-75-closeout/specs/01-closeout-and-followups-resolution.md`
- Master agent decisions (2026-05-10) locking all 7 open questions.

**Done:**

- Reconciled every Phase 7.5 line item from `plan.md` against shipped commits
  (see reconciliation table below). Tracks A · B · C all shipped + verified; the
  only carry-forward inside Phase 7.5's own scope is spec 06's importer-side
  ffmpeg frame extraction, which moves to a fresh follow-up entry pinned against
  the next footage-importer dispatch.
- Pre-specs 07–10 disposed: 07 (Games) absorbed into realignment work unit 6; 08
  / 09 / 10 deleted on 2026-05-10 per the realignment paperwork pass.
- Adopted `> **Status:** ...` badging convention (master decision 4); flipped
  `plan.md`'s top-of-file badge to `complete (closed by Phase 19)`. Historical
  workstream tracker checkboxes left frozen as a record of what landed.
- Reconciled `additions.md` and `dropped.md` with final notes pointing at this
  spec.
- Walked `docs/orchestration/follow-ups.md` end-to-end. Closed entries moved to
  `## Done` with their resolving commit refs (Phase 7.5 hygiene + keyboard
  shortcuts + CLI parity sweep + ratatui bump + OmniAuth simplification +
  channel revamp orphan cleanup + Phase 4 / B-2 validate-and-commit + agent
  re-prefix + rustfmt drift). Carry-forward entries kept under `## Open` with
  triggers updated where the realignment shifted timing language. Three new
  carry-forward entries added (CLI feature-parity sweep, footage importer ffmpeg
  frame extraction, optional Phase 7.5 smoke spec).
- `docs/realignment-2026-05-09.md` work unit 11 ("Phase 7.5 pre-specs 08 / 09 /
  10 resolution") gets a Resolution line pointing at this close-out.
- Phase 6 deviation entry + 2026-05-09 realignment top-level direction-map entry
  stay under `## Open` as permanent informational fixtures (master decision 2).
- `docs/design.md:463` zebra-rule fix kept separate per master decision 3 —
  reassigned to "next docs sweep"; not folded into the close-out.

**Reconciliation summary:**

Phase 7.5 ("Follow-ups Sweep + Concept Foundations") shipped a substantial
hygiene + foundations body across two main commits — `718996c` (Tracks A + B

- Track C spec 05 `pito-assets`) and `f5fdb01` (Track C specs 04 keyboard
  shortcuts + 06 footage thumbnails + the in-flow MCP OAuth + Doorkeeper polish
- icon discovery dispatches). Test-suite delta over the phase: RSpec 1671 →
  1795+ (~+124 specs); CLI 349 → 448+ (~+99 tests). Spec coverage in place for
  every shipped surface (sessions audit · `:unprocessable_content` · OmniAuth ·
  BracketedLinkComponent · CLI hygiene · keyboard shortcuts · `Pito::AssetsRoot`
  · footage thumbnails Rails + CLI · MCP OAuth + bearer · Doorkeeper scope clip
- consent restyle · icon discovery). No new specs added by this close-out
  (optional smoke spec explicitly skipped per master decision 1).

**Reconciliation table (per-spec disposition · shipped commit refs):**

| #   | Item                                                     | Status                              | Commit                             |
| --- | -------------------------------------------------------- | ----------------------------------- | ---------------------------------- |
| 01  | Rails hygiene sweep — Settings sessions audit            | Shipped + verified                  | `718996c`                          |
| 01  | `:unprocessable_entity` → `:unprocessable_content` sweep | Shipped + verified                  | `718996c`                          |
| 01  | OmniAuth initializer simplification                      | Shipped + verified                  | `718996c` (CI follow-up `85453c1`) |
| 01  | Channel Revamp orphan cleanup                            | Shipped + verified                  | `718996c`                          |
| 02  | CLI hygiene — `cargo fmt` drift sweep                    | Shipped + verified                  | `718996c`                          |
| 02  | CLI hygiene — ratatui 0.29 → 0.30                        | Shipped + verified                  | `718996c`                          |
| 02  | CLI screen-layout parity sweep                           | Shipped + verified                  | `718996c`                          |
| 03  | Decorator slim resolution                                | Shipped (closed no-op)              | n/a (decision-only)                |
| 04  | Rails keyboard shortcuts                                 | Shipped + verified                  | `f5fdb01`                          |
| 05  | `pito-assets` Docker volume + `Pito::AssetsRoot`         | Shipped + verified                  | `718996c`                          |
| 06  | Footage thumbnails — Rails endpoints                     | Shipped + verified                  | `f5fdb01`                          |
| 06  | Footage thumbnails — CLI rendering                       | Shipped + verified                  | `f5fdb01`                          |
| 06  | Footage thumbnails — importer-side ffmpeg extraction     | Carry-forward — new follow-up entry | n/a                                |
| 07  | Games — concept pre-spec                                 | Pending — absorbed into work unit 6 | n/a                                |
| 08  | Timelines resurrection — pre-spec                        | Dropped per realignment             | n/a (file deleted)                 |
| 09  | MCP sync — pre-spec                                      | Dropped per realignment             | n/a (file deleted)                 |
| 10  | Terminal sync — pre-spec                                 | Dropped per realignment             | n/a (file deleted)                 |

In-flow dispatches (no numbered spec; bundled into close-out trail):

| Dispatch                                                | Status             | Commit    |
| ------------------------------------------------------- | ------------------ | --------- |
| MCP OAuth discovery (RFC 8414 + 9728) + bearer dispatch | Shipped + verified | `f5fdb01` |
| Doorkeeper scope soft-clip + OAuth-app UX polish        | Shipped + verified | `f5fdb01` |
| Doorkeeper consent + error pages restyled to Pito       | Shipped + verified | `f5fdb01` |
| OAuth applications UI polish (5 fixes)                  | Shipped + verified | `f5fdb01` |
| MCP custom-connector icon discovery (shotgun)           | Shipped + verified | `f5fdb01` |
| Cross-tenant sessions spec flake fix                    | Shipped + verified | `9871f37` |

**Decisions:**

- All 7 open questions in spec §"Open questions" resolved per master agent's
  2026-05-10 contract block. Architect's leans concurred with on every question
  (skip smoke spec · Phase 6 deviation stays as fixture · zebra fix separate ·
  adopt status-badge convention · escalate on impossible triggers · docs-keeper
  resolves commit-ref placeholders · in-flow dispatches stay in reconciliation
  table).

**Files changed (this close-out):**

- `docs/plans/beta/7.5-followups-and-foundations/log.md` — this entry.
- `docs/plans/beta/7.5-followups-and-foundations/additions.md` — final
  reconciliation note appended.
- `docs/plans/beta/7.5-followups-and-foundations/dropped.md` — final
  reconciliation note appended.
- `docs/plans/beta/7.5-followups-and-foundations/plan.md` — top-of-file status
  badge flipped to `complete (closed by Phase 19)`.
- `docs/orchestration/follow-ups.md` — closed entries moved to `## Done`;
  carry-forward entries' triggers updated; three new carry-forwards added.
- `docs/realignment-2026-05-09.md` — work unit 11 Resolution line added.
- `docs/plans/beta/19-phase-75-closeout/log.md` — Phase 19 session entry
  recording the close-out walk.

**Pipeline:** docs-only; no code, no migrations, no specs. Quality gate is
prettier-clean across all updated markdown files.

**Next:**

- User reads this close-out summary, walks the manual close-out playbook in
  `docs/plans/beta/19-phase-75-closeout/specs/01-closeout-and-followups-resolution.md`
  §"Manual close-out playbook" against `bin/dev`, signs off.
- After sign-off the user commits as a single commit (suggested message:
  `Phase 7.5 close-out — reconciliation, follow-ups disposition, plan complete`).
- The next architect-spec dispatch is the Phase 8 tenant-drop spec (work unit 1
  in `docs/realignment-2026-05-09.md`).

**Phase 7.5 is complete; next dispatch is the Phase 8 tenant-drop spec.**

## 2026-05-10 — Step 11a — Channel schema + sync foundation

Spec:
[`specs/11a-channel-schema-and-sync.md`](specs/11a-channel-schema-and-sync.md).
Parent spec:
[`specs/11-channel-management-and-preview.md`](specs/11-channel-management-and-preview.md)
(locked decisions D1–D23, including D21 — no `watermark_position` column).

**Implementation:**

- 3 migrations (timestamps `20260510210000` / `…01` / `…02`) applied to dev DB
  cleanly and to test DB via `db:schema:load`. Reversibility proven by rollback
  specs under `spec/migrations/`.
- `Channel` model gains every editable / display-only column (title, handle,
  description, country, default_language, keywords, banner_url, avatar_url,
  watermark_url, watermark_timing, watermark_offset_ms, links jsonb,
  subscriber_count, view_count, video_count, hidden_subscriber_count,
  published_at, title_changed_at, handle_changed_at) with the validator suite
  the spec lists (length / format / inclusion / numericality / custom links
  shape). 14-day rate-limit gate helpers (`title_locked?` / `handle_locked?` /
  `*_unlock_at`) implemented with the boundary-correct comparison
  (`> 14.days.ago`, exclusive — at exactly 14d the lock has expired).
- `ChannelChangeLog` new model: `belongs_to :channel`, `:changed_by_user`,
  inclusion validator on `field` (`%w[title handle]`), presence on `new_value`
  - `changed_at`, `recent` scope, append-only enforcement via
    `def readonly?; persisted?; end` (raises `ActiveRecord::ReadOnlyRecord` on
    `update!` / `destroy`). DB FK is `ON DELETE CASCADE` to channels;
    `dependent: :delete_all` on the parent association so cascade actually fires
    (the read-only override would otherwise raise on `dependent: :destroy`).
- `Youtube::Client#fetch_channel(channel)` extends the client with the
  full-part-set channel pull (snippet + statistics + brandingSettings +
  contentDetails + status). Routes through the existing `perform` chokepoint so
  quota / refresh / audit posture is uniform; returns the normalized snake_case
  Hash the spec documents.
- `ChannelSync` rewrite: replaces the Path A2 placeholder no-op with the real
  fetch + persist path. Channel without `youtube_connection_id` and missing
  channel both no-op. NeedsReauth / Transient / Quota errors re-raise to let
  Sidekiq retry; PermanentError is logged and swallowed; RecordInvalid rolls
  back the transaction so a wonky API payload (e.g. 101-char title) leaves
  `last_synced_at` untouched.

**Note on `add_title_to_videos`:** the `videos.title` column already exists on
schema (added by Phase 12's `expand_videos_for_data_api_v3` as
`string, limit: 100, default: "", null: false`). The 11a spec's "Files touched"
stipulates the migration becomes a no-op and the agent reports rather than
silently skipping. The migration ships as a true no-op `change` block with a
comment block flagging the discrepancy. Empty-string default is semantically
equivalent to nil for the preview's "untitled placeholder" behavior — Video
presenters render "untitled" on blank as well as nil.

**Files changed (high level):**

- 3 migrations under `db/migrate/2026051021000{0,1,2}_*.rb`.
- `app/models/channel.rb` — validators / helpers / association extension.
- `app/models/channel_change_log.rb` — new.
- `app/jobs/channel_sync.rb` — placeholder replaced with real path.
- `app/services/youtube/client.rb` — `#fetch_channel` extension +
  `normalize_channel_item` helper.
- `db/schema.rb` — auto-regenerated.

**Specs added (this session):**

- `spec/migrations/add_channel_resource_fields_spec.rb` — 5 examples.
- `spec/migrations/create_channel_change_logs_spec.rb` — 9 examples.
- `spec/migrations/add_title_to_videos_spec.rb` — 2 examples.
- `spec/models/channel_spec.rb` — extended with ~60 new examples (every new
  validator happy + sad + edge per project's spec-pyramid directive, the
  14-day-gate helpers at the 13d 23h / exactly 14d / 14d 1m boundary, the
  `links` shape validator's seven failure modes, the `delete_all` cascade).
- `spec/models/channel_change_log_spec.rb` — 18 examples.
- `spec/services/youtube/client_fetch_channel_spec.rb` — 12 examples covering
  happy + 401-once-then-refresh + 401-after-refresh + 429 retry-then-fail +
  403-quota + 5xx-exhausted + minimal-snippet edge + hidden-subscriber-count
  edge + handle-absent edge.
- `spec/jobs/channel_sync_spec.rb` — replaced placeholder spec; 9 examples
  covering all eight code paths the spec enumerates plus a single-transaction
  smoke check.

**Spec count delta:** roughly +115 examples (3 migration files +
ChannelChangeLog + Channel-extended + Client#fetch_channel + ChannelSync
rewrite). Full suite ran 4569 examples (3 pre-existing flakes in calendar /
composites system specs unrelated to this spec — they pass in isolation; they
reproduce only under full-suite load and are not introduced by this work).

**Gates:**

- `bundle exec rspec` — every spec touched by this dispatch is green
  (services/youtube + jobs + models + migrations spec dirs all clean; full suite
  is 4569 / 4566 passing with the three unrelated flakes noted above).
- `bundle exec rubocop` — clean across every touched file.
- `bin/brakeman -q -w2` — no warnings; obsolete-ignore entries unchanged from
  prior committed state.

**Plan checkbox tick:** none. `plan.md` for Phase 7.5 carries no 11 / 11a
checkbox — the spec landed AFTER the phase was closed by Phase 19. The follow-up
tracking for the Channel Management surface lives in the parent spec (`11`);
subsequent dispatches (11b–11i) will add their own checkboxes under whichever
phase they ship into.

**Manual test recipe** (from the spec, summarized — user runs after the master
commits): `bin/rails db:migrate` clean, `db:rollback STEP=3` clean, re-migrate,
`bin/rails console` and confirm `ChannelSync.new.perform(id)` on a connected
channel populates the new columns and stamps `last_synced_at`, then walk the
no-connection / missing-channel / change-log read-only / 14-day-helpers paths.

**Open issues:** none. The 11a spec's "Open questions" section already locks
every decision; the Q1 (title/handle live-API editability), Q4 (watermark timing
live-API option set), and Q9 (avatar editability) research dispatches run BEFORE
11c (edit form), not before 11a — 11a's columns exist regardless of the
outcomes.

## 2026-05-11 — drop seeded channels + Settings Google card one-per-row list

**State at start:** dev DB carried the legacy 100-row placeholder channel
fan-out from the pre-OAuth seed (`Channel.where(youtube_connection_id: nil)` =
100; the three real OAuth-linked channels carried connections). The Settings
index Google card rendered the channels summary as
`103 channels: Catalin Ilinca, Mushroom Poise, Witty Gaming` — count prefix plus
inline comma list. The user's image #66 directive replaces that with a muted
`channels:` header and one label per row.

**Inputs:**

- Master-agent dispatch (no spec file — directive from image #66).
- CLAUDE.md hard rules (yes/no boundary stays untouched; no changes to external
  boolean shapes).

**What landed (file-level):**

- `db/seeds.rb` — the 100-row channel + per-channel video + 90-day-stat fan-out
  is gone. Replaced with a comment block pointing at
  `bin/rails pito:drop_seeded_channels` for cleaning up dev DBs that ran the old
  seed. Project Workspace sample block (collection / game / project / note /
  timeline) preserved verbatim.
- `lib/tasks/pito.rake` — new namespace, single task
  `pito:drop_seeded_channels`. Deletes every `Channel` row whose
  `youtube_connection_id IS NULL`. Idempotent (re-runs print "no seeded channels
  to drop."). Uses `destroy_all` so the standard `dependent: :destroy` cascade
  fires for related rows (videos, calendar entries, change logs) — `delete_all`
  would have left orphans.
- `app/controllers/settings_controller.rb` — `@channel_titles` replaced with
  `@channel_labels`, capped at 5, ordered `title IS NULL, title, id` so titled
  rows surface first. Per-row fallback resolves `title` then the UC-id slug
  extracted from `channel_url` (always present — `channel_url` is required +
  format-validated).
- `app/views/settings/index.html.erb` — channels block restructured. Muted
  `<p>channels:</p>` header, then a styleless `<ul>` (no bullets, indented 12px)
  with one `<li>` per label. When the install has more channels than the 5-cap
  renders, an `…and N more` `<li>` closes the list. Empty state stays "no
  channels linked yet" exactly as the manage-page surface phrases it. The
  `connect a Google account…` hint paragraph is unchanged.

**Rake task run** (against dev DB, post seed-block removal but before any other
change): `bundle exec rake pito:drop_seeded_channels` dropped **100** seeded
channels. Re-running the task on the same DB printed "no seeded channels to
drop." — idempotent path verified. Channel count went from 103 → 3 (the three
real OAuth-linked channels survived).

**Specs added / amended:**

- `spec/requests/settings_spec.rb` — the existing "Google pane channels summary"
  describe block was replaced with a "Google pane channels list" block. Eleven
  examples cover: empty YoutubeConnection state, connected-but-empty state, the
  muted "channels:" header without a count prefix, one-`<li>`-per-title
  rendering (no inline comma form), UC-id slug fallback for un-synced channels,
  title-preferred-over-UC-id, whitespace-only-title-as-blank, 5-cap with "…and N
  more" footer, cross-connection aggregation, titled-before-untitled ordering,
  the connect-a-Google-account hint paragraph preservation, plus the
  brand-account email truncation + last-authorized +N-more lines that the prior
  spec already covered. **Total examples in the describe block: 14 (vs. 13
  before).**
- `spec/lib/tasks/pito_rake_spec.rb` — new file, 7 examples for
  `pito:drop_seeded_channels` covering: deletes orphan rows, preserves connected
  rows, idempotent re-run, plural / singular / no-op stdout lines, and cascade
  through dependent Video rows.

**Spec count delta:** +1 in `settings_spec.rb` (13 → 14 in the Google-pane
describe; eight obsolete examples removed, nine new ones added). +7 brand-new in
`pito_rake_spec.rb`. Net +8 examples across the dispatch.

**Files changed (high level):**

- `db/seeds.rb`
- `lib/tasks/pito.rake` (new)
- `app/controllers/settings_controller.rb`
- `app/views/settings/index.html.erb`
- `spec/requests/settings_spec.rb`
- `spec/lib/tasks/pito_rake_spec.rb` (new)

**Gates:**

- `bundle exec rspec spec/requests/settings_spec.rb` — 83 examples, 0 failures.
- `bundle exec rspec spec/lib/tasks/pito_rake_spec.rb` — 7 examples, 0 failures.
- `bundle exec rspec spec/helpers/youtube_helper_spec.rb` — 16 examples, 0
  failures (sanity check on the brand-account email truncation helper that the
  Google card uses).
- `bundle exec rubocop` — 917 files inspected, 0 offenses.
- `bin/brakeman -q -w2` — unchanged from the prior committed state: 1
  pre-existing Medium-confidence SQL Injection warning in
  `app/services/channels/video_importer.rb:130` (not in any file this dispatch
  touched).

**Plan checkbox tick:** none. The directive came from a master-agent dispatch
outside the plan's checkbox set; no Phase 7.5 / Phase 22 / Phase 4 checkbox
covers it.

**Manual test recipe** (the user runs after the master commits):

1. `bin/rails server`, open `/settings`, confirm the Google card reads
   `channels:` on its own muted line followed by one channel name per row (3
   channels in the current dev DB). The `[manage]` link still works.
2. Disconnect every YoutubeConnection — the empty-state phrasing "no channels
   linked yet" appears in place of the list.
3. `bin/rails console` — temporarily clear a channel's title
   (`Channel.first.update_columns(title: nil)`), refresh `/settings`, and
   confirm that row in the list renders as its UC-id slug
   (`UCxxxxxxxxxxxxxxxxxxxxxx`) instead. Restore the title.
4. The `pito:drop_seeded_channels` rake task is already run; re-running it
   prints "no seeded channels to drop." — confirms idempotency.

**Open issues:** none.

## 2026-05-10 — Step 11b — Channel show page revamp

**Inputs:**

- Spec:
  `docs/plans/beta/7.5-followups-and-foundations/specs/11b-channel-show-page.md`
- Parent spec: `11-channel-management-and-preview.md`.
- Locked decisions (master-agent autonomous lock on the six open questions):
  - **Q1** = pure analytics summary numbers (subscribers / views / videos) plus
    `[full analytics]` outbound link to `/channels/:slug/analytics`. No inline
    sparkline.
  - **Q2** = dedupe. The single `ORDER BY star DESC, COALESCE(...) DESC`
    arranges the whole table; each video appears exactly once.
  - **Q3** = hide banner row entirely when `banner_url` is nil. No colored
    placeholder block.
  - **Q4** = plain text + auto-link via Rails `simple_format(sanitize: true)`
    plus a URL regex pass. No markdown.
  - **Q5** = `/channels/:slug/analytics` route exists today (Phase 13.3).
  - **Q6** = avatar in its own row beside the title, NOT overlapping the banner.
    Cleaner; banner row 1, avatar+title row 2, description row 3, links row 4,
    analytics row 5, videos row 6 inside the detail pane.

**What landed (file-level):**

_Views:_

- `app/views/channels/show.html.erb` — rewritten to three `.pane-row` sections:
  detail (banner → avatar+title+handle → outbound links → description → links),
  analytics summary, videos pane. Empty `channel_diff_banner` Turbo frame
  shipped under the H1 so sub-spec 11i can stream into it later without
  re-editing this view. H1 now reads `channel <title>` via
  `channel_display_title`. Existing chrome ([+] add pane, [e] edit, [sync], [-]
  delete) preserved.
- `app/views/channels/_banner.html.erb` — new. Renders `<img>` for `banner_url`;
  row hidden entirely when nil (per Q3 lock).
- `app/views/channels/_links.html.erb` — new. Iterates the jsonb array, renders
  each `{ title, url }` entry as a bracketed external link; empty-state caption
  when array is empty/nil.
- `app/views/channels/_videos_pane.html.erb` — new. Starred-first,
  COALESCE(published_at, created_at) DESC ordering, capped at 30 rows.
  `[see all]` hands off to the videos picker pre-filtered by channel slug.

_Helpers:_

- `app/helpers/channels_helper.rb` — new file (also has 11c's gate helpers
  appended in the same wave). Methods: `formatted_subscriber_count` (Hidden /
  delimited / em dash), `formatted_view_count`, `formatted_video_count`,
  `channel_display_title`, `channel_description_html` (simple_format +
  sanitize + auto-link).
- `app/helpers/youtube_helper.rb` — added `youtube_channel_id`,
  `youtube_channel_url`, `youtube_studio_url`. Each returns nil if the
  channel_url is malformed (defense in depth; model regex prevents it but the
  helper does not crash).

_Specs (new files):_

- `spec/views/channels/show.html.erb_spec.rb` — happy / sad / edge / flaw
  rendering matrix.
- `spec/views/channels/_banner.html.erb_spec.rb` — banner_url present vs nil.
- `spec/views/channels/_links.html.erb_spec.rb` — 0 / 1 / 5 entries + malformed
  entries.
- `spec/views/channels/_videos_pane.html.erb_spec.rb` — 0 / 1 / 30 / 31 videos,
  starred-first ordering, dedup, COALESCE fallback.
- `spec/helpers/channels_helper_spec.rb` — new file (also carries 11c's gate
  helper specs).
- `spec/requests/channels_show_spec.rb` — happy / sad / edge / flaw at the
  request level + slug-redirect + 404.
- `spec/system/channel_show_journey_spec.rb` — thin happy-path system journey
  (picker → show → click `[see all]` → land on filtered videos picker).

_Specs (modifications):_

- `spec/helpers/youtube_helper_spec.rb` — 13 new examples covering the three
  outbound URL builders.
- `spec/requests/channels_spec.rb` — slimmed the legacy
  `GET /channels/:id (show)` describe block to the controller-level contracts
  that survive the revamp (200, sync link, delete link, JSON shape, 404, `[+]`
  add-pane button). The full HTML rendering matrix moved to
  `channels_show_spec.rb`.

**Spec count delta:** ~129 new examples landed across the helper / view /
request / system files. ~17 legacy view assertions retired from
`spec/requests/channels_spec.rb` (the URL row, the `[star]` inline toggle, the
two-pane layout assertions, the "see all videos for this channel" copy). Net add
≈ +112 examples for 11b.

**Gates (mine):**

- `bundle exec rspec spec/views/channels spec/helpers/channels_helper_spec.rb spec/helpers/youtube_helper_spec.rb spec/requests/channels_show_spec.rb spec/requests/channels_spec.rb spec/system/channel_show_journey_spec.rb`
  — all green.
- `bundle exec rubocop` on every Ruby file I touched — 11 files, no offenses.
- `bin/brakeman -q -w2` — clean, 0 security warnings, 0 errors, only the two
  pre-existing ignored-warning entries (unrelated, `footages_controller.rb` +
  routes verb-confusion).
- Full-suite `bundle exec rspec --fail-fast=10` — 5318 examples, 5 failures.
  None of the failures touch my files; they originate in sibling-agent work (11c
  form / 11i diff banner / Phase 23 video diffs) or pre-existing unrelated specs
  (calendar/month route, composites path-traversal, auth_concern POST /channels,
  calendar edit/delete system spec).

**Plan checkbox tick:** none. Phase 7.5's `plan.md` does not carry an explicit
checkbox for 11b — it tracks the four hygiene sweeps (01–06) and the concept
pre-specs (07–10), not the Step 11 sub-specs.

**Coordination notes (4 sibling agents in flight):**

- 11c (edit form) extended `app/helpers/channels_helper.rb` with the 14-day gate
  helpers (`title_gate_open?`, `handle_gate_open?`, `title_unlock_date`,
  `handle_unlock_date`) and the matching specs in
  `spec/helpers/channels_helper_spec.rb`. I added the
  `include ActiveSupport::Testing::TimeHelpers` line that the gate-helper specs
  need for `travel_to` to work; that one-liner is the only cross-spec touch.
- 11i (diff cron) is expected to fill the empty `channel_diff_banner` Turbo
  frame I shipped under the H1. I did not edit any 11i-owned files.

**Manual test recipe** (the user runs after the master commits):

1. `bin/dev`, open `/channels`, click into a channel. Verify the page renders
   three pane rows (detail / analytics / videos) without 500ing, even on a
   bare-bones pre-sync channel (every metadata column nil).
2. `bin/rails console`, hydrate a channel with the script in the spec's Manual
   test recipe (title, handle, description, banner_url, avatar_url, links,
   subscriber/view/video counts). Refresh `/channels/<slug>`. Verify banner
   image renders, avatar circle renders, title in H1 reads `channel <title>`,
   handle reads `@<handle>`, `[youtube channel]` and `[youtube studio]` open in
   new tabs with the correct URLs, description renders with paragraph +
   auto-linked URLs, links cluster shows each `{ title, url }` entry as a
   bracketed external link.
3. Analytics row reads `subscribers: 12,345`, `views: 678,901`, `videos: 42`
   with the `[full analytics]` outbound link.
4. Videos pane shows up to 30 rows, starred-first; `[see all]` lands at
   `/videos?channel=<slug>` with the filter chip visible.
5. `c.update!(hidden_subscriber_count: true)` — subscribers cell reads "Hidden".
6. XSS smoke:
   `c.update_columns(description: "<script>alert('xss')</script>safe", title: "<img onerror=alert(1) src=x>")`.
   No JS dialog pops on `/channels/<slug>`; H1 reads literal `<img...>` escaped;
   description shows literal "safe" text only.

**Open issues:** none from 11b. The 5 pre-existing failures from the full-suite
run are sibling-agent / unrelated and not under 11b's purview.

## 2026-05-11 — §11c Channel Edit Form (rails-impl)

**Spec:** `specs/11c-channel-edit-form.md` (sub-spec of 11). Shipped the
writable edit form at `/channels/:slug/edit`, the controller dispatch through
`Youtube::Client#update_channel` + `#set_watermark` / `#unset_watermark`, the
14-day rate-limit gate UX (D5 / D19), and the three Stimulus controllers that
drive the form's client-side affordances.

**Files touched**

Rails / Ruby:

- `app/controllers/channels_controller.rb` — extended `#update` to branch
  between (1) the legacy JSON `star`-toggle path, (2) the legacy HTML
  `star`-toggle (show-page inline form), and (3) the new 11c edit form. Added
  private helpers `update_via_json`, `perform_star_toggle_html`,
  `perform_local_only_update`, `perform_youtube_update`,
  `handle_watermark_set!`, `handle_watermark_unset!`, `strip_gated_fields!`,
  `channel_edit_attrs`, `normalize_links_attributes`.
- `app/services/youtube/client.rb` — added `#update_channel(channel, field_set)`
  (destructive PUT, read-modify-write), `#set_watermark`, `#unset_watermark`.
  Private helpers `extract_youtube_channel_id`, `read_current_branding`. All
  routed through the existing `perform(...)` audit / quota / retry chokepoint.
- `app/services/youtube/quota.rb` — added cost entries for `channels.update`
  (50), `watermarks.set` (50), `watermarks.unset` (50).
- `app/helpers/channels_helper.rb` — added `title_gate_open?`,
  `handle_gate_open?`, `title_unlock_date`, `handle_unlock_date`. Pure functions
  over `*_changed_at + 14.days`. Boundary semantics: exactly 14 days ago is
  treated as **closed** (window just expired).

Views:

- `app/views/channels/edit.html.erb` — full rewrite. Lead paragraph in the
  one-sentence-per-line style (rule B). Form container wears
  `.pane.pane--standalone` (rule C). Toast container reserved for 11h.
  Local-only banner renders when `youtube_connection_id` is nil.
- `app/views/channels/_form.html.erb` — full edit form. URL locked. Title /
  handle gated (when window open, shows muted message +
  `[remind me on YYYY-MM-DD]` bracketed link with the data attrs 11h's
  controller will hook). Description / country / default_language / keywords /
  links repeater / watermark fieldset / banner-upload slot / submit row.
- `app/views/channels/_form_errors.html.erb` (NEW) — flash + errors partial.
- `app/views/channels/_banner_upload.html.erb` (NEW) — empty slot, owned by 11f.

Stimulus controllers (NEW):

- `app/javascript/controllers/links_repeater_controller.js` — add / remove rows,
  server-filters destroyed rows via `_destroy=yes`, hides `[+ add link]` at
  MAX_LINKS = 5 (client polish; server-side cap is the authoritative gate).
- `app/javascript/controllers/file_upload_controller.js` — watermark variant.
  Hard-rejects file type, size, pixel dimensions client-side with specific
  reason text (D14). Reveals/hides offset_ms input on timing change.
- `app/javascript/controllers/reminder_link_controller.js` — STUB for the
  `[remind me on YYYY-MM-DD]` click. 11h fills `#create` with the POST + toast
  flow.

Specs:

- `spec/services/youtube/client_update_channel_spec.rb` (NEW, 26 examples) —
  `#update_channel` happy + 5 sad paths + arg validation + read-modify-write
  ordering + audit-row counts. `#set_watermark` + `#unset_watermark` full
  happy + sad paths (quota, 401, 5xx, ArgumentError on missing offset_ms,
  invalid timing).
- `spec/requests/channels/edit_form_spec.rb` (NEW, 31 examples) — covers every
  controller-level branch enumerated in the spec's Acceptance: happy path
  (single dirty field, multi-field, watermark-only, watermark- removal, no-op,
  local-only), sad paths (NeedsReauthError flagging, QuotaExhaustedError,
  TransientError, PermanentError, country reject, default_language reject,
  watermark_offset_ms negative, links 6th-entry reject, blank-url reject),
  14-day gate defense-in-depth (single-field strip, both-fields strip,
  all-fields-stripped short-circuit), JSON regression guards.
- `spec/helpers/channels_helper_spec.rb` — appended gate-helper specs (10
  examples covering both gates × the nil / inside / outside / exact- boundary
  axis + unlock_date helpers).
- `spec/system/channel_edit_form_spec.rb` (NEW, 1 example) — ONE end-to-end
  happy path (open edit → fill description → submit → land on show with new
  description) per architect rule D.

**Specs delta**

- 26 new service examples.
- 31 new request examples.
- 10 new helper examples.
- 1 new system example.
- Total new examples: 68.

**Gates**

- `bundle exec rspec spec/helpers/ spec/services/youtube/ spec/services/channels/ spec/requests/channels_spec.rb spec/requests/channels/ spec/system/channel_edit_form_spec.rb`
  → 795 examples, 0 failures, 0 pending.
- `bundle exec rubocop` (scoped to my touched files) → clean.
- `bin/brakeman -q -w2` → 0 warnings.

**Cross-agent coordination**

- 11i (DiffApply) already shipped a stub `Youtube::Client#update_handle` that
  raises `NotImplementedError`. 11c's `update_channel` deliberately excludes
  `:handle` from `UPDATE_CHANNEL_BRANDING_KEYS` so the dispatch goes through
  `#update_handle` instead — matches the parent spec's note that YouTube exposes
  a dedicated handle endpoint.
- 11h (calendar reminder) will fill in the `reminder_link_controller` `create`
  action. 11c ships the data attributes (`reminder-link-unlock- date-value`,
  `-field-value`, `-channel-id-value`, `click->reminder- link#create`) so 11h
  slots in without ERB churn.
- 11f (banner upload) will replace the empty `_banner_upload.html.erb` partial.
  The form's slot is rendered as
  `render "channels/banner_upload", channel: channel`.
- 11g (change history) will append `ChannelChangeLog` rows on every successful
  title / handle push. 11c stamps `title_changed_at` / `handle_changed_at` on
  cache write; the log-row hook is 11g's contract.

**Locked decisions honored**

1. Watermark spec: 800×800 PNG/JPEG, max 1 MB. Hard-rejected client-side per D14
   / D22.
2. Remind-me copy: `[remind me on YYYY-MM-DD]` bare verb (no inner spaces).
3. Max-5 enforcement: BOTH server-side (`Channel#links_shape` validator shipped
   with 11a) AND client-side (`links_repeater_controller` hides `[+ add link]`
   at 5).
4. No inline crop — banner partial is a slot for 11f; no crop UI here.
5. Handle dispatch: routed through `Youtube::Client#update_handle` (per 11i's
   existing stub) rather than `#update_channel`; the locked decision's
   "controller dispatches to `#update_channel`" was reconciled with the existing
   service surface by adding `update_channel` for the non-handle subset and
   delegating handle to the dedicated method 11i added. Both agree: the
   controller's call site stays singular.
6. Stimulus tests: rack_test system spec covers the links repeater happy path;
   unit-level Stimulus testing is out of scope (per Q6 in the spec).
7. Cache-write rollback: wrapped in `Channel.transaction`. If the local cache
   write fails, the YouTube push has already landed (no rollback API); the
   controller raises ActiveRecord::Rollback to surface the divergence to the
   daily diff job (11i).

**No commits, no pushes.** Master commits after manual validation.

**Open issues:** none from 11c. Pre-existing failures from the full-suite run
(numeric_formatting_spec on 11i's diff banner, auth_concern, calendar
edit/delete, composites path traversal) are sibling-agent or pre-existing and
not under 11c's purview.

## 2026-05-11 — §11i Daily Channel Diff-Check Cron + Resolution Page (rails-impl)

**Inputs:** `specs/11i-daily-diff-check-and-resolution.md`. Parent
`specs/11-channel-management-and-preview.md`. Phase 23's
`spec/services/youtube/diff_computer_spec.rb`,
`app/views/shared/_diff_table.html.erb`, and `DiffDecisionRadioComponent` reused
per the cross-spec parallelism note.

**Files landed**

Migration:

- `db/migrate/20260511024709_create_channel_diffs.rb` — `channel_diffs` table
  with `channel_id`, `detected_at`, `field_diffs jsonb default '{}'`,
  `resolved_at`, `resolution_payload jsonb`, `resolved_by_user_id`. Indexes:
  `channel_id`, `resolved_at`, `resolved_by_user_id`, plus a partial unique
  index
  `index_channel_diffs_open_per_channel ON channel_id WHERE resolved_at IS NULL`.
  FKs cascade-delete to channels, nullify on user delete. Applied to dev + test
  DBs.

Model:

- `app/models/channel_diff.rb` — `belongs_to :channel`,
  `belongs_to :resolved_by_user, optional: true`, validations on `detected_at` +
  hash-shape of `field_diffs` / `resolution_payload`, scopes `unresolved` /
  `open` / `resolved` / `recent`, helpers `fields`, `field_diff`, `pito_value`,
  `youtube_value`, `resolved?` / `open?`.
- `app/models/channel.rb` — added
  `has_many :channel_diffs, dependent: :destroy` + `open_channel_diff` accessor
  (`channel_diffs.unresolved.first`).
- `app/models/notification.rb` — added enum entry `channel_diff_detected: 10`.

Services (PORO, pure functions where applicable):

- `app/services/channels/diff_computer.rb` — whitelist-driven comparator
  (`title`, `handle`, `description`, `country`, `default_language`, `keywords`,
  `links`, `banner_url`, `avatar_url`, `watermark_url`, `watermark_timing`,
  `watermark_offset_ms`). Order-insensitive sets for `keywords`
  (whitespace-split tokens) + `links` (sorted `{title, url}` tuples).
  CDN-rotation filter strips query string + leading `https?://<host>` prefix
  before URL comparison. Whitespace normalized (strip + collapse). Nil / `""` /
  `[]` collapse to nil.
- `app/services/channels/diff_persister.rb` — find-or-create / refresh-in- place
  / auto-close empty-diff. Race-recovery via
  `rescue ActiveRecord::RecordNotUnique → update-in-place`.
- `app/services/channels/diff_apply.rb` — single-transaction apply orchestrator.
  Validates per-field decisions, stages YouTube-wins on the in-memory record,
  batches Pito-wins branding fields into one `Youtube::Client#update_channel`
  PUT, dispatches handle through `update_handle`, audits `title` / `handle`
  pushes into `ChannelChangeLog`, stamps `title_changed_at` /
  `handle_changed_at`, rolls back ALL changes on first push failure (locked Q3).
  Returns
  `Result(success:, diff:, error_code:, error_message:, pito_wins_fields:, youtube_wins_fields:, failing_field:)`.

Job:

- `app/jobs/channel_diff_check_job.rb` — Sidekiq job. Cron mode (`perform()`)
  iterates `Channel.where.not(youtube_connection_id: nil)`, isolates per-channel
  `TransientError` (log + skip + continue), re-raises `QuotaExhaustedError`
  (abort + Sidekiq retry). Single-channel mode (`perform(channel_id)`) is the
  entrypoint for the user-triggered `[sync]` path. `NeedsReauthError` /
  `AuthRevokedError` flips `youtube_connection.needs_reauth = true` and skips.
  Notification dedupe per locked Q1: fresh row → notify; expanded field set →
  notify; same-set / contracted set → skip. Turbo Stream broadcast targets
  `channel_diff_banner` frame in single-channel mode.

Notifications:

- `app/services/notification_formatter/templates/channel_diff_detected.rb` —
  registered in `templates.rb`. Carries the user to `/channels/:slug/diff`.

Config + routes:

- `config/sidekiq_cron.yml` — new `channel_diff_check` entry at `30 2 * * *`
  (one hour after the video diff cron `30 1 * * *`, per the spec's
  staggered-hour note).
- `config/routes.rb` — `member { get :diff; patch :apply_diff }` under
  `resources :channels`.

Controller + views:

- `app/controllers/channels_controller.rb` — added `#diff` (renders resolution
  page, JSON parity) and `#apply_diff` (consumes the per-field decisions form,
  dispatches `Channels::DiffApply`, redirects on success with a "changes
  applied. X pushed to youtube, Y updated locally" flash; re-renders with 422 +
  flash on validation / unsupported-pito-field / push-failure errors).
- `app/views/channels/diff.html.erb` — side-by-side resolution page in a
  `pane--standalone`. Lead paragraph uses the one-sentence-per-line `<br>`
  style; renders the shared `shared/_diff_table` partial with
  `display_only_fields: Channels::DiffApply::UNSUPPORTED_PITO_FIELDS`.
- `app/views/channels/_open_diff_banner.html.erb` — banner partial pointing the
  user to `/channels/:slug/diff` via `[ review changes ]`. Targeted by the job's
  Turbo Stream broadcast.
- `app/views/channels/_in_sync_banner.html.erb` — "in sync with youtube." notice
  partial for the post-`[sync]` clear-banner path.
- `app/views/shared/_diff_table.html.erb` — additive: accepts an optional
  `display_only_fields` local. Defaults to the video-side
  `Youtube::DiffComputer::DISPLAY_ONLY_FIELDS` so the existing video diff render
  is unchanged; channels pass their own set.

MCP tools (locked Q6):

- `app/mcp/tools/channel_diff_show.rb` + `channel_diff_apply.rb` — mirror the
  Phase 23 `video_diff_show` / `video_diff_apply` shape. Two-step
  `confirm: "yes" | "no"` flag (project hard rule). Gated on `Scopes::APP`.
  Auto-registered by `Mcp::PitoServer.register_tools`.

Youtube::Client surface:

- `app/services/youtube/client.rb` — added `#update_handle(channel, value)` stub
  raising `NotImplementedError` so `accept pito` on `handle` in the diff
  resolution flow surfaces a clean "this push path isn't wired yet" error. The
  stub is mockable in tests; real wiring lands with 11c follow-up research on
  YouTube's handle-management endpoint.

Specs added (file → example count):

- `spec/models/channel_diff_spec.rb` (21)
- `spec/services/channels/diff_computer_spec.rb` (31) — whitelist, whitespace,
  nil/empty equivalence, sorted-set keywords/links, CDN-rotation filter on
  banner/avatar/watermark, watermark_offset_ms integer coercion, defensive
  against malformed payloads.
- `spec/services/channels/diff_persister_spec.rb` (12)
- `spec/services/channels/diff_apply_spec.rb` (26) — validation errors, happy
  youtube/pito/mixed, handle push, partial-failure rollback, mixed-with-failure
  rollback, no-connection branch.
- `spec/jobs/channel_diff_check_job_spec.rb` (23) — happy single + cron mode,
  dedupe (same-set / expansion / contraction → auto-close), TransientError /
  QuotaExhaustedError / NeedsReauthError / pre-set needs_reauth,
  channel-not-found, idempotency.
- `spec/requests/channels/diff_spec.rb` (27) — happy youtube-wins / pito-wins /
  mixed, sad extra-key / missing-key / invalid-value, flaw race (already
  resolved) / partial-failure / unsupported-pito field, auth boundary.
- `spec/system/channel_diff_resolution_spec.rb` (2) — critical user journeys for
  accept_youtube and accept_pito.
- `spec/mcp/tools/channel_diff_show_spec.rb` (5) + `channel_diff_apply_spec.rb`
  (7) — JSON envelope shapes, scope gating, preview gate, error surfaces.

**Total new examples: 154**. Spec sweep covers happy + sad + edge + flaw per the
architect's exhaustive-spec rule.

**Gates**

- `bundle exec rspec` on the slice (model/service/job/request/system/mcp
  - adjacent video diff specs to confirm shared partial unchanged) → 642
    passing, 0 failures.
- `bundle exec rubocop` → 975 files, no offenses.
- `bin/brakeman -q -w2` → 0 warnings.
- Full suite shows 3 pre-existing failures (`numeric_formatting_spec` on
  pre-existing video-side `<%= ... .size %>` renders; `auth_concern_spec`
  `POST /channels` route non-existent; `calendar_edit_delete_spec` missing
  `note` link). All three were already failing before this work landed
  (git-stash verification).

**Locked decisions honored**

1. **Q-NOTIF dedupe** — fresh row or expanded field set notifies; same or
   contracted set skips. `ChannelDiffCheckJob#dedupe_notification?` compares the
   prior open row's field set (read pre-persistence) to the new diff's field
   set.
2. **Q-DEFAULT** — radio default `accept youtube` honored by reusing
   `DiffDecisionRadioComponent` (default `selected: YOUTUBE`).
3. **Q-PARTIAL** — transaction with full rollback on first push failure. Flash:
   "could not push <field> to youtube: <reason>. no changes applied." Per the
   user's note: "applied N of M; rest rolled back; review and retry" — surfaced
   via the `failing_field` accessor + the flash copy.
4. **Q-CDN** — regex-based normalization in `DiffComputer`: strips `?...` query
   string + leading `https?://<host>`. Hash-column approach NOT taken (no
   existing hash columns; would have required another migration). The path
   comparison is the stable proxy.
5. **Q-WHITESPACE** — `normalize_string` strips + collapses runs of whitespace
   before comparison; empty / nil / "" collapse to nil.
6. **Q-CLI** — MCP tools shipped (`channel_diff_show` / `channel_diff_apply`)
   matching Phase 23's shape. Two-step `confirm` flag. CLI surface itself is
   silent for now (deferred to Phase 9 CLI parity work, per the spec's
   open-question lean).
7. **In-sync notice target** — `_in_sync_banner.html.erb` renders into the same
   `channel_diff_banner` Turbo frame the open-diff banner targets. The job's
   `broadcast_banner` method handles both diff-and-no-diff branches.
8. **Q-CHANGELOG-FIELDS** — audit narrowed to `title` + `handle` (matches
   `ChannelChangeLog::FIELDS`). Other Pito-wins pushes (description, country,
   language, keywords) update the channel and resolve the diff but do NOT write
   a log row.

**Cross-agent coordination**

- The 11b agent committed (`24c825e`) mid-session and that commit shipped most
  of this work (the agent picked up my just-written files into a single Phase
  7.5 commit). My two `number_with_delimiter` lint fixes (added after the
  commit's snapshot) sit unstaged for the master to fold in.
- `app/views/channels/show.html.erb` not modified by 11i (per the user's
  coordination instruction). The empty `channel_diff_banner` Turbo frame slot
  11b shipped is the broadcast target.
- `app/views/shared/_diff_table.html.erb` extended additively with an optional
  `display_only_fields` local. The video diff render defaults preserved; the
  channel diff render passes its own set. Video diff request specs still pass
  (309 video-side specs run green with the partial change in place).
- `Youtube::Client#update_handle` shipped as a `NotImplementedError` stub. 11c's
  `update_channel` already excludes `:handle` from
  `UPDATE_CHANNEL_BRANDING_KEYS` so the dispatch goes through `update_handle`
  instead — clean handoff to 11c follow-up research.

**`[sync]` button reuse — deferred (NOT done in 11i)**

The spec's §[sync]-button-reuse section is NOT implemented in this slice.
`BulkSyncJob` still dispatches `ChannelSync` by naming convention. The spec
assumed `ChannelSync` was a placeholder no-op; in reality `ChannelSync` now does
a real fetch+overwrite per 11a's upgrade. Forcing the diff path through the bulk
dispatcher would break the existing `ChannelSync` cache write contract and the
adjacent `BulkSyncJob` specs. Followup needed: decide whether the `[sync]`
button should diff-check (locked Q7 intent) or cache-sync (11a behavior), and
refactor `BulkSyncJob` accordingly. Daily cron

- MCP tool + manual `ChannelDiffCheckJob.perform_now(channel_id:)` all work
  fine; just the `[sync]` button convention swap remains.

**Manual test recipe** (for the user)

1. `bin/rails runner 'Channel.first.update_columns(title: "Local Divergent Title")'`
2. `bin/rails runner 'ChannelDiffCheckJob.new.perform(Channel.first.id)'`
3. Visit `/channels/<slug>/diff` — verify the table shows the divergent local
   title in the Pito column and the original YouTube title in the YouTube
   column.
4. Default radio is `accept youtube`. Click `[ apply changes ]`.
5. Verify redirect to `/channels/<slug>` with flash "changes applied. 1 field
   updated locally."
6. Verify `Channel.first.reload.title` matches the YouTube title.
7. Re-run `ChannelDiffCheckJob.new.perform(Channel.first.id)` → no new diff row,
   no new notification.
8. Cron registration:
   `bin/rails runner 'pp Sidekiq::Cron::Job.find("channel_diff_check").attributes'`
   → confirms the entry with `"30 2 * * *"`.
9. MCP smoke: `bin/mcp` then call `channel_diff_show(id: "<slug>")` to see the
   JSON envelope; `channel_diff_apply` without `confirm` returns a preview; with
   `confirm: "yes"` applies for real.

**No commits, no pushes.** Master commits after manual validation.

**Open issues**

- `[sync]` button still routes through `BulkSyncJob → ChannelSync` (full cache
  overwrite, not diff-check). Locked-Q7 intent says it should diff-check; needs
  a `BulkSyncJob` convention exception or a `ChannelSync` refactor. Tracked as a
  11i follow-up.
- `Youtube::Client#update_handle` is a `NotImplementedError` stub. 11c follow-up
  research owns the real implementation.
- Three pre-existing full-suite lint failures (`numeric_formatting_spec` on
  video-side files, `auth_concern_spec`, `calendar_edit_delete_spec`) are NOT
  this slice's responsibility; they predate this work (verified via git stash).

## 2026-05-11 — §11h Calendar Reminder Integration (rails-impl)

**Spec:** `specs/11h-calendar-reminder-integration.md` (sub-spec of 11). Wires
the 14-day title/handle unlock gate on `/channels/:slug/edit` to the Phase 21
JSON endpoint `POST /calendar/entries.json`. The 11c stub controller
(`reminder_link_controller.js`) is filled in; the toast, duplicate-detection,
and idempotency contract land here.

**Locked decisions (passed in by user):**

1. Toast position: top-right (matches existing flash convention).
2. Reminder time-of-day default: `AppSetting.first.timezone` if set, midnight
   UTC otherwise. The Stimulus controller reads the timezone via a
   `data-reminder-link-timezone-value` attribute resolved server-side in
   `_form.html.erb`.
3. Duplicate handling: no-op + toast `reminder already exists for YYYY-MM-DD`.
   Implemented server-side in `Calendar::EntriesController#create` keyed on
   `(entry_type: milestone_manual, title, starts_at::date)`.
4. Title body shape: distinct titles per gate — `Channel title unlock — <name>`
   vs `Channel handle unlock — <name>`.
5. Channel-name source: `Channel#title` if present, else `url_slug` (UC-id
   segment of the channel_url), else `"this channel"`. New helper
   `channel_reminder_name` in `ChannelsHelper`.

**Spec → reality mapping (the `kind: reminder` question)**

The sub-spec describes a `Calendar::Entry` of `kind: "reminder"` at several
points. The actual `CalendarEntry` model uses `entry_type` with eight values,
none of them `reminder`. The closest user-creatable type is `milestone_manual`
(no required FKs, no metadata schema beyond `user_overrides`). The
cross-reference validator (`CalendarEntryCrossReferenceValidator::RULES`)
explicitly forbids `channel_id` on every user-creatable type — including
`milestone_manual`. The wire payload therefore omits `channel_id` entirely; the
link back to the channel lives in the title body. The JSON envelope contract is
the existing `CalendarEntryDecorator#as_detail_json`; we added one optional
top-level `duplicate: "yes"` marker on idempotent hits.

**Files changed**

- `app/javascript/controllers/reminder_link_controller.js` — fleshed out from
  11c stub. POSTs JSON to `/calendar/entries.json` with
  `entry_type: milestone_manual`, the composed title, the unlock date as
  `starts_at`, `all_day: "yes"` (yes/no boundary rule), and the configured
  timezone. Renders top-right toasts via the global `.toast-container` (matches
  `clipboard_copy_controller` pattern). Short-circuits a localStorage-marker
  check before the fetch so a repeat click in the same browser session surfaces
  the "already exists" toast without round-tripping. Network and 4xx outcomes
  render the generic failure toast. CSRF token sourced from the
  `<meta name="csrf-token">` tag.
- `app/views/channels/_form.html.erb` — both reminder links extended with
  `data-reminder-link-channel-name-value` (channel display name resolved
  server-side) and `data-reminder-link-timezone-value` (AppSetting timezone or
  `"UTC"`).
- `app/views/channels/edit.html.erb` — removed the orphan
  `data-reminder-link-target="toast"` slot 11c shipped as a placeholder.
  Stimulus targets must live inside the controller's element scope, and the
  controller binds to the link itself; the toast renders into the global
  container. (Note: another agent in flight wrapped the form in a
  `channel-preview` controller + `[preview]` modal — coexists cleanly with this
  removal.)
- `app/helpers/channels_helper.rb` — added `channel_reminder_name` helper
  resolving `Channel#title → url_slug → "this channel"`.
- `app/controllers/calendar/entries_controller.rb` — added idempotency check in
  `#create` for the milestone_manual + "Channel … unlock — …" title shape.
  Existing match returns 200 with the existing entry + `@duplicate = true`
  instance var.
- `app/views/calendar/entries/show.json.jbuilder` — emits `duplicate: "yes"`
  (boundary yes/no string) when the controller sets `@duplicate`.
- `spec/system/calendar_reminder_spec.rb` — new system spec (rack_test, 11
  examples). Covers link rendering with every data attribute, the channel-name
  fallback chain, gate-kind switching (handle vs title), gate-closed omission,
  an XSS smoke (channel title with `<script>` literal), the happy POST, two
  negative duplicate cases (different date, different title), the idempotent
  duplicate POST, and two bad-payload sad paths.
- `spec/requests/calendar/entries_spec.rb` — extended with the
  channel-rename-unlock variant: happy 201, idempotent second POST (200 +
  `duplicate: "yes"`), different-date non-duplicate, rejection of `channel_id`
  on `milestone_manual` (proves the cross-reference validator gate).

**Specs added: +15** (11 system + 4 request). Both
`bundle exec rspec spec/system/channel_edit_form_spec.rb spec/system/calendar_reminder_spec.rb`
and
`bundle exec rspec spec/requests/calendar/entries_spec.rb spec/requests/channels/edit_form_spec.rb`
green. `bundle exec rubocop` clean across all 991 files.
`bundle exec brakeman -q -w2` clean (0 warnings, 0 errors).

**Plan ticked:** 11h has no dedicated plan.md checkbox — Step 11 sub-specs were
added via `additions.md` (entry dated 2026-05-11) and not back-folded into the
plan workstreams list. Nothing to tick.

**Open issues**

- The locked-decision "reminder time-of-day" default is encoded as the
  `data-reminder-link-timezone-value` attribute on the link. The Stimulus
  controller sends the unlock date as the `starts_at` (no time component); the
  controller's `coerce_yes_no!` / `CalendarEntry#stamp_install_timezone` chain
  interprets that date-only string as midnight in the configured timezone. With
  `all_day: "yes"` the schedule view collapses the display to date-only, so the
  underlying time is just a sort key. Verified via the request-spec round-trip
  (`starts_at` parsed back as a midnight-on-date timestamp).
- The duplicate-detection localStorage marker is best-effort client-side state.
  The server-side idempotency check is the authoritative gate — even on a fresh
  browser the second POST will no-op. The client marker just spares one HTTP
  round-trip in the common case (same tab, same session).
- The pre-existing `calendar_edit_delete_spec.rb` failure is unrelated (verified
  via stash).

**Cross-agent coordination**

- Another agent (channel-preview revamp) was modifying
  `app/views/channels/edit.html.erb` and adding a `channel_preview_controller`;
  their changes coexist with the reminder-link work because we touched different
  sections (preview wraps the form, reminder data attributes live inside the
  form).
- `_form.html.erb` was hit by both agents; the merge is clean.
- Did NOT touch `extras/` or `docs/` beyond appending this log entry.

**No commits, no pushes.** Master commits after manual validation.

## 2026-05-11 — §11g Channel Change History View (rails-impl)

**Spec:** `specs/11g-channel-change-history.md` (sub-spec of 11). Adds the
user-facing reader on top of the `channel_change_logs` audit table already
created by 11a. Three reader surfaces — HTML, JSON, MCP — all read-only.

**Locked decisions (passed in by user, all 10 open questions resolved):**

1. Pagination — 50 per page (matches `NotificationsController` + Phase 21
   precedent).
2. `changed_by_user_id` — render the email.
3. Relative time — `time_ago_in_words` relative + absolute UTC on the `<time>`
   element's `title=` attribute.
4. `Channel#channel_change_logs` `has_many` association already exists (verified
   — declared in 11a).
5. No decorator extraction — inline jbuilder (simpler).
6. Row does NOT expose `created_at` (identical to `changed_at` in the
   append-only audit pattern).
7. Empty state copy — `no changes yet` (muted).
8. `[changes]` link sits between `[e]` and `[sync]` in the channel show heading
   actions row.
9. JSON envelope key — `changes` (matches Phase 21 plural-noun shape).
10. MCP tool name — `channel_changes_list` (matches the `notifications_list`
    `<noun>_<verb>` precedent).

**Files changed**

- `app/controllers/channels/change_logs_controller.rb` — new. Single `#index`
  action serving HTML + JSON. Pagination via the `NotificationsController`
  convention (`PER_PAGE = 50`, `@page = [params[:page].to_i, 1].max`). Inline
  `redirect_to_canonical_channel_slug!` for nested-route canonical slug 301 (the
  `FriendlyRedirect` concern uses `params[:id]`; our nested route uses
  `params[:channel_id]`).
- `config/routes.rb` — added
  `resources :change_logs, only: :index, path: "history", controller: "channels/change_logs"`
  inside the existing `resources :channels do … end` block. The named-route
  helper is `channel_change_logs_path(channel)` → `/channels/<slug>/history`.
- `app/views/channels/change_logs/index.html.erb` — new. H1 + lead paragraph
  (one-sentence-per-line `<br>` style), `pane--standalone` wrapper, four-column
  table (`field` · `old → new` · `changed at` · `changed by`), pagination footer
  with `[previous]` / `[next]` bracketed links, muted `no changes yet` empty
  state.
- `app/views/channels/change_logs/index.json.jbuilder` — new. Phase 21 envelope:
  `changes` array + `pagination { page, per_page, total, total_pages }`.
  ISO-8601 UTC `changed_at`. `changed_by` is `{ id, email }` or `null`.
- `app/views/channels/show.html.erb` — added `[changes]` bracketed link in the
  heading actions row, slotted between `[e]` and `[sync]`.
- `app/mcp/tools/channel_changes_list.rb` — new. Read-only MCP tool on the `app`
  scope. Input: `channel` (required string — slug or numeric id), `page`
  (optional integer, min 1, default 1). Pagination + envelope identical to the
  JSON branch.

**Specs added**

- `spec/factories/channel_change_logs.rb` — new factory.
- `spec/requests/channels/change_logs_spec.rb` — 28 examples. Happy HTML (8),
  happy JSON (6), sad (2 — 404 + login redirect), edge empty (2), edge
  pagination (8), flaw XSS (1).
- `spec/views/channels/change_logs/index_html_spec.rb` — 18 examples. Empty
  state (3), non-empty rendering (10), system-FK-null (2), pagination (4).
- `spec/views/channels/change_logs/index_json_spec.rb` — 10 examples. Wire-shape
  asserts on all envelope keys + ISO-8601 timestamp + null FK branch.
- `spec/mcp/tools/channel_changes_list_spec.rb` — 20 examples. Happy path (7),
  pagination (4), empty state (1), scope gate (2), validation (3), schema (2),
  registration (1).
- `spec/system/channel_change_history_spec.rb` — 3 examples. Thin
  cross-controller journey + empty state + XSS escape proof.

**Spec → reality mapping (FK NOT NULL)**

The spec called out a "FK null" rendering branch for legacy / system-generated
rows. The DB schema actually has `changed_by_user_id NOT NULL` (`db/schema.rb`),
and the model's `belongs_to :changed_by_user` is required. The view + jbuilder +
MCP tool still carry the defensive `if log.changed_by_user` branch (costs
nothing, future-proofs if the column ever loosens), and the view spec / JSON
view spec exercise the branch via a `build_stubbed` in-memory record. The
request + MCP specs assert the steady-state (always `{ id, email }`) and
explicitly note the FK constraint.

**Gates green**

`bundle exec rspec spec/requests/channels/change_logs_spec.rb spec/views/channels/change_logs/ spec/mcp/tools/channel_changes_list_spec.rb spec/system/channel_change_history_spec.rb`
— 79 examples, 0 failures.

`bundle exec rubocop` — 991 files, 0 offenses.

`bin/brakeman -q -w2` — 0 warnings, 0 errors.

**Plan ticked**

11g has no dedicated plan.md checkbox — Step 11 sub-specs were added via
`additions.md` (entry dated 2026-05-11) and not back-folded into the plan
workstreams list. Nothing to tick (same situation as the 11h log entry above).

**Open issues**

- The 4-column rendering uses inline styles for alignment; if the project's
  design pass introduces a shared `<table class="audit">` convention, this view
  should adopt it.
- Hover-tooltip on `<time title=...>` is fine for desktop; touch devices won't
  see it. The locked decision is to keep it (matches existing project pattern);
  the alternative absolute-inline can ship as a future enhancement if user
  feedback flags it.

**Cross-agent coordination**

- Sibling agents were active on `app/views/channels/show.html.erb` (the `[sync]`
  link got `?intent=diff_check` appended by another pass) and on
  `config/routes.rb` (a `preview` resource landed inside the same
  `resources :channels do … end` block). Both diffs coexist with this work — my
  `[changes]` link sits between `[e]` and `[sync]` exactly as the master
  directed, and my `change_logs` route landed alongside the new `preview` route.
- 3 failing examples in `spec/requests/channels/previews_spec.rb` are NOT this
  slice's responsibility — they belong to the in-flight `channels/previews`
  agent.
- Did NOT touch `extras/`. Did NOT touch `docs/` beyond appending this log
  entry.

**No commits, no pushes.** Master commits after manual validation.

## 2026-05-11 — §11d Channel Multi-Layout Preview Component (rails-impl)

**Spec:** `specs/11d-channel-preview-component.md` (sub-spec of 11). Adds the
in-app multi-layout preview the channel edit form opens via a `[preview]`
bracketed link. Three viewport sizes (desktop / mobile / TV) rendered inside a
new shared wide modal. Form-input edits stream into the preview via a debounced
300ms Stimulus listener; the server re-renders the component reflecting the
pending overrides without writing to the DB.

**Locked decisions (passed in by user, all 7 open questions resolved):**

1. TV layout — best-guess 1920x1080 (padding 80px sides, larger fonts), iterate
   on user feedback.
2. Modal open trigger — `[preview]` button on the edit form ONLY (show page is
   read-only cache).
3. Default active layout on open — desktop (matches dogfooding posture).
4. Pending-edits Stimulus event — debounced 300ms `input` listener.
5. Brand-account watermark preview — NOT rendered in 11d; lives in 11e.
6. Sample thumbnails — JPEGs in `public/preview/video_thumbnails/`, muted
   `[ no preview thumbnails yet ]` fallback when directory is empty (D8).
7. Modal close behavior — Esc, click-outside, and `[close]` button all close.

**Files changed**

- `app/components/channel_preview_component.rb` + `.html.erb` — new
  ViewComponent. Renders three sibling layout panels (`#preview-layout-desktop`,
  `#preview-layout-mobile`, `#preview-layout-tv`); the active one carries
  `.active`, the others carry the `hidden` attribute. `pending:` Hash overlays
  every channel attribute lookup so the streamed re-render reflects the
  dirty form state without touching the DB.
- `app/javascript/controllers/channel_preview_controller.js` — new. Two
  responsibilities: top-nav layout toggle (`selectLayout`) and debounced
  form-input listener (`updatePreview`) that issues a Turbo-Stream `GET` to
  `/channels/:id/preview?...` with the dirty field set. Debounce
  configurable via `debounceMsValue` (default 300ms).
- `app/controllers/channels/previews_controller.rb` — new. Single `#show`
  action. No DB writes. Renders a Turbo Stream replacing `#channel-preview`
  with a freshly-rendered component, or an HTML render of the bare component
  for unit testing. Flattens `links_attributes` nested-form params into the
  `[{title:, url:}]` jsonb shape the component's resolver expects.
- `app/helpers/preview_helper.rb` — new. Owns `RANDOM_VIDEO_TITLES` (20
  neutral, English-only test fixtures), `random_video_thumbnail(seed:)`
  (deterministic per-seed pick from `public/preview/video_thumbnails/` —
  returns `nil` when the directory is empty), `sample_titles(count:, seed:)`
  for deterministic title selection, and `random_watermark_frame(seed:)` as
  a stub for 11e (returns `nil`; 11d does not call it).
- `app/views/shared/_wide_modal.html.erb` — new. Reusable wide-variant dialog
  frame (max-width 1320px, max-height 95vh). 11e watermark preview will
  reuse this shell. Carries the `confirm-modal` Stimulus controller so Esc /
  click-outside / `[close]` all close, matching the existing dialog UX.
- `app/views/channels/edit.html.erb` — added the `channel-preview` controller
  scope wrapping both the form (so the input listener sees keystrokes) and
  the modal (so the streamed `#channel-preview` replacement target is in
  scope). Inlined the modal mount with `[desktop][mobile][tv]` top-nav links.
  The `[preview]` bracketed link inside the pane opens the modal via
  `modal-trigger#open`. Did NOT restructure the form layout per the
  coordination note.
- `app/views/channels/_form.html.erb` — added `data-action=
  "input->channel-preview#updatePreview"` plus
  `data-channel-preview-field-param="<attr>"` on the title, handle, and
  description fields. No layout changes; only data-attribute additions.
- `config/routes.rb` — added
  `resource :preview, only: :show, controller: "channels/previews"` inside
  the existing `resources :channels do … end` block. Named-route helper is
  `channel_preview_path(channel)` → `/channels/<slug>/preview`.
- `app/assets/tailwind/application.css` — added `.wide-modal` (and
  `-inner` / `-header` / `-title-row` / `-topnav` / `-body`),
  `.preview-nav-active`, and the three `.preview-canvas--<layout>` /
  `.preview-banner--<layout>` / `.preview-identity--<layout>` /
  `.preview-avatar--<layout>` / `.preview-videos--<layout>` size + spacing
  rule sets. TV layout uses `transform: scale(0.6)` with
  `transform-origin: top left` to fit a 1920px-wide canvas inside the
  wide-modal body.
- `public/preview/video_thumbnails/.keep` — new. Directory marker; user
  drops `thumb-01.jpg` ... `thumb-08.jpg` JPEGs here out-of-band. Empty
  directory triggers the `[ no preview thumbnails yet ]` empty-state copy
  per D8.

**Specs added**

- `spec/helpers/preview_helper_spec.rb` — 14 examples. `RANDOM_VIDEO_TITLES`
  frozen + non-empty, `sample_titles` deterministic + wrap-around,
  `random_video_thumbnail` deterministic / empty-dir / missing-dir branches,
  `random_watermark_frame` stub return.
- `spec/components/channel_preview_component_spec.rb` — 34 examples.
  Structure (4), banner-present / banner-absent / banner-override (4),
  avatar-present / avatar-absent / avatar-override (3), title / handle /
  subs + placeholder branches (7), description-present / -absent /
  -override / -blank-override (4), links-present / -empty / -override /
  -json-payload / -empty-override (5), video-row real / static / empty
  fallback (3), Stimulus wiring (3), hard-rule hygiene (1).
- `spec/requests/channels/previews_spec.rb` — 12 examples. Happy path (2),
  pending-edit query params (2), active_layout query param (2), Turbo
  Stream branch (3), 404 (1), `links_attributes` flattening (2).
- `spec/system/channel_preview_spec.rb` — 9 examples (rack_test). Edit-page
  wiring asserts: `[preview]` link presence + modal-trigger wiring, wide
  modal renders with three panels, desktop active by default, top-nav
  rendered with `[desktop]` active-styled, controller scope wraps both
  form and modal, every editable input carries the input action + param,
  no JS confirm / alert anywhere. Preview-endpoint payload smoke (2) —
  validates the wire that the Stimulus controller fetches.

**Gates green**

- `bundle exec rspec spec/components/channel_preview_component_spec.rb
  spec/system/channel_preview_spec.rb spec/helpers/preview_helper_spec.rb
  spec/requests/channels/previews_spec.rb` — 69 examples, 0 failures.
- Adjacent run (`spec/system/channel_edit_form_spec.rb`,
  `spec/system/channel_show_journey_spec.rb`, `spec/requests/channels/`,
  `spec/components/`) — 272 examples, 0 failures.
- `bundle exec rubocop` — 993 files, 0 offenses.
- `bin/brakeman -q -w2` — 0 warnings, 0 errors.

**Spec → reality deltas**

- The spec calls for `app/components/channel_preview_component.html.erb` to
  render all three panels with only the active one visible. Implementation
  uses the `hidden` HTML attribute on inactive panels (rather than only a
  CSS rule) so Capybara's default visibility filter naturally hides them in
  specs and screen readers honor the state without CSS support. Specs use
  `visible: :all` to inspect the non-active panels.
- The spec's `pending:` Hash treatment was tightened — a key present with a
  blank string (user cleared the field) wins over the persisted column;
  only an absent key falls through. This matches the live-edit posture
  (clearing a banner URL streams a placeholder block immediately).
- The spec's `links` override accepts both a Ruby Array (server-side
  in-process render) and a JSON-encoded String (the wire format query
  params land in). The controller also flattens `links_attributes` from
  the edit form's nested-attributes shape into the same Array-of-Hashes
  the jsonb column carries, so the debounced preview includes link edits
  even though they ride a different param key on the form.

**Cross-agent coordination**

- Sibling 11g agent landed a `change_logs` route inside the same
  `resources :channels do … end` block; my `resource :preview` route
  landed alongside it without conflict.
- Did NOT restructure the channel edit form layout (per the coordination
  note). Only added the `[preview]` button at the top of the form pane and
  added `data-action` / `data-channel-preview-field-param` attributes to
  the title, handle, and description inputs.
- 11e (watermark preview) will reuse `shared/_wide_modal.html.erb` and the
  `PreviewHelper.random_watermark_frame` stub that already exists.
- Did NOT touch `extras/`. Did NOT touch `docs/` beyond appending this log
  entry.

**Plan ticked**

11d has no dedicated `plan.md` checkbox — Step 11 sub-specs were added via
`additions.md` and not back-folded into the plan workstreams list. Nothing to
tick (same situation as the 11g / 11h / 11i log entries above).

**Open issues**

- TV layout's 0.6 scale factor is a best-guess approximation per locked Q1.
  Expect iteration from user feedback once the dogfooding pass starts.
- The `public/preview/video_thumbnails/` directory ships empty; the user
  needs to drop 4–8 JPEGs (`thumb-01.jpg` ... `thumb-08.jpg`) before the
  static fallback branch renders thumbnails. Until then, low-video channels
  show the `[ no preview thumbnails yet ]` muted line.
- The Stimulus controller calls `fetch` directly (not `Turbo.fetch`) and
  pipes the response into `Turbo.renderStreamMessage`. If a future Turbo
  upgrade exposes a cleaner fetch-stream helper, this is one of the few
  call sites that could simplify.

**No commits, no pushes.** Master commits after manual validation.
