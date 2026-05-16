# HANDOFF — pito onboarding for a fresh Claude conversation

This file is the entry point when a new Claude session needs to pick up where
the previous one left off without resuming the conversation history.

## How to onboard yourself (read these in order)

1. **`CLAUDE.md`** — project rules, tech stack, hard rules, current active
   follow-ups list.
2. **Latest `docs/notes/*.md`** — Mobile-facing session summary, sorted by mtime
   descending. The newest file is the most recent session's recap (what shipped,
   what's queued, what's paused).
3. **`docs/orchestration/follow-ups.md`** — live backlog of open items. The
   "Open" section at the top is what's actually pending.
4. **`docs/decisions/`** — append-only ADRs (Context / Decision / Consequences).
   Read at least the most recent 4-5 to get the architectural rationale for
   current patterns.
5. **`git log --oneline -30`** — recent commits. Commits with `[skipci]` are
   routine autonomous work; commits without are validation milestones.
6. **Newest `docs/plans/beta/<NN>-*/log.md`** by mtime — the most recent phase's
   session entries tell you what was in flight at session close.

## After onboarding, do this

Tell the user where things stand: 📊

- **Shipped:** which phases / major surfaces just closed
- **Queued (small):** outstanding polish items ready to dispatch
- **Paused:** lanes the user explicitly closed (e.g., MCP / TUI / CLI at the
  time of writing — re-check the latest session note to confirm the pause is
  still in effect)
- **Blocked:** anything waiting on an external signal (rare)
- **Recommended next move:** propose 1-3 concrete dispatches the user could
  greenlight

## Persistent surfaces you don't need to read explicitly

Both load automatically:

- **`CLAUDE.md`** is injected into every session (no need to fetch).
- **Auto-memory** at `~/.claude/projects/-home-catalin-Dev-pito/memory/` loads
  feedback memories (emoji preference, autonomy cadence, MCP/TUI pause
  direction, bracketed-link conventions, commit `[skipci]` flag, etc.).

So `CLAUDE.md` + auto-memory + the latest session note already get you ~90% of
the way there. The rest of the read-list is for full depth.

## MCP Dev KB tools (for Claude on Mobile or another MCP client)

Available on the `dev` MCP scope:

- `list_docs(prefix:, name_pattern:)` — list markdown under `docs/` with mtime
  ordering. Filter with `prefix: "notes/"` to find the newest session summary.
- `read_doc(path:)` — read a single `.md` file under `docs/` or `CLAUDE.md`.
- `save_note` — drop a markdown capture to `docs/notes/`. Filename is
  server-generated; safe for multiple captures of the same thought.

These tools let Mobile recover the same context the Desktop session has —
without filesystem access.

## What you should NOT do without explicit user direction

- Don't lift the MCP / TUI / CLI pause if it's still active in the latest
  session note + auto-memory.
- Don't drop `[skipci]` from commit messages — it stays on routine autonomous
  work until the user explicitly says "land with full CI."
- Don't write code or project markdown directly from the master conversation —
  delegate to the appropriate subagent (`pito-rails`, `pito-docs`, `pito-rust`,
  `pito-architect`, `pito-reviewer`, `pito-security`, `pito-slack`, etc.).
- Don't call Slack MCP tools directly from the master conversation — every
  Slack notification flows through the `pito-slack` agent. See `CLAUDE.md`
  § Slack notifications and `docs/agents/slack.md` for the style + delegation
  contract.

## Canonical surface map

| Surface                            | Purpose                                           | Refresh cadence                             |
| ---------------------------------- | ------------------------------------------------- | ------------------------------------------- |
| `CLAUDE.md`                        | Project rules + active follow-ups                 | Updated at session close                    |
| `docs/orchestration/follow-ups.md` | Live backlog                                      | Updated at session close + ad hoc           |
| `docs/notes/`                      | Mobile-facing session summaries (newest = latest) | One per session at close                    |
| `docs/decisions/`                  | ADRs (durable architectural decisions)            | When a decision produces a lasting artifact |
| `docs/plans/beta/<NN>-*/plan.md`   | Per-phase checkbox state                          | Ticked as work lands                        |
| `docs/plans/beta/<NN>-*/log.md`    | Per-phase session entries                         | Appended per implementation session         |
| `git log --oneline -N`             | Recent commits                                    | Always-on                                   |
| `~/.claude/projects/.../memory/`   | Cross-conversation memories                       | Updated when behavior should persist        |

---

That's it. Read the 6 sources above, summarize, propose next steps, wait for
direction. 🚀
