# Phase 9 — YouTube KB + Production Notes

> **DROPPED 2026-05-03.** This phase has been retired alongside the `pito-yt-kb`
> repo. Channel-level and video-level notes will reuse the project-notes pattern
> introduced in Phase 4 — Project Workspace, when the relevant downstream phases
> revisit them. The original phase content below is preserved as historical
> reference.

> **Goal:** Establish a markdown-on-disk knowledge base for YouTube content.
> Per-channel context (voice, audience, skills, strategy, progress), per-video
> production notes (plan, notes, retro), and external research files. Extend the
> `yt:*` MCP namespace from Phase 3 with markdown-file tools so Claude can read
> and write KB content. The KB is what makes Pito "Claude-aware" of the user's
> channels — relational data describes _what_ exists, the KB describes _how_ the
> user thinks about it.

**Repo:** `~/Dev/pito-yt-kb` (created in Phase 1).

**Depends on:** Phase 1 (sibling repo and the sandbox pattern reference), Phase
3 (`yt:read` / `yt:write` scopes already declared and applied to relational
tools), Phase 8 (real channel and video records to attach notes to).

**Unblocks:** Phase 10 (KB content is what gets embedded), Phase 11 (workflow
features can reference notes during production planning).

---

## Why Phase 9 is now

By Phase 9, real YouTube data is in Postgres. The next leap is making Claude
useful **about** that content — not just metadata, but the human context: how a
channel sounds, who its audience is, what the user is trying to accomplish, what
worked and didn't, what's planned next. That context is what makes Claude
actually helpful when reasoning about the user's content, drafting metadata, or
suggesting directions.

**Markdown on disk** (versus DB rows) is the right call because:

1. The user can edit notes from anywhere with a text editor (or `yt:*` tools
   from Claude mobile)
2. Files are diffable, searchable with grep, easy to back up via git push
3. They survive Pito disasters — the data lives outside the database in a
   separate git repo
4. They're excellent input for embeddings (Phase 10)
5. The pattern is already proven by `dev:*` (Phase 1) and `website:*` (Phase 6)
   — third sandbox following the same shape

**The `yt:*` namespace expands here, not appears.** Phase 3 already established
`yt:read` / `yt:write` / `yt:destructive` for the relational tools (channels,
videos, stats, dashboards). Phase 9 adds markdown-file tools to the same
namespace. From the user's perspective, "anything YouTube-related" is one set of
permissions — both relational data and content notes — which is exactly what
`beta.md` describes (`yt:*` is "operating the user's YouTube presence," spanning
relational data **and** content markdown).

---

## In scope

### Repo structure for `pito-yt-kb`

```
pito-yt-kb/
├── README.md
├── CLAUDE.md
├── LICENSE.md
├── channels/
│   └── <channel-slug>/
│       ├── voice.md          (how this channel sounds, tone, vocabulary)
│       ├── audience.md       (who watches, demographics, expectations)
│       ├── skills.md         (what topics fit, what doesn't)
│       ├── strategy.md       (current direction, growth plan)
│       └── progress.md       (recent results, what worked, what didn't)
├── videos/
│   └── <channel-slug>/
│       └── <video-id>/
│           ├── plan.md       (pre-production: outline, hook, structure)
│           ├── notes.md      (production notes, what went well, edits)
│           └── retro.md      (post-publication retrospective)
└── research/
    └── <topic-slug>/
        └── <date>-<slug>.md  (external research, competitor analysis, trends)
```

### Channel slug stability

The KB folder name needs to be stable across channel renames in Pito. Two
options:

- **A) Use Pito's `Channel.slug`** (changes if the channel is renamed in Pito) —
  folder rename required on slug change
- **B) Use the YouTube channel ID** (`UC...`) — stable forever; folder names
  look ugly but are a non-issue since users rarely browse the file system
  directly

**Recommendation: B (YouTube channel ID).** External channels also have YouTube
channel IDs, so it's universal. For external research that doesn't tie to a
specific channel, use a user-provided topic slug.

This decision is captured in `challenges.md` along with rationale.

### YAML front-matter convention

Every file gets YAML front-matter:

