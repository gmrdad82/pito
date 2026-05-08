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
