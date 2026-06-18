# frozen_string_literal: true

module Pito
  module Game
    # Normalises free-text platform input (typed via the `platform` chat verb)
    # into a canonical stored string that MATCHES one of the
    # +Pito::Game::PlatformTokens::IGDB_TO_TOKEN+ family regexes, so the correct
    # logo renders for the game.
    #
    # Spelling variants converge to one family:
    #
    #   "ps5" / "PS5" / "PlayStation 5" / "PlayStation5" → "PlayStation 5"
    #   "ps4" / "PS 4"                                   → "PlayStation 4"
    #   "ps"  / "playstation"                           → "PlayStation"
    #   "switch" / "Nintendo Switch"                    → "Nintendo Switch"
    #   "steam" / "pc" / "windows" / "gog" / "epic"     → "PC (Steam)"
    #
    # Anything the families don't recognise (e.g. "Xbox", "Stadia") is kept as a
    # cleaned/titleized string and stored as-is — no logo, but never rejected.
    module PlatformInput
      module_function

      # PlayStation: optional "play"/"playstation"/"ps" stem, then an optional
      # console number we preserve (PS5 → "PlayStation 5").
      PLAYSTATION = /\A(?:play\s?station|ps)\s*(\d+)?\b/i
      SWITCH      = /switch|nintendo/i
      STEAM       = /steam|\bpc\b|windows|gog|epic|amazon|battle\.?net/i

      # @param raw [String, nil] free-text platform name typed by the operator.
      # @return [String] canonical stored string ("" when blank).
      def normalize(raw)
        text = raw.to_s.strip
        return "" if text.blank?

        case text
        when PLAYSTATION
          number = Regexp.last_match(1)
          number ? "PlayStation #{number}" : "PlayStation"
        when SWITCH
          "Nintendo Switch"
        when STEAM
          "PC (Steam)"
        else
          text.titleize
        end
      end
    end
  end
end
