# Phase 3 — Step C — Settings UI for Tokens and Documentation

> The visible part. Adds a Settings UI for token CRUD, seeds a default dev
> token, writes `docs/auth.md`, and updates `docs/architecture.md` and
> `docs/mcp.md` to reflect the auth model finalized by Steps A and B.
> Date: 2026-05-05. Locked decisions are pinned exactly — do not reinvent.

---

## 1. Goal

Make the auth model usable end-to-end without dropping to a rake console.
The user can mint tokens, pick scopes via checkboxes, see plaintext exactly
once, and revoke tokens — all from the existing Settings page chrome. A
dev token is minted at seed time and printed to STDOUT during `bin/setup`,
so the first `curl` against `mcp.pitomd.com` works after a fresh install.

Documentation is the second deliverable. `docs/auth.md` is new — it's the
single source of truth for the auth model. `docs/architecture.md` and
`docs/mcp.md` get updates so they stop telling the old (pre-Step-A,
pre-Step-B) story. The `:tokens.pepper` credential ceremony documented
here is the practical bootstrap path the user follows on first install.

## 2. Depends on

- Step A — `Tenant`, `User`, `BelongsToTenant`, the multi-tenant schema.
- Step B — `ApiToken` model, `Scopes` catalog, `Api::AuthConcern`,
  `:tokens.pepper` credential block, audit log, throttling.

## 3. Unblocks

- Phase 4 closeout — the dev token printed at `bin/setup` lets the
  `pito footage` CLI authenticate against the local Web Puma without
  manual rake gymnastics.
- Phase 6 onward — `docs/auth.md` is the reference every later phase
  links to when wiring scopes into new tools.

## 4. Why now

Step B leaves the auth machinery functional but headless: tokens exist,
scopes are enforced, but the only way to mint or revoke is via rake.
Step C closes the loop. It also locks the bootstrap ceremony — generate
the pepper, mint the dev token, capture plaintext — into a documented
flow so future fresh installs (or the eventual production cutover) are
reproducible.

The doc updates are equally non-deferrable: leaving `docs/architecture.md`
saying "no auth in this phase" while Step B has wired bearer enforcement
across both Pumas would be a dishonesty trap for the next session.

---

## 5. Locked decisions

- **UI location.** Settings is currently a multi-pane page (5 panes from
  recent work). Tokens go in their own dedicated page —
  `/settings/tokens` — linked from a sixth "Tokens" entry in the
  Settings nav. Reasoning: token CRUD has its own list / new / show flow;
  cramming it into a 6th pane on the same page strains the layout. The
  nav link uses bracketed-link styling (`[ tokens ]`).
- **Plaintext display ceremony.** After `create`, the success page shows
  the plaintext exactly once in a monospace block, framed by a clear
  notice: "Save this now — it cannot be shown again." A `[ I have
  saved it ]` bracketed link returns to the token list. No copy-button
  Stimulus magic in this phase; the user selects + copies (keeps the
  surface tight, matches CLI-vibe defaults).
- **Revoke, do not delete.** The `destroy` action sets `revoked_at =
  Time.current`. The row stays in the database forever for audit trail.
  The list page shows revoked tokens grayed out, sorted to the bottom.
  Confirmation goes through the existing `shared/_action_screen.html.erb`
  framework — no JS confirm.
- **Default dev token at seed.** Seed mints a token named `"dev"` with
  scopes `[Scopes::DEV_READ, Scopes::DEV_WRITE, Scopes::YT_READ,
  Scopes::YT_WRITE, Scopes::PROJECT_READ, Scopes::PROJECT_WRITE]`. No
  `yt:destructive` by default; user opts in. Plaintext printed to
  STDOUT during `bin/setup` so the install ceremony captures it once.
  `db:seed` re-running with the dev token already present is a no-op
  (idempotent).
- **Pepper bootstrap.** `bin/setup` script gains a check: if
  `Rails.application.credentials.dig(:tokens, :pepper)` is missing, it
  prints a `bin/rails credentials:edit` walkthrough and exits 1. The
  user sets the pepper to `SecureRandom.hex(32)`, re-runs `bin/setup`.
  Documented in `docs/setup.md`.

---

## 6. In scope

### 6.1 `Settings::TokensController`

New controller at `app/controllers/settings/tokens_controller.rb`.
Inherits from whatever the existing settings controllers inherit from
(presumably `ApplicationController` with a `Settings::Base` parent).

Actions:

- `index` — lists tokens for `Current.tenant` (scope already applied via
  `BelongsToTenant`). Columns: name, scopes (comma-joined), created_at,
  last_used_at, expires_at, revoked_at, `last_token_preview` (the
  stored last-4 chars). Active tokens listed first; revoked grayed and
  sorted last. Links: `[ new token ]` to `new`, `[ revoke ]` per row
  to the action confirmation page.
