# Phase 6 — Landing Page Tooling

> **Goal:** Ship a static landing page at `pitomd.com` (Cloudflare Pages,
> single-branch deploy with PR previews on feature branches), and implement the
> `website:*` MCP tool namespace declared in Phase 3 so the user can edit copy
> and trigger deploys from inside Pito without leaving the app.

**Repo:** `~/Dev/pito-website` (created in Phase 1).

**Depends on:** Phase 1 (sibling repos exist), Phase 3 (`ApiToken` +
`website:read`/`website:write` scopes already declared in the catalog).

**Unblocks:** Theta's marketing surface (the conditional showcase phase).
Establishes the third sandbox pattern (`Website::Sandbox`) so Phase 9's `yt:*`
markdown tools have two reference implementations to follow.

---

## Why Phase 6 is now

The landing page is content-light infrastructure that:

1. **Anchors the product visually.** `pitomd.com` should look unmistakably like
   Pito — same monospace, bracketed-link aesthetic, same color tokens — so the
   design language locked in Phase 4 extends to the public-facing surface. Doing
   this here, before Phase 11's many new screens, keeps the design discipline
   consistent.
2. **Sets up the deploy pipeline.** Cloudflare Pages with PR previews is a
   generic pattern that future static surfaces (potential docs site, status
   page, blog if Theta happens) can reuse. The pattern gets validated once.
3. **Demonstrates the `website:*` namespace pattern.** With `dev:*` from Phase 1
   and the scope catalog formalized in Phase 3, this phase implements the second
   namespace under the same sandbox shape. By the time `yt:*` markdown tools
   land in Phase 9, the pattern is well-tested with two reference
   implementations.
4. **In-app editor is genuinely useful.** The user can tweak landing-page copy
   from inside Pito's Settings without context-switching to a terminal.
   Mobile-Claude can also edit landing copy (with appropriate scope), useful for
   catching typos on the go.

---

## In scope

### `pito-website` static site

- Single page (`index.html`) — hero, what Pito is, screenshots, contact /
  signup-waitlist (mailto for now)
- Visual style identical to Pito web app: monospace, `[bracketed]` links,
  light/dark theme via `prefers-color-scheme`, same color tokens as
  `pito/docs/design.md`
- **No build step.** Pure HTML/CSS, no JS framework. CSS hand-written using the
  same custom properties as `design.md` documents. Document the choice; build
  steps can come later if needed.
- Optional: a small JS file for prefers-color-scheme override toggle (if the
  user wants a manual dark/light switch on the landing page)
- Static assets in the same repo: `style.css`, `favicon.ico`, `robots.txt`,
  `sitemap.xml`, screenshot images (`.webp` preferred for size)

### Cloudflare Pages config

- Connect `pito-website` repo
- Production branch: `main`
- Preview branches: any non-main branch gets an automatic preview URL
  (`<branch-slug>.pito-website.pages.dev` or similar)
- No custom build command (no build step) — Cloudflare serves `index.html`
  directly from the repo root
- Custom domain: `pitomd.com` apex
- DNS: Cloudflare DNS already manages `pitomd.com`; the apex switches from "no
  record / parked" to Cloudflare Pages
- TLS: Cloudflare's edge cert handles `pitomd.com` automatically (no origin cert
  needed for Pages)

### `website:*` MCP tool namespace

Implemented in Pito, exposed via MCP Puma. Required scopes from the Phase 3
catalog:

- `website:list_pages` — list editable files (HTML, CSS, JS, MD, TXT, common
  image formats)
- `website:read_page(path)` — read content
- `website:write_page(path, content, overwrite=false)` — write to disk (no
  commit)
- `website:preview_url()` — return current production URL and last preview URL
  deterministically (no Cloudflare API call)
- `website:commit_and_push(message, branch="main")` — runs
  `git add -A && git commit -m <msg> && git push` from the website repo
- `website:create_pr_branch(branch, message)` — creates a feature branch,
  commits changes there, pushes; returns the branch name and the deterministic
  Cloudflare preview URL pattern

### Sandbox

`Website::Sandbox` follows the same shape as `Dev::Sandbox` from Phase 1:

- Realpath check against `realpath(PITO_WEBSITE_PATH)` — no escape via `..`,
  symlinks, or encoded traversal
- Extension whitelist: `.html`, `.css`, `.js`, `.md`, `.txt`, `.svg`, `.png`,
  `.jpg`, `.jpeg`, `.webp`, `.ico`
