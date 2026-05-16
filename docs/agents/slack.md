# pito-slack project stub

The `pito-slack` agent reads this file at dispatch time.

## Channel

- `default_channel: "#dev"` — private channel; agent uses
  `slack_search_channels` with `channel_types: "private_channel"` to resolve
  the channel ID at send time.

## Message style

Messages must be **git-commit-subject concise**. Think of every ping as if
it had to fit in a single-line git commit subject. Signal-only, no
enumerated details, no SHAs unless the user must act on them.

**Good shape:** `dotfiles green`, `specs running`, `specs green`,
`/games ready`, `commit pushed`.

**Too verbose:** `✅ claude-dotfiles checks all green (prettier, bash
syntax, install dry-run, roundtrip, frontmatter lint). pushed 2 commits…`

Status verbs only: `running`, `green`, `red`, `done`, `ready`, `blocked`.
Add specifics only when the user must act on them (failing spec count for
triage, commit SHA they need to verify). Otherwise, shorter wins. The chat
conversation remains the detailed surface — Slack is the heads-up only.

## How the master agent uses pito-slack

The master agent NEVER calls `mcp__claude_ai_Slack__slack_send_message`
directly. All pings flow through this agent: dispatch `pito-slack` with the
message body, the agent does the send. This keeps Slack message style
governance in one place (here) and avoids per-call drift in tone or length.
