# Pito Beta — Master Plan

> Read this document **first** before executing any Beta phase. It establishes
> context, ground rules, the full phase ordering, dependencies, and the
> philosophy each phase shares.

---

## The arc: Alpha → Beta → Theta

**Alpha was a probe.** A multi-front exploration: Rails 8.x and a newer Ruby;
Turbo/Hotwire/Stimulus; MCP as a concept worth understanding; minimal Tailwind
in a 2000s-era aesthetic; charts outside React (Chartkick); modern Sidekiq;
Meilisearch as an Elasticsearch alternative; Claude Code on the 90€ plan; plan
mode with parallel sub-agents; and — most importantly — finding something
genuinely useful for the engineer-and-YouTube-hobbyist hybrid the user happens
to be. Every axis came back positive. Alpha concluded successfully.

**Beta is the real product becoming.** No ceiling. Pito stops being a probe and
starts being a tool the user actually depends on. Some sub-bets get dropped fast
on contact with reality (the Slack probe is structured to accept "no" cleanly).
Others receive heavy investment. By the end of Beta, Pito runs in
production-grade infrastructure on Hetzner, with real YouTube data, real
embeddings, real backups, and real auth.

**Theta is conditional and forward-looking.** _If_ Beta delivers something worth
showing, Theta is where Pito gets shown — marketing, YouTube videos, seeing if
anyone bites. Theta is also where multi-tenancy, billing, and distribution
("Pito Once" or similar) would be tackled. Theta does not influence Beta scope;
Beta builds for the user only, with multi-tenant primitives in the schema so
Theta isn't a rewrite.

The only Alpha artifact carried forward unconditionally is the domain
`pitomd.com` (purchased, non-refundable). Everything else — code, schemas, tool
names, architectural choices — is decided on the merits inside Beta, not
preserved out of inertia.

---

## Who Pito serves through Beta