- `new` — form. Fields: `name` (text), scope checkboxes grouped by
  namespace (`dev:`, `yt:`, `website:`, `project:`), optional
  `expires_at` (date input, blank = never).
- `create` — validates, calls `ApiToken.generate!(...)`. Renders
  `create.html.erb` (the success page) with `@plaintext` and
  `@token`. The plaintext is held in a flash-like ivar — never
  persisted, never re-displayed.
- `destroy` — confirmation flow via `Confirmable` concern. On confirm,
  sets `revoked_at = Time.current` (does NOT call `destroy!`). Redirects
  back to `index` with a flash.

Routes:

```ruby
namespace :settings do
  resources :tokens, only: %i[index new create destroy]
end
```

Confirmation pattern: matches the rest of the app — the destroy form
goes through the action screen framework (`shared/_action_screen.html.erb`
+ `Confirmable` concern), no `data-turbo-confirm`, no JS `confirm`.

### 6.2 Views

- `app/views/settings/tokens/index.html.erb` — list. Bracketed-link
  styling per `docs/design.md`. Active tokens first, revoked grayed. No
  red except on the `[ revoke ]` link (destructive action — red is
  permitted there). Each row links to a per-token detail (or just
  inline expand — implementer's call; spec accepts either as long as the
  visible info matches §6.1's column list).
- `app/views/settings/tokens/new.html.erb` — form. Scope checkboxes
  rendered via a partial that iterates `Scopes::DESCRIPTIONS`, grouping
  by the namespace prefix. Each checkbox label shows the scope name
  in monospace plus the description in muted text.
- `app/views/settings/tokens/create.html.erb` — the
  show-plaintext-once page. Big monospace block. Clear notice. `[ I
  have saved it ]` bracketed link to `index`.
- `app/views/settings/tokens/_form.html.erb` — partial used by `new`.
- `app/views/shared/_action_screen.html.erb` — already exists; reused
  for the revoke confirmation.

### 6.3 Settings nav update

The Settings page currently has its own nav / chrome. Add a `[ tokens ]`
entry pointing at `/settings/tokens`. Position: after the existing
panes' nav entries, before any "danger zone" entries (if such a section
exists).

### 6.4 Seeds — default dev token

Update `db/seeds.rb`:

```ruby
unless ApiToken.unscoped.exists?(name: "dev")
  Current.tenant = Tenant.first
  Current.user   = User.first
  token, plaintext = ApiToken.generate!(
    tenant: Tenant.first,
    user:   User.first,
    name:   "dev",
    scopes: [
      Scopes::DEV_READ, Scopes::DEV_WRITE,
      Scopes::YT_READ, Scopes::YT_WRITE,
      Scopes::PROJECT_READ, Scopes::PROJECT_WRITE
    ]
  )
  puts ""
  puts "=" * 64
  puts "Dev token minted (save this now — cannot be shown again):"
  puts plaintext
  puts "=" * 64
  puts ""
end
```

Idempotent: re-running `db:seed` after the token exists is a no-op.
Plaintext only prints on the run that actually mints.

### 6.5 `bin/setup` extension

Add a pre-flight check near the top of `bin/setup`:

```bash
# Pseudocode — exact shape is implementer's call
if ! bin/rails runner 'exit Rails.application.credentials.dig(:tokens, :pepper).present? ? 0 : 1'; then
  echo "Missing :tokens.pepper credential."
  echo "Run: bin/rails credentials:edit"
  echo "Add: tokens:\n  pepper: $(openssl rand -hex 32)"
  echo "Then re-run bin/setup."
  exit 1
fi
```

Order: after `bundle install`, before `db:setup`. Without the pepper, the
seed step in §6.4 would mint a token whose digest is computed against
`nil`, breaking auth on first request.

### 6.6 `docs/auth.md` — new

New file. Sections:

1. **Model overview** — `Tenant`, `User`, `ApiToken`, `Current`. Diagram
   in ASCII or simple table form: token → user → tenant.
2. **Scope catalog** — full table, copied from `Scopes::DESCRIPTIONS`
   with the namespace grouping. Marked authoritative; `app/lib/scopes.rb`
   is the source.
3. **Tool/endpoint scope map** — every MCP tool and JSON endpoint
   listed with its required scope. Kept in sync with `docs/mcp.md`'s
   tool table (which links here).
4. **Request flow** — bearer header → `Api::TokenAuthenticator` →
   digest lookup → `Current` populated → `require_scope!` runs → action
   runs → `Current.reset` on response. Both Pumas. ASCII flowchart.
5. **`belongs_to_tenant` enforcement** — the default scope, the
   fail-loud raise on missing `Current.tenant`, the `unscoped` escape
   for tests.
