# Orchestration Scripts

This folder holds bash scripts that keep `.claude/` configuration synchronized
across machines and across the subprojects of the Pito ecosystem.

The scripts themselves are not in this folder yet. The **agents-bootstrap**
agent will create them as a separate, dedicated task. This README documents what
they will do so the architect can plan around them.

## Planned scripts

### `pull-claude-config.sh`

Pulls the latest `.claude/` configuration from the source-of-truth location into
the current working tree. Used when starting a session on a fresh clone or a new
machine, so the local Claude Code harness picks up the project's agents, hooks,
and permissions.

### `install-claude-config.sh`

Installs the `.claude/` configuration into the user's environment for the
current repo. Wires up settings, registers any project-level agents, and
verifies that the harness sees the configuration it expects.

## Why these live here

The Pito ecosystem is multi-repo. Each subrepo has its own `CLAUDE.md` and its
own `.claude/` folder, but the orchestration layer (this dev knowledge base) is
the only place that sees the whole picture. Keeping the sync scripts here means
a single `pull-claude-config.sh` invocation can fan out across all subrepos
without any one of them owning the cross-cutting logic.
