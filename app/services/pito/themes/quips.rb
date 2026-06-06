# frozen_string_literal: true

module Pito
  module Themes
    # Sampler for witty apply-confirmation quips.
    #
    # Quips live in `pito.hashtag.theme.apply.quips` (i18n array, each entry
    # interpolates `%{theme}` with the theme label). This module provides a
    # single public method that samples one interpolated string.
    #
    # Determinism in tests
    # --------------------
    # Pass `rng: Random.new(seed)` to get a reproducible sample. In production
    # the default `Random` module is used, which produces a fresh seed on each
    # invocation.
    #
    # NOTE: A centralized message-generation engine (to consolidate quips across
    # all pito responses) is tracked in docs/follow-up.md.
    module Quips
      # Return one interpolated quip string for the given theme label.
      #
      # @param label [String] the theme's display label (e.g. "Dracula")
      # @param rng   [#rand] a Random-compatible object for sampling
      # @return [String]
      def self.applied(label, rng: Random)
        entries = I18n.t("pito.hashtag.theme.apply.quips")
        entry   = entries[rng.rand(entries.size)]
        entry % { theme: label }
      end
    end
  end
end
