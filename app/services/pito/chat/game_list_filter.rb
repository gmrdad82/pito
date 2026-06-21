# frozen_string_literal: true

module Pito
  module Chat
    # Parses a raw `list games …` body and builds a filtered Game relation.
    #
    # == Filter semantics
    #   - `upcoming` keyword (anywhere in the body) → Game.upcoming scope
    #   - genre tokens → OR within the matched genre set
    #   - platform tokens → OR within the matched platform set
    #   - AND across the three filter types
    #   - Tokens matching neither a genre alias nor a platform synonym are ignored.
    #
    # == Platform synonym map
    #   Each synonym maps to an Array of substrings that must appear (case-insensitively)
    #   in the stored platform name. A game passes the platform filter when ANY of its
    #   platform strings contains ANY of the requested substrings (OR across platforms,
    #   OR across synonyms).
    #
    # == Genre alias map
    #   Each alias maps to a substring matched case-insensitively against Genre#name.
    #   A game passes the genre filter when it has ANY genre whose name contains ANY of
    #   the requested substrings (OR across genres, OR across aliases).
    module GameListFilter
      # Substrings to match against the stored platform strings (case-insensitive).
      # One synonym key can expand to multiple match substrings (e.g. "ps" covers
      # both "PlayStation 4" and "PlayStation 5").
      PLATFORM_SYNONYMS = {
        "ps"             => %w[PlayStation],
        "playstation"    => %w[PlayStation],
        "psn"            => %w[PlayStation],
        "ps5"            => [ "PlayStation 5" ],
        "ps4"            => [ "PlayStation 4" ],
        "xbox"           => %w[Xbox],
        "microsoft"      => %w[Xbox],
        "xbs"            => [ "Xbox Series" ],
        "xb1"            => [ "Xbox One" ],
        "xbone"          => [ "Xbox One" ],
        "switch"         => [ "Nintendo Switch" ],
        "nintendo"       => %w[Nintendo],
        "pc"             => [ "PC (Microsoft Windows)", "PC" ],
        "steam"          => [ "PC (Microsoft Windows)", "PC" ],
        "windows"        => [ "PC (Microsoft Windows)" ],
        "ios"            => [ "iOS" ],
        "iphone"         => [ "iOS" ],
        "ipad"           => [ "iOS" ],
        "android"        => [ "Android" ],
        "mobile"         => %w[iOS Android],
        "arcade"         => [ "Arcade" ]
      }.freeze

      # Substrings to match against Genre#name (case-insensitive).
      GENRE_ALIASES = {
        "rpg"            => "Role-playing",
        "role-playing"   => "Role-playing",
        "shooter"        => "Shooter",
        "fps"            => "Shooter",
        "action"         => "Action",
        "adventure"      => "Adventure",
        "platform"       => "Platform",
        "platformer"     => "Platform",
        "racing"         => "Racing",
        "strategy"       => "Strategy",
        "puzzle"         => "Puzzle",
        "fighting"       => "Fighting",
        "sports"         => "Sports",
        "sport"          => "Sports",
        "simulation"     => "Simulation",
        "sim"            => "Simulation",
        "indie"          => "Indie",
        "arcade"         => "Arcade",
        "hack"           => "Hack and slash",
        "beat"           => "Hack and slash",
        "hack-and-slash" => "Hack and slash"
      }.freeze

      UPCOMING_TOKEN = "upcoming"
      NOISE_WORDS    = %w[list ls games game the a an please by ordered sorted show me].freeze

      class << self
        # Parses the raw body string and returns a filtered ActiveRecord relation.
        #
        # @param raw [String] the raw chat message body (e.g. "list games upcoming rpg ps")
        # @return [ActiveRecord::Relation]
        def call(raw)
          tokens    = tokenize(raw)
          upcoming  = tokens.delete(UPCOMING_TOKEN)
          genres    = []
          platforms = []

          tokens.each do |token|
            if (genre_sub = GENRE_ALIASES[token])
              genres << genre_sub
            elsif (plat_subs = PLATFORM_SYNONYMS[token])
              platforms.concat(plat_subs)
            end
            # unrecognised tokens are silently ignored
          end

          relation = ::Game.order(id: :desc)
          relation = relation.upcoming              if upcoming
          relation = apply_genre_filter(relation, genres.uniq) if genres.any?
          relation = apply_platform_filter(relation, platforms.uniq) if platforms.any?
          relation
        end

        # Returns true when the raw body contains any filter tokens beyond the bare
        # list/games/ls noise words. Used by the handler to pick the right empty-state.
        def filtered?(raw)
          tokens = tokenize(raw)
          return true if tokens.include?(UPCOMING_TOKEN)

          tokens.any? { |t| GENRE_ALIASES.key?(t) || PLATFORM_SYNONYMS.key?(t) }
        end

        # Tokens in `raw` that are neither noise words, `upcoming`, a genre alias,
        # nor a platform synonym — i.e. unrecognized filter terms (e.g. "asd" in
        # `list asd`). The list handler uses this to reject an unknown target
        # instead of silently falling back to the full game list.
        def unrecognized_tokens(raw)
          tokenize(raw).reject do |t|
            t == UPCOMING_TOKEN || GENRE_ALIASES.key?(t) || PLATFORM_SYNONYMS.key?(t)
          end
        end

        private

        def tokenize(raw)
          raw.to_s
             .downcase
             .split(/\s+/)
             .reject { |t| NOISE_WORDS.include?(t) }
        end

        def apply_genre_filter(relation, genre_substrings)
          # Games that have at least one matching genre (OR across substrings).
          conditions = genre_substrings.map { "genres.name ILIKE ?" }.join(" OR ")
          args       = genre_substrings.map { |s| "%#{s}%" }

          relation.joins(:genres).where(conditions, *args).distinct
        end

        def apply_platform_filter(relation, platform_substrings)
          # `platforms` is a PostgreSQL text[] column. Match any array element
          # case-insensitively via unnest. Multiple substrings → OR.
          #   EXISTS (SELECT 1 FROM unnest(games.platforms) AS p WHERE p ILIKE '%X%' OR …)
          sub_conditions = platform_substrings.map { "p ILIKE ?" }.join(" OR ")
          sql  = "EXISTS (SELECT 1 FROM unnest(games.platforms) AS p WHERE #{sub_conditions})"
          args = platform_substrings.map { |s| "%#{s}%" }
          relation.where(sql, *args)
        end
      end
    end
  end
end
