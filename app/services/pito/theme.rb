module Pito
  # 2026-05-20 — Single source of truth for the pito theme system.
  #
  # This module supersedes `Pito::SectionColors` as the canonical theme
  # surface. `SectionColors` remains as the lower-level mix() / per-section
  # bg+accent primitive that Theme delegates to (so we don't have two
  # sources of truth for the same hex values).
  #
  # The L1-L4 architecture is documented in ADR 0015 (theme system
  # mathematical derivation). Briefly:
  #
  # - L1 — Dracula palette atoms (immutable hex literals, no cross-refs)
  # - L2 — Section accents + per-section page backgrounds (picks from L1)
  # - L3 — Semantic tokens (derived where possible, hand-picked where not)
  # - L4 — Effect tokens (derived from L3 via mix)
  #
  # Two clients consume this module:
  #
  # 1. The Rails CSS pipeline via `rake pito:theme:export` which writes
  #    `app/assets/tailwind/_theme.css` with a `:root { ... }` block
  #    matching `Pito::Theme.export_css`.
  # 2. The future Ratatui CLI under `extras/cli/` which consumes
  #    `extras/cli/src/theme.rs` (also written by the rake task) — atoms
  #    are exposed as `pub const` string literals; the CLI's existing
  #    typed-Color wrapper layer will be refactored to read from them.
  #
  # Keeping both artifacts generated from the same Ruby source means a
  # color change is a one-line edit to this file + one rake task run,
  # never a hunt-and-replace across CSS + Rust.
  module Theme
    # L1 — Dracula palette atoms (immutable).
    DRACULA = {
      bg:           "#282a36",
      current_line: "#44475a",
      fg:           "#f8f8f2",
      comment:      "#6272a4",
      cyan:         "#8be9fd",
      green:        "#50fa7b",
      orange:       "#ffb86c",
      pink:         "#ff79c6",
      purple:       "#bd93f9",
      red:          "#ff5555",
      yellow:       "#f1fa8c"
    }.freeze

    # L1 derived atom — /games + /projects section accent. Pale cobalt
    # gives the gaming surfaces a PlayStation-blue feel that Dracula
    # Cyan (too greenish) and Purple (already home) don't cover.
    PALE_COBALT = "#7eb6ff".freeze

    # L2 — section accents (picks from L1). Cascade source for
    # `--section-accent`. Mirrors `Pito::SectionColors::ACCENT`.
    SECTION_ACCENTS = {
      "home"          => DRACULA.fetch(:purple),
      "channels"      => DRACULA.fetch(:red),
      "videos"        => DRACULA.fetch(:red),
      "games"         => PALE_COBALT,
      "projects"      => PALE_COBALT,
      "settings"      => DRACULA.fetch(:orange),
      "notifications" => DRACULA.fetch(:purple),
      "calendar"      => DRACULA.fetch(:purple)
    }.freeze

    # L2 — per-section page backgrounds (hand-picked atoms, NOT derived).
    # See `Pito::SectionColors::BG` for the canonical lock dates per
    # section.
    SECTION_BGS = {
      "home"          => "#2c2a36",
      "channels"      => "#36292d",
      "videos"        => "#36292d",
      "games"         => "#292c33",
      "projects"      => "#292c33",
      "settings"      => "#34333b",
      "notifications" => "#2c2a36",
      "calendar"      => "#2c2a36"
    }.freeze

    # L3 — semantic tokens. Most reference L1 atoms; `color-link`
    # references the section-aware `--section-accent` CSS variable so
    # the cascade keeps working at CSS-render time.
    SEMANTIC = {
      "color-bg"               => DRACULA.fetch(:bg),
      "color-text"             => DRACULA.fetch(:fg),
      "color-muted"            => DRACULA.fetch(:comment),
      "color-border"           => DRACULA.fetch(:current_line),
      "color-danger"           => DRACULA.fetch(:pink),
      "color-danger-hover"     => "color-mix(in srgb, #{DRACULA.fetch(:pink)} 80%, #{DRACULA.fetch(:bg)})",
      "color-success"          => DRACULA.fetch(:green),
      "color-warn"             => DRACULA.fetch(:orange),
      "color-link"             => "var(--section-accent)",
      "color-rating-bad"       => DRACULA.fetch(:red),
      "color-rating-fair"      => DRACULA.fetch(:yellow),
      "color-rating-good"      => DRACULA.fetch(:green),
      "color-rating-excellent" => DRACULA.fetch(:green),
      "color-ttb-main"         => DRACULA.fetch(:green),
      "color-ttb-extras"       => DRACULA.fetch(:cyan),
      "color-ttb-completionist" => DRACULA.fetch(:pink),
      "color-ttb-footage"      => DRACULA.fetch(:fg),
      # System-mono-only — browser picks whatever monospace the
      # OS/user has configured. No font download.
      "font-mono"              => %(ui-monospace, Menlo, "Cascadia Code", "Source Code Pro", Consolas, monospace),
      # Override Tailwind v4's framework default so code/kbd/samp/pre
      # resolve to the same system-mono stack. Same value as
      # --font-mono (single source of truth — the Tailwind-specific
      # token name just makes the override land at the right cascade
      # level).
      "default-mono-font-family" => %(ui-monospace, Menlo, "Cascadia Code", "Source Code Pro", Consolas, monospace)
    }.freeze

    # ----- Accessors ---------------------------------------------------

    def self.atoms
      DRACULA
    end

    def self.section_accent(section)
      SECTION_ACCENTS.fetch(section.to_s, DRACULA.fetch(:purple))
    end

    def self.section_bg(section)
      SECTION_BGS.fetch(section.to_s, DRACULA.fetch(:bg))
    end

    def self.semantic
      SEMANTIC
    end

    # L3 — derived pane border per section (35% accent + section bg).
    # Delegates to `Pito::SectionColors` so the derivation lives in one
    # place.
    def self.section_border(section)
      Pito::SectionColors.section_border(section)
    end

    # L4 — derived effect tokens.
    def self.color_link_hover(section)
      Pito::SectionColors.mix(section_accent(section), 80, "#ffffff")
    end

    def self.color_focus_ring(section)
      # 40% accent on a transparent base ≈ accent at 40% opacity. We
      # approximate by mixing against bg for the hex form; consumers
      # that need true alpha use the CSS `color-mix(... transparent)`
      # form directly.
      Pito::SectionColors.mix(section_accent(section), 40, section_bg(section))
    end

    # ----- Export -----------------------------------------------------

    # Build the canonical `:root { ... }` block that ships as
    # `app/assets/tailwind/_theme.css`.
    def self.export_css
      lines = [ ":root {" ]
      lines << "  /* L1 — Dracula palette atoms */"
      DRACULA.each do |name, hex|
        lines << "  --dracula-#{name.to_s.tr('_', '-')}: #{hex};"
      end
      lines << "  --pale-cobalt: #{PALE_COBALT};"
      lines << ""
      lines << "  /* L2 — section accents */"
      SECTION_ACCENTS.each do |section, hex|
        lines << "  --section-accent-#{section}: #{hex};"
      end
      lines << "  --section-accent: var(--section-accent-home); /* default */"
      lines << ""
      lines << "  /* L2 — per-section background atoms */"
      SECTION_BGS.each do |section, hex|
        lines << "  --bg-section-#{section}: #{hex};"
      end
      lines << ""
      lines << "  /* L3 — semantic tokens */"
      SEMANTIC.each do |name, value|
        lines << "  --#{name}: #{value};"
      end
      lines << "}"
      lines.join("\n") + "\n"
    end

    # Build the Ratatui-side `pub mod theme { ... }` block that ships
    # as `extras/cli/src/theme.rs`. Atoms become `pub const &str` hex
    # literals; CSS-var-referencing entries (e.g. `color-link =
    # var(--section-accent)`) are SKIPPED because Ratatui has no
    # equivalent of CSS cascade.
    def self.export_rust
      lines = []
      lines << "// Auto-generated by `rake pito:theme:export`."
      lines << "// Do not edit by hand — edit `app/services/pito/theme.rb`"
      lines << "// and re-run the task."
      lines << ""
      lines << "pub mod theme {"
      lines << "    // L1 — Dracula palette atoms"
      DRACULA.each do |name, hex|
        lines << "    pub const DRACULA_#{name.to_s.upcase}: &str = #{hex.inspect};"
      end
      lines << "    pub const PALE_COBALT: &str = #{PALE_COBALT.inspect};"
      lines << ""
      lines << "    // L2 — section accents"
      SECTION_ACCENTS.each do |section, hex|
        lines << "    pub const SECTION_ACCENT_#{section.upcase}: &str = #{hex.inspect};"
      end
      lines << ""
      lines << "    // L2 — section backgrounds"
      SECTION_BGS.each do |section, hex|
        lines << "    pub const SECTION_BG_#{section.upcase}: &str = #{hex.inspect};"
      end
      lines << ""
      lines << "    // L3 — semantic tokens (CSS-var-referencing entries skipped)"
      SEMANTIC.each do |name, value|
        next if value.start_with?("var(")
        const_name = name.upcase.tr("-", "_")
        lines << "    pub const #{const_name}: &str = #{value.inspect};"
      end
      lines << "}"
      lines.join("\n") + "\n"
    end
  end
end
