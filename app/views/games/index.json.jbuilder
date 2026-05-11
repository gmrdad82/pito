# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Index response. Echoes the sort + filter the caller asked for so the
# CLI / MCP caller can verify what it asked for.
json.games(@json_games) do |game|
  json.partial! "games/game", game: game
end

json.filter do
  json.genre_id @filter[:genre_id]
  # Phase 27 §1a — the singular `platform_owned_id` filter (integer fk)
  # was replaced by the slug-keyed `platform_owned_slug` that flows
  # through `Game.owned_on(slug)`. The JSON contract reflects the new
  # shape so callers can echo back what they asked for.
  json.platform_owned_slug @filter[:platform_owned_slug]
end

json.sort do
  json.key @json_sort[:key]
  json.dir @json_sort[:dir]
end