```yaml
---
title: <human-readable title>
type: voice | audience | skills | strategy | progress | plan | notes | retro | research
channel_id: <YouTube channel ID, e.g. UCxxxxxxxxxxxxxxx; optional for research>
video_id: <YouTube video ID; optional, only for video files>
external_channel_url: <optional, for research files referencing an external channel>
tags: [tag1, tag2]
created_at: 2026-04-28
updated_at: 2026-04-28
---

(markdown body follows)
```

`type` must match what the path expects (e.g., `channels/<id>/voice.md` requires
`type: voice`). Validation enforces this on save; mismatched type → reject with
clear error.

### Templates

When creating a new file, the MCP tool offers a starter template per `type`.
Templates live in the Pito application repo
(`pito/lib/yt_kb_templates/<type>.md.erb`), are read-only (templates aren't
editable through `yt:*` tools), and contain prompts/scaffolding to help the user
think about the file's content:

- `voice.md.erb` — prompts for tone, vocabulary, voice consistency examples
- `audience.md.erb` — prompts for demographics, expectations, what they come for
- `skills.md.erb` — prompts for topic fit, expertise areas, no-go zones
- `strategy.md.erb` — prompts for direction, growth plan, content pillars
- `progress.md.erb` — prompts for recent results, learnings, course corrections
- `plan.md.erb` — pre-production outline template
- `notes.md.erb` — production notes template
- `retro.md.erb` — post-publication retrospective template
- `research.md.erb` — external research template with channel/topic linking

Templates render with ERB to fill in known values (channel ID, video ID, current
date) before being written.

### `yt:*` markdown tools (extending the namespace)

Phase 3 established the namespace with relational tools. Phase 9 adds:

- `yt:list_kb_files(subdir?)` — list `.md` files under `PITO_YT_KB_PATH` or a
  subdirectory
- `yt:read_kb_file(path)` — read a single `.md` file with parsed front-matter
  and body
- `yt:write_kb_file(path, content, overwrite=false)` — write
- `yt:delete_kb_file(path)` — delete
- `yt:search_kb(query, regex=false, context_lines=2, max_results=50)` —
  grep-style full-text search across the KB
- `yt:create_kb_from_template(channel_id, type, video_id=nil)` — instantiate the
  template for the given type, write the new file, return the path
- `yt:list_channel_context(channel_id)` — convenience: returns all 5
  channel-context files (voice/audience/skills/strategy/progress) in one
  response, parsed

The tools are named with a `kb_` prefix (`list_kb_files`, not `list_files`) to
disambiguate from existing `yt:*` relational tools. This keeps the namespace
flat — no second-level namespace like `yt:kb:list` — while remaining readable.

### Sandbox

`Yt::KbSandbox` (or similar; named distinctly from the relational data layer to
avoid confusion). Mirrors the `Dev::Sandbox` and `Website::Sandbox` patterns:

- Realpath check against `realpath(PITO_YT_KB_PATH)` — no escape via `..`,
  symlinks, or encoded traversal
- `.md` extension only
- Filename pattern allowing channel IDs (`UC` followed by alphanumerics) and
  topic slugs:
  `^(channels|videos|research)/[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*\.md$`
