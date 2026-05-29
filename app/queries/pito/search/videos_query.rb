# frozen_string_literal: true

module Pito
  module Search
    # Search query object for Video records.
    #
    # Usage:
    #   Pito::Search::VideosQuery.call(scope: Video.all, text: "ocean", genre_id: 5)
    #   # => scope narrowed by full-text and/or genre (via linked game)
    class VideosQuery
      attr_reader :scope, :text, :genre_id

      def initialize(scope: Video.all, text: nil, genre_id: nil)
        @scope    = scope
        @text     = text
        @genre_id = genre_id
      end

      def results
        rel = scope
        rel = by_text(rel)              if text.present?
        rel = by_genre_via_game_link(rel) if genre_id.present?
        rel
      end

      private

      # Full-text match against the generated search_vector column.
      def by_text(rel)
        rel.where(Pito::Search.matches(:search_vector, text))
      end

      # Narrow videos to those linked to games in a given genre.
      #
      # Route: videos → video_game_links → games → game_genres → genres
      def by_genre_via_game_link(rel)
        rel.where(id:
          VideoGameLink.where(game_id:
            GameGenre.where(genre_id: genre_id).select(:game_id)
          ).select(:video_id)
        )
      end
    end
  end
end
