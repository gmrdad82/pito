# 2026-05-18 — Pito::Search::Omnisearch dispatcher.
#
# Generic per-area omnisearch dispatcher. Routes a `(area, query, **kwargs)`
# triple to the implementation class registered for that area. Adding a new
# omnisearch area (videos, projects, channels, notifications, ...) is a 1-line
# addition to the `AREAS` table — the dispatcher contract stays stable.
#
# Today the only registered area is `:games`, served by
# `Pito::Search::SearchGames` which queries the shared `games_<env>` index
# carrying both Game and Bundle documents.
#
# Signature note: the dispatcher accepts `query:` as a kwarg for symmetry with
# the area kwarg + future area implementations. The current `:games`
# implementation (`Pito::Search::SearchGames.call`) takes `query` as a positional
# argument; the dispatcher adapts by passing it positionally. New per-area
# implementations are free to choose their own internal arg style — only the
# dispatcher's external contract (`area:`, `query:`, **kwargs) is locked.
module Pito
  module Search
    class Omnisearch
      AREAS = {
        games: Pito::Search::SearchGames
        # videos: Meilisearch::SearchVideos,        # future
        # projects: Meilisearch::SearchProjects,    # future
        # channels: Meilisearch::SearchChannels,    # future
        # notifications: Meilisearch::SearchNotifications, # future
      }.freeze

      def self.call(area:, query:, **kwargs)
        impl = AREAS.fetch(area) { raise ArgumentError, "unknown omnisearch area: #{area.inspect}" }
        impl.call(query, **kwargs)
      end
    end
  end
end
