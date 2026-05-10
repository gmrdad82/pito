# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Detail response. Uses `GameDecorator#as_detail_json` for the full
# IGDB-backed payload.
json.game GameDecorator.new(@game).as_detail_json
