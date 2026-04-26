# Skills

What Pito (and its assistant) should be able to do, and how to route work correctly.

## Routing Rules

- **Channel work** lives in `docs/channels/<channel>/`. Never mix channel-specific content across channels.
- **Application/tooling work** lives in `docs/tools/`. Code, scripts, dashboards — anything that operates across channels.
- **Workflows** live in `docs/workflow/`. Shared production processes.
- When asked about a specific channel, consult ONLY that channel's folder for style, history, and planning.
- When asked for cross-channel views or comparisons, consult `docs/tools/` and read from all channel folders as data sources.
- When building code or tools, never hardcode channel-specific style or content decisions — those belong in the channel docs.

## Skill Areas

### 1. Overview & Organization
- Birds-eye view of all channels, status, and plans
- Track progress across sessions
- Maintain specs, decisions, and history
- **Where:** `docs/progress.md`, `docs/purpose.md`

### 2. Channel Assistant
Per-channel, kept strictly separate:
- Style guide — tone, format, editing approach
- History — published videos, what worked, what didn't
- Planning — video ideas, backlog, schedule
- Channel-specific skills and techniques
- **Where:** `docs/channels/<channel-name>/`

### 3. YouTube Data Tools (future)
- Ruby scripts to pull data from YouTube Data API / YouTube Studio
- Channel analytics: views, subscribers, watch time
- Video performance tracking
- **Where:** `docs/tools/`, code in `scripts/`

### 4. Cross-Channel Dashboard (future)
- Compare performance across all 3 channels
- Spot trends and patterns
- Unified view of activity
- **Where:** `docs/tools/`