- File size cap: 1 MB (markdown files don't need to be huge)
- Audit log at `log/mcp_yt_kb_audit.log` for writes and deletes (separate from
  the existing `yt:*` relational audit, since they're different concerns)

### Token scopes

No new scopes — `yt:read` and `yt:write` from Phase 3 cover both relational and
KB markdown tools. A token with `yt:read yt:write` can do everything in the
YouTube domain. This is the runtime-vs-build-time distinction working as
designed: anything the user-as-creator does about their channels lives under
`yt:*`.

### Front-matter parsing

- Add a `KbFile` decorator/parser:
  `KbFile.from_path(path) → { metadata:, body:, raw: }`
- `YAML.safe_load` always (never `load`)
- On write: parser merges new content with existing metadata, preserving
  `created_at`, updating `updated_at` to current date
- Validation: `type` matches path expectation (e.g., a file at
  `channels/UC.../voice.md` must have `type: voice`)

### In-app integration

The KB tools are most powerful through Claude (mobile or desktop) calling them
directly. But the web app gets a UI surface too, so the user can edit context
without leaving Pito:

- **Channel show page** — "Production Notes" panel listing the 5 channel-context
  files (voice, audience, skills, strategy, progress). Each section shows the
  file's content; bracketed `[edit]` link opens a textarea editor. If a context
  file is missing, show `[Create from template]` button.
- **Video show page** — "Production Notes" panel showing `plan.md`, `notes.md`,
  `retro.md` for that video. Same edit / create-from-template pattern.
- **All edits route through the `yt:*` KB tools** — single code path. The web
  UI's save button hits an internal API that calls `yt:write_kb_file`. No
  business logic duplicated.
- **"Auto-create channel context" button** — when a channel is connected
  (Phase 7) and no context files exist, offer to instantiate all 5 templates at
  once. Opt-in to avoid creating files the user doesn't want.

### Environment

- New env var: `PITO_YT_KB_PATH`. Default in `.env.example` is
  `/home/<user>/Dev/pito-yt-kb`. Add to both `.env.example` and
  `.env.development`.
- Both Puma processes need this exported (web Puma for the in-app editor; MCP
  Puma for tool calls). Standard `Procfile` and `.env*` propagation.

### Out of scope

- Embeddings / vector search of KB content (Phase 10 — depends on Phase 9
  structure existing first)
- Auto-generated retrospectives from analytics (interesting Theta idea; not
  Beta)
- Collaborative editing / real-time multi-user (single-user Beta)
- Image attachments embedded in notes (markdown supports image links to external
  URLs; embedded image upload is out of scope)
- Per-file git history view in UI (use GitHub directly)
- Markdown preview / syntax highlighting in the in-app editor (textarea is v1;
  richer editing tooling is post-Beta if desired)

---

## Plan checklist

### Repo + scaffolding

- [ ] Confirm `pito-yt-kb` scaffolding from Phase 1 (README, CLAUDE, LICENSE)
- [ ] Create `channels/`, `videos/`, `research/` directories with `.gitkeep`
      files
- [ ] Populate `pito-yt-kb/README.md`: structure, taxonomy, conventions, the
      channel-ID-based folder naming choice
- [ ] Populate `pito-yt-kb/CLAUDE.md`: how Claude should think about this KB,
      how `yt:*` tools interact with it

### Templates

- [ ] Create `pito/lib/yt_kb_templates/voice.md.erb` with prompts and YAML
      front-matter scaffolding
- [ ] Create `audience.md.erb`, `skills.md.erb`, `strategy.md.erb`,
      `progress.md.erb` (channel context)
- [ ] Create `plan.md.erb`, `notes.md.erb`, `retro.md.erb` (per-video)
- [ ] Create `research.md.erb` (external research)
- [ ] All templates include type-correct YAML front-matter and ERB placeholders
      for known values
- [ ] Each template ends with markdown headings the user can fill in

### Sandbox + tools

- [ ] Add `PITO_YT_KB_PATH` to `.env.example` and `.env.development`
- [ ] Implement `Yt::KbSandbox` mirroring `Dev::Sandbox` from Phase 1
- [ ] Unit specs for `Yt::KbSandbox` covering the standard rejection set
      (traversal, symlink escape, oversized writes, malformed filenames,
      non-`.md` extensions)
- [ ] Implement `Mcp::Tools::Yt::ListKbFiles`
- [ ] Implement `Mcp::Tools::Yt::ReadKbFile`
- [ ] Implement `Mcp::Tools::Yt::WriteKbFile` (overwrite guard, audit log)
- [ ] Implement `Mcp::Tools::Yt::DeleteKbFile` (audit log)
- [ ] Implement `Mcp::Tools::Yt::SearchKb` (grep-style with snippets)
- [ ] Implement `Mcp::Tools::Yt::CreateKbFromTemplate` (validates type, renders
      ERB, writes new file)
- [ ] Implement `Mcp::Tools::Yt::ListChannelContext` (convenience tool returning
      all 5 context files)
- [ ] Wire all 7 tools into the MCP server registration
- [ ] Audit log file `log/mcp_yt_kb_audit.log` written for every write, delete,
      template-create
- [ ] Specs for each tool: happy path, sandbox rejection, scope rejection,
      oversized payload, type-mismatch validation

### Front-matter parsing

- [ ] Implement `KbFile` parser/decorator with `YAML.safe_load`
- [ ] On write: merge metadata, preserve `created_at`, set `updated_at`
- [ ] Validation: enforce `type` matches path expectation
- [ ] Specs covering parsing, malformed front-matter rejection, type mismatch
      rejection, ERB rendering at template-create time

### In-app integration

- [ ] Channel show page: "Production Notes" panel with 5 sections, bracketed
      `[edit]` per section, `[Create from template]` for missing files
- [ ] Video show page: "Production Notes" panel with 3 sections, bracketed
      `[edit]` and `[create]` actions
- [ ] Editor surface: textarea with save button (same FormField pattern as
      existing settings UI)
- [ ] All edits route through `Mcp::Tools::Yt::*` tool methods (internal API;
      same code path)
- [ ] "Auto-create channel context" button on channel show page when no context
      files exist
- [ ] Specs for the in-app integration controllers

### Documentation

- [ ] Update `pito/docs/architecture.md`: KB section, file layout, MCP namespace
      expansion (relational + markdown under `yt:*`)
- [ ] Update `pito/docs/mcp.md`: `yt:*` tool list now includes the markdown
      tools; scope requirements unchanged
- [ ] `pito-yt-kb/README.md`: structure, taxonomy, conventions, the channel-ID
      folder naming
- [ ] `pito-yt-kb/CLAUDE.md`: KB purpose for Claude, when to read/write what,
      the runtime-vs-build-time distinction
- [ ] Update `pito/docs/setup.md`: brief mention of `PITO_YT_KB_PATH` and the
      `pito-yt-kb` repo cloning step

### Validation

- [ ] Manual: connect a channel → channel show page offers "Auto-create
      context"; click → 5 files created on disk under `channels/<channel-id>/`
- [ ] Manual: click `[edit]` on `voice.md`; modify; save; verify file on disk
      updated and `updated_at` field changed in front-matter
- [ ] Manual: from Claude mobile (token: `yt:read yt:write`), call
      `yt:list_channel_context('UC...')`; receive all 5 files parsed
- [ ] Manual: from Claude mobile, call
      `yt:write_kb_file('videos/UC.../VIDEOID/plan.md', ...)` for an upcoming
      video; confirm file lands on disk
- [ ] Manual: scope rejection — `dev:*`-only token cannot call any `yt:*` tool;
      `yt:read`-only token can read/list/search but not write
- [ ] Manual: type mismatch rejection — try
      `yt:write_kb_file('channels/.../voice.md', "---\ntype: audience\n---\n...")`
      → rejected with clear error
- [ ] Manual: path traversal attempt rejected
- [ ] All RSpec specs pass
- [ ] Brakeman, bundler-audit, Dependabot — clean

---

## Specs requirements

- `Yt::KbSandbox` unit specs parallel to `Dev::Sandbox` from Phase 1.
- One spec file per `yt:*` markdown tool: happy path, sandbox rejection, scope
  rejection, oversized payload, malformed input.
- `KbFile` parser specs: front-matter parsing, body extraction, type validation,
  malformed YAML rejection, ERB template rendering.
- `CreateKbFromTemplate` spec: each template type instantiates correctly with
  placeholders filled.
- In-app UI request specs: "Production Notes" panels render correctly; edit form
  posts route through tool; content lands on disk.
- Cross-tenant scoping: KB tools enforce that the resolved `Current.tenant`
  matches the channel's tenant before reading/writing files about that channel.

## Security requirements

- `yt:write_kb_file`, `yt:delete_kb_file`, `yt:create_kb_from_template` require
  `yt:write` scope.
- `yt:list_kb_files`, `yt:read_kb_file`, `yt:search_kb`,
  `yt:list_channel_context` require `yt:read` scope.
- All filesystem operations realpath-checked against `PITO_YT_KB_PATH`.
- Filename pattern enforces no traversal and matches the
  `(channels|videos|research)/...` structure.
- Front-matter parsing uses `YAML.safe_load` exclusively (never `load`).
- Templates served from `pito/lib/yt_kb_templates/` are read-only — `yt:*` tools
  cannot modify them; they're application code.
- Audit log every write, delete, template instantiation. Read operations are not
  audited (volume).
- Brakeman: no new warnings.
- bundler-audit: clean.
- Dependabot: review.
- `pito/docs/design.md`: Production Notes panel design documented (per-section
  edit pattern, create-from-template UI).

## Manual testing checklist

The user runs through this before commit:

1. Set `PITO_YT_KB_PATH=/home/<user>/Dev/pito-yt-kb` in `.env.development`;
   restart `bin/dev` so both Pumas pick up the var
2. Visit a connected channel show page → see "Production Notes" panel with
   "[Auto-create context]" if no files exist
3. Click → 5 files appear under `channels/<channel-id>/`; verify each has
   correct YAML front-matter with the right `type` field
4. Click `[edit]` on `voice.md` → textarea opens with template content → modify
   → save
5. Verify on disk: `cat ~/Dev/pito-yt-kb/channels/<channel-id>/voice.md` shows
   new content; `updated_at` in front-matter is today
6. Visit a connected video show page → "Production Notes" panel with
   `[create plan]`, `[create notes]`, `[create retro]`
7. Click `[create plan]` → file appears under
   `videos/<channel-id>/<video-id>/plan.md`
8. From Claude mobile (token: `dev:read dev:write yt:read yt:write`), prompt:
   "show me the channel context for channel UC..." — calls
   `yt:list_channel_context`, returns all 5 files parsed
9. Mobile prompt: "create a research note about competitor X under topic
   ratchet-and-clank" → tool calls succeed; file appears under
   `research/ratchet-and-clank/...`
10. Token without `yt:*` scopes — all `yt:*` calls return scope error
11. Path traversal attempt: `yt:write_kb_file('../../etc/passwd', ...)` →
    rejected
12. Type mismatch: write a file at `channels/UC.../voice.md` with
    `type: audience` in front-matter → rejected
13. `bundle exec rspec` — green

---

## Challenges to anticipate

- **Channel slug stability.** The decision is YouTube channel ID for folder
  names (option B). External channels have IDs too; pure-research files use a
  user-provided topic slug. Document this clearly in `challenges.md` so
  future-you doesn't second-guess.
- **Video ID conflicts.** YouTube video IDs are globally unique; the path
  `videos/<channel-id>/<video-id>/plan.md` is unambiguous. For videos that move
  between channels (rare but possible if YouTube re-attributes), the file path
  becomes stale. Document the edge case.
- **Template versioning.** If templates evolve after files are created, existing
  files don't auto-update. Templates are starting points, not living docs. Treat
  them as code; bump them as needed; existing files keep their original content.
- **Editor UX.** Textarea is minimal. If the user requests markdown preview or
  syntax highlighting, capture in `additions.md` for follow-up. Out of Phase 9
  scope.
- **Search performance at scale.** Grep across the KB is fast for the first
  hundreds-to-low-thousands of files; if it grows beyond ~10k files, Meilisearch
  indexing becomes attractive. Phase 10 introduces Meilisearch for KB content
  for vector reasons anyway, but keyword search will benefit too.
- **KB and tenant boundaries.** Single-user Beta: KB has no per-tenant
  subdirectory. For Theta multi-tenant, structure might need a `tenants/<slug>/`
  prefix. Document the future-refactor cost. Acceptable now; not free later.
- **`yt:*` tool sprawl.** The `yt:*` namespace now includes both relational
  tools (from Alpha-era code re-scoped in Phase 3) and markdown tools (added
  here). The list could become long. Document the namespace clearly in
  `pito/docs/mcp.md` so users picking scopes for tokens understand what they're
  granting.
- **Both Pumas and the env var.** `PITO_YT_KB_PATH` must reach both Web Puma
  (in-app editor) and MCP Puma (tool calls). Same propagation discipline as the
  previous KB env vars.

---

## Confirmation gates for Claude Code

Before executing, confirm with the user:

1. The folder-naming choice is YouTube channel ID (option B). Folder names are
   ugly but stable. Acceptable?
2. Auto-creation of context files is opt-in (user clicks button). Alternative:
   auto-create on channel connection. Recommend opt-in to avoid surprise files.
3. Editor UX is textarea v1. Richer editor (preview, syntax highlighting) is out
   of scope.
4. Single-user / single-tenant assumption holds — KB has no per-tenant directory
   prefix. Theta refactor cost acknowledged.
5. The `yt:*` namespace covers both relational and markdown tools (per
   `beta.md`'s runtime-vs-build-time framing). No second-level namespace
   introduced.
6. Templates live in the application repo (`pito/lib/yt_kb_templates/`) and are
   application code (not editable through `yt:*` tools). Confirm.
