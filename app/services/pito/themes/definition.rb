require_relative "mix"

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
    # Resolved tokens
    # ---------------
    # `tokens` is a Hash with Symbol keys:
    #   bg_root, bg_surface, bg_elevated,
    #   border_default, border_faded,
    #   fg_default, fg_dim, fg_faded,
    #   accent_purple, accent_blue, accent_cyan, accent_green,
    #   accent_yellow, accent_orange, accent_red,
    #   brand_pito
    class Definition
      BRAND_PITO = "#5170ff"

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
          brand_pito:     BRAND_PITO
        }

        new(slug: slug, label: label, mode: mode, tokens: tokens)
      end
    end
  end
end
