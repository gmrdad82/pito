# frozen_string_literal: true

module Pito
  module Search
    # Search query object for Game records.
    #
    # Usage:
    #   Pito::Search::GamesQuery.call(scope: Game.all, text: "zelda", genre_id: 5)
    #   # => scope narrowed by full-text and/or genre filter
    class GamesQuery
      attr_reader :scope, :text, :genre_id

      def initialize(scope: Game.all, text: nil, genre_id: nil)
        @scope    = scope
        @text     = text
        @genre_id = genre_id
      end

      def results
        rel = scope
        rel = by_text(rel)   if text.present?
        rel = by_genre(rel)  if genre_id.present?
        rel
      end

      private

      # Full-text match against the generated search_vector column.
      def by_text(rel)
        rel.where(Pito::Search.matches(:search_vector, text))
      end

      # Narrow to a specific genre via the join table.
      def by_genre(rel)
        rel.where(id: GameGenre.where(genre_id: genre_id).select(:game_id))
      end
    end
  end
end
