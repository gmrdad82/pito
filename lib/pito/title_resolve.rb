# frozen_string_literal: true

module Pito
  # The shared exact-first title-resolution ladder: free text in, at most
  # one record out. `Game.resolve_by_title` and `Video.resolve_by_title`
  # both compose this exact same ladder so a typed title means the same
  # thing everywhere — the chatbox never resolves the SAME free-text query
  # to a different record depending on which handler happened to call it.
  #
  # Numeric refs (bare ids) are NOT this mechanism's business — callers
  # resolve an id BEFORE ever reaching here. This only ever sees a title
  # string.
  #
  # Four tiers, tried in order, first non-empty tier wins:
  #
  #   1. Exact case-insensitive full-name match wins OUTRIGHT — "mortal
  #      kombat" resolves to "Mortal Kombat", never "Mortal Kombat 2" (that
  #      would only be a same-tier PREFIX match — a different, later tier).
  #   2. Else a case-insensitive PREFIX match (the query is the literal lead
  #      of the name) — "mortal" still finds "Mortal Kombat" over "Mortal
  #      Kombat 2".
  #   3. Else the best match by anchored token-run scoring — see
  #      `Pito::TitleMatch` (the proven MK2-vs-MK logic shared with
  #      `Video::GameLinkSuggester`).
  #   4. Else an acronym-of-initials match: "mk" → "Mortal Kombat", "mk2" →
  #      "Mortal Kombat 2", "kcd" → "Kingdom Come Deliverance" — see
  #      `acronym_for`. TITLE ONLY, deliberately: `alternative_names`
  #      already participates in tiers 1-2, so a game with an IGDB-recorded
  #      "MK" alias resolves there and never reaches this tier at all.
  #
  # Every tier breaks its own ties the same way: the SHORTEST name wins (the
  # most exact/specific match), so "Mortal Kombat" always wins over "Mortal
  # Kombat 2" whenever both qualify within a tier. No match at any tier →
  # nil.
  module TitleResolve
    module_function

    # `records` — an Array/Relation of candidate rows, already scoped to the
    # caller's model (and channel/library, if that scoping matters to the
    # caller). `query` — the free-text title typed by the owner. `names` — a
    # `->(record) { [...] }` proc returning every searchable name for a
    # record (title alone for a Video; title + alternative_names for a
    # Game) — the ladder itself never assumes a column exists, so a model
    # with no alt-names concept just returns `[record.title]`.
    def call(records, query, names:)
      q = query.to_s.strip
      return nil if q.blank?

      candidates = records.to_a
      return nil if candidates.empty?

      down_q = q.downcase
      exact_match(candidates, down_q, names) ||
        prefix_match(candidates, down_q, names) ||
        token_match(candidates, down_q, names) ||
        acronym_match(candidates, down_q)
    end

    def exact_match(candidates, down_q, names)
      winner(candidates) { |record| names.call(record).any? { |name| name.to_s.downcase == down_q } }
    end

    def prefix_match(candidates, down_q, names)
      winner(candidates) { |record| names.call(record).any? { |name| name.to_s.downcase.start_with?(down_q) } }
    end

    def token_match(candidates, down_q, names)
      zone_tokens = Pito::TitleMatch.tokenize(down_q)
      return nil if zone_tokens.empty?

      scored = candidates.filter_map { |record|
        score = Pito::TitleMatch.score_names(zone_tokens, names.call(record))
        [ record, score ] if score
      }
      return nil if scored.empty?

      top_score = scored.map(&:last).max
      shortest_title(scored.select { |_, score| score == top_score }.map(&:first))
    end

    # Tier 4: candidate's TITLE (never alternative_names — see the class
    # docstring) reduced to its initials-acronym equals the query outright.
    def acronym_match(candidates, down_q)
      shortest_title(candidates.select { |record| acronym_for(record.title) == down_q })
    end

    # "Mortal Kombat 2" → "mk2": first letter of every word, except a
    # standalone TRAILING numeral (a multi-word title's last token being
    # pure digits) is appended whole rather than reduced to its own first
    # digit — that's what makes "2" survive as "2" instead of collapsing
    # into a same first-letter-only initial.
    def acronym_for(title)
      words = Pito::TitleMatch.tokenize(title)
      return "" if words.empty?

      trailing_numeral = words.last if words.size > 1 && words.last.match?(/\A\d+\z/)
      letters = trailing_numeral ? words[0...-1] : words
      "#{letters.map { |word| word[0] }.join}#{trailing_numeral}"
    end

    # Filters `candidates` by the block, then breaks any tie via shortest
    # title — nil (no winner, fall through to the next tier) when nothing
    # matches at all.
    def winner(candidates)
      shortest_title(candidates.select { |record| yield record })
    end

    def shortest_title(records)
      return nil if records.empty?

      records.min_by { |record| record.title.to_s.length }
    end
  end
end
