# frozen_string_literal: true

module Pito
  module Game
    # Maps IGDB platform name patterns to the three operator tokens
    # (ps / switch / steam) used throughout the app for display and sorting.
    #
    # First-match wins, so ordering matters.  Unrecognised platforms (e.g. Xbox,
    # Google Stadia, Mac) are silently dropped.
    module PlatformTokens
      module_function

      IGDB_TO_TOKEN = [
        [ /playstation|ps\s?\d/i,                          "ps"     ],
        [ /switch/i,                                       "switch" ],
        [ /steam|pc|windows|gog|epic|amazon|battle\.?net/i, "steam"  ]
      ].freeze

      # Returns the de-duped operator tokens (ps/switch/steam) derived from an
      # array of raw IGDB platform name strings.
      #
      # @param platforms [Array<String>, nil]
      # @return [Array<String>]
      def tokens(platforms)
        Array(platforms).filter_map do |name|
          _m, token = IGDB_TO_TOKEN.find { |pattern, _| name.match?(pattern) }
          token
        end.uniq
      end

      # Plain comma-joined platform display names (PlayStation / Switch / Steam).
      # Returns nil when no platform matches (e.g. empty or Xbox-only list).
      #
      # @param platforms [Array<String>, nil]
      # @return [String, nil]
      def labels(platforms)
        toks = tokens(platforms)
        return nil if toks.blank?

        toks.map { |t| I18n.t("pito.game.platform_label.#{t}") }.join(", ")
      end
    end
  end
end
