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
    # == Allowlist over denylist (Z36)
    #   The parser KEEPS only tokens that match a known vocabulary (genre alias,
    #   platform synonym, `upcoming`, the listable nouns, or the bare `list`/`ls`
    #   verb) and treats EVERYTHING ELSE as ignorable filler — dropped silently,
    #   never a hard rejection. There is no maintained denylist of filler words
    #   (`please`, `yo`, `thanks`, …): if a word isn't recognized vocabulary it is
    #   simply ignored. The one exception is `#suggestions`, which flags an
    #   unrecognized token that is FUZZY-CLOSE to a real vocabulary term so the
    #   handler can offer a friendly "did you mean `<x>`?".
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

      # The bare list verb + its short alias. Recognized so they are never read
      # as a stray/typo token (e.g. the leading word of `list rpg`).
      VERB_TOKENS = %w[list ls].freeze

      # Did-you-mean tuning. A token is offered as a correction only when it is
      # at least FUZZY_MIN_LENGTH chars (short tokens like "me"/"the"/"yo" are
      # too noisy — they sit within edit-distance 2 of real terms by accident)
      # AND within FUZZY_MAX_DISTANCE edits of a real vocabulary term.
      FUZZY_MIN_LENGTH  = 4
      FUZZY_MAX_DISTANCE = 2

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

        # True when the body requests upcoming games. The handler skips the
        # channel scope for these — upcoming games are unreleased, so they have no
        # game↔vid links and a channel scope would always exclude them.
        def upcoming?(raw)
          tokenize(raw).include?(UPCOMING_TOKEN)
        end

        # Did-you-mean candidates for `raw`. Each unrecognized token (not a known
        # genre/platform/`upcoming`/noun/verb) that is FUZZY-CLOSE to a real
        # vocabulary term yields that term as a suggestion; tokens that are close
        # to nothing are filler and produce no suggestion. The list handler uses
        # this to offer "did you mean `<x>`?" instead of a flat rejection — and to
        # decide whether to correct (suggestions present) or just list (none).
        #
        # @param raw [String] the (clause-stripped) command head.
        # @return [Array<String>] unique suggested canonical terms, in first-seen order.
        def suggestions(raw)
          tokenize(raw)
            .reject { |t| recognized?(t) }
            .filter_map { |t| closest_term(t) }
            .uniq
        end

        # True when `token` is a member of the known list vocabulary — a genre
        # alias, platform synonym, `upcoming`, the verb, or a listable noun. Such
        # tokens are kept by the parser and never offered as a typo correction.
        def recognized?(token)
          GENRE_ALIASES.key?(token) ||
            PLATFORM_SYNONYMS.key?(token) ||
            token == UPCOMING_TOKEN ||
            VERB_TOKENS.include?(token) ||
            !nouns_vocab.resolve(token).nil?
        end

        private

        def tokenize(raw)
          raw.to_s.downcase.split(/\s+/)
        end

        # The centralized listable-noun registry (channels / vids / games + their
        # synonyms). Shared with the typeahead so an added alias propagates to
        # both the parser and the suggestions engine. See Grammar::Vocabularies.
        def nouns_vocab
          Pito::Grammar::Registry.vocabulary(:nouns)
        end

        # All real vocabulary terms a typo could be corrected toward: genre
        # aliases, platform synonyms, `upcoming`, and the noun terms.
        def fuzzy_vocabulary
          @fuzzy_vocabulary ||= (
            GENRE_ALIASES.keys +
            PLATFORM_SYNONYMS.keys +
            [ UPCOMING_TOKEN ] +
            nouns_vocab.canonical +
            nouns_vocab.synonyms.keys
          ).map(&:downcase).uniq
        end

        # The closest vocabulary term to `token` within the fuzzy threshold, or
        # nil when the token is too short or close to nothing (i.e. it's filler).
        def closest_term(token)
          return nil if token.length < FUZZY_MIN_LENGTH

          best, best_distance = nil, FUZZY_MAX_DISTANCE + 1
          fuzzy_vocabulary.each do |term|
            next if (token.length - term.length).abs > FUZZY_MAX_DISTANCE

            distance = levenshtein(token, term)
            best, best_distance = term, distance if distance < best_distance
          end

          best_distance <= FUZZY_MAX_DISTANCE ? best : nil
        end

        # Edit distance via the shared Pito::Fuzzy.levenshtein — single source of
        # truth, also used by Conversation#similar_titles (`/resume` typo recovery).
        def levenshtein(str_a, str_b)
          Pito::Fuzzy.levenshtein(str_a, str_b)
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
