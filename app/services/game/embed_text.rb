# frozen_string_literal: true

class Game
  # Builds the multi-field text embedded for a Game — the single
  # source of truth shared by `Game::EmbeddingIndexer` and the
  # `pito:embeddings:reindex` bulk sweep (so the per-record and bulk paths
  # can never drift).
  #
  # Fields (em-dash joined, blank slots skipped): title · alt names · genres ·
  # developer(s) · publisher(s) · platforms · time-to-beat · rating · traits ·
  # summary.
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
      parts << traits_phrase(game)
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

    # The owner's judgment ontology (games.traits jsonb; see
    # traits-design.md section 7) reaches vector search
    # through this slot alone — no structured filter, no keyword matcher.
    # Scale values render "<name> <value>" (e.g. "difficulty brutal"); tags
    # render with underscores turned to spaces so the embedder sees natural
    # words ("skill_based" -> "skill based"), which is why traits.yml names
    # every trait in full words (never abbreviations like "goty").
    #
    # Empty traits ({} — the unclassified default) return "" here, so an
    # untraited game's embed text — and therefore its embedded_digest — stays
    # BYTE-IDENTICAL to before this section existed: no mass re-embed on
    # deploy. A game only re-embeds once it first gains (or changes) traits,
    # because that changes this slot's text, which changes the digest the
    # indexers gate on — the same digest change is what lets the 02:00
    # nightly reindex (NightlyReindexJob) pick up newly classified games on
    # its own, with no force flag.
    def traits_phrase(game)
      scales = Game::Traits::Vocabulary.scale_names.filter_map do |s|
        v = game.trait_value(s)
        "#{s} #{v}" if v
      end
      tags = (Game::Traits::Vocabulary.tag_names & game.trait_tags)
        .map { |t| t.tr("_", " ") }
      list = scales + tags
      list.any? ? "traits: #{list.join(', ')}" : ""
    end
  end
end
