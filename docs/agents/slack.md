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

## Incoming convention — `#code` prefix only

`#dev` carries traffic from other people and other apps too. The agent
acts ONLY on user messages whose body STARTS with `#code `. Everything
else is noise — read past, do not act.

Examples that DO count as direct requests to Claude Code:

- `#code status?` — user wants a current-task summary.
- `#code yes` — affirmative reply to the agent's last pending question.
- `#code cancel that, try X instead` — direction change.
- `#code back at laptop` — stop the polling loop; user is back in chat.

Examples that DO NOT count (ignore):

- `ok`, `yes`, plain prose — these may be replying to another person/app
  in the channel, not to Claude Code.
- `@Claude …` — this tags the Anthropic-built Claude Slack app (a
  separate brain), not this agent.

## Polling cadence

When the user has walked away from the laptop and asked Claude Code to
poll Slack, the master agent schedules wakeups at **60-second intervals**
to call `slack_read_channel` on the configured channel, filtered for
`#code`-prefixed messages newer than the last seen ts. Polling continues
until the user replies `#code back at laptop` (or equivalent) — then the
loop stops and the master agent continues with normal chat-driven flow.
