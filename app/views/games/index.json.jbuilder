# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Index response. Echoes the sort + filter the caller asked for so the
# CLI / MCP caller can verify what it asked for.
json.games(@json_games) do |game|
  json.partial! "games/game", game: game
end

json.filter do
  json.genre_id @filter[:genre_id]
  json.platform_owned_id @filter[:platform_owned_id]
end

json.sort do
  json.key @json_sort[:key]
  json.dir @json_sort[:dir]
end
