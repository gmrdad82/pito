# frozen_string_literal: true

module Pito
  module Game
    # Maps IGDB platform name patterns to the four operator tokens
    # (ps / switch / xbox / steam) used throughout the app for display and sorting.
    #
    # This module is the SINGLE SOURCE OF TRUTH for all platform output.
    # It decides whether to emit plain text labels (via +labels+) or SVG logo
    # HTML (via +icons_html+).  Raw IGDB data is stored unchanged; only display
    # normalises to these four tokens.
    #
    # First-match wins, so ordering matters.  Each token catches a whole FAMILY
    # of IGDB platforms (ps → PS4/PS5/…, xbox → Xbox One/Series X|S/360/…).
    # Unrecognised platforms (e.g. Google Stadia, Mac) are silently dropped.
    module PlatformTokens
      module_function

      IGDB_TO_TOKEN = [
        [ /playstation|ps\s?\d/i,                           "ps"     ],
        [ /switch/i,                                        "switch" ],
        [ /xbox|x-?box/i,                                   "xbox"   ],
        [ /steam|pc|windows|gog|epic|amazon|battle\.?net/i, "steam"  ]
      ].freeze

      # Canonical display order: PS → Switch → Xbox → Steam.
      ORDER = %w[ps switch xbox steam].freeze

      # Token → display metadata (label text + SVG src path).
      META = {
        "ps"     => { label: "PlayStation", src: "/platforms/playstation.svg" },
        "switch" => { label: "Switch",       src: "/platforms/switch.svg"      },
        "xbox"   => { label: "Xbox",         src: "/platforms/xbox.svg"        },
        "steam"  => { label: "Steam",        src: "/platforms/steam.svg"       }
      }.freeze

      # Returns the de-duped operator tokens (ps/switch/xbox/steam) derived from an
      # array of raw IGDB platform name strings, always in PS → Switch → Xbox → Steam
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
      # the platforms' matched tokens, wrapped in a <span class="pito-platform-icons">.
      # Returns "".html_safe when no tokens match.
      #
      # Icons are always emitted in ORDER (PS → Switch → Xbox → Steam).
      #
      # @param platforms [Array<String>, nil]
      # @return [ActiveSupport::SafeBuffer]
      def icons_html(platforms)
        icons_html_for_tokens(tokens(platforms))
      end

      # Same, but from an already-resolved token list (ps/switch/xbox/steam) —
      # used by the per-platform release display (Item 24). Unknown tokens are
      # dropped; output is always in ORDER.
      #
      # @param toks [Array<String>, nil]
      # @return [ActiveSupport::SafeBuffer]
      def icons_html_for_tokens(toks)
        toks = Array(toks).select { |t| META.key?(t) }.uniq.sort_by { |t| ORDER.index(t) }
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
