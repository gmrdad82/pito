module Pito
  module Themes
    # Pure-Ruby hex ↔ OKLCH colour conversion (Björn Ottosson's Oklab).
    #
    # Contract
    # --------
    #   from_hex("#rrggbb") → [l, c, h]
    #   to_hex(l, c, h)      → "#rrggbb"
    #   delta(from, to)      → [dl, dc, dh]
    #   apply(base, delta)   → "#rrggbb"
    #
    # `from_hex` decomposes an sRGB hex colour into OKLCH components: `l` in
    # 0..1, `c` (chroma) >= 0, `h` (hue) in degrees 0...360. Achromatic colours
    # (c < 1e-6) report h = 0.0 rather than an undefined angle.
    #
    # `to_hex` is the inverse. OKLCH covers a wider gamut than sRGB, so a given
    # (l, c, h) triple may not be displayable: when the round-trip through
    # linear RGB lands outside [0, 1] on any channel, chroma is reduced via
    # binary search (~20 iterations, `l` and `h` held fixed) until the colour
    # first falls inside sRGB gamut, then channels are rounded and clamped to
    # 0..255. This mirrors how browsers render out-of-gamut `oklch()` colours.
    #
    # `delta` and `apply` are a pair: `delta(a, b)` measures the OKLCH offset
    # from colour `a` to colour `b` (component-wise, with `dh` the signed
    # shortest-arc hue difference in (-180, 180]); `apply(base, [dl, dc, dh])`
    # re-applies that same offset onto a different base colour. Together they
    # let one theme's two "comet" animation colours be measured once and
    # re-derived onto every other theme's background, so each theme gets a
    # comet pair with the same perceptual lightness/chroma/hue relationship
    # without hand-picking colours per theme.
    module Oklch
      # @param hex [String] source colour "#rrggbb"
      # @return [Array<Float>] [l, c, h] — l in 0..1, c >= 0, h in degrees 0...360
      def self.from_hex(hex)
        r, g, b = hex_to_linear(hex)
        l, m, s = linear_to_lms(r, g, b)
        lab_l, a, lab_b = lms_to_oklab(l, m, s)

        c = Math.sqrt((a * a) + (lab_b * lab_b))
        h = c < 1e-6 ? 0.0 : normalize_degrees(Math.atan2(lab_b, a) * 180.0 / Math::PI)

        [ lab_l, c, h ]
      end

      # @param l [Float] lightness 0..1
      # @param c [Float] chroma >= 0
      # @param h [Float] hue in degrees
      # @return [String] "#rrggbb", chroma-reduced to fit sRGB gamut if needed
      def self.to_hex(l, c, h)
        fitted_c = fit_chroma(l, c, h)
        r, g, b = oklch_to_linear(l, fitted_c, h)
        to_srgb_hex(r, g, b)
      end

      # @param from_hex_val [String] "#rrggbb"
      # @param to_hex_val [String] "#rrggbb"
      # @return [Array<Float>] [dl, dc, dh] component deltas (to - from); dh is
      #   the signed shortest-arc hue difference in (-180, 180]
      def self.delta(from_hex_val, to_hex_val)
        fl, fc, fh = from_hex(from_hex_val)
        tl, tc, th = from_hex(to_hex_val)

        [ tl - fl, tc - fc, hue_delta(fh, th) ]
      end

      # @param base_hex [String] "#rrggbb"
      # @param delta [Array<Float>] [dl, dc, dh] as returned by `delta`
      # @return [String] "#rrggbb"
      def self.apply(base_hex, delta)
        l, c, h = from_hex(base_hex)
        dl, dc, dh = delta

        new_l = (l + dl).clamp(0.0, 1.0)
        new_c = [ c + dc, 0.0 ].max
        new_h = normalize_degrees(h + dh)

        to_hex(new_l, new_c, new_h)
      end

      def self.hex_to_linear(hex)
        hex = hex.delete_prefix("#")
        [ hex[0..1].to_i(16), hex[2..3].to_i(16), hex[4..5].to_i(16) ].map do |channel|
          srgb_to_linear(channel / 255.0)
        end
      end
      private_class_method :hex_to_linear

      def self.srgb_to_linear(v)
        v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055)**2.4
      end
      private_class_method :srgb_to_linear

      def self.linear_to_srgb(v)
        v <= 0.0031308 ? 12.92 * v : (1.055 * (v**(1.0 / 2.4))) - 0.055
      end
      private_class_method :linear_to_srgb

      def self.linear_to_lms(r, g, b)
        l = (0.4122214708 * r) + (0.5363325363 * g) + (0.0514459929 * b)
        m = (0.2119034982 * r) + (0.6806995451 * g) + (0.1073969566 * b)
        s = (0.0883024619 * r) + (0.2817188376 * g) + (0.6299787005 * b)
        [ l, m, s ]
      end
      private_class_method :linear_to_lms

      def self.lms_to_oklab(l, m, s)
        l_ = Math.cbrt(l)
        m_ = Math.cbrt(m)
        s_ = Math.cbrt(s)

        lab_l = (0.2104542553 * l_) + (0.7936177850 * m_) - (0.0040720468 * s_)
        a = (1.9779984951 * l_) - (2.4285922050 * m_) + (0.4505937099 * s_)
        b = (0.0259040371 * l_) + (0.7827717662 * m_) - (0.8086757660 * s_)

        [ lab_l, a, b ]
      end
      private_class_method :lms_to_oklab

      def self.oklch_to_linear(l, c, h)
        h_rad = h * Math::PI / 180.0
        a = c * Math.cos(h_rad)
        b = c * Math.sin(h_rad)

        l_ = l + (0.3963377774 * a) + (0.2158037573 * b)
        m_ = l - (0.1055613458 * a) - (0.0638541728 * b)
        s_ = l - (0.0894841775 * a) - (1.2914855480 * b)

        ll = l_**3
        mm = m_**3
        ss = s_**3

        r = (4.0767416621 * ll) - (3.3077115913 * mm) + (0.2309699292 * ss)
        g = (-1.2684380046 * ll) + (2.6097574011 * mm) - (0.3413193965 * ss)
        b_out = (-0.0041960863 * ll) - (0.7034186147 * mm) + (1.7076147010 * ss)

        [ r, g, b_out ]
      end
      private_class_method :oklch_to_linear

      def self.in_gamut?(r, g, b, epsilon: 1e-6)
        [ r, g, b ].all? { |v| v >= -epsilon && v <= 1.0 + epsilon }
      end
      private_class_method :in_gamut?

      def self.fit_chroma(l, c, h)
        r, g, b = oklch_to_linear(l, c, h)
        return c if in_gamut?(r, g, b)

        low = 0.0
        high = c

        20.times do
          mid = (low + high) / 2.0
          mr, mg, mb = oklch_to_linear(l, mid, h)

          if in_gamut?(mr, mg, mb)
            low = mid
          else
            high = mid
          end
        end

        low
      end
      private_class_method :fit_chroma

      def self.to_srgb_hex(r, g, b)
        channels = [ r, g, b ].map do |v|
          (linear_to_srgb(v) * 255.0).round.clamp(0, 255)
        end

        format("#%02x%02x%02x", *channels)
      end
      private_class_method :to_srgb_hex

      def self.normalize_degrees(h)
        h % 360.0
      end
      private_class_method :normalize_degrees

      def self.hue_delta(from_h, to_h)
        diff = (to_h - from_h) % 360.0
        diff > 180.0 ? diff - 360.0 : diff
      end
      private_class_method :hue_delta
    end
  end
end
