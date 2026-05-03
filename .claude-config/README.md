# .claude-config

Versioned mirror of the parts of `~/.claude/` that we want shared across
machines for the Pito project: custom agents, custom slash commands, and custom
skills.

This directory is the canonical agent definition source for the pito monolith. A
fresh laptop install can pull the same Claude Code agent toolkit that the Pito
architect (parent Claude session) relies on. Without it, the agent fleet would
have to be re-authored from memory every time a new workstation joins the
project.

## What this folder mirrors

```
~/.claude/agents/    <->  .claude-config/agents/
~/.claude/commands/  <->  .claude-config/commands/
~/.claude/skills/    <->  .claude-config/skills/
```

The mirror is scoped: only files relevant to the Pito project are tracked.
Personal or unrelated agents/commands/skills sitting in `~/.claude/` are left
alone by both sync scripts.

## Sync scripts

Both scripts live in `docs/orchestration/scripts/` and use `set -euo pipefail`.
Both refuse destructive operations by default.

### `pull-claude-config.sh`

Pulls **from** `~/.claude/` **into** this repo. Run after editing an agent or
command on disk via the Claude Code UI or by hand under `~/.claude/`. Uses
`rsync --delete` scoped to the agent/command/skill subfolders only, and only
mirrors files that match the Pito-relevant allow-list (the nine named agents
below, plus anything matching the `pito-*` prefix).

Prints every file that was copied or removed.

### `install-claude-config.sh`

Installs **from** this repo **into** `~/.claude/`. Run after pulling the latest
monolith on a fresh laptop, or after a teammate updates an agent definition.

Safety behavior:

- Refuses to overwrite files in `~/.claude/` that are newer than the repo
  version, unless `--force` is passed.
- Prints every file that _would_ change, then prompts before applying, unless
  `--yes` is passed.
- No file is ever deleted from `~/.claude/` by this script — only created or
  updated.

## What is NOT mirrored

The mirror is deliberately narrow. None of the following are tracked:

- `~/.claude/.credentials.json` or any other token / API key file.
- `~/.claude/settings.json` machine-local settings (model selection, theme,
  keybindings).
- `~/.claude/projects/` conversation history and per-project memory.
- `~/.claude/todos/`, caches, logs, or any runtime state.
- Any agent / command / skill that does not match the Pito allow-list.

If you find yourself wanting to share a non-listed item across machines, add it
to the allow-list in `pull-claude-config.sh` explicitly — never broaden the
rsync filter to "everything."

## The nine Pito agents

The current allow-list of agent files mirrored from `~/.claude/agents/` into
`.claude-config/agents/` (absolute path: `~/Dev/pito/.claude-config/agents/`):

1. `architect-spec.md` — writes feature specs into `docs/plans/beta/`.
2. `audit-state.md` — read-only repository vs. plan gap report.
3. `cli-impl.md` — implements Lane 2a Rust/Ratatui mirrors at `extras/cli/`.
4. `docs-keeper.md` — keeps docs and phase logs in sync with reality.
5. `mcp-impl.md` — adds MCP tool surfaces for Lane 1 features.
6. `rails-impl.md` — implements Lane 1 Rails features.
7. `reviewer.md` — runs the review pipeline and writes manual test playbooks.
8. `security-auditor.md` — runs the security review pipeline and writes finding
   reports.
9. `website-impl.md` — implements the Cloudflare Pages landing page at
   `extras/website/`.

Plus any future file matching the `pito-*` prefix.
