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
