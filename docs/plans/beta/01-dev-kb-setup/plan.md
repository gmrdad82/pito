# Phase 1 — Dev KB Setup

> **Goal:** Establish the multi-repo workspace (`pito`, `pito-dev-kb`,
> `pito-website`, `pito-sh`), create the alpha record under
> `pito-dev-kb/plans/alpha/` so probe history is preserved, and add the `dev:*`
> MCP tool namespace so mobile-Claude can read and write planning documents from
> anywhere.
>
> **Note (2026-05-03):** Phase 1 originally provisioned a fifth sibling repo
> `pito-yt-kb`. That repo was retired on 2026-05-03; channel-level and
> video-level notes will reuse the project-notes pattern from Phase 4 — Project
> Workspace. The historical references below are preserved as written.

**Depends on:** None. This is the entry point of Beta.

**Unblocks:** Every subsequent phase. After Phase 1 the user can plan future
phases on mobile while away from the laptop, and the workspace structure is
correct from day one.

---

## Why Phase 1 is first

The user works across multiple devices and contexts. Without `dev:*` MCP tools,
mobile planning sessions cannot touch `plan.md` or append to `log.md` — every
working session at the laptop becomes a bottleneck for _thinking_ about the next
phase, not just _executing_ it.

Doing this first means:

- Every subsequent phase's plan and log live in the right place from the moment
  they're created
- Mobile-Claude can plan, reflect on, and adjust upcoming phases while the user
  is away from the laptop
- The four-repo structure is locked in before any code change wants to assume
  otherwise
- The pattern for sandboxed MCP namespaces (`dev:*`) is established once; Phase
  6 (`website:*`) and Phase 9 (`yt:*` markdown) follow the same shape

This is organizational infrastructure. It produces no user-visible product
feature. It enables every feature that follows.

---

## In scope

### Sibling repository creation

Create three new private repositories on GitHub: `pito-dev-kb`, `pito-website`,
`pito-sh`. Pito (`pito`) already exists from Alpha. Each new repository gets
identical scaffolding (`README.md`, `CLAUDE.md`, `LICENSE.md`) with content
distinct to its purpose. The license is the same private "not for sale, not for
redistribution" notice across all repos.

Clone all three to `~/Dev/`. They are independent repositories — no submodules,
no symlinks, no shared history. The user manages tabs in nvim with `:tcd` and
`:mksession!` to switch between them.

### Alpha record preservation

The Pito repo currently has `pito/docs/alpha/plan.md` and
`pito/docs/alpha/log.md` containing the Alpha probe history. Beta treats these
as preserved record, not active material. Move them:

- `pito/docs/alpha/plan.md` → `pito-dev-kb/plans/alpha/plan.md`
- `pito/docs/alpha/log.md` → `pito-dev-kb/plans/alpha/log.md`

Then delete `pito/docs/alpha/` from the application repo. Update
`pito/CLAUDE.md` to remove the "After each build step: update `docs/plan.md`"
instruction; replace it with a directive pointing at the active phase folder
under `~/Dev/pito-dev-kb/plans/beta/<NN>-<slug>/`.

The application repo's `docs/` directory continues to ship with Pito (it's the
product-facing documentation: `design.md`, `mcp.md`, `architecture.md`,
`setup.md`). Beta's planning churn lives in `pito-dev-kb/`, not in the product
repo.

If `architecture.md` or `setup.md` don't already exist in `pito/docs/`, create
them in this phase. Architecture covers the system as it stands at the start of
Beta (post-Alpha probe outcome). Setup covers a fresh local install on Linux
(Omarchy, Debian, Ubuntu).

### `dev:*` MCP tool namespace

Add a `dev:*` namespace to Pito's MCP server with these tools:

- `dev:list_files(subdir?)` — list `.md` files under `PITO_DEV_KB_PATH` or a
  subdirectory
- `dev:read_file(path)` — read a single `.md` file
- `dev:write_file(path, content, overwrite=false)` — create or overwrite
  (overwrite guard prevents accidental clobber)
- `dev:delete_file(path)` — delete a `.md` file
- `dev:search(query, regex=false, context_lines=2, max_results=50)` — full-text
  search via grep-style implementation; the dev KB is small enough that SQLite
  FTS5 or Meilisearch would be over-engineering

