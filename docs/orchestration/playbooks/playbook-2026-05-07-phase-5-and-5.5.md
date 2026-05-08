# Manual test playbook — Phase 5 (Auth Foundation) + Phase 5.5 (polish bundle)

**Branch:** `main` **Diff range:** `f4b8c68..HEAD` (11 commits) **Specs:**
`docs/plans/beta/03-auth-foundation/specs/{5a,5b,5c}-*.md` **Reviewer run:**
2026-05-07 15:13

## Pipeline summary

- Code review: pass — no correctness or spec-conformance blockers; a handful of
  non-blocking suggestions below.
- Simplify: pass — one minor inconsistency flagged below; nothing structural.
- Test suite: **1582 examples, 0 failures, 0 pending** (7m24s wall, includes the
  new Settings tokens system spec).
- Rubocop: **clean** (344 files inspected, 0 offenses).
- Brakeman (`-q -A -w1`): **6 warnings** (1 ForceSSL + 5 Weak-confidence
  UnscopedFind). This is a **net improvement** over the f4b8c68 baseline (1
  ForceSSL + 20 Weak-confidence UnscopedFind). The five remaining unscoped finds
  (`Note.find` in `notes_controller.rb:122`, four `Video.find` calls in
  `videos_controller.rb`) are pre-existing — Brakeman cannot see the
  `BelongsToTenant` default scope wired in this diff.
- bundler-audit: **clean** (1078 advisories scanned against the lockfile,
  ruby-advisory-db at b1e3c15 / 2026-03-30).