6. **Token lifecycle** — generate (Settings UI or rake) → use
   (`last_used_at` updates) → revoke (`revoked_at` set; row preserved).
   No automatic expiry sweep.
7. **Bootstrap ceremony** — pepper credential, dev token mint,
   plaintext capture. Step-by-step.
8. **Audit log** — file path, JSON line shape, event types, log
   rotation note.
9. **Throttling** — `rack-attack` rule, 10 failed lookups per 5 min
   per IP, 429 response shape.
10. **Departures from the original Phase 3 plan** — list (global
    uniqueness on `users.email`/`username`, dropped `users.role` and
    `users.name`, `tenants.slug` added late, table renamed from
    `mcp_access_tokens` to `api_tokens` rather than dropped). One
    paragraph each, with rationale.
11. **Future phases hooks** — Phase 6 plugs `website:*`; Phase 7 ties
    Google OAuth tokens to users; Phase 12 adds login UI + Doorkeeper
    on top of this foundation; Phase 15 hardens rate limits.

### 6.7 `docs/architecture.md` updates

- The auth section is rewritten to match Step A + Step B reality.
- The "no auth in this phase" / "Auth Foundation deferred" sentences
  are removed.
- New paragraphs on:
  - `belongs_to_tenant` default scoping pattern (one paragraph plus
    code snippet, linking to `docs/auth.md` for the full story).
  - `Current.token` flow.
  - The schema departures from the Phase 3 plan are summarized; full
    rationale lives in `docs/auth.md`.
- The `before_action :set_current_tenant_and_user` claim is verified
  true (post-Step-A) and the doc reflects that.

### 6.8 `docs/mcp.md` updates

- Add a "Scope-per-tool" table. Columns: tool name, scope required,
  one-line description. Every tool currently registered gets a row.
