# frozen_string_literal: true

class Game
  # Builds the multi-field text embedded for a Game — the single
  # source of truth shared by `Game::EmbeddingIndexer` and the
  # `pito:embeddings:reindex` bulk sweep (so the per-record and bulk paths
  # can never drift).
  #
  # Fields (em-dash joined, blank slots skipped): title · alt names · genres ·
  # developer(s) · publisher(s) · platforms · time-to-beat · rating · summary.
  module EmbedText
    SEPARATOR = " — "

    module_function

    def call(game)
      parts = []
      parts << game.title.to_s.strip if game.title.present?
      parts << alt_names(game)
      parts << labelled("genres", game.genres.map(&:name))
      parts << labelled("developer", game.developer_companies.map(&:name))
      parts << labelled("publisher", game.publisher_companies.map(&:name))
      parts << labelled("platforms", Array(game.platforms))
      parts << ttb_phrase(game)
      parts << rating_phrase(game)
      parts << game.summary.to_s.strip if game.summary.present?
      parts.reject(&:blank?).join(SEPARATOR)
    end

    def alt_names(game)
      names = Array(game.alternative_names).map { |n| n.to_s.strip }.reject(&:blank?)
      names.join(" ")
    end

    def labelled(label, values)
      list = Array(values).map { |v| v.to_s.strip }.reject(&:blank?).uniq
      return "" if list.empty?

      "#{label}: #{list.join(', ')}"
    end

    def ttb_phrase(game)
      bits = []
      bits << "main #{game.ttb_main_seconds / 3600}h" if game.ttb_main_seconds.to_i.positive?
      bits << "extras #{game.ttb_extras_seconds / 3600}h" if game.ttb_extras_seconds.to_i.positive?
      bits << "completionist #{game.ttb_completionist_seconds / 3600}h" if game.ttb_completionist_seconds.to_i.positive?
      bits.any? ? "time to beat: #{bits.join(', ')}" : ""
    end

    def rating_phrase(game)
      game.score.to_i.positive? ? "rating: #{game.score}" : ""
    end
  end
end
