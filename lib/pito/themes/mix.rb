module Pito
  module Themes
    # Pure-Ruby sRGB hex blend helper.
    #
    # Contract
    # --------
    #   mix(a, b, t) → "#rrggbb"
    #
    # Computes a component-wise linear interpolation between two `#rrggbb` hex
    # colours:
    #
    #   result[channel] = a[channel] + (b[channel] - a[channel]) * t
    #
    # Where `t` is a Float in [0.0, 1.0]:
    #   t = 0.0 → returns `a` exactly
    #   t = 0.5 → midpoint
    #   t = 1.0 → returns `b` exactly
    #
    # This matches the CSS `color-mix(in srgb, a (1-t)*100%, b)` formula to
    # within 1 LSB per channel (rounding). It is used by `Definition` to
    # auto-derive surface/border/fg tokens from a theme's bg + fg atoms.
    module Mix
      # @param a [String] source colour "#rrggbb"
      # @param b [String] target colour "#rrggbb"
      # @param t [Float]  blend factor 0.0 (= a) … 1.0 (= b)
      # @return  [String] blended "#rrggbb"
      def self.call(a, b, t)
        raise ArgumentError, "t must be 0.0–1.0, got #{t}" unless t >= 0.0 && t <= 1.0

        ar, ag, ab = hex_to_rgb(a)
        br, bg, bb = hex_to_rgb(b)

        r = (ar + (br - ar) * t).round.clamp(0, 255)
        g = (ag + (bg - ag) * t).round.clamp(0, 255)
        b_out = (ab + (bb - ab) * t).round.clamp(0, 255)

        format("#%02x%02x%02x", r, g, b_out)
      end

      def self.hex_to_rgb(hex)
        hex = hex.delete_prefix("#")
        [ hex[0..1].to_i(16), hex[2..3].to_i(16), hex[4..5].to_i(16) ]
      end
      private_class_method :hex_to_rgb
    end
  end
end
