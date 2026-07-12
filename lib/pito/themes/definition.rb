require_relative "mix"
require_relative "oklch"

module Pito
  module Themes
    # Immutable value object describing a fully-resolved theme.
    #
    # Construction
    # ------------
    # Build via `Definition.from_raw(hash)` where `hash` is:
    #
    #   {
    #     slug:  String,           # e.g. "tokyo-night"
    #     label: String,           # e.g. "Tokyo Night"
    #     mode:  :dark | :light,
    #     base: {
    #       bg:     "#rrggbb",     # bg_root
    #       fg:     "#rrggbb",     # fg_default
    #       purple: "#rrggbb",     # accent_purple
    #       blue:   "#rrggbb",     # accent_blue
    #       cyan:   "#rrggbb",     # accent_cyan
    #       green:  "#rrggbb",     # accent_green
    #       yellow: "#rrggbb",     # accent_yellow
    #       orange: "#rrggbb",     # accent_orange
    #       red:    "#rrggbb",     # accent_red
    #     },
    #     overrides: {             # optional; any derived or base key
    #       surface:       "#rrggbb",
    #       elevated:      "#rrggbb",
    #       border_default:"#rrggbb",
    #       border_faded:  "#rrggbb",
    #       fg_dim:        "#rrggbb",
    #       fg_faded:      "#rrggbb",
    #       comet_a:       "#rrggbb",   # loading-dot pair (see below)
    #       comet_b:       "#rrggbb",
    #     }
    #   }
    #
    # Token derivation (mode-agnostic, all via Mix)
    # ----------------------------------------------
    # Let bg = base[:bg], fg = base[:fg]:
    #
    #   bg_surface      = mix(bg, fg, 0.06)
    #   bg_elevated     = mix(bg, fg, 0.12)
    #   border_default  = mix(bg, fg, 0.16)
    #   border_faded    = mix(bg, fg, 0.28)
    #   fg_dim          = mix(fg, bg, 0.40)
    #   fg_faded        = mix(fg, bg, 0.60)
    #
    # Any key listed in `overrides:` replaces the derived value.
    # `brand_pito` is always `#5170ff` (constant, not part of theme data).
    #
    # Comet pair (loading-dot animation colours)
    # -------------------------------------------
    # Synthwave's purple→pito-blue comet is the reference look. Rather than
    # hand-picking a pair per theme, the OKLCH offsets from Synthwave's bg to
    # each of its two comet colours are measured once (COMET_A_DELTA /
    # COMET_B_DELTA) and re-applied to every theme's own bg_root — each theme
    # gets a pair with the same perceptual lightness/chroma/hue relationship
    # to its background. Two corrections keep the derivation sane at the
    # edges: LIGHT themes subtract the lightness offset instead of adding it
    # (a near-white bg plus +0.48 L pins at white — invisible dots), and a
    # (near-)NEUTRAL bg (chroma < COMET_NEUTRAL_CHROMA, greys/whites) falls
    # back to the anchor pair's ABSOLUTE hues — a hue offset from an
    # achromatic base is noise, and those themes get the classic purple/blue.
    # Tinted backgrounds carry their tint into the pair (solarized → teal).
    # Synthwave itself resolves back to exactly #b967ff / #5170ff. A
    # definition may override the pair explicitly via
    # `overrides: { comet_a:, comet_b: }`.
    #
    # Resolved tokens
    # ---------------
    # `tokens` is a Hash with Symbol keys:
    #   bg_root, bg_surface, bg_elevated,
    #   border_default, border_faded,
    #   fg_default, fg_dim, fg_faded,
    #   accent_purple, accent_blue, accent_cyan, accent_green,
    #   accent_yellow, accent_orange, accent_red,
    #   brand_pito, comet_a, comet_b
    class Definition
      BRAND_PITO = "#5170ff"

      # The Synthwave anchor: its bg and the two comet colours the owner
      # signed off on. The deltas are computed once at load and applied to
      # every theme's bg_root (see class doc); the absolute hues are the
      # neutral-background fallback.
      COMET_ANCHOR_BG = "#1a0b2e"
      COMET_A_COLOR   = "#b967ff" # Synthwave's accent purple
      COMET_A_DELTA   = Oklch.delta(COMET_ANCHOR_BG, COMET_A_COLOR).freeze
      COMET_B_DELTA   = Oklch.delta(COMET_ANCHOR_BG, BRAND_PITO).freeze
      COMET_A_HUE     = Oklch.from_hex(COMET_A_COLOR)[2]
      COMET_B_HUE     = Oklch.from_hex(BRAND_PITO)[2]

      # Below this bg chroma the background counts as neutral (hue is noise).
      COMET_NEUTRAL_CHROMA = 0.02

      # Derivation blend factors (bg → fg direction unless noted)
      DERIVE = {
        bg_surface:     [ :bg_to_fg, 0.06 ],
        bg_elevated:    [ :bg_to_fg, 0.12 ],
        border_default: [ :bg_to_fg, 0.16 ],
        border_faded:   [ :bg_to_fg, 0.28 ],
        fg_dim:         [ :fg_to_bg, 0.40 ],
        fg_faded:       [ :fg_to_bg, 0.60 ]
      }.freeze

      attr_reader :slug, :label, :mode, :tokens

      def initialize(slug:, label:, mode:, tokens:)
        @slug   = slug.freeze
        @label  = label.freeze
        @mode   = mode
        @tokens = tokens.freeze
        freeze
      end

      def self.from_raw(raw)
        slug  = raw.fetch(:slug)
        label = raw.fetch(:label)
        mode  = raw.fetch(:mode)
        base  = raw.fetch(:base)
        overrides = raw.fetch(:overrides, {})

        bg = base.fetch(:bg)
        fg = base.fetch(:fg)

        derived = DERIVE.transform_values do |spec|
          direction, t = spec
          case direction
          when :bg_to_fg then Mix.call(bg, fg, t)
          when :fg_to_bg then Mix.call(fg, bg, t)
          end
        end

        # Override key aliases: definition files may use short keys
        # (surface:, elevated:) or full keys (bg_surface:, bg_elevated:).
        override_map = {
          surface:        :bg_surface,
          elevated:       :bg_elevated,
          border_default: :border_default,
          border_faded:   :border_faded,
          fg_dim:         :fg_dim,
          fg_faded:       :fg_faded
        }

        override_map.each do |short, full|
          next unless overrides.key?(short)
          derived[full] = overrides[short]
        end
        # Also accept full-key overrides directly
        derived.each_key do |full|
          derived[full] = overrides[full] if overrides.key?(full)
        end

        tokens = {
          bg_root:        bg,
          bg_surface:     derived[:bg_surface],
          bg_elevated:    derived[:bg_elevated],
          border_default: derived[:border_default],
          border_faded:   derived[:border_faded],
          fg_default:     fg,
          fg_dim:         derived[:fg_dim],
          fg_faded:       derived[:fg_faded],
          accent_purple:  base.fetch(:purple),
          accent_blue:    base.fetch(:blue),
          accent_cyan:    base.fetch(:cyan),
          accent_green:   base.fetch(:green),
          accent_yellow:  base.fetch(:yellow),
          accent_orange:  base.fetch(:orange),
          accent_red:     base.fetch(:red),
          brand_pito:     BRAND_PITO,
          comet_a:        overrides.fetch(:comet_a) { comet_color(bg, mode, COMET_A_DELTA, COMET_A_HUE) },
          comet_b:        overrides.fetch(:comet_b) { comet_color(bg, mode, COMET_B_DELTA, COMET_B_HUE) }
        }

        new(slug: slug, label: label, mode: mode, tokens: tokens)
      end

      # One comet colour from a theme's bg: the anchor delta re-applied with
      # the light-mode lightness flip and the neutral-bg absolute-hue
      # fallback (see the "Comet pair" section of the class doc). to_hex
      # gamut-clamps by reducing chroma, so the result is always displayable.
      def self.comet_color(bg, mode, delta, fallback_hue)
        l, c, h = Oklch.from_hex(bg)
        dl, dc, dh = delta

        lightness = (mode == :light ? l - dl : l + dl).clamp(0.0, 1.0)
        hue       = c < COMET_NEUTRAL_CHROMA ? fallback_hue : (h + dh) % 360.0
        Oklch.to_hex(lightness, [ c + dc, 0.0 ].max, hue)
      end
      private_class_method :comet_color
    end
  end
end
