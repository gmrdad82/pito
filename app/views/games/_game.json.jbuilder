# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Summary row for a Game. Reused by `index.json` and consumers that
# embed game summaries inline. Uses `GameDecorator#as_summary_json` so
# the shape stays in one place.
json.merge!(GameDecorator.new(game).as_summary_json)
