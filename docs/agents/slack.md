# pito-slack — project-specific extensions

The `pito-slack` agent reads this file at dispatch time. Base template:
`~/Dev/claude-dotfiles/agents/slack.md`. Read project-wide rules in
`~/Dev/pito/CLAUDE.md` first.

## Channel

- **`#pito-app`** — private channel. Channel ID: `C0B18G4E25B`.
- The agent uses `slack_search_channels` with `channel_types:
  "private_channel"` to resolve the ID at send time, OR uses the literal ID
  above directly.
- (Channel was renamed from `#dev` → `#pito-app` on 2026-05-18.)

## One-way only

`pito-slack` is **Claude → user only**. No polling, no `#claude`-prefix
monitoring, no async response loop. The user reaches Claude via the chat
session; Slack pings are heads-up signals one-way.

## Message style — signal-only, concise

Every ping is git-commit-subject concise. Status verb + 3-8 words. Emoji
allowed and encouraged as the signal accent — match the actual signal
(✅ done, ⏳ in flight, 🚫 blocked, ⚠️ conflict, 🚀 next, ✨ delivered).

**Good shape:**
- `✅ dotfiles green`
- `🧪 specs running`
- `✅ /games ready`
- `🚀 commit pushed`
- `🚫 needs auth — Cloudflare token`

**Too verbose:** any sentence with enumerated details, multiple clauses, or
commit SHAs that the user is not expected to click immediately.

**SHAs:** include only when the user needs to verify a specific commit. Wrap
as `<https://github.com/gmrdad82/pito/commit/SHA|SHA>` so the SHA is
one-click to GitHub.

## When to ping

- **Task completion awaiting validation** — every dispatch landing surfaces
  in both chat AND Slack. Never silent.
- **Real blocker requiring user input** — auth, design pick, destructive op
  authorization, locked-rule conflict.
- **Long-running process milestones** — full spec sweep finished,
  commit+push milestone, batch completion in autonomous-completion mode.
- **NOT** for routine in-chat status (the conversation is the detail
  surface).

## Always through this agent — never direct MCP

The master agent NEVER calls `mcp__claude_ai_Slack__slack_send_message`
directly. Every ping flows through `pito-slack` so message-style governance
stays in this one file. Direct MCP calls are a process failure.

## Pointers

- `CLAUDE.md` → "Slack notifications" — the cross-stack contract.
- `CLAUDE.md` → "Communication style" — emoji-mapping rules (chat-side).
