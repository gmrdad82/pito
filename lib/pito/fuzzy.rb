# frozen_string_literal: true

module Pito
  # Shared fuzzy-matching helpers (typo recovery / did-you-mean).
  #
  # Single source of truth for edit-distance, so the list-filter "did you mean"
  # suggestions and the `/resume <name>` similar-conversation suggestions use the
  # exact same algorithm.
  module Fuzzy
    module_function

    # Iterative Levenshtein edit distance (single-row DP). Case-sensitive — the
    # caller downcases when it wants case-insensitive matching.
    def levenshtein(str_a, str_b)
      str_a = str_a.to_s
      str_b = str_b.to_s
      return str_b.length if str_a.empty?
      return str_a.length if str_b.empty?

      previous = (0..str_b.length).to_a
      str_a.each_char.with_index do |char_a, i|
        current = [ i + 1 ]
        str_b.each_char.with_index do |char_b, j|
          cost = char_a == char_b ? 0 : 1
          current << [ current[j] + 1, previous[j + 1] + 1, previous[j] + cost ].min
        end
        previous = current
      end
      previous.last
    end
  end
end
