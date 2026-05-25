module Pito
  module Theme
    # 2026-05-20 — Per-section color decisions extracted from CSS to Ruby
    # so they are specced, single-source-of-truth, and can be computed
    # server-side instead of via opaque browser `color-mix()` cascades.
    #
    # 2026-05-25 — SINGLE ACCENT DECISION. The user unified all screen
    # accents to one Pito purple (`#bd93f9`, Dracula Purple). The
    # per-section accent map below is DEPRECATED — every entry now resolves
    # to the same purple. `ACCENT`, `accent(section)`, and the BG derivation
    # still function (bg tints still differ slightly because different
    # sections historically had different accents feeding the 4% recipe, but
    # all entries now share the same purple input). The per-section CSS
    # cascade (`body[data-section]` overrides) has been dropped from
    # `application.css`; `--section-accent` is a single `:root` value.
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
      # CANONICAL — single Pito purple accent. All section lookups resolve here.
      PITO_PURPLE = "#bd93f9".freeze # Dracula Purple

      # L2 — section accent. DEPRECATED: all entries now resolve to PITO_PURPLE.
      # Kept for backwards-compatibility with callers that pass a section key;
      # the cascade source is `--section-accent: #bd93f9` in `:root`.
      ACCENT = {
        "home"          => PITO_PURPLE,
        "channels"      => PITO_PURPLE,
        "videos"        => PITO_PURPLE,
        "games"         => PITO_PURPLE,
        "projects"      => PITO_PURPLE,
        "settings"      => PITO_PURPLE,
        "notifications" => PITO_PURPLE,
        "calendar"      => PITO_PURPLE
      }.freeze

      # 2026-05-22 — Section page bg canonical recipe lock.
      #
      # The canonical visual contract for every screen's page bg is
      # `color-mix(in srgb, <section accent> 4%, <dracula bg>)`. The
      # demo `tmp/dracula-swatches-v2.html` (§ B + § Section pane
      # composition) is the source of truth for the 4% lock.
      #
      # Previously this constant held hand-picked per-section hex
      # atoms that drifted from the recipe (e.g. home = #2c2a36,
      # which is only ~1% purple — visibly washed-out vs the
      # canonical #2e2e3e). The drift surfaced in the
      # `body[data-section] style="background: <hex>;"` inline that
      # the layout writes via `pito_section_bg`, so the live page bg
      # diverged from the demo and from the in-CSS
      # `--color-bg-tint = color-mix(... 4% ...)` recipe.
      #
      # The current set DERIVES bg from the ACCENT table via the
      # canonical 4%/Dracula recipe. The only override is `settings`,
      # which the user explicitly locked to `#34333b` on 2026-05-20
      # — a slightly warmer charcoal that visually de-emphasizes the
      # /settings screen vs the orange accent's 4% tint.
      RECIPE_PCT  = 4
      DRACULA_BG  = "#282a36".freeze
      USER_LOCKED_BG = {
        "settings" => "#34333b"
      }.freeze
      BG = ACCENT.each_with_object({}) do |(section, accent_hex), acc|
        acc[section] = USER_LOCKED_BG[section] || begin
          ar = accent_hex[1..2].to_i(16)
          ag = accent_hex[3..4].to_i(16)
          ab = accent_hex[5..6].to_i(16)
          br = DRACULA_BG[1..2].to_i(16)
          bg_val = DRACULA_BG[3..4].to_i(16)
          bb = DRACULA_BG[5..6].to_i(16)
          ratio = RECIPE_PCT.to_f / 100.0
          r = (br + ((ar - br) * ratio)).round.clamp(0, 255)
          g = (bg_val + ((ag - bg_val) * ratio)).round.clamp(0, 255)
          b = (bb + ((ab - bb) * ratio)).round.clamp(0, 255)
          format("#%02x%02x%02x", r, g, b)
        end
      end.freeze

      # ACCENTS — canonical alias for the 3 named screen accents. All resolve
      # to PITO_PURPLE following the 2026-05-25 single-accent decision.
      ACCENTS = {
        home:   PITO_PURPLE,
        videos: PITO_PURPLE,
        games:  PITO_PURPLE
      }.freeze

      # Fallbacks when section is nil / unknown.
      DEFAULT_BG     = DRACULA_BG
      DEFAULT_ACCENT = PITO_PURPLE

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
