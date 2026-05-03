# Conversation Summaries

This folder preserves key chat summaries the architect wants kept as durable
context across machines and across Claude Code sessions.

The architect's working memory is bounded by the session. Important
conversations — scope-shaping discussions, decisions that didn't quite become
ADRs, design dead-ends and why we rejected them, exchange history that frames
how a phase plan came to be — would otherwise be lost when the session ends.
Capturing them here makes them portable: any future session on any machine can
read this folder and recover the reasoning, not just the outcome.

## What belongs here

- Scope-shaping discussions where the user and the architect aligned on what a
  phase covers and what it doesn't.
- Design conversations that produced a decision but where the trade-off space is
  worth preserving in detail (even when the outcome itself becomes an ADR).
- Rejected alternatives and why — useful when the same idea resurfaces later.
- Long-form context the architect wants future sessions to read on boot.

## What does not belong here

- Routine implementation chatter. That goes in the phase log.
- Final decisions that are clean enough to be ADRs. Write the ADR in
  `decisions/` and link it from here only if the path to it is interesting.
- Anything that would be better stored as a feature spec. That belongs under
  `docs/plans/beta/<phase>/`.

## Naming

One file per conversation, named:

```
<YYYY-MM-DD>-<topic>.md
```

The topic slug is short and descriptive (e.g., `lanes-model`, `upload-strategy`,
`mcp-scope`). The date is the date of the conversation, not the date the summary
was written.

## Format

A summary is not a transcript. Each file should have:

- **Participants** — usually "user + architect" but record other agents if they
  materially contributed.
- **Topic** — one sentence.
- **Outcome** — the decision, plan, or shift in direction the conversation
  produced.
- **Reasoning** — the path that got us there, in enough detail that a future
  session can re-derive it.
- **Open threads** — anything left unresolved that future work needs to pick up.
- **Links** — related ADRs, specs, phase logs.
