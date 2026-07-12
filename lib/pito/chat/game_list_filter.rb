# frozen_string_literal: true

module Pito
  module Chat
    # Parses a raw `list games …` body and builds a filtered Game relation.
    #
    # == Config-derived vocabulary, Ruby match behavior (v1.6 "one grammar")
    #   The tokens this parser accepts — every genre alias and platform synonym —
    #   come from ONE place: the `genres:` / `platforms:` vocabularies in
    #   config/pito/tools.yml (exposed via Pito::Grammar::Registry). That is the
    #   SAME vocabulary `--help`, the MCP tools, and `find` read, so there is no
    #   longer a hand-maintained filter dictionary that can drift from them.
    #
    #   What STAYS in Ruby is the match BEHAVIOR — how a canonical vocabulary
    #   MEMBER maps to the substring(s) we ILIKE against the stored genre /
    #   platform strings. MEMBER_GENRE_SUBSTRINGS / MEMBER_PLATFORM_SUBSTRINGS
    #   below are that behavior layer, keyed by canonical member name (mirroring
    #   how the list COLUMNS work: config = vocabulary, Ruby = behavior keyed by
    #   canonical name).
    #
    #   GENRE_ALIASES (token → substring String) and PLATFORM_SYNONYMS (token →
    #   substrings Array) are then DERIVED: for every config token (canonical
    #   members downcased + synonym keys) we resolve → member → its Ruby behavior.
    #   They keep their old public names + value shapes so external readers
    #   (Handlers::Show, OrdinalResolver, the dispatch matrix spec) are unchanged.
    #   The derivation is LAZY (const_missing): the vocab registry is populated in
    #   a boot `to_prepare` that runs AFTER eager load, so the maps cannot be
    #   built at class-body time — they materialize on first reference (always a
    #   request or a spec example, i.e. post-boot) and cache as frozen constants.
    #
    # == Filter semantics
    #   - `upcoming` keyword (anywhere in the body) → Game.upcoming scope
    #   - genre tokens → OR within the matched genre set
    #   - platform tokens → OR within the matched platform set
    #   - AND across the three filter types
    #   - Tokens matching no vocabulary term are ignored.
    #   Multi-word members / synonyms now exist ("series x", "playstation 5", …),
    #   so token scanning tries a two-word BIGRAM before each single word (see
    #   #walk); `list games series x` filters Xbox Series X, not the whole family.
    #
    # == Allowlist over denylist (Z36)
    #   The parser KEEPS only tokens that match a known vocabulary (genre alias,
    #   platform synonym, `upcoming`, the listable nouns, or the bare `list`/`ls`
    #   tool) and treats EVERYTHING ELSE as ignorable filler — dropped silently,
    #   never a hard rejection. There is no maintained denylist of filler words
    #   (`please`, `yo`, `thanks`, …): if a word isn't recognized vocabulary it is
    #   simply ignored. The one exception is `#suggestions`, which flags an
    #   unrecognized token that is FUZZY-CLOSE to a real vocabulary term so the
    #   handler can offer a friendly "did you mean `<x>`?".
    #
    # == Platform synonym map (derived)
    #   Each synonym maps to an Array of substrings that must appear (case-insensitively)
    #   in the stored platform name. A game passes the platform filter when ANY of its
    #   platform strings contains ANY of the requested substrings (OR across platforms,
    #   OR across synonyms).
    #
    # == Genre alias map (derived)
    #   Each alias maps to a substring matched case-insensitively against Genre#name.
    #   A game passes the genre filter when it has ANY genre whose name contains ANY of
    #   the requested substrings (OR across genres, OR across aliases).
    module GameListFilter
      # ── Ruby match-behavior layer (keyed by canonical vocabulary MEMBER) ───────

      # Canonical genre MEMBER → the substring matched (case-insensitively) against
      # Genre#name. Keyed by the exact canonical member from the :genres vocab.
      MEMBER_GENRE_SUBSTRINGS = {
        "Shooter"        => "Shooter",
        "Simulation"     => "Simulation",
        "RPG"            => "Role-playing",
        "Racing"         => "Racing",
        "Strategy"       => "Strategy",
        "Sports"         => "Sports",
        "Puzzle"         => "Puzzle",
        "Platformer"     => "Platform",
        "Fighting"       => "Fighting",
        "Adventure"      => "Adventure",
        "Action"         => "Action",
        "Indie"          => "Indie",
        "Hack and slash" => "Hack and slash"
      }.freeze

      # Canonical platform MEMBER → the Array of substrings matched against the
      # stored platform strings. One member can expand to several substrings (e.g.
      # "PC" matches both "PC (Microsoft Windows)" and a bare "PC"; the "Mobile"
      # family fans out to iOS + Android). Keyed by the exact canonical member
      # from the :platforms vocab.
      MEMBER_PLATFORM_SUBSTRINGS = {
        "PlayStation 5"   => [ "PlayStation 5" ],
        "PlayStation 4"   => [ "PlayStation 4" ],
        "PlayStation"     => [ "PlayStation" ],
        "Nintendo Switch" => [ "Nintendo Switch" ],
        "Nintendo"        => [ "Nintendo" ],
        "PC"              => [ "PC (Microsoft Windows)", "PC" ],
        "Xbox"            => [ "Xbox" ],
        "Xbox Series X"   => [ "Xbox Series X" ],
        "Xbox Series S"   => [ "Xbox Series S" ],
        "Xbox Series"     => [ "Xbox Series" ],
        "Xbox One"        => [ "Xbox One" ],
        "iOS"             => [ "iOS" ],
        "Android"         => [ "Android" ],
        "Mobile"          => [ "iOS", "Android" ]
      }.freeze

      UPCOMING_TOKEN = "upcoming"

      # The bare list tool + its short alias. Recognized so they are never read
      # as a stray/typo token (e.g. the leading word of `list rpg`).
      VERB_TOKENS = %w[list ls].freeze

      # Did-you-mean tuning. A token is offered as a correction only when it is
      # at least FUZZY_MIN_LENGTH chars (short tokens like "me"/"the"/"yo" are
      # too noisy — they sit within edit-distance 2 of real terms by accident)
      # AND within FUZZY_MAX_DISTANCE edits of a real vocabulary term.
      FUZZY_MIN_LENGTH  = 4
      FUZZY_MAX_DISTANCE = 2

      class << self
        # Materialize the derived, frozen vocabulary constants on first reference.
        # See the class comment: the config registry these read is populated at
        # boot AFTER eager load, so evaluating them at class-body time would race
        # an empty registry. Deferring to first use (a request or a spec example)
        # guarantees the vocab is present, then caches as a real frozen constant.
        def const_missing(name)
          case name
          when :GENRE_ALIASES     then const_set(name, genre_aliases)
          when :PLATFORM_SYNONYMS then const_set(name, platform_synonyms)
          else super
          end
        end

        # Parses the raw body string and returns a filtered ActiveRecord relation.
        #
        # @param raw [String] the raw chat message body (e.g. "list games upcoming rpg ps")
        # @return [ActiveRecord::Relation]
        def call(raw)
          scan     = walk(tokenize(raw))
          relation = ::Game.order(id: :desc)
          relation = relation.upcoming                                      if scan[:upcoming]
          relation = apply_genre_filter(relation, scan[:genres].uniq)       if scan[:genres].any?
          relation = apply_platform_filter(relation, scan[:platforms].uniq) if scan[:platforms].any?
          relation
        end

        # Returns true when the raw body contains any filter tokens beyond the bare
        # list/games/ls noise words. Used by the handler to pick the right empty-state.
        def filtered?(raw)
          scan = walk(tokenize(raw))
          scan[:upcoming] || scan[:genres].any? || scan[:platforms].any?
        end

        # True when the body requests upcoming games. The handler skips the
        # channel scope for these — upcoming games are unreleased, so they have no
        # game↔vid links and a channel scope would always exclude them.
        def upcoming?(raw)
          tokenize(raw).include?(UPCOMING_TOKEN)
        end

        # Did-you-mean candidates for `raw`. Each leftover token (one that matched
        # no genre/platform/`upcoming`/noun/tool and was not consumed as part of a
        # recognized bigram) that is FUZZY-CLOSE to a real vocabulary term yields
        # that term as a suggestion; tokens close to nothing are filler and
        # produce no suggestion. The list handler uses this to offer "did you mean
        # `<x>`?" instead of a flat rejection — and to decide whether to correct
        # (suggestions present) or just list (none).
        #
        # @param raw [String] the (clause-stripped) command head.
        # @return [Array<String>] unique suggested canonical terms, in first-seen order.
        def suggestions(raw)
          walk(tokenize(raw))[:leftover]
            .filter_map { |token| closest_term(token) }
            .uniq
        end

        # True when `token` is a member of the known list vocabulary — a genre
        # alias, platform synonym, `upcoming`, the tool, a listable noun, or one
        # of the individual WORDS of a multi-word member/synonym. That last case
        # matters because a bigram like `series x` is a valid filter, so its
        # component words must not be flagged as gibberish by the no-guess head
        # check even though neither word filters on its own.
        def recognized?(token)
          token = token.to_s.downcase
          genre_aliases.key?(token) ||
            platform_synonyms.key?(token) ||
            token == UPCOMING_TOKEN ||
            VERB_TOKENS.include?(token) ||
            phrase_words.include?(token) ||
            !nouns_vocab.resolve(token).nil?
        end

        private

        # ── Derived, config-sourced token maps ────────────────────────────────

        # token (String) → genre-name substring (String). Memoized frozen map.
        def genre_aliases
          @genre_aliases ||= derive_tokens(:genres, MEMBER_GENRE_SUBSTRINGS)
        end

        # token (String) → platform-name substrings (Array<String>). Memoized frozen map.
        def platform_synonyms
          @platform_synonyms ||= derive_tokens(:platforms, MEMBER_PLATFORM_SUBSTRINGS)
        end

        # Builds { token => match-behavior } for every token in the named config
        # vocabulary: each canonical member (downcased) and every synonym key is
        # resolved to its canonical member, then mapped through the Ruby behavior
        # table keyed by that member. Config is the single token source; Ruby owns
        # only the member→substring behavior. Frozen.
        def derive_tokens(vocab_name, member_behavior)
          vocab  = Pito::Grammar::Registry.vocabulary(vocab_name)
          tokens = vocab.canonical.map(&:downcase) + vocab.synonyms.keys

          tokens.uniq.each_with_object({}) do |token, map|
            member   = vocab.resolve(token)
            behavior = member && member_behavior[member]
            map[token] = behavior if behavior
          end.freeze
        end

        # ── Token scanning (bigram-aware) ──────────────────────────────────────

        # Walks the token list left-to-right, trying a two-word BIGRAM before each
        # single word so multi-word members/synonyms ("series x", "playstation 5")
        # match ahead of their component words. Returns the collected genre
        # substrings, platform substrings, an `upcoming` flag, and the `leftover`
        # single tokens that matched nothing (typo candidates for #suggestions).
        def walk(tokens)
          genres    = []
          platforms = []
          upcoming  = false
          leftover  = []
          i = 0

          while i < tokens.length
            single = tokens[i]
            bigram = (i + 1 < tokens.length) ? "#{single} #{tokens[i + 1]}" : nil

            if bigram && (subs = platform_synonyms[bigram])
              platforms.concat(subs)
              i += 2
            elsif bigram && (sub = genre_aliases[bigram])
              genres << sub
              i += 2
            elsif single == UPCOMING_TOKEN
              upcoming = true
              i += 1
            elsif (sub = genre_aliases[single])
              genres << sub
              i += 1
            elsif (subs = platform_synonyms[single])
              platforms.concat(subs)
              i += 1
            elsif VERB_TOKENS.include?(single) || !nouns_vocab.resolve(single).nil?
              # recognized tool/noun — consumed, neither a filter nor a typo.
              i += 1
            else
              leftover << single
              i += 1
            end
          end

          { genres:, platforms:, upcoming:, leftover: }
        end

        def tokenize(raw)
          raw.to_s.downcase.split(/\s+/)
        end

        # The centralized listable-noun registry (channels / vids / games + their
        # synonyms). Shared with the typeahead so an added alias propagates to
        # both the parser and the suggestions engine. See Grammar::Vocabularies.
        def nouns_vocab
          Pito::Grammar::Registry.vocabulary(:nouns)
        end

        # The individual words of every multi-word alias/synonym (e.g. "series",
        # "x", "one", "hack", "and", "slash"). Derived from the same config tokens
        # so `recognized?` treats each half of a bigram-matchable pair as known.
        def phrase_words
          @phrase_words ||= (genre_aliases.keys + platform_synonyms.keys)
            .select { |token| token.include?(" ") }
            .flat_map { |token| token.split(/\s+/) }
            .uniq
        end

        # All real vocabulary terms a typo could be corrected toward: genre
        # aliases, platform synonyms, `upcoming`, and the noun terms.
        def fuzzy_vocabulary
          @fuzzy_vocabulary ||= (
            genre_aliases.keys +
            platform_synonyms.keys +
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
