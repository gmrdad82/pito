module Pito
  module Theme
    # 2026-05-20 — Per-section color decisions extracted from CSS to Ruby
    # so they are specced, single-source-of-truth, and can be computed
    # server-side instead of via opaque browser `color-mix()` cascades.
    #
    # L1 atoms (`BG`, `ACCENT`) are hand-picked per-section hex values.
    # The accent set mirrors the L2 Dracula tokens that used to drive the
    # `body[data-section]` cascade in `app/assets/tailwind/application.css`;
    # the bg set is the small `color-mix(in srgb, accent X%, dracula-bg)`
    # tint family that used to derive at browser paint time.
    #
    # `mix(accent, percent, bg)` performs the equivalent of CSS
    # `color-mix(in srgb, accent percent%, bg)` in pure Ruby so derived
    # tokens (e.g. the 35%-accent pane border) can be computed and tested
    # in isolation.
    module Sections
      # L1 atoms — hand-picked per-section page background.
      # `settings` is user-locked 2026-05-20 to #34333b; the other sections
      # are placeholders until the user locks per-section bgs.
      BG = {
        "home"          => "#2c2a36",
        "channels"      => "#36292d",
        "videos"        => "#36292d",
        "games"         => "#292c33",
        "projects"      => "#292c33",
        "settings"      => "#34333b",
        "notifications" => "#2c2a36",
        "calendar"      => "#2c2a36"
      }.freeze

      # L2 — section accent. Cascade source for `--section-accent` /
      # `--color-section-accent`. Values mirror the Dracula L2 tokens
      # declared in `app/assets/tailwind/application.css`.
      ACCENT = {
        "home"          => "#bd93f9", # Dracula Purple
        "channels"      => "#ff5555", # Dracula Red
        "videos"        => "#ff5555",
        "games"         => "#7eb6ff", # Pale Cobalt
        "projects"      => "#7eb6ff",
        "settings"      => "#ffb86c", # Dracula Orange
        "notifications" => "#bd93f9",
        "calendar"      => "#bd93f9"
      }.freeze

      # ACCENTS — canonical alias for the 3 named screen accents referenced in
      # `tmp/dracula-swatches-v2.html` § B (Section mapping). Delegates to the
      # full ACCENT table so there is a single hex source of truth.
      ACCENTS = {
        home:   ACCENT.fetch("home"),   # Dracula Purple
        videos: ACCENT.fetch("videos"), # Dracula Red
        games:  ACCENT.fetch("games")   # Pale Cobalt
      }.freeze

      # Dracula bg — base for recipe-derived CSS color-mix() tokens.
      DRACULA_BG = "#282a36".freeze

      # Fallbacks when section is nil / unknown.
      DEFAULT_BG     = DRACULA_BG
      DEFAULT_ACCENT = "#bd93f9" # Dracula Purple

      def self.bg(section)
        BG.fetch(section.to_s, DEFAULT_BG)
      end

      def self.accent(section)
        ACCENT.fetch(section.to_s, DEFAULT_ACCENT)
      end

      # Recipe: focused-pane border = 35% accent over Dracula bg.
      # Returns a CSS `color-mix()` string — safe to embed in inline styles
      # or written to `_theme.css` by the rake task.
      def self.border(section)
        "color-mix(in srgb, #{accent(section)} 35%, #{DRACULA_BG})"
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