- Filename pattern:
  `^[a-z0-9][a-z0-9-_./]*\.(html|css|js|md|txt|svg|png|jpg|jpeg|webp|ico)$`
- Size cap: 5 MB (larger than dev KB's 1 MB cap because images are in scope)
- Audit log at `log/mcp_website_audit.log` for writes, deletes, commits, and
  branch creations

### Token scope mapping

- `website:list_pages`, `website:read_page`, `website:preview_url` → require
  `website:read`
- `website:write_page`, `website:commit_and_push`, `website:create_pr_branch` →
  require `website:write`

### Environment

- New env var: `PITO_WEBSITE_PATH`. Default in `.env.example` is
  `/home/<user>/Dev/pito-website`. Add to both `.env.example` and
  `.env.development`.
- Both Puma processes need this exported (web Puma for the in-app editor's UI,
  MCP Puma for tool calls). The `Procfile` and `.env*` files propagate it.
- Git author identity for commits: `pito.bot@<user-domain>` or whatever the user
  prefers, configured in Rails credentials. Never read from request input.

### In-app Settings UI

A new Settings sub-page: "Landing Page" (bracketed link from main Settings). The
UI wraps `website:*` tools so the same code path is exercised whether the user
uses MCP or the web UI:

- **File list** (calls `website:list_pages`) — table of editable files with
  sizes and last-modified timestamps
- **Editor** — click a file → textarea editor (same FormField pattern as Phase
  3's token UI). Save button calls `website:write_page` via internal API route.
- **Commit & deploy to production** button — calls `website:commit_and_push`
  with a default message + user-editable message field
- **Create preview branch** button — calls `website:create_pr_branch`, displays
  the preview URL
- **Status section** — last commit time, last commit message, link to GitHub
  commits page, link to Cloudflare deploys page (manual link; Cloudflare API
  integration is out of scope for Beta)

### Out of scope

- Documentation site (Theta or post-Beta)
- Blog / changelog (Theta — part of the conditional showcase)
- A/B testing or analytics — out of scope for a single-tenant tool's landing
  page
- Multi-page site — single page is sufficient for Beta
- Form submissions / signup processing — `mailto` link is fine for the
  probe-style waitlist
- Cloudflare API integration (deploy status, log streaming) — possible Phase 13
  enhancement if there's value
- Markdown preview / syntax highlighting in the in-app editor — textarea is v1;
  richer editor is a Phase 12+ enhancement if needed

---

## Plan checklist

### `pito-website` site

- [ ] Confirm `pito-website` scaffolding from Phase 1 (README, CLAUDE, LICENSE)
- [ ] Create `index.html` with semantic markup
- [ ] Create `style.css` with custom properties matching `pito/docs/design.md`
      color tokens
- [ ] Add `favicon.ico`, `robots.txt`, `sitemap.xml`
- [ ] Add 2-4 screenshots of the Pito app (web UI, terminal app, dashboard) as
      `.webp`
- [ ] Test locally: `cd ~/Dev/pito-website && python3 -m http.server` — page
      renders, dark mode follows system preference
- [ ] First commit: stub site that renders correctly

### Cloudflare Pages

- [ ] Create Cloudflare Pages project pointed at `pito-website` repo
- [ ] Production branch: `main`
- [ ] Preview branches: enabled for any non-main branch
- [ ] Set custom domain `pitomd.com`
- [ ] Verify DNS — `pitomd.com` apex points at Cloudflare Pages;
      `app.pitomd.com` and `mcp.pitomd.com` continue pointing at the laptop
      tunnel (or Hetzner once Phase 16 is done)
- [ ] Test push: small change to a feature branch, push, observe preview URL;
      merge to main, observe production update at `pitomd.com`

### `website:*` MCP tools

- [ ] Add `PITO_WEBSITE_PATH` to `.env.example` and `.env.development`
- [ ] Implement `Website::Sandbox` (realpath check, extension whitelist,
      traversal rejection, filename pattern, size cap)
- [ ] Unit specs for `Website::Sandbox` — same coverage shape as `Dev::Sandbox`
      from Phase 1
- [ ] Implement `Mcp::Tools::Website::ListPages`
- [ ] Implement `Mcp::Tools::Website::ReadPage`
- [ ] Implement `Mcp::Tools::Website::WritePage` (overwrite guard, audit log)
- [ ] Implement `Mcp::Tools::Website::PreviewUrl` (deterministic; no Cloudflare
      API call)
- [ ] Implement `Mcp::Tools::Website::CommitAndPush` (shell-out to `git`, safe
      argument array, validated message and branch name)
- [ ] Implement `Mcp::Tools::Website::CreatePrBranch` (shell-out to
      `git checkout -b`, commit, push)
- [ ] Wire all six tools into the MCP server registration
- [ ] Audit log file `log/mcp_website_audit.log` written for every write,
      delete, commit, and branch creation
- [ ] Specs for each tool: happy path, sandbox rejection, scope rejection,
      oversized payload, malformed branch name, malformed commit message

### In-app Settings UI

- [ ] New Settings sub-page route and view: "Landing Page"
- [ ] File list view (calls `website:list_pages`) with size and last-modified
      columns
- [ ] Editor view: textarea with current content, Save button calls
      `website:write_page` via internal API
- [ ] Commit & deploy form: editable message field, default message template,
      button calls `website:commit_and_push`
- [ ] Create preview branch form: branch name input, message input, button calls
      `website:create_pr_branch`, displays preview URL
- [ ] Status section: last commit info, links to GitHub and Cloudflare
      dashboards
- [ ] Apply existing Pito design tokens (bracketed buttons, monospace,
      dark/light theme)
- [ ] Specs for the Settings UI controllers

### Documentation

- [ ] Update `pito/docs/architecture.md`: landing page client added to diagram,
      Cloudflare Pages topology documented, `website:*` namespace added to MCP
      section
- [ ] Update `pito/docs/mcp.md`: `website:*` namespace, tools, scope
      requirements, env var, audit log location
- [ ] Update `pito/docs/design.md`: landing page is part of the design system,
      color tokens shared, screenshots reference the same component patterns
- [ ] `pito-website/README.md`: how to develop locally (no build step), how
      Cloudflare deploy works, how to use the in-app editor

### Validation

- [ ] Visit `pitomd.com` over HTTPS — page loads, design matches Pito web app,
      dark mode follows system preference
- [ ] In-app: edit `index.html` → Save → Commit & Deploy → confirm production
      updates within 1-2 minutes
- [ ] In-app: create preview branch named `try-new-cta`, edit, push — confirm
      Cloudflare preview URL works
- [ ] From Claude mobile (with `website:read website:write` token), call
      `website:list_pages` and `website:read_page('index.html')` — succeeds
- [ ] From Claude mobile, call `website:write_page` to make a small change, then
      `website:commit_and_push` — confirm production updates
- [ ] Token without `website:*` scopes: all `website:*` calls return scope error
- [ ] Token with only `website:read`: read tools succeed; write/commit tools
      rejected
- [ ] Path escape attempt: `website:write_page('../../etc/passwd', ...)` —
      rejected
- [ ] All RSpec specs pass
- [ ] Brakeman, bundler-audit, Dependabot — clean
- [ ] `pito/docs/design.md` reviewed for any UI changes

---

## Specs requirements

- `Website::Sandbox` unit specs — coverage parallel to `Dev::Sandbox` from Phase
  1, plus extension whitelist edge cases (binary files, malformed extensions,
  mixed case).
- One spec file per `website:*` tool: happy path, sandbox rejection, scope
  rejection, oversized payload.
- `website:commit_and_push` spec — mocks `git` shell-out, asserts safe argument
  array (no string interpolation, no shell metacharacters), audit log entry
  written. Plus an integration test that runs against a real local repo to
  verify behavior.
- `website:create_pr_branch` spec — same shape as commit_and_push; includes
  branch name validation.
- Settings UI request specs — file list, edit, save, deploy.

## Security requirements

- `website:write_page`, `website:commit_and_push`, `website:create_pr_branch`
  require `website:write` scope.
- `website:list_pages`, `website:read_page`, `website:preview_url` require
  `website:read` scope.
- Path validation enforces files stay within `realpath(PITO_WEBSITE_PATH)`.
- `git` shell-out uses safe argument arrays
  (`Open3.capture3('git', 'add', '-A', chdir: PITO_WEBSITE_PATH)`), never string
  interpolation.
- Commit messages validated: no shell metacharacters, max length 200 characters,
  no leading dashes.
- Branch names match `^[a-z0-9][a-z0-9-_/]*$`, max length 80 characters.
- Git author identity comes from Rails credentials (`git_author_name`,
  `git_author_email`), never from request input. Each commit explicitly sets
  `--author` to override any local Git config inconsistency.
- Audit log records every commit, push, and branch creation with timestamp, tool
  name, resolved path, message, branch, and resulting Git SHA.
- Brakeman: review shell-out patterns; expect zero warnings (safe-array
  invocation should not trigger).
- bundler-audit: clean.
- Dependabot: review.
- `pito/docs/design.md`: landing page palette must match Pito web app palette.

## Manual testing checklist

The user runs through this before commit:

1. `cd ~/Dev/pito-website && python3 -m http.server 8000` — landing renders
   locally with correct design
2. Push `main` (after the initial Cloudflare Pages connection) — Cloudflare
   Pages deploys to `pitomd.com` within ~1 minute
3. Visit `pitomd.com` over HTTPS in incognito — page loads, follows OS dark mode
   preference
4. In Pito web Settings → Landing Page → see file list (`index.html`,
   `style.css`, etc.)
5. Click `index.html` → editor opens with current content; modify the hero
   headline
6. Save → verify file on disk via `cat ~/Dev/pito-website/index.html`
7. Commit & Deploy with message "tweak hero" → confirm Git log on disk → wait
   1-2 min → verify `pitomd.com` shows new headline
8. Create preview branch `try-cta`, edit, push — Cloudflare provides preview URL
   like `try-cta.pito-website.pages.dev`; verify it shows the change without
   affecting production
9. From Claude mobile (token: `dev:read dev:write website:read website:write`),
   prompt: "what files are in the landing page repo?" — calls
   `website:list_pages`, returns the list
10. Mobile prompt: "fix the typo on line 24 of index.html" — calls
    `website:read_page`, then `website:write_page`, then
    `website:commit_and_push` — production updates
11. Test scope rejection: token with only `dev:*` cannot call any `website:*`
    tool
12. Path escape attempt: tool rejects `../../etc/passwd`
13. `bundle exec rspec` — green

---

## Challenges to anticipate

- **Cloudflare Pages account and DNS state.** The user has a Cloudflare account
  already (DNS for `pitomd.com` subdomains is managed there). Pages just needs
  to be enabled for the project. The apex `pitomd.com` may currently be
  unallocated (parked) or pointing somewhere — verify before pointing at Pages
  to avoid clobbering anything. The free tier covers this use case fully.
- **Git from controller vs Sidekiq.** Running `git` synchronously in a
  controller is fine for single-user with small commits (Pito's landing page is
  one HTML file plus a CSS file plus a few images — commits complete in
  milliseconds). If commits ever feel slow, move to a Sidekiq job. Document the
  threshold: commit + push completing >2s in development is the trigger to
  refactor.
- **Branch name collisions.** If the user creates the same-named branch twice,
  the second `git checkout -b` fails. The tool should detect this clearly and
  return a structured error: "Branch already exists; choose a different name or
  pull/delete the existing one."
- **Cloudflare preview URL pattern is deterministic but not API-verified.** The
  tool returns a constructed URL that _should_ work; if Cloudflare hasn't
  deployed the branch yet (typically takes 30-60s), the URL returns a
  placeholder. Document this; future enhancement could poll Cloudflare API for
  confirmation.
- **In-app editor is a textarea.** No syntax highlighting, no live preview. If
  the user really wants either, capture in `additions.md` for follow-up — out of
  Phase 6 scope.
- **Both Pumas need the env var.** `PITO_WEBSITE_PATH` must reach both Web Puma
  (for the Settings UI) and MCP Puma (for the tools). Same propagation
  discipline as `PITO_DEV_KB_PATH` from Phase 1.

---

## Confirmation gates for Claude Code

Before executing, confirm with the user:

1. The user has a Cloudflare account with Pages access (free tier is fine).
2. DNS for `pitomd.com` apex is currently parked or repointable to Cloudflare
   Pages without conflict.
3. The user is OK with direct-to-`main` commits via the `website:write` scope.
   (A token leak means production landing page can be modified — but content can
   be reverted via Git, so blast radius is small. Acceptable for Beta
   single-user; Theta would tighten this.)
4. The user is OK with the in-app editor being a textarea (no syntax
   highlighting / live preview in this phase).
5. The Git author identity for automated commits is set correctly in Rails
   credentials.