- cargo audit: **NOT RUN — `cargo-audit` is not installed on this machine.** See
  "Blockers" below; the user must install and run it locally before signing off
  (the f4b8c68 baseline carried 1 known low-severity `lru` advisory deferred via
  follow-ups #4).
- Hard-rule grep:
  - `data-turbo-confirm`: 1 hit, in a doc comment in
    `app/components/bracketed_link_component.rb` only — clean.
  - `window.confirm` / `alert(` / `prompt(`: only doc-comment / `beforeunload`
    references in `unsaved_form_controller.js` and the bracketed-link comment —
    clean.
  - `target="_blank"`: 1 hit (`app/views/channels/_pane.html.erb`) and it
    carries `rel="noopener noreferrer"` — clean.
- Yes/no boundary: clean. New `has_commentary_track` payload uses `"yes"` /
  `"no"` strings end-to-end (Rails `Api::FootagesController#coerce_yes_no_attrs`
  ↔ Rust `extras/cli/src/footage/api/{client,models}.rs`). The new `htmlLegend`
  plugin uses `dataset.hidden = "yes"|"no"` for its DOM hint.
- Tenant scoping: 17 data models include `BelongsToTenant`. Documented
  exceptions: `Tenant`, `User`, `ApiToken`, `AppSetting` (singletons / identity
  primitives), `ApplicationRecord`, `Current` (not models in the data sense).
  `User` carries an explicit `belongs_to :tenant` without the concern (no
  default-scope crash) so login lookups can run pre-tenant-context — correct.

## Blockers

1. **`cargo-audit` is not installed** in your local PATH (no binary at
   `~/.cargo/bin/cargo-audit`, not in `pacman`, not in `~/.local/bin`). The
   pipeline could not confirm the Rust dependency-advisory state. Before you
   commit, install it with `cargo install cargo-audit --locked` and run
   `cargo audit` from the repo root (the lockfile is at
   `~/Dev/pito/Cargo.lock`). The expected outcome is **1 known
   low-severity `lru` advisory deferred via follow-ups #4**; flag anything else.

(No code-level blockers; everything else is non-blocking polish.)

## Concerns and suggestions

### Code review

1. **`Settings::TokensController#create` mixes `:unprocessable_entity` and
   `:unprocessable_content` status symbols** within the same method (line 41 vs
   50/57/64 in `app/controllers/settings/tokens_controller.rb`). Rails treats
   them identically, but the inconsistency reads as a leftover from the Rack 3
   deprecation pass. Pick one — prefer `:unprocessable_content` since the rest
   of the bundle has migrated.
2. **`Settings::TokensController#create` has 4 near-identical
   `ApiToken.new(...) + errors.add + render :new + return` blocks** for
   pre-validation (expires_at parse, scope catalog, name presence, scopes
   presence). The model's `validates :name, presence: true` and
   `validate :scopes_subset_of_catalog` already cover three of the four. The
   only truly controller-level check is `expires_at` parsing; the rest could
   collapse into a single
   `ApiToken.new(...).tap { |t| ... }; render :new unless t.save` flow.
   Non-blocking — the explicit version is at least clear.
3. **`Api::TokenAuthenticator#audit` swallows `StandardError`.** Comment says
   "audit logging must never break the request path" — fine — but a logger
   that's silently dropping every event is hard to debug. Consider swallowing
   only `IOError` / `Errno::ENOSPC` and letting unexpected errors surface in
   `Rails.logger.warn` so you notice if the audit logger is ever broken.
   Non-blocking.
4. **`Mcp::RackApp#call` resets `Current` in `ensure`, but Rails
   `CurrentAttributes` already resets per-request** via
   `ActiveSupport::Executor`. The explicit `Current.reset` is harmless but
   redundant. Optional cleanup.
5. **Brakeman's 5 weak `UnscopedFind` warnings on
   `app/controllers/{notes,videos}_controller.rb`** are now false positives —
   `BelongsToTenant`'s default scope makes the bare `.find(params[:id])`
   tenant-safe. Adding an explicit `where(tenant_id: Current.tenant_id)` (or
   wrapping in `tenant_scope!`) before `.find` would clear the warning AND
   protect against accidental `.unscoped` regressions. Worth a follow-up entry.

### Simplify

1. **`Scopes::ALL` is constructed by hand from the individual constants** when a
   `freeze`-stable list of values from `DESCRIPTIONS.keys` would do the same.
   Mostly stylistic; the explicit form is easier to scan when re-reading.
2. **`htmlLegendPlugin.afterUpdate` re-creates every legend `<a>` from scratch
   on every chart update.** For dashboards with frequent re-renders this churns
   DOM. A `dataset-index → element` map and toggling text-color/`dataset.hidden`
   would be enough. Cosmetic; current charts don't update often.
3. **The footage pane's `<colgroup>` widths**
   (`180/100/110/48/80/80/80/80 px = 758px`) plus `td` padding overflow the
   452px pane — the table intentionally horizontally scrolls inside the pane.
   Worth confirming visually that the themed scrollbar inside the pane is the
   desired UX (vs reflow into a smaller fixed column set on narrow viewports).

## Manual test steps

> Setup preamble — run BEFORE the User Validation walkthrough.

1. **Verify the pepper credential is present.** Run:
   `bin/rails runner 'puts Rails.application.credentials.dig(:tokens, :pepper).present?'`
   Expected: `true`. If `false`: `bin/rails credentials:edit` and add
   `tokens:\n  pepper: <openssl rand -hex 32>`.
2. **Reset the database to a clean state with a freshly-seeded dev token.** Run:
   `bin/rails db:reset`. Expected: somewhere in the seed output, look for the
   line block `"Dev token minted (save this now — cannot be shown again):"`
   followed by the plaintext. Save the plaintext to a scratch file (we'll need
   it for the CLI step).
3. **Start the app and the MCP HTTP server.** Run: `bin/dev` in one terminal
   (Web Puma + Sidekiq + Tailwind watcher), `bin/mcp-web` in a second terminal
   (MCP Puma on `:3001`). Expected: Puma reports listening on `:3000`, MCP Puma
   reports listening on `:3001`. No stack traces.
4. **Pepper-resolver test fallback (CI-shaped run).** In a fresh shell with
   `unset RAILS_MASTER_KEY` and the master.key file temporarily renamed, run:
   `bundle exec rspec spec/models/api_token_spec.rb spec/seeds_spec.rb`.
   Expected: green. The test-env third-tier fallback
   (`"test-pepper-not-a-secret"`) keeps digests deterministic without a master
   key.
5. **Run cargo audit (BLOCKER above).** Install if needed:
   `cargo install cargo-audit --locked`. Run from repo root:
   `cd ~/Dev/pito && cargo audit`. Expected: 1 advisory for `lru`
   (known, deferred). Anything else → STOP.

### Phase 5 — token CRUD + MCP bearer auth

6. **Visit `/settings/tokens`** in the browser. Expected: the dev token (name:
   `dev`) appears in the active tokens table with scopes
   `dev:read, dev:write, yt:read, yt:write, project:read, project:write`. Status
   column reads `active`.

7. **Click `[ new token ]`, fill in name `playbook-test` and check `dev:read`
   only, leave expires blank, submit.** Expected: the create page renders with
   the warning banner "save this now — it cannot be shown again", a
   `pre.code-block` with the plaintext token, and the same metadata table (name,
   scopes, expires, preview). Copy the plaintext to a scratch file as
   `PLAINTEXT_RO`.

8. **Click `[ I have saved it ]`, return to the index, locate the
   `playbook-test` row, click `[ revoke ]`.** Expected: the action confirmation
   screen renders with metadata table, `[ revoke ]` and `[ cancel ]` buttons
   (red destructive style on `[ revoke ]`). Submit. Index reloads with
   `playbook-test` now in the revoked tokens block, opacity 0.6, status
   `revoked YYYY-MM-DD`.

9. **MCP HTTP happy path.** Replace `<DEV_PLAINTEXT>` with the dev token:

   ```bash
   curl -s -i -X POST http://localhost:3001/mcp \
     -H "Authorization: Bearer <DEV_PLAINTEXT>" \
     -H "Content-Type: application/json" \
     -H "Accept: application/json, text/event-stream" \
     -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
   ```

   Expected: HTTP 200 with a JSON envelope listing the MCP tools.

10. **MCP HTTP bad-token path.** Same curl but with
    `Authorization: Bearer this-is-garbage`. Expected: HTTP 401 with body
    `{"error":"invalid_token"}`.

11. **MCP HTTP missing-header path.** Same curl with no `Authorization` header.
    Expected: HTTP 401 with body `{"error":"missing_token"}`.

12. **MCP HTTP scope rejection.** Use `PLAINTEXT_RO` (the `dev:read`-only token
    created in step 7 — `playbook-test` BEFORE you revoked it; if you already
    revoked, mint a fresh dev:read-only token first), and call a tool that needs
    `dev:write`:

    ```bash
    curl -s -i -X POST http://localhost:3001/mcp \
      -H "Authorization: Bearer <PLAINTEXT_RO>" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json, text/event-stream" \
      -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"save_note","arguments":{"content":"test"}}}'
    ```

    Expected: 200 envelope but the tool result indicates an
    `insufficient_scope: dev:write` failure (MCP wraps tool errors in the
    JSON-RPC payload, not in HTTP status).

13. **Revoked-token path.** Use the plaintext of a revoked token (revoke
    `playbook-test` first if you haven't):

    ```bash
    curl -s -i -X POST http://localhost:3001/mcp \
      -H "Authorization: Bearer <PLAINTEXT_RO>" \
      -H "Content-Type: application/json" \
      -H "Accept: application/json, text/event-stream" \
      -d '{"jsonrpc":"2.0","id":3,"method":"tools/list"}'
    ```

    Expected: HTTP 401 with body `{"error":"revoked_token"}`.

14. **Rack-attack throttle.** Fire 12 bad-token requests in rapid succession
    from the same IP:

    ```bash
    for i in $(seq 1 12); do
      curl -s -o /dev/null -w "%{http_code}\n" -X POST http://localhost:3001/mcp \
        -H "Authorization: Bearer junk-$i" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json, text/event-stream" \
        -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
    done
    ```

    Expected: the first ~10 return `401`. After the 10th the bucket is
    exhausted; subsequent requests return `429` (with body
    `{"error":"rate_limited","retry_after":300}`). A successful bearer request
    immediately after also returns `429` from the same IP until the 5-minute
    window rolls.

15. **CLI footage round-trip with the dev token.**
    ```bash
    export PITO_API_TOKEN=<DEV_PLAINTEXT>
    export PITO_HOST=http://localhost:3000
    cd extras/cli
    cargo run -- footage import --project <PROJECT_ID_FROM_SEED> --path /tmp/empty
    ```
    Expected: the importer exits cleanly (empty directory → 0 files diffed).
    Repeat with a real folder containing one MP4 to confirm the `Add` branch
    posts to `/api/projects/:id/footages.json` with a `Bearer` header and lands
    a row in the project's footage table. Then run with no `PITO_API_TOKEN`:
    `unset PITO_API_TOKEN && cargo run -- footage import --project <ID> --path /tmp/empty`.
    Expected: any update or delete branch fails with a clear "PITO_API_TOKEN env
    var not set" error message; the read branch (index/diff) still works because
    the token is added there but isn't strictly required by the cargo build's
    offline tests — the live server WILL reject it 401.

### Phase 5.5 — visual / pane / morph polish

These steps are visual; the User Validation section below is the pure-UI
walkthrough. The setup commands above are the only command-line work needed for
the rest.

## Cleanup

If you want a clean slate to retry from scratch:

```bash
# Drop, recreate, reseed.
bin/rails db:reset

# Restart the dev stack.
# Ctrl-C bin/dev and bin/mcp-web, then re-launch each.

# Roll back the working tree if you tried something destructive (DON'T run
# without confirming there are no other uncommitted changes you want to keep):
git status
git diff
# Only if you're sure:
# git restore .

# Clear the rack-attack throttle bucket between runs:
bin/rails runner 'Rack::Attack.cache.store.clear'
```

## User Validation

[ ] 1. **Settings tokens page renders.** Visit `/settings/tokens` → expect a
heading "tokens", an explanatory paragraph about plaintext and `revoked_at`, the
dev token row in the active block, no JS errors in the browser console.

[ ] 2. **New token form fields and scope grouping.** Click `[ new token ]` →
expect three sections: name (text input), scopes (checkbox tree grouped by
namespace `dev:`, `yt:`, `website:`, `project:`), expires (date input). The
`[create]` and `[ cancel ]` buttons sit on a single dot-list row.

[ ] 3. **Token create plaintext display.** Submit the form with name
`validation-1` and any single scope → expect the create page to render with the
warning banner "save this now — it cannot be shown again", a `pre` block showing
the plaintext (full string, monospace, selectable on click), and the metadata
table beside it. Click `[ I have saved it ]` → expect to land back on the index
with the new row.

[ ] 4. **Plaintext is never re-shown.** From the index, expect the
`validation-1` row to display only `...<last 4 chars>` in the preview column,
never the full plaintext, even on hover.

[ ] 5. **Revoke confirmation screen.** Click `[ revoke ]` on `validation-1` →
expect the action confirmation page (NOT a JS confirm dialog). Page shows the
token metadata + a red `[revoke]` submit button + `[ cancel ]` link. Click
`[ cancel ]` → returns to the index unchanged.

[ ] 6. **Revoke commits and renders revoked block.** Repeat the click and this
time submit `[revoke]` → flash reads "token revoked.", the row moves to the
revoked block at lower opacity, status column shows `revoked YYYY-MM-DD`.

[ ] 7. **Settings home 2-up panes at laptop width.** Resize browser to ~1024px
wide. Visit `/settings` → expect each section to render as a `.pane` (452px
each), two side-by-side per row, alternating backgrounds (zebra). On a wider
monitor, more columns appear. On narrow (<955px) viewports the panes wrap to
single column.

[ ] 8. **Horizontal scroll surface theming — Chromium.** In Chrome / any
Chromium browser, navigate to `/channels` (a workspace where `.pane-strip`
scrolls horizontally) → expect the horizontal scrollbar at the bottom to be 8px
tall, thumb in the muted/text palette, NOT the OS default chunky scrollbar.
Vertical scrollbars on the page remain the OS default.

[ ] 9. **Horizontal scroll surface theming — Firefox.** Same `/channels` page in
Firefox → expect a thin themed horizontal scrollbar (`scrollbar-width: thin` +
`scrollbar-color: muted bg`). Vertical scrollbars elsewhere on the page remain
Firefox-default.

[ ] 10. **Project show: footage pane table rendering.** Visit `/projects/:id`
for a project that has footage. Expect the footage pane to render the
import-snippet code block on top with a `[copy]` button, then below that a table
with columns
`filename | game | resolution | fps | bit | duration | size |         source`.
Filenames are middle-truncated (e.g. `OBS_recording_2…7c2a.mp4`); hover for the
full filename via `title=` attribute.

[ ] 11. **Footage table sort (filename).** Click the `filename` header → expect
URL to update to include `?sort=filename&dir=asc`, an arrow indicator on the
column, and the rows reorder alphabetically. Click again → toggles to
`dir=desc`. Other columns show a neutral `▲▼` indicator.

[ ] 12. **Footage table sort (every other column).** Click each of `game`,
`resolution`, `fps`, `bit`, `duration`, `size`, `source` in turn → expect each
to sort cleanly with no JS errors and the page only re-renders inside the
`<turbo-frame id="footage-table">` (the rest of the project show page does not
flash).

[ ] 13. **Footage row click escapes the frame.** Click any filename in the
footage pane → expect a full-page navigation to `/footages/:id/edit` (the page
chrome — header, breadcrumb — re-renders). It must NOT load the edit page inside
the `footage-table` turbo-frame.

[ ] 14. **`<colgroup>` widths hold.** Resize the project show window narrow →
expect the footage table to keep its column widths (180px filename, 100px game,
etc.) and overflow horizontally inside the pane rather than reflowing into
squashed columns. The themed horizontal scrollbar should appear inside the pane.

[ ] 15. **Charts page (videos index) — bracketed legend below canvas.** Visit
`/videos` (or another page with a Chartkick line chart) → expect each series's
legend to render as `[ label ]` text BELOW the canvas (the canvas height is
fixed; the legend grows below). Hover the legend label → cursor: pointer. Click
→ toggles series visibility (label fades to muted color).

[ ] 16. **Charts: no animation, no red, crosshair.** Hover the chart plot area →
expect a vertical dashed muted hairline at the cursor x-position, with colored
dots at each series intersection. No red anywhere on the chart (red is reserved
for destructive actions). Switching pages does not animate the chart in/out.

[ ] 17. **Turbo morph preserves scroll on navigation.** From `/projects`, scroll
halfway down the page, then click any project row → navigate to `/projects/:id`.
Click the breadcrumb `projects` link to return to `/projects` → expect the
scroll position to be preserved (not reset to top). The
`<meta name="turbo-refresh-method"         content="morph">` +
`turbo-refresh-scroll content="preserve">` tags in the head are doing this.

[ ] 18. **Browser tab title escaping.** Open a project whose name contains an
apostrophe (or HTML-entity-flavored character). Expect the tab title to read
"<name> ~ pito" with the apostrophe rendered correctly, not double-escaped (the
layout uses `safe_join` rather than string interpolation specifically to
preserve `SafeBuffer` semantics).

[ ] 19. **No JS confirm dialogs anywhere.** During the entire walkthrough,
confirm you never saw a browser-native `confirm()` modal — only the
action-confirmation full-page screens for destructive flows (revoke token,
delete footage, etc.).

[ ] 20. **Beforeunload guard still works.** Open a footage edit page
(`/footages/:id/edit`), change a field, then click the breadcrumb link → expect
the browser's native "Leave site?" dialog (NOT a JS confirm — the browser
renders this itself). Cancel → stay on the form. Reset (or save) and try again →
no dialog.
