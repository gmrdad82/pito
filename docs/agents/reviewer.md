# pito-reviewer — project-specific extensions

Project-scoped overrides for the reviewer agent in pito. Base template:
`~/Dev/claude-dotfiles/agents/reviewer.md`.

## Project conventions (review checklist)

Treat each rule as a checklist item. Failures route back through the architect
to the relevant impl agent in FIX MODE.

### A. Bracketed-link convention — `[label]` (no inner spaces)

Reject any new `[ label ]` (with inner padding) outside the `[ ]` / `[x]`
checkbox shape. Verify `BracketedLinkComponent` is used rather than hand-rolled
HTML. Verify redundant nouns dropped when the heading carries context (`[add]`
not `[add channel]` inside an "Add channel" page). Canonical: `docs/design.md` →
"Bracketed Links / Buttons".

### B. Lead-paragraph copy — one sentence per line

Lead paragraphs under each page H1 must split one sentence per line via `<br>`
inside a single `<p class="text-muted">`. Reject chunky multi- sentence body
text under the heading.

### C. Pane primitives

Verify three primitives, no `.framed-block`:

- `.pane` for fixed-width (`flex: 0 0 452px`) workspace columns inside
  `.pane-row`.
- `.pane.pane--standalone` for full-width single-column containers
  (oauth_applications, doorkeeper authorizations, settings/tokens,
  settings/sessions revoke, form pages).
- `.pane--wide` for the 904px double-column workspace variant.

`.framed-block` is orphaned; flag any new use as a regression.

### D. Spec pyramid

Every implementation pass covers model / service / job / component / helper /
validator / lib / MCP tool / request specs. System specs reserved for critical
user journeys only (login, OAuth pair, publish flow, MCP token re-pair). Routing
specs only when route logic is non-trivial. Reject PRs that ship code without
the corresponding tier of specs.

### E. Yes / no boundary

External booleans (URL params, JSON, MCP I/O, CLI args, Rust client wire format)
must be `"yes"` / `"no"` strings — never `true` / `false` / `0` / `1`. Internal
storage stays Boolean. Verify conversion at every boundary.

### F. Tenant-free single-install + multi-user

No `tenant_id` columns, no `BelongsToTenant` concern, no `Current.tenant` reads.
IDOR tests for tenant scoping are retired — flag any new attempt to add tenant
scoping. Canonical:
`docs/decisions/0003-drop-tenant-single-install-multi-user.md`.

## pito specifics

- Review pipeline: `bundle exec rubocop` (changed files), `bundle exec rspec`
  (relevant slice, read-only), `bundle exec brakeman -q`,
  `bundle exec bundler-audit`. For Rust changes (`extras/cli/`):
  `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`,
  `cargo test`.
- Manual test playbook output:
  `docs/orchestration/playbooks/<YYYY-MM-DD>-<slug>.md`.
- Playbook structure rule: numbered steps, each with a `[ ]` checkbox. User
  crosses off as they validate; final sign-off list at the end.
- Read-only on app code. Never edit `app/`, `extras/`, `lib/`, `db/`, `spec/`.
  Only writes the playbook markdown under `docs/orchestration/playbooks/`.
- Failures route back through the architect to the relevant impl agent in FIX
  MODE.

## Out of scope

- Committing or pushing.
- Editing source code.