- Add a callout that auth is now enforced at the rack-app layer (was
  "open" in Step B's predecessor).
- Reference `docs/auth.md` for the request flow.
- Fix any stale Channel-shape references flagged in the Phase 3 plan
  (the plan called this out as a follow-up; this is a good moment).

### 6.9 `docs/setup.md` updates

- Pepper credential ceremony added to the first-run section.
- Dev token capture added to the first-run section: "After
  `bin/setup`, copy the dev token printed to STDOUT — you cannot
  retrieve it later."
- Reference to `docs/auth.md` for the full auth model.

### 6.10 Specs

- `spec/requests/settings/tokens_spec.rb` — index, new, create
  (asserts plaintext rendered exactly once and not in subsequent
  requests), destroy via the action confirmation flow.
- `spec/system/settings/tokens_spec.rb` — feature spec covering the
  full Settings → Tokens → mint → save → revoke flow with Capybara,
  matching the manual playbook's web-side steps.
- `spec/seeds_spec.rb` (or extend existing) — assert the dev token is
  minted on a fresh seed and not re-minted on a second seed run.
- No new model or concern specs — those are owned by Steps A and B.

---

## 7. Out of scope

- Doorkeeper / OAuth client flows — Phase 12.
- Login form, signup form, session UI — Phase 12.
- Token expiry automation (background job to sweep expired tokens) —
  Phase 12 / 15.
- Pepper rotation — future phase.
- Per-token audit detail page (showing last-N requests) — future
  enhancement.
- Editing existing tokens (changing scopes, renaming) — out of scope
  intentionally; revoke + mint a new token is the workflow.
- CLI / MCP UX changes — `pito` CLI bearer-header support already
  exists from Phase 4; this step does not change CLI surfaces.

---

## 8. Acceptance criteria

- [ ] `/settings/tokens` lists tokens for `Current.tenant`.
- [ ] `/settings/tokens/new` renders a form with one checkbox per
      `Scopes::DESCRIPTIONS` entry, grouped by namespace.
- [ ] `POST /settings/tokens` creates the token, renders plaintext
      exactly once on the success page, with a clear "save now"
      notice.
- [ ] `DELETE /settings/tokens/:id` goes through the action
      confirmation framework (no JS confirm) and sets `revoked_at`
      (does not delete the row).
- [ ] Revoked tokens appear grayed out at the bottom of the list.
- [ ] Settings nav has a `[ tokens ]` entry linking to the new page.
- [ ] `db/seeds.rb` mints a `name: "dev"` token (idempotent) and
      prints plaintext to STDOUT exactly once.
- [ ] `bin/setup` exits 1 with a clear walkthrough if
      `:tokens.pepper` is missing; succeeds on the second run after
      the user sets it.
- [ ] `docs/auth.md` exists, covers all eleven sections in §6.6.
- [ ] `docs/architecture.md` no longer claims auth is deferred;
      describes `belongs_to_tenant` and `Current.token`.
- [ ] `docs/mcp.md` has the scope-per-tool table; references
      `docs/auth.md`.
- [ ] `docs/setup.md` covers the pepper ceremony and dev-token
      capture.
- [ ] Bracketed-link styling, monospace, no red except on the
      `[ revoke ]` link, no JS `confirm` — all per `docs/design.md`.
- [ ] All previously-green specs remain green; new request and
      system specs cover the UI flow.
- [ ] Brakeman, bundler-audit, Dependabot — clean.

---

## 9. Manual playbook

The 12-step ceremony the user runs end-to-end before commit:

1. `bin/rails credentials:edit` — confirm `tokens.pepper` is set
   (or set it now to `openssl rand -hex 32`'s output).
2. `bin/rails db:reset` — fresh DB. The seed run prints the dev
   token plaintext to STDOUT. Copy it; save it in your password
   manager labeled `pito-dev`.
3. `bin/dev` — start the app.
4. Open `/settings` in the browser. Find the `[ tokens ]` entry.
   Click it.
5. `/settings/tokens` lists exactly one token: `dev`, with the six
   default scopes, no `last_used_at` yet, no `expires_at`.
6. Click `[ new token ]`. Form loads. Name it `read-only`. Check
   only `yt:read`. Submit.
7. The success page shows the plaintext token in a monospace block
   with the "save now" notice. Copy the plaintext. Click `[ I have
   saved it ]`. Land back on the list — the new token is there with
   `last_token_preview` showing only the last 4 chars.
8. Open a terminal:
   `curl -H "Authorization: Bearer <plaintext>" https://app.pitomd.com/api/footages` →
   200. Verify `last_used_at` updates on the token row.
9. `curl -X POST -H "Authorization: Bearer <plaintext>" https://app.pitomd.com/api/footages -d '...'` →
   403 with `{"error":"insufficient_scope","required":"project:write"}`.
10. Mint a token via the UI with `project:read project:write
    yt:read yt:write`. Repeat the POST → 200 (or whatever the
    expected success status is for that endpoint).
11. From `/settings/tokens`, click `[ revoke ]` on the
    `read-only` token. The action confirmation page loads. Confirm.
    Land back on the list — the token is grayed at the bottom with a
    `revoked_at` timestamp.
12. Re-run step 8 with the revoked token's plaintext → 401 with
    `{"error":"revoked_token"}`. `tail log/auth_audit.log` — the
    revoke event and the rejected request both appear as JSON lines.

---

## 10. File-scope inventory

Implementer (Lane 1 rails-impl + a parallel Lane docs-keeper) touches:

Rails-impl files:

- `app/controllers/settings/tokens_controller.rb` — new.
- `app/views/settings/tokens/index.html.erb` — new.
- `app/views/settings/tokens/new.html.erb` — new.
- `app/views/settings/tokens/create.html.erb` — new.
- `app/views/settings/tokens/_form.html.erb` — new.
- `app/views/settings/_nav.html.erb` (or wherever Settings nav lives)
  — add `[ tokens ]` entry.
- `config/routes.rb` — `namespace :settings { resources :tokens,
  only: %i[index new create destroy] }`.
- `db/seeds.rb` — dev-token mint (idempotent).
- `bin/setup` — pepper pre-flight check.
- `spec/requests/settings/tokens_spec.rb` — new.
- `spec/system/settings/tokens_spec.rb` — new.
- `spec/seeds_spec.rb` — extend (or new).

Docs-keeper files:

- `docs/auth.md` — new.
- `docs/architecture.md` — auth section rewrite.
- `docs/mcp.md` — scope-per-tool table, auth reference.
- `docs/setup.md` — pepper ceremony, dev-token capture.

Out of bounds for this step:

- Anything under `app/models/` — Steps A and B own model surfaces.
- Anything under `app/mcp/` — Step B owns MCP wiring.
- `extras/cli/`, `extras/website/` — CLI / website are downstream.
- `app/lib/scopes.rb` — Step B owns it; Step C just references it.
- `Gemfile` — no new gems in this step (rack-attack lands in Step B).

## 11. Open questions

- Settings nav location: confirm whether the existing settings page
  has a single nav (top-of-page) or one nav per pane. The spec
  assumes a single nav row that gains a `[ tokens ]` link. If the
  layout is per-pane, the implementer adds the link to whichever
  pane currently hosts global settings entries (e.g., the AppSetting
  pane).
- The success page (`create.html.erb`) flash semantics: the spec
  forbids re-display, so the plaintext lives in an instance variable,
  not the flash hash. Confirm this matches existing patterns in the
  codebase (no other "show secret once" surface exists yet).
- `bin/setup` is currently shell — a Ruby check via `bin/rails
  runner` adds a Rails boot step to setup. If that's already the
  case (because `db:setup` runs anyway), no change. If `bin/setup` is
  meant to be Rails-free pre-DB, the pepper check moves to a
  post-`db:setup` step instead. Implementer's call at execution
  time.