- **One user** (the developer / sole user)
- **One tenant** (the user's own organization)
- **Multiple channels** owned by the user
- **Multiple external channels** tracked for competitive / reference purposes

Multi-tenancy is a Theta concern. Beta builds the **schema and primitives** for
multi-tenancy (User and Tenant models, scoped tokens, tenant-scoped queries) but
does **not** ship multi-tenant UI, signups, billing, or admin tooling. By Beta's
end, Pito is a single-tenant tool with a multi-tenant-ready foundation.

---

## Architecture at the end of Beta

```
┌──────────────────────────────────────────────────────────────────────┐
│                           Clients                                    │
├──────────────────────────────────────────────────────────────────────┤
│  Web (Rails ERB + Hotwire)    Claude (mobile + desktop, via MCP)     │
│  pito-sh (Rust + Ratatui)     Slack (probe — may be dropped)         │
└──────────────────────────────────────────────────────────────────────┘
                          │                          │
                          ▼                          ▼
              ┌───────────────────────┐   ┌───────────────────────┐
              │  app.pitomd.com       │   │  mcp.pitomd.com       │
              │  (HTTPS, Web Puma)    │   │  (HTTPS, MCP Puma)    │
              └───────────────────────┘   └───────────────────────┘
                          │                          │
                          └──────────┬───────────────┘
                                     ▼
                ┌────────────────────────────────────────┐
                │   Pito codebase (Rails 8)              │
                │   - Web controllers / views (ERB)      │
                │   - JSON API (header bearer auth)      │
                │   - MCP HTTP transport                 │
                │   - OAuth server (for clients)         │
                │   - Sidekiq jobs                       │
                └────────────────────────────────────────┘
                     │       │         │        │
            ┌────────┴──┐ ┌──┴────┐ ┌──┴───┐ ┌──┴─────────┐
            │ Postgres  │ │ Meili │ │Redis │ │ Filesystem │
            │ +pgvector │ │ search│ │      │ │ (KB roots) │
            └───────────┘ └───────┘ └──────┘ └────────────┘

External services: YouTube Data API v3, YouTube Analytics API,
Voyage AI, Google OAuth 2.0, Slack API (if probe survives)

Landing page: pitomd.com → Cloudflare Pages → pito-website repo
```

### Dual Puma processes

Pito runs **two independent Puma processes** declared in the `Procfile` (and
`Procfile.dev` for development):

- **Web Puma** serves `app.pitomd.com` — Rails web stack, ERB views, Hotwire,
  Stimulus, controllers, JSON API endpoints. Tuned for human request patterns
  (bursty, mixed read/write, HTML-heavy).
- **MCP Puma** serves `mcp.pitomd.com` — MCP HTTP transport only. No HTML
  rendering. Tuned for AI-client request patterns (smaller payloads, JSON-only,
  possibly different concurrency profile).

Both Pumas load the same Rails codebase, talk to the same Postgres / Redis /
Meilisearch / KB filesystem, and share the same auth model. They scale and get
configured independently — different worker/thread counts, different memory
ceilings, different rate-limit profiles, possibly different deploy timing in
production.

This dual-Puma reality has implications throughout Beta. It is called out
explicitly at the Auth Foundation phase (auth applies to both), the App Stats /
Observability phase (observability tracks both separately), the Security
Hardening Pass (rate limiting and CSP differ between them), and the Hetzner
Deployment phase (Kamal config declares both as services). See the phase index
above for current numbering and the corresponding on-disk folders.

### Other key architectural facts

- **Postgres replaces MySQL** in the Postgres Migration phase. The `pgvector`
  extension is installed at migration time but unused until the Voyage
  Embeddings + Hybrid Search phase.
- **Meilisearch** stays for keyword search and gains hybrid (keyword + vector)
  capability in the Voyage Embeddings + Hybrid Search phase.
- **Voyage AI** is the embedding provider. Embeddings are computed once per
  content change and **dual-written** to both Postgres pgvector columns (for
  SQL-native related-content joins) and Meilisearch (for the hybrid search bar).
  One Voyage call per content change; two stores; cheapest possible.
- **Markdown files on disk** are the storage medium for project notes, knowledge
  base, and landing-page content. Files live in dedicated repositories
  (`pito-dev-kb`, `pito-website`) and inside project-notes roots introduced by
  Phase 4 — Project Workspace; Pito reads/writes them via env-var-configured KB
  roots. Each MCP namespace has a sandboxed path validator. (The original Beta
  plan included a separate `pito-yt-kb` repo for YouTube channel/video notes;
  that repo was dropped on 2026-05-03 and those notes will reuse the Phase 4
  project-notes pattern.)
- **Token-based auth with scopes** for all programmatic clients. Scopes are
  namespaced — see below.

---

## MCP tool namespaces

Beta establishes three MCP tool namespaces. The split is **intent**, not file
location:

- **`dev:*`** — Building Pito. Reads/writes plans, logs, specs, security notes,
  architecture docs, anything in `pito-dev-kb/`. The tools Claude Code (or
  mobile-Claude planning a phase) calls to _develop_ Pito.
- **`yt:*`** — Operating the user's YouTube presence. Reads/writes channels,
  videos, stats, dashboards, playlists, production notes, channel context
  markdown. Spans relational data in Postgres **and** content markdown stored
  under the project-notes roots introduced in Phase 4 — Project Workspace
  (originally a dedicated `pito-yt-kb/` repo, dropped 2026-05-03). The tools the
  user (or Claude on the user's behalf) calls to _use_ Pito.
- **`website:*`** — Editing the landing page. Reads/writes files in
  `pito-website/`. Triggers commits and Cloudflare Pages deploys.

The boundary is clean: `dev:*` is build-time, `yt:*` is runtime YouTube content,
`website:*` is the marketing surface. Production notes about a channel live
under `yt:*` (they're the user's content). Plans for building Pito's notes
feature live under `dev:*` (they're about constructing the product).

### Scope catalog

| Scope            | Phase introduced | Permits                                                     |
| ---------------- | ---------------- | ----------------------------------------------------------- |
| `dev:read`       | 1                | List, read, search files under `PITO_DEV_KB_PATH`           |
| `dev:write`      | 1                | Write, delete files under `PITO_DEV_KB_PATH`                |
| `yt:read`        | 3                | List/read channels, videos, stats, dashboards, KB markdown  |
| `yt:write`       | 3                | Create/update channels, videos, settings, KB markdown       |
| `yt:destructive` | 3                | Delete channels/videos/saved views, bulk-delete, purge data |
| `website:read`   | 6                | List, read files under `PITO_WEBSITE_PATH`                  |
| `website:write`  | 6                | Write, commit, push, create PR branches                     |

A token can hold any combination. Sensible defaults exist (e.g., the in-app
generated token for Claude mobile defaults to `yt:read yt:write` and the user
opts into `yt:destructive` only when needed). Tokens are minted per-purpose: a
`dev:*`-only token for mobile planning, a `yt:*`-only token for content
automation, a `website:write` token for the in-app landing-page editor.

---

## The Beta phases

Phases run sequentially by default but **independent workstreams within a phase
may be parallelized** by spawning sub-agents. Some phases have intentional
ordering because later phases need earlier outputs (e.g., the embeddings phase
needs the project-notes / KB structure to exist).

The phase index was refactored on 2026-05-03 (see "Phase index history" below).
The numbering used in this table is the **current narrative ordering**; on-disk
phase folders under `pito-dev-kb/plans/beta/<NN>-<slug>/` retain their
**original** numeric prefixes from the pre-refactor plan (so e.g. the "Auth
Foundation" phase below maps to the existing folder `03-auth-foundation/`).
Folders are not renumbered.

| #   | Phase                                 | Adds capability                                                                                                                       | Status / Depends on                                               |
| --- | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| 1   | Dev KB Setup                          | Sibling repos exist; `dev:*` MCP tools online; mobile planning works                                                                  | done                                                              |
| 2   | Postgres Migration                    | MySQL → Postgres 17 + pgvector extension installed                                                                                    | done                                                              |
| 3   | Channel Revamp                        | Channel model rebuild; web + MCP + terminal parity; deletion/sync framework                                                           | done (was "Auth Foundation"; auth foundation deferred to phase 5) |
| 4   | **Project Workspace**                 | Project, Game, Collection, Footage, Notes, Timeline; assets volume; footage importer (Rust binary); three-pane layout; design refresh | next active phase; depends on 3                                   |
| 5   | Auth Foundation                       | User, Tenant, scoped tokens; header-based JSON auth on both Pumas; no UI                                                              | depends on 4 (was original phase 3)                               |
| 6   | Auth UI + Multi-User Readiness        | Login UI, sessions, OAuth server (Doorkeeper), tenant-leak audit                                                                      | depends on 5 (was original phase 12)                              |
| 7   | Google OAuth + YouTube API Foundation | Google sign-in; YouTube tokens; rate-limit-aware API client                                                                           | depends on 5 (was original phase 7)                               |
| 8   | YouTube Data Sync                     | Auto-sync owned channels; on-demand external sync; quota tracking                                                                     | depends on 7 (was original phase 8)                               |
| 9   | Voyage Embeddings + Hybrid Search     | Vectors in Postgres + Meilisearch; hybrid queries; related content                                                                    | depends on 8 (was original phase 10)                              |
| 10  | Video Workflow Features               | Calendar, upload, metadata, scheduling, thumbnails, playlists                                                                         | depends on 8, 9 (was original phase 11)                           |
| 11  | App Stats / Observability             | Stack health, both Pumas, DB, Voyage, YouTube quota, Sidekiq, audit logs                                                              | depends on 10 (was original phase 13)                             |
| 12  | Backup / Restore Tooling              | Postgres dump, Meili snapshot, pgvector data, KB state, restore drill                                                                 | depends on 9 (was original phase 14)                              |
| 13  | Slack Probe                           | Validate Slack as a fourth client — or drop                                                                                           | depends on 5 (was original phase 5)                               |
| 14  | Landing Page Tooling                  | `pito-website` + Cloudflare Pages; `website:*` MCP tools                                                                              | depends on 1, 5 (was original phase 6)                            |
| 15  | Security Hardening Pass               | Comprehensive Brakeman + bundler-audit + headers + rate limit on both Pumas                                                           | all prior (was original phase 15)                                 |
| 16  | Hetzner Deployment                    | Production cutover; Kamal with two web roles + Sidekiq; backups; rollback                                                             | depends on 12, 15 (was original phase 16)                         |

### Paused / dropped phases

- **Original Phase 4 — Terminal App `pito-sh`** — **PARTIAL / paused.**
  Scaffolded with Channel Revamp; paused. Will return to dictate the keyboard
  shortcut schema in a later phase. Folder
  `pito-dev-kb/plans/beta/04-terminal-app/` stays in place as the historical
  spec. Cross-cutting terminal-app work since Channel Revamp lives under the
  active phase folders that touched it.
- **Original Phase 9 — YouTube KB + Production Notes** — **DROPPED 2026-05-03**
  when the `pito-yt-kb` repo was retired. Channel-level and video-level notes
  reuse the Phase 4 — Project Workspace project-notes pattern when their
  respective downstream phases revisit them. Folder
  `pito-dev-kb/plans/beta/09-youtube-kb-production-notes/` is preserved as the
  historical record (its first paragraph carries a "DROPPED" addendum).

### Follow-ups queued after Phase 4

The following items live in `pito-dev-kb/orchestration/follow-ups.md`. They are
**cleanups, not phases** — interleaved into the work after Phase 4 — Project
Workspace completes:

- Channel Revamp post-commit cleanup (orphaned confirm-dialog primitives)
- Rails-app keyboard shortcuts (mirror pito-sh schema)
- Terminal app screen layout parity with the Rails app
- pito-sh Dependabot alert (low-severity)

### Phase index history

The original Beta plan had 16 phases. The 2026-05-03 refactor:

- Promoted "Project Workspace" to Phase 4 as the next active phase.
- Marked the original Phase 4 (Terminal App `pito-sh`) as paused/partial.
- Dropped the original Phase 9 (YouTube KB + Production Notes) with the
  retirement of the `pito-yt-kb` repo. Channel/video notes reuse the Phase 4
  project-notes pattern.
- Renumbered the remaining phases to fill the gap.

The on-disk phase folders under `pito-dev-kb/plans/beta/<NN>-<slug>/` keep their
**pre-refactor** numeric prefixes. The mapping from current narrative number to
existing folder is given inline in the table above.

---

## Per-phase quality gates

Every phase, no exceptions, must satisfy these before being marked complete:

1. **`plan.md` checkboxes all ticked** (or remaining items moved to `dropped.md`
   with rationale).
2. **`log.md` has a final session entry** summarizing the completed phase.
3. **RSpec coverage for new code.** All existing specs still pass.
4. **Brakeman scan clean** — exceptions documented in `security.md`.
5. **bundler-audit clean** — exceptions documented.
6. **Dependabot alerts reviewed** — new vulnerabilities triaged in
   `security.md`.
7. **Design alignment** — if UI/UX touched, `pito/docs/design.md` is updated to
   reflect changes.
8. **Manual test instructions** provided in the session log so the user can
   validate before committing.
9. **User has manually validated** before commit. Always.

The user does not commit on Claude Code's behalf. Claude Code does not commit
until the user validates.

---

## Working principles

**Plan mode is mandatory.** Before executing any phase, read its `plan.md` and
this document, present an execution plan, ask for confirmation. Never assume.

**Parallel sub-agents when phases allow.** Independent workstreams (e.g.,
model + UI + specs in the same phase) should run concurrently. Identify them in
plan mode and spawn appropriately.

**Challenge the user.** If a phase plan instruction conflicts with prior
decisions, recent codebase state, or industry best practice — stop, raise it,
propose alternatives. Do not silently rewrite the plan.

**Track drift honestly.** Plan changes mid-phase go to `additions.md` (new) or
`dropped.md` (removed) with rationale. `plan.md` is then updated to match. No
silent edits.

**Real API calls only on explicit user action.** Until the Google OAuth +
YouTube API Foundation and YouTube Data Sync phases land, all work uses expanded
seed data. Once real APIs are wired (YouTube, Voyage), tests use VCR/WebMock
fixtures; jobs only fire against live APIs when the user triggers them or
schedules them.

**Local first, Hetzner last.** The user's laptop is treated as the production
stand-in. Every architectural choice must be **portable** — env-var-driven
paths, Docker Compose for services, secrets via Rails credentials, no
laptop-specific assumptions. The Hetzner Deployment phase cuts over to Hetzner;
everything before assumes it works on a local machine.

**Backups are not optional.** The Backup / Restore Tooling phase ships scripts
for full data backup including Meilisearch indices and pgvector data. The user
does not pay for re-embedding or re-indexing because data was lost. Backup
tooling is built once, tested locally, and ports to Hetzner unchanged.

**Single branch on dev-kb / website / project-notes repos.** No feature
branching for documents or static content. Plan/log/note edits are committed to
`main` directly with meaningful messages. Application repo (`pito`) and terminal
app repo (`pito-sh`) follow the existing `step-NN` branch + PR pattern.

**Single user, but multi-tenant ready.** Every model that holds user data has
`user_id` and `tenant_id` from the Auth Foundation phase onward. UI may not
surface either yet, but the schema is correct from the start.

**No commit messages mention AI authorship.** One-line meaningful commits. No
"Co-Authored-By," no Claude attribution. Manual commit cadence — commit when
meaningful work is done, not on every file write.

---

## What's _not_ in Beta

These are explicitly Theta or later concerns:

- Public signup / billing / Stripe / payment processing
- Multi-tenant admin tooling
- Distributable installer / "Pito Once" packaging
- Marketing site beyond the basic landing page
- Public API for third-party developers
- Mobile native apps (iOS / Android)
- Browser extensions
- Microsoft Teams integration — deferred indefinitely
- Federated / multi-instance peering

If the user proposes one of these mid-Beta, raise it as a Theta-or-later item
and capture in `additions.md` of the active phase for traceability.

---

## File and folder layout reference

```
~/Dev/
├── pito/                            ← Rails app + MCP server (existing)
│   ├── app/
│   ├── config/
│   │   └── (Procfile + Procfile.dev declare web Puma + mcp Puma + sidekiq)
│   ├── docs/                        ← ships with the product
│   │   ├── design.md               (authoritative design system)
│   │   ├── mcp.md                  (MCP namespaces + scope reference)
│   │   ├── architecture.md         (Dev KB Setup deliverable)
│   │   └── setup.md                (Dev KB Setup deliverable)
│   └── ...
│
├── pito-dev-kb/                     ← THIS REPO
│   ├── README.md
│   ├── CLAUDE.md
│   ├── LICENSE.md
│   └── plans/
│       ├── alpha/                   ← probe records, preserved
│       └── beta/
│           ├── beta.md             (this file)
│           ├── 01-dev-kb-setup/
│           ├── 02-postgres-migration/
│           └── ... (phase folders; numbering preserved from pre-2026-05-03)
│
├── pito-website/                    ← Landing page
└── pito-sh/                         ← Terminal client
```

The sibling repos have identical scaffolding (README + CLAUDE + LICENSE) but
distinct purposes. They are independent Git repositories — no submodules, no
symlinks. Each is cloned and pushed independently. The original Beta plan also
included a `pito-yt-kb/` repo (YouTube knowledge base); that repo was dropped on
2026-05-03 — channel/video notes will reuse the project-notes pattern from Phase
4 — Project Workspace.

---

## Environment variables introduced during Beta

The "Phase" column refers to the phase that introduces each variable, by name
(numbering changed in the 2026-05-03 refactor — see "Phase index history").

| Variable                      | Phase                                 | Purpose                                  | Local default                   |
| ----------------------------- | ------------------------------------- | ---------------------------------------- | ------------------------------- |
| `PITO_DEV_KB_PATH`            | Dev KB Setup                          | Root of dev knowledge base               | `/home/<user>/Dev/pito-dev-kb`  |
| `PITO_WEBSITE_PATH`           | Landing Page Tooling                  | Root of landing page repo                | `/home/<user>/Dev/pito-website` |
| `DATABASE_URL`                | Postgres Migration                    | Postgres connection (replaces MySQL)     | `postgres://localhost/pito_dev` |
| `YOUTUBE_OAUTH_CLIENT_ID`     | Google OAuth + YouTube API Foundation | Google OAuth client ID for YouTube       | (in Rails credentials)          |
| `YOUTUBE_OAUTH_CLIENT_SECRET` | Google OAuth + YouTube API Foundation | Google OAuth client secret               | (in Rails credentials)          |
| `YOUTUBE_PUBLIC_API_KEY`      | YouTube Data Sync                     | Public-data API key (external channels)  | (in Rails credentials)          |
| `VOYAGE_API_KEY`              | Voyage Embeddings + Hybrid Search     | Voyage AI embedding API key              | (in Rails credentials)          |
| `SLACK_BOT_TOKEN`             | Slack Probe                           | Slack bot user token (if probe survives) | (in Rails credentials)          |
| `SLACK_SIGNING_SECRET`        | Slack Probe                           | Slack request verification               | (in Rails credentials)          |
| `BACKUP_REMOTE_*`             | Backup / Restore Tooling              | Off-site backup destination (optional)   | (in Rails credentials)          |

`.env.example` is updated in each phase that introduces variables. Real secrets
always go in Rails credentials, never in `.env`.

The original env-var list also included `PITO_YT_KB_PATH` (root of the YouTube
knowledge base, introduced in the original Phase 9). That repo was dropped on
2026-05-03; the variable has been retired. Channel/video notes paths come from
Phase 4 — Project Workspace's project-notes configuration.

---

## How to start a phase

1. **Read this file** (`beta.md`) front to back.
2. **Read the phase folder's `plan.md`** front to back.
3. **Read prior phase logs** if the current phase depends on them.
4. **Enter plan mode.** Present an execution plan, identify parallelizable work,
   identify risks. Ask user for confirmation.
5. **Spawn sub-agents** for parallelizable workstreams.
6. **Execute, ticking checkboxes in `plan.md` as work completes.**
7. **Append to `log.md` after every working session** — what was done, what was
   decided, what's next.
8. **Run quality gates** (RSpec, Brakeman, bundler-audit, design alignment).
9. **Provide manual test instructions** in the session log.
10. **Wait for user validation.** Do not commit until validated.
11. **Commit and push** with a 1-line meaningful message.

---

## Phase index — quick links

The narrative number on the left is the **current** ordering (post-2026-05-03
refactor). The folder path on the right is the **original** on-disk location;
folders were not renumbered. Phase 4 — Project Workspace's folder
(`04-project-workspace/`) is created by the architect-spec agent when that phase
opens.

- 1. Dev KB Setup — `01-dev-kb-setup/plan.md`
- 2. Postgres Migration — `02-postgres-migration/plan.md`
- 3. Channel Revamp — `03-channel-revamp/specs/channel-revamp.md` (folder
     replaces the original Auth Foundation slot for this number)
- 4. **Project Workspace** — `04-project-workspace/` (to be created)
- 5. Auth Foundation — `03-auth-foundation/plan.md`
- 6. Auth UI + Multi-User Readiness —
     `12-auth-ui-multi-user-readiness/plan.md`
- 7. Google OAuth + YouTube API Foundation —
     `07-google-oauth-youtube-foundation/plan.md`
- 8. YouTube Data Sync — `08-youtube-data-sync/plan.md`
- 9. Voyage Embeddings + Hybrid Search —
     `10-voyage-embeddings-hybrid-search/plan.md`
- 10. Video Workflow Features — `11-video-workflow-features/plan.md`
- 11. App Stats / Observability — `13-app-stats-observability/plan.md`
- 12. Backup / Restore Tooling — `14-backup-restore-tooling/plan.md`
- 13. Slack Probe — `05-slack-probe/plan.md`
- 14. Landing Page Tooling — `06-landing-page/plan.md`
- 15. Security Hardening Pass — `15-security-hardening-pass/plan.md`
- 16. Hetzner Deployment — `16-hetzner-deployment/plan.md`

Paused / dropped (not active phases):

- Original Phase 4 — Terminal App `pito-sh` — `04-terminal-app/plan.md`
  (PAUSED; will return to dictate the keyboard shortcut schema in a later phase)
- Original Phase 9 — YouTube KB + Production Notes —
  `09-youtube-kb-production-notes/plan.md` (DROPPED 2026-05-03; channel/
  video notes reuse the Phase 4 — Project Workspace project-notes pattern)

---

## Glossary

- **Pito** — the application.
- **Alpha** — the multi-front probe. Concluded successfully. Codebase is prior
  art, not a previous product version.
- **Beta** — the current phase. Real product becoming. Open ceiling.
- **Theta** — conditional future. Distribution, marketing, multi-tenancy.
- **Tenant** — an isolated unit of data ownership. Currently 1.
- **MCP** — Model Context Protocol.
- **Web Puma** — the Rails Puma process serving `app.pitomd.com`.
- **MCP Puma** — the separate Rails Puma process serving `mcp.pitomd.com` for
  MCP HTTP transport.
- **Voyage** — Voyage AI. Anthropic-recommended embedding provider.
- **pgvector** — Postgres extension for vector storage.
- **Meilisearch** — keyword + hybrid search engine.
- **`pito-sh`** — terminal client, Rust + Ratatui.
- **`pito-website`** — landing page on Cloudflare Pages.
- **`pito-dev-kb`** — this repo. Plans and logs.
