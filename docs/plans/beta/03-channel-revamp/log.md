# Phase 3 — Channel Revamp · Session Log

## 2026-05-02 — Pre-implementation kickoff

**State at start:** Phase 2 (Postgres migration) merged via PR #24 + cleanup
commit `9f0fd39`. pito on main with Postgres 17 + pgvector + citext. pito-sh has
bootstrap Ratatui UI with mock data only. Channel Revamp scope: drop Alpha-era
Channel columns, add tenant_id + channel_url + star + connected + syncing +
last_synced_at. Add Tenant + User schema-only models. Add ChannelSync job +
cron. Add BulkSync mirror of BulkDelete. Add dashboard chart visibility
persistence in localStorage.

**Decisions captured before execution:**

- Phase scope replaces original Phase 3 (Auth Foundation). Auth is deferred to a
  future phase. This phase is data-only Tenant + User (no UI, no scopes, no
  ApiToken).
- Channel URL format: strict regex
  `\Ahttps://www\.youtube\.com/channel/UC[A-Za-z0-9_-]{22}\z`. youtu.be (videos
  only) and @handle (mutable) explicitly rejected.
- URL is locked after create — never editable.
- Saved view label for kind=channels uses `Channel#id.to_s` for now. Title comes
  back when YouTube sync lands.
- User schema: `username + email + password_digest`. No display name. Username
  regex: must start with letter, alphanumerics only, no spaces, no special
  chars. Both username and email globally unique.
- Bulk-as-foundation: single delete and single sync are bulk operations with one
  ID. Applies to web + MCP + terminal.
- MCP requires `confirm: bool` two-step flow on destructive/sync tools. First
  call returns preview; second call with confirm: true executes.
- Terminal app uses in-TUI confirmation (no system dialogs).
- No JavaScript alert/confirm/prompt dialogs anywhere in Pito (forward-going
  hard rule).
- Searchable concern dropped from Channel (no title/description to index).
- Workflow: direct commits to main on every repo (no branches, no PRs).
- Owner credentials read from `:owner` block in Rails encrypted credentials with
  placeholder fallback.

**Phase A complete:** schema migrated, models created/refactored, factories
updated, seeds rewritten with 100 channels (7 starred, 6 connected, 2
intersection). 87 model specs green. Existing controller/MCP/decorator specs
left for Phase B agents to fix.

**Next entry will record:** Phase B fan-out results from pito-channels-app,
pito-bulk-sync, pito-mcp, pito-sh-impl agents, plus the reviewer's manual test
playbook.

## 2026-05-02 — Phase B implementation complete

**Outcome**: Channel Revamp implementation landed across all three lanes. Pito
(Rails web + MCP), pito-sh (terminal). Schema migrated. 100 channels seeded with
correct distribution (7 starred, 6 connected, 2 intersection).

**Phase B agents ran in parallel:**

- pito-channels-app — ChannelsController + views + JSON API + decorator +
  ChannelSync job + cron + dashboard chart visibility (Stimulus +
  localStorage) + saved_view spec finalization. ~533 specs (1 residual
  cross-agent failure resolved by pito-mcp). Brakeman + bundler-audit clean.
- pito-bulk-sync — Confirmable concern + SyncsController + BulkSyncJob +
  skip-state UI everywhere + bulk_select extension. Focused 61/0; full suite
  residuals owned by other agents at run time, resolved when all finished.
- pito-mcp — 8 channel-touching MCP tools refactored + 2 new bulk tools with
  two-step confirm flow + Searchable branch dropped from search_content. 62/0 in
  spec/mcp.
- pito-sh-impl — full Channel struct refactor + 5 UI screen rewrites + new
  in-TUI confirmation module + bulk picker + filter chips + URL opening via open
  crate. 29/0 cargo tests.

**Cross-agent integration**: pito-channels-app's picker added the
`data-bulk-select-sync-type-value="channel"` value attribute. Reviewer added the
matching `<span data-bulk-select-target="syncAction" hidden></span>` element if
missing.

**Reviewer + security-auditor verdicts**: see playbooks under
`pito-dev-kb/orchestration/playbooks/2026-05-02-channel-revamp*.md`.

**What's queued but not yet hot**:

- ChannelSync job is a placeholder (no real API calls yet). Real public API +
  OAuth API integration lands in future phases.
- SyncStarredChannelsJob cron runs daily at midnight UTC; no real work yet.
- Auth Foundation (Api::AuthConcern, scopes, ApiToken, login UI, Doorkeeper) is
  deferred to a future phase. Tenant + User schema is in place; auth surface
  comes later.
- The `:mysql` credentials block was already removed in Phase 2 cleanup. The new
  `:owner` credentials block carries tenant/user values for the seed.

**Verified state**:

- pito on `main`, all Phase B commits applied; tests gates green
- pito-sh on `main`, cargo tests green
- pito-dev-kb has the spec, kickoff log, additions, and playbooks
- All three docker containers healthy; client-api containers untouched
- localStorage chart visibility key: pito_dashboard_charts_visible

**Manual playbook**:
`pito-dev-kb/orchestration/playbooks/2026-05-02-channel-revamp.md` — to be run
by the user before commit.

**Next**: user runs the playbook end-to-end. On green, the architect commits +
pushes to main on each repo (no PR — direct main per workflow). Architect
remembers to also commit pito-dev-kb (spec, log, additions, playbooks) and to
remind the user to run install-claude-config.sh --yes if any agent definitions
changed.
