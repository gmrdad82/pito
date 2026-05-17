# pito-slack project stub

The `pito-slack` agent reads this file at dispatch time.

## When to use Slack at all

`pito-slack` agent dispatches and Slack-MCP polling are **opt-in
asynchronous-coordination tools**, NOT default communication channels.

**Master agent uses Slack ONLY when:**

- User has explicitly signaled async mode in chat (examples below).
- A long-running process needs a checkpoint while user is known-away.

**Master agent does NOT use Slack when:**

- User is actively chatting in the session (any chat message in the last
  few turns).
- The information can be communicated in the chat response itself.
- The user has signaled "I'm back" or equivalent.

**Explicit async signals (the only ways to enable Slack mode):**

- "I'm going off / going on Slack"
- "Ping me on Slack when X done"
- "I'll be on Slack for a while"
- "Keep me posted on Slack"

**Explicit return signals (any of these turn Slack mode off):**

- "I'm back"
- `#claude I'm back` (in Slack)
- Any chat message from the user in the active session (implicit return)

When in doubt: prefer chat. Slack is for "user is away and needs a heads-up";
chat is for everything else.

**In-flight exception.** If the user has just asked for an async update and
then returns mid-update, finish the in-flight Slack message but DO NOT
initiate new ones. Subsequent communication flows back through chat.

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

## Incoming convention — `#claude` prefix only

`#dev` carries traffic from other people and other apps too. The agent
acts ONLY on user messages whose body STARTS with `#claude `. Everything
else is noise — read past, do not act. (The earlier `#code` prefix was
deprecated 2026-05-17 — user prefers a single convention.)

Examples that DO count as direct requests to Claude Code:

- `#claude status?` — user wants a current-task summary.
- `#claude yes` — affirmative reply to the agent's last pending question.
- `#claude cancel that, try X instead` — direction change.
- `#claude back at laptop` — stop the polling loop; user is back in chat.
- `#claude all good. Continue...` — go-ahead signal.

Examples that DO NOT count (ignore):

- `ok`, `yes`, plain prose — these may be replying to another person/app
  in the channel, not to Claude Code.
- `@Claude …` — this tags the Anthropic-built Claude Slack app (a
  separate brain), not this agent. The `#claude` prefix is a text marker
  the agent grep-filters for, NOT a Slack mention.

## Polling cadence

ONLY active when explicit async mode is on (see "When to use Slack at all"
above). When active, the master agent schedules wakeups at **60-second intervals (standard, do not deviate)** to call `slack_read_channel` on the configured channel,
filtered for `#claude`-prefixed messages newer than the last seen ts.

Polling is NEVER scheduled while the user is actively chatting in the
session. A chat message from the user implicitly cancels Slack mode and
stops the loop (see the explicit-return-signals list above).

**The loop stops on any of these signals:**
- User types `I'm back` (or close paraphrase) in the chat session.
- User sends `#claude I'm back` in `#dev`.
- User sends ANY message in the chat session — active in-chat
  conversation implicitly means the user is at the keyboard, so polling
  Slack is redundant. The master agent stops scheduling new wakeups; the
  next-scheduled wakeup fires harmlessly once, detects the in-chat
  activity from context, and does not reschedule.

After any signal, no more wakeups are scheduled and the master agent
returns to normal chat-driven flow.
