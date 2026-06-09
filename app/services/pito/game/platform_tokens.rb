# frozen_string_literal: true

module Pito
  module Game
    # Maps IGDB platform name patterns to the three operator tokens
    # (ps / switch / steam) used throughout the app for display and sorting.
    #
    # This module is the SINGLE SOURCE OF TRUTH for all platform output.
    # It decides whether to emit plain text labels (via +labels+) or SVG logo
    # HTML (via +icons_html+).  Raw IGDB data is stored unchanged; only display
    # normalises to these three tokens.
    #
    # First-match wins, so ordering matters.  Unrecognised platforms (e.g. Xbox,
    # Google Stadia, Mac) are silently dropped.
    module PlatformTokens
      module_function

      IGDB_TO_TOKEN = [
        [ /playstation|ps\s?\d/i,                           "ps"     ],
        [ /switch/i,                                        "switch" ],
        [ /steam|pc|windows|gog|epic|amazon|battle\.?net/i, "steam"  ]
      ].freeze

      # Canonical display order: PS → Switch → Steam.
      ORDER = %w[ps switch steam].freeze

      # Token → display metadata (label text + SVG src path).
      META = {
        "ps"     => { label: "PlayStation", src: "/platforms/playstation.svg" },
        "switch" => { label: "Switch",       src: "/platforms/switch.svg"      },
        "steam"  => { label: "Steam",        src: "/platforms/steam.svg"       }
      }.freeze

      # Returns the de-duped operator tokens (ps/switch/steam) derived from an
      # array of raw IGDB platform name strings, always in PS → Switch → Steam
      # order regardless of the input order.
      #
      # @param platforms [Array<String>, nil]
      # @return [Array<String>]
      def tokens(platforms)
        raw = Array(platforms).filter_map do |name|
          _m, token = IGDB_TO_TOKEN.find { |pattern, _| name.match?(pattern) }
          token
        end.uniq
        raw.sort_by { |t| ORDER.index(t) || ORDER.size }
      end

      # Plain comma-joined platform display names (PlayStation / Switch / Steam),
      # always in ORDER.
      # Returns nil when no platform matches (e.g. empty or Xbox-only list).
      #
      # @param platforms [Array<String>, nil]
      # @return [String, nil]
      def labels(platforms)
        toks = tokens(platforms)
        return nil if toks.blank?

        toks.map { |t| I18n.t("pito.game.platform_label.#{t}") }.join(", ")
      end

      # Returns an html_safe String containing inline SVG logo <img> tags for
      # the matched tokens, wrapped in a <span class="pito-platform-icons">.
      # Returns "".html_safe when no tokens match.
      #
      # Icons are always emitted in ORDER (PS → Switch → Steam).
      #
      # @param platforms [Array<String>, nil]
      # @return [ActiveSupport::SafeBuffer]
      def icons_html(platforms)
        toks = tokens(platforms)
        return "".html_safe if toks.blank?

        imgs = toks.map do |t|
          meta  = META[t]
          label = ERB::Util.html_escape(meta[:label])
          src   = ERB::Util.html_escape(meta[:src])
          %(<img class="pito-platform-icon" src="#{src}" alt="#{label}" title="#{label}" loading="lazy">)
        end.join

        %(<span class="pito-platform-icons">#{imgs}</span>).html_safe
      end
    end
  end
end
