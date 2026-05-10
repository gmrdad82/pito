# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Resync enqueue acknowledgment (HTTP 202 Accepted). Surfaces the
# Sidekiq job id so the CLI / MCP caller can poll an audit row keyed
# by jid in a future phase.
json.game_id @game.id
json.resyncing YesNo.to_yes_no(true)
json.enqueued_jid @enqueued_jid
json.message "refreshing from igdb…"
