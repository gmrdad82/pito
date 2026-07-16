# frozen_string_literal: true

module Pito
  # Shared token-anchored title-scoring primitives — the proven MK2-vs-MK
  # logic, lifted out of `Video::GameLinkSuggester` so every consumer scores
  # a free-text zone against a candidate's name(s) identically instead of
  # reimplementing the same DP by hand.
  #
  # Tokenize a string, then score how well a candidate's name(s) overlap a
  # "zone" (the text being matched against) via the longest contiguous
  # (order-preserving) token run, with an anchor bonus when the name's run
  # starts at the very front of the zone rather than somewhere in the
  # middle — a run anchored at the start outranks an equal-or-longer run
  # found mid-zone (see `score_name`).
  #
  # Reused by:
  #   - `Video::GameLinkSuggester` — unlinked-video → library-game nudges.
  #   - `Pito::TitleResolve` — the Game/Video free-text title-resolution
  #     ladder's tier-3 fallback.
  module TitleMatch
    module_function

    TOKEN_PATTERN = /[a-z0-9]+/

    def tokenize(text)
      text.to_s.downcase.scan(TOKEN_PATTERN)
    end

    # Best `[anchor_flag, run_length]` score of `zone_tokens` against ANY of
    # `names` (raw strings — e.g. a game's title + alternative_names), or nil
    # when nothing overlaps at all. The pair compares lexicographically, so
    # any anchored match beats every non-anchored match regardless of raw
    # run length.
    def score_names(zone_tokens, names)
      Array(names).filter_map { |name| score_name(zone_tokens, tokenize(name)) }.max
    end

    def score_name(zone_tokens, name_tokens)
      return nil if name_tokens.empty?

      run = longest_common_run(zone_tokens, name_tokens)
      return nil if run.zero?

      anchored = name_tokens == zone_tokens.first(name_tokens.size)
      [ anchored ? 1 : 0, run ]
    end

    # Longest contiguous (order-preserving) token run shared by both token
    # lists — classic longest-common-substring DP over the token arrays
    # instead of characters.
    def longest_common_run(zone_tokens, name_tokens)
      previous_row = Array.new(name_tokens.size + 1, 0)
      best = 0

      zone_tokens.each do |zone_token|
        current_row = Array.new(name_tokens.size + 1, 0)
        name_tokens.each_with_index do |name_token, j|
          next unless zone_token == name_token

          current_row[j + 1] = previous_row[j] + 1
          best = current_row[j + 1] if current_row[j + 1] > best
        end
        previous_row = current_row
      end

      best
    end
  end
end
