# Phase 21 — JSON Endpoints for CLI / MCP Parity.
#
# Index response. Echoes the sort + filter the caller asked for so the
# CLI / MCP caller can verify what it asked for.
#
# Phase 27 P27 reviewer follow-up (non-blocking concern #1, 2026-05-11)
# — the legacy `platform_owned_slug` key was emitted here but the
# controller never populated `@filter[:platform_owned_slug]`, so the
# JSON contract always serialised `"platform_owned_slug": null`. The
# canonical platform-ownership filter has moved to the §01b filter row
# (`?filters=owned,ps5` / `Games::Filter`); no downstream consumer
# reads `platform_owned_slug` (verified by repo-wide grep). The key
# is dropped here. Re-introduce it (or a successor) only when a
# controller-populated field justifies the wire contract addition.
json.games(@json_games) do |game|
  json.partial! "games/game", game: game
end

json.filter do
  json.genre_id @filter[:genre_id]
end

json.sort do
  json.key @json_sort[:key]
  json.dir @json_sort[:dir]
end
