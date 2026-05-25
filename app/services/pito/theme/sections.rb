module Pito
  module Theme
    # 2026-05-20 — Per-section color decisions extracted from CSS to Ruby
    # so they are specced, single-source-of-truth, and can be computed
    # server-side instead of via opaque browser `color-mix()` cascades.
    #
    # 2026-05-25 — SINGLE ACCENT DECISION (historical). The user unified
    # all screen accents to one Pito purple (`#bd93f9`, Dracula Purple).
    #
    # 2026-05-26 — TOKYO NIGHT MIGRATION. Per-section accents restored with
    # Tokyo Night colors: home=blue (#7aa2f7), videos=red (#f7768e),
    # games=teal (#1abc9c). Other sections default to the blue accent.
    # The BG derivation recipe continues to work (4% accent over Tokyo
    # Night bg), now producing distinct tints per section again.
    #
    # L1 atoms (`BG`, `ACCENT`) are hand-picked per-section hex values.
    # The accent set mirrors the L2 Tokyo Night tokens that drive the
    # section accents; the bg set is the small `color-mix(in srgb, accent
    # X%, tokyo-night-bg)` tint family that used to derive at browser paint
    # time.
    #
    # `mix(accent, percent, bg)` performs the equivalent of CSS
    # `color-mix(in srgb, accent percent%, bg)` in pure Ruby so derived
    # tokens (e.g. the 35%-accent pane border) can be computed and tested
    # in isolation.
    module Sections
      # CANONICAL — Tokyo Night blue as the default accent. All section
      # lookups that don't have a specific color resolve here.
      BLUE_ACCENT = "#7aa2f7".freeze

      # L2 — section accent. Each section resolves to its Tokyo Night color.
      ACCENT = {
        "home"          => BLUE_ACCENT,
        "channels"      => BLUE_ACCENT,
        "videos"        => "#f7768e".freeze,
        "games"         => "#1abc9c".freeze,
        "projects"      => BLUE_ACCENT,
        "settings"      => BLUE_ACCENT,
        "notifications" => BLUE_ACCENT,
        "calendar"      => BLUE_ACCENT
      }.freeze

      # 2026-05-22 — Section page bg canonical recipe lock.
      #
      # The canonical visual contract for every screen's page bg is
      # `color-mix(in srgb, <section accent> 4%, <tokyo-night bg>)`. The
      # demo `tmp/dracula-swatches-v2.html` (§ B + § Section pane
      # composition) is the source of truth for the 4% lock.
      #
      # Previously this constant held hand-picked per-section hex
      # atoms that drifted from the recipe. The current set DERIVES bg
      # from the ACCENT table via the canonical 4%/Tokyo Night recipe.
      # The only override is `settings`, which the user explicitly
      # locked to `#34333b` on 2026-05-20 — a slightly warmer charcoal
      # that visually de-emphasizes the /settings screen.
      RECIPE_PCT  = 4
      TOKYO_NIGHT_BG  = "#1a1b26".freeze
      USER_LOCKED_BG = {
        "settings" => "#34333b"
      }.freeze
      BG = ACCENT.each_with_object({}) do |(section, accent_hex), acc|
        acc[section] = USER_LOCKED_BG[section] || begin
          ar = accent_hex[1..2].to_i(16)
          ag = accent_hex[3..4].to_i(16)
          ab = accent_hex[5..6].to_i(16)
          br = TOKYO_NIGHT_BG[1..2].to_i(16)
          bg_val = TOKYO_NIGHT_BG[3..4].to_i(16)
          bb = TOKYO_NIGHT_BG[5..6].to_i(16)
          ratio = RECIPE_PCT.to_f / 100.0
          r = (br + ((ar - br) * ratio)).round.clamp(0, 255)
          g = (bg_val + ((ag - bg_val) * ratio)).round.clamp(0, 255)
          b = (bb + ((ab - bb) * ratio)).round.clamp(0, 255)
          format("#%02x%02x%02x", r, g, b)
        end
      end.freeze

      # ACCENTS — canonical alias for the 3 named screen accents.
      ACCENTS = {
        home:   BLUE_ACCENT,
        videos: "#f7768e".freeze,
        games:  "#1abc9c".freeze
      }.freeze

      # Fallbacks when section is nil / unknown.
      DEFAULT_BG     = TOKYO_NIGHT_BG
      DEFAULT_ACCENT = BLUE_ACCENT

      def self.bg(section)
        BG.fetch(section.to_s, DEFAULT_BG)
      end

      def self.accent(section)
        ACCENT.fetch(section.to_s, DEFAULT_ACCENT)
      end

      # Recipe: focused-pane border = 35% accent over Tokyo Night bg.
      # Returns a CSS `color-mix()` string — safe to embed in inline styles
      # or written to `_theme.css` by the rake task.
      def self.border(section)
        "color-mix(in srgb, #{accent(section)} 35%, #{TOKYO_NIGHT_BG})"
      end

      # Recipe: row / action focus tint = 18% accent over transparent.
      # Returns a CSS `color-mix()` string.
      def self.focus_tint(section)
        "color-mix(in srgb, #{accent(section)} 18%, transparent)"
      end

      # Pure-Ruby equivalent of CSS `color-mix(in srgb, accent_hex percent%,
      # bg_hex)`. Returns a `#rrggbb` string. Component-wise linear blend
      # in the sRGB space — matches the browser's `color-mix` output to
      # within 1 LSB per channel (rounding).
      def self.mix(accent_hex, percent, bg_hex)
        raise ArgumentError, "percent must be 0-100" unless (0..100).cover?(percent)

        ar, ag, ab = hex_to_rgb(accent_hex)
        br, bg_val, bb = hex_to_rgb(bg_hex)
        ratio = percent.to_f / 100.0

        r = (br + ((ar - br) * ratio)).round.clamp(0, 255)
        g = (bg_val + ((ag - bg_val) * ratio)).round.clamp(0, 255)
        b = (bb + ((ab - bb) * ratio)).round.clamp(0, 255)

        rgb_to_hex(r, g, b)
      end

      # Derived: section pane border at 35% accent + section bg.
      # Mirrors the legacy `--color-section-border` CSS token.
      def self.section_border(section)
        mix(accent(section), 35, bg(section))
      end

      def self.hex_to_rgb(hex)
        hex = hex.delete_prefix("#")
        [ hex[0..1].to_i(16), hex[2..3].to_i(16), hex[4..5].to_i(16) ]
      end

      def self.rgb_to_hex(red, green, blue)
        format("#%02x%02x%02x", red, green, blue)
      end
    end
  end
end
