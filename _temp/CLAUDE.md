# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project

Pito — a personal tool to track and organize YouTube activity across 3 channels.

## Tech Stack

- **Docs/Specs:** Markdown files
- **Code:** Ruby scripts (when needed)
- **Database:** SQLite (when needed)

## Rules

- Never modify files outside this repository folder.
- Commit with meaningful 1-line messages. No AI authoring mentions.
- Push on session close.

## Routing — How to Navigate This Repo

- **Channel-specific work** → `docs/channels/<channel-name>/` (profile, style,
  history, planning)
- **Shared workflows** → `docs/workflow/`
- **Tool/app specs** → `docs/tools/`
- **Code** → `scripts/`
- **Skills & routing logic** → `docs/skills/overview.md`

**Critical:** Never mix channel-specific content across channels. When working
on a channel, consult ONLY that channel's folder. When building tools, keep them
channel-agnostic.

## Structure

```
docs/
  purpose.md                    — project goals
  progress.md                   — session log
  skills/overview.md            — skill areas and routing rules
  channels/
    catalin-ilinca/             — story/personal channel
      profile.md, style.md, history.md, planning.md
    witty-gaming/               — gaming super super-cuts with voice
      profile.md, style.md, history.md, planning.md
    micless-gaming/             — gaming super-cuts, no voice
      profile.md, style.md, history.md, planning.md
  workflow/
    gaming-pipeline.md          — OBS → DaVinci → export pipeline
  tools/
    README.md                   — tooling plans and principles
```
