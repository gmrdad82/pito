# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Soft-cancel response. Locked decision #4: minimal `{ id, state }`
# for cancelled rows and `{ id, reason }` for skipped rows. Caller
# re-fetches detail via `GET /calendar/entries/:id.json` if needed.
json.cancelled(@cancelled) do |row|
  json.id row[:id]
  json.state row[:state]
end

json.skipped(@skipped) do |row|
  json.id row[:id]
  json.reason row[:reason]
end