Path validation is encapsulated in a `Dev::Sandbox` module (or equivalent name).
It enforces:

- Realpath check against `realpath(PITO_DEV_KB_PATH)` — no escape via `..`,
  symlinks, or encoded traversal
- `.md` extension only
- Filename pattern `^[a-z0-9][a-z0-9-_./]*\.md$` (subdirs allowed; each segment
  must match the leading-segment pattern)
- File size cap of 1 MB
- For writes to new files: realpath the _parent directory_ (the file itself
  doesn't exist yet)
- For symlinks: follow and re-check the target — symlinks pointing outside the
  root are rejected

Token scopes: `dev:read` (covers list, read, search) and `dev:write` (covers
write and delete). These are the first two entries in Beta's scope catalog —
Phase 3 formally establishes the scope-token model and adds `yt:*`; Phase 6 adds
`website:*`.

Audit log at `log/mcp_dev_audit.log`. Every write and every delete records: ISO
timestamp, tool name, resolved path, content hash on writes, and the token name
(resolved from the bearer token's owning record). Reads are not audited
(volume).

### Environment configuration

New env var: `PITO_DEV_KB_PATH`. Default in `.env.example` is
`/home/<user>/Dev/pito-dev-kb`. Add to both `.env.example` and
`.env.development`. The MCP server reads this at boot; tool invocations resolve
paths relative to it.

### Documentation updates

- `pito/docs/mcp.md` — document the `dev:*` namespace, its scopes, and its env
  var
- `pito/docs/architecture.md` — establish the Beta architecture baseline (or
  update if the file exists from Alpha): web Puma + MCP Puma, the four-repo
  layout, the dev KB sandbox pattern as the reference for `website:*` and `yt:*`
  to follow
- `pito/docs/setup.md` — local install on Linux, including how to clone the four
  sibling repos and set the env vars
- `pito-dev-kb/README.md` — repository purpose, layout, cross-references to the
  other three sibling repos
- `pito-dev-kb/CLAUDE.md` — context for Claude Code working in this repo,
  including the per-phase folder convention and the `plan.md`/`log.md`
  discipline

### What this phase does _not_ touch

- Postgres migration (Phase 2)
- User/Tenant model and auth foundation (Phase 3) — but this phase introduces
  `dev:read`/`dev:write` scopes that Phase 3 will add to the formal scope
  catalog and ApiToken model
- `yt:*` namespace (Phase 9) and `website:*` namespace (Phase 6) — same sandbox
  pattern, different roots
- Auto-commit on file write — explicitly deferred. Mobile-Claude writes files;
  the user (or laptop-Claude in a later session) commits manually with a
  meaningful message. Auto-commit can be added later if the workflow demands it.

---

## Plan checklist

### Sibling repos

- [ ] Create GitHub repository `pito-dev-kb` (private)
- [ ] Create GitHub repository `pito-website` (private)
- [ ] Create GitHub repository `pito-sh` (private)
- [ ] Clone all three to `~/Dev/`
- [ ] Add `README.md`, `CLAUDE.md`, `LICENSE.md` to each new repo with
      purpose-specific content
- [ ] Initial commit + push for each new repo

### Alpha record migration

- [ ] Copy `pito/docs/alpha/plan.md` → `pito-dev-kb/plans/alpha/plan.md`
- [ ] Copy `pito/docs/alpha/log.md` → `pito-dev-kb/plans/alpha/log.md`
- [ ] Verify content is byte-identical after copy
- [ ] Delete `pito/docs/alpha/` from the application repo
- [ ] Update `pito/CLAUDE.md`: remove `docs/plan.md` references, add the
      cross-repo workflow note pointing at `pito-dev-kb/plans/beta/<NN>-<slug>/`
- [ ] Create `pito/docs/architecture.md` if it doesn't exist (system at the
      start of Beta — dual Puma, Postgres-pending, four sibling repos)
- [ ] Create `pito/docs/setup.md` if it doesn't exist (local Linux install)

### `dev:*` namespace

- [ ] Add `PITO_DEV_KB_PATH` to `.env.example` and `.env.development`
- [ ] Document the env var in `pito/docs/mcp.md`
- [ ] Implement `Dev::Sandbox` (path resolution, realpath check, extension
      whitelist, traversal rejection, filename pattern, size cap)
- [ ] Unit specs for `Dev::Sandbox` — at least 12 cases covering valid paths,
      all rejection conditions, edge cases (symlinks, null bytes, control chars,
      encoded traversal, oversized writes, non-`.md` extensions)
- [ ] Implement `Mcp::Tools::Dev::ListFiles`
- [ ] Implement `Mcp::Tools::Dev::ReadFile`
- [ ] Implement `Mcp::Tools::Dev::WriteFile` (overwrite guard, audit log entry)
- [ ] Implement `Mcp::Tools::Dev::DeleteFile` (audit log entry)
- [ ] Implement `Mcp::Tools::Dev::Search` (grep-style with snippet context)
- [ ] Wire all five tools into the MCP server registration
- [ ] Specs for each tool: happy path, sandbox rejection, scope rejection,
      oversized payload
- [ ] Audit log file `log/mcp_dev_audit.log` written for every write/delete;
      format documented

### Token scopes (groundwork for Phase 3)

- [ ] Add `dev:read` and `dev:write` to the application's scope catalog
- [ ] In whatever token mechanism currently exists (Alpha had something —
      replace, extend, or build from scratch on the merits): tools enforce scope
      at runtime; missing scope returns a structured error
- [ ] Specs: `dev:*` tools reject tokens without the right scope; accept with
      the right scope
- [ ] Surface the new scopes in the Settings UI (if Alpha had a token UI) or add
      a minimal placeholder UI for token generation. Phase 3 matures this into
      the formal `ApiToken` model with full scope picker.

### Documentation

- [ ] Update `pito/docs/mcp.md`: `dev:*` namespace, tool descriptions, scope
      requirements, env var, audit log location
- [ ] Add a "Cross-repo workflow" section to `pito-dev-kb/README.md` explaining
      how plans flow between mobile and laptop sessions
- [ ] Confirm Alpha records preserved unmodified in `pito-dev-kb/plans/alpha/`

### Validation

- [ ] Generate a token with `dev:read dev:write` scopes via whatever Settings UI
      exists
- [ ] From Claude mobile, connect to `mcp.pitomd.com` with the new token
- [ ] Call `dev:list_files` — returns the directory contents
- [ ] Call `dev:read_file('plans/beta/beta.md')` — returns the master plan
- [ ] Call
      `dev:write_file('plans/beta/01-dev-kb-setup/_mobile_test.md', 'hello')` —
      succeeds; verify file appears on disk on the laptop
- [ ] Call `dev:delete_file('plans/beta/01-dev-kb-setup/_mobile_test.md')` —
      succeeds; verify file is gone
- [ ] Generate a token without `dev:*` scopes; confirm `dev:*` calls are
      rejected with a scope error
- [ ] Run full RSpec suite — all existing specs still pass
- [ ] Run Brakeman — no new warnings (or document waivers in `security.md`)
- [ ] Run `bundler-audit` — clean
- [ ] Review Dependabot alerts — clean or documented
- [ ] `pito/docs/design.md` reviewed for any UI changes (likely none in this
      phase; the token scope picker may need a small note)

---

## Specs requirements

- `Dev::Sandbox` unit specs covering valid paths, traversal attempts (literal
  `..`, encoded `%2e%2e`, null bytes, control chars), symlink escape, oversized
  writes, non-`.md` extensions, malformed filenames.
- One spec file per `dev:*` tool: happy path, sandbox rejection, scope
  rejection, oversized payload, missing-scope rejection.
- Token scope spec: assert each `dev:*` tool checks the right scope and rejects
  tokens without it.
- All Alpha specs continue to pass without modification.

## Security requirements

- `dev:write_file` and `dev:delete_file` require `dev:write`. The other three
  (`dev:list_files`, `dev:read_file`, `dev:search`) require `dev:read`.
- All filesystem operations resolve the path with `Pathname#realpath` and
  confirm prefix match against `realpath(PITO_DEV_KB_PATH)`. Rejection is the
  default; success is the exception.
- Symlink targets are followed during realpath and re-checked. A symlink inside
  the KB pointing outside is rejected.
- Filename pattern `^[a-z0-9][a-z0-9-_./]*\.md$` enforced. The `/` is allowed
  for subdirectories, but each path segment must match the leading-segment
  pattern.
- Audit log at `log/mcp_dev_audit.log` for every write and delete. Format: ISO
  8601 timestamp, tool name, resolved path, content hash for writes, token name.
  Read operations are not audited.
- Brakeman: no new warnings.
- bundler-audit: clean.
- Dependabot: review and resolve any new alerts.
- `pito/docs/design.md`: small update only if a token-scope picker UI is added
  or visibly modified.

---

## Manual testing checklist

The user runs through this before commit:

1. Start Pito locally (`bin/dev`). Both Puma processes (web + MCP) and Sidekiq
   come up cleanly.
2. Open Settings → tokens (whatever the current path is). Generate a token named
   `mobile-dev` with scopes `dev:read`, `dev:write`. Copy the plaintext token
   (it shows once).
3. On Claude mobile, configure a custom MCP connector pointed at
   `mcp.pitomd.com` with the new bearer token.
4. From Claude mobile, prompt: "list dev kb files in plans/beta/" — expect to
   see the 16 phase folders.
5. Prompt: "read plans/beta/beta.md" — expect to receive the master plan
   content.
6. Prompt: "write a test note at plans/beta/01-dev-kb-setup/\_test.md with body
   'hello from mobile'" — expect success.
7. On the laptop, `cat ~/Dev/pito-dev-kb/plans/beta/01-dev-kb-setup/_test.md` —
   confirm the content is there.
8. From Claude mobile, prompt: "delete plans/beta/01-dev-kb-setup/\_test.md" —
   expect success.
9. On the laptop, confirm the file is gone.
10. Generate a second token with only `yt:read` (placeholder for now; Phase 3
    makes this real). Try a `dev:*` call — expect a scope rejection error.
11. `bundle exec rspec` — green.

---

## Challenges to anticipate

- **MCP gem scope enforcement.** The current `mcp` gem version may not have
  first-class scope enforcement built in. If so, this phase introduces a thin
  wrapper around tool dispatch that all three namespaces (`dev`, `yt`,
  `website`) will follow. Document the wrapper pattern in `challenges.md` so
  Phase 6 and Phase 9 inherit it cleanly.
- **`Pathname#realpath` on non-existent files.** `realpath` raises if the file
  doesn't exist. Writes to new files must validate the _parent directory_'s
  realpath. Document this for `Yt::Sandbox` and `Website::Sandbox` to mirror.
- **Cross-repo Git history for the alpha move.** History doesn't transfer
  cleanly between repos without `git filter-repo` or similar. Don't try. Just
  copy + commit; the alpha records are preserved as a snapshot in
  `pito-dev-kb/plans/alpha/`, with the original Pito repo's Git history
  retaining the historical commits for anyone who really wants to dig.
- **Both Puma processes need the env var.** `PITO_DEV_KB_PATH` must be exported
  in the environment that starts _both_ Web Puma and MCP Puma. The `Procfile`
  and `.env*` files must propagate it.

---

## Confirmation gates for Claude Code

Before executing, confirm with the user:

1. The four new repos can be created on GitHub (Claude Code can do this via
   `gh repo create` if authorized; otherwise the user creates them manually and
   Claude Code clones).
2. The user's `~/Dev/` path is correct. If on a different OS or path layout, the
   env var defaults need adjusting.
3. The user is OK with `dev:write` scope behavior — i.e., understands that
   mobile sessions can now modify planning docs without local review. (This is
   the intended workflow, but worth surfacing once.)
4. The current MCP gem version supports adding new tool namespaces without a
   major refactor. If not, that becomes a sub-task of this phase.
5. Whatever token mechanism Alpha left behind is acceptable to extend with
   `dev:read`/`dev:write` scopes here, with the formal `ApiToken` model coming
   in Phase 3. (Alternative: skip token enforcement in Phase 1 and rely entirely
   on Phase 3's model. Less safe; not recommended.)

If any answer is unclear, raise in plan mode before starting.
