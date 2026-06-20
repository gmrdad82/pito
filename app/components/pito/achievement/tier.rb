# frozen_string_literal: true

module Pito
  module Achievement
    # Shared tier data for the achievement subsystem.
    #
    # Exposes the canonical 22-step milestone series and maps each threshold to
    # its display tier token string.  Both BadgeComponent and TrackComponent
    # delegate here — the mapping must never be duplicated.
    #
    # Usage:
    #   Pito::Achievement::Tier::SERIES      # => [1, 2, 5, 10, …, 10_000_000]
    #   Pito::Achievement::Tier.token_for(1_000)  # => "blue"
    module Tier
      SERIES = [
        1, 2, 5,
        10, 20, 50,
        100, 200, 500,
        1_000, 2_000, 5_000,
        10_000, 20_000, 50_000,
        100_000, 200_000, 500_000,
        1_000_000, 2_000_000, 5_000_000,
        10_000_000
      ].freeze

      TOKENS = {
                1 => "muted",    2 => "muted",    5 => "muted",
               10 => "green",   20 => "green",   50 => "green",
              100 => "cyan",   200 => "cyan",   500 => "cyan",
            1_000 => "blue",  2_000 => "blue",  5_000 => "blue",
           10_000 => "purple", 20_000 => "purple", 50_000 => "purple",
          100_000 => "orange", 200_000 => "orange", 500_000 => "orange",
        1_000_000 => "yellow", 2_000_000 => "yellow", 5_000_000 => "yellow",
       10_000_000 => "pito"
      }.freeze

      module_function

      # Returns the display tier token string for +threshold+.
      # Raises +KeyError+ if +threshold+ is not in the series.
      def token_for(threshold)
        TOKENS.fetch(threshold)
      end
    end
  end
end
