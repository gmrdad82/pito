module Pito
  # 2026-05-20 — Single source of truth for the pito theme system.
  #
  # 2026-05-25 — SINGLE ACCENT DECISION (historical). All screen accents
  # were unified to one Pito purple (`#bd93f9`, Dracula Purple).
  #
  # 2026-05-26 — TOKYO NIGHT MIGRATION. Palette switched from Dracula to
  # Tokyo Night. Per-section accents restored: home=blue (#7aa2f7),
  # videos=red (#f7768e), games=teal (#1abc9c). Other sections default to
  # the blue accent. The CSS variable names retain the `--dracula-*` prefix
  # for backward compatibility with `app/assets/tailwind/application.css`.
  #
  # This module supersedes `Pito::Theme::Sections` as the canonical theme
  # surface. `Sections` remains as the lower-level mix() / per-section
  # bg+accent primitive that Theme delegates to (so we don't have two
  # sources of truth for the same hex values).
  #
  # The L1-L4 architecture is documented in ADR 0015 (theme system
  # mathematical derivation). Briefly:
  #
  # - L1 — Tokyo Night palette atoms (immutable hex literals, no cross-refs)
  # - L2 — Section accents + per-section page backgrounds (picks from L1)
  # - L3 — Semantic tokens (derived where possible, hand-picked where not)
  # - L4 — Effect tokens (derived from L3 via mix)
  #
  # The Rails CSS pipeline consumes this module via `rake pito:theme:export`,
  # which writes `tmp/_theme.css` with a `:root { ... }` block matching
  # `Pito::Theme.export_css`. A color change is a one-line edit to this file
  # plus one rake task run, never a hunt-and-replace across the CSS.
  module Theme
    # L1 — Tokyo Night palette atoms (immutable).
    TOKYO_NIGHT = {
      bg:           "#1a1b26",
      selection:    "#33467c",
      current_line: "#292e42",
      fg:           "#c0caf5",
      comment:      "#565f89",
      cyan:         "#1abc9c",
      green:        "#9ece6a",
      orange:       "#ff9e64",
      pink:         "#ad8ee6",
      purple:       "#bb9af7",
      red:          "#f7768e",
      yellow:       "#e0af68"
    }.freeze

    # L1 derived atom — Tokyo Night blue (#7aa2f7); the section accent for
    # home/channels/projects/settings/notifications/calendar (see SECTION_ACCENTS).
    BLUE_ACCENT = "#7aa2f7".freeze

    # L2 — section accents. Per the Tokyo Night migration, the three primary
    # screens get distinct accent colors; all other sections default to the
    # blue accent.
    SECTION_ACCENTS = {
      "home"          => BLUE_ACCENT,
      "channels"      => BLUE_ACCENT,
      "videos"        => TOKYO_NIGHT.fetch(:red),
      "games"         => TOKYO_NIGHT.fetch(:cyan),
      "projects"      => BLUE_ACCENT,
      "settings"      => BLUE_ACCENT,
      "notifications" => BLUE_ACCENT,
      "calendar"      => BLUE_ACCENT
    }.freeze

    # L2 — per-section page backgrounds.
    #
    # 2026-05-22 — Delegated to `Pito::Theme::Sections::BG` to keep a
    # single source of truth. The Sections table derives bg from the
    # canonical 4%-accent-over-Tokyo-Night-bg recipe (with `settings` as a
    # user-locked override at `#34333b`). Previously this constant
    # duplicated hand-picked atoms that drifted from the recipe —
    # delegation eliminates the drift.
    SECTION_BGS = Pito::Theme::Sections::BG

    # L3 — semantic tokens. Most reference L1 atoms; `color-link`
    # references the section-aware `--section-accent` CSS variable so
    # the cascade keeps working at CSS-render time.
    SEMANTIC = {
      "color-bg"               => TOKYO_NIGHT.fetch(:bg),
      "color-text"             => TOKYO_NIGHT.fetch(:fg),
      "color-muted"            => TOKYO_NIGHT.fetch(:comment),
      # 2026-05-23 — Wave 2E refinement. Washed-out home-accent blue,
      # distinct from --color-muted (Tokyo Night comment gray, owned by
      # AppVersion). Used by Tui::BreadcrumbComponent's idle + host
      # colors so the breadcrumb stays "soft brand-family" against the
      # focused panel's accent without competing with AppVersion's muted
      # gray.
      "color-accent-pale"      => "color-mix(in srgb, var(--section-accent-home) 55%, var(--color-bg))",
      "color-border"           => TOKYO_NIGHT.fetch(:current_line),
      "color-danger"           => TOKYO_NIGHT.fetch(:pink),
      "color-danger-hover"     => "color-mix(in srgb, #{TOKYO_NIGHT.fetch(:pink)} 80%, #{TOKYO_NIGHT.fetch(:bg)})",
      "color-success"          => TOKYO_NIGHT.fetch(:green),
      "color-warn"             => TOKYO_NIGHT.fetch(:orange),
      "color-fatal"            => TOKYO_NIGHT.fetch(:red),
      "color-link"             => "var(--section-accent)",
      "color-rating-bad"       => TOKYO_NIGHT.fetch(:red),
      "color-rating-fair"      => TOKYO_NIGHT.fetch(:yellow),
      "color-rating-good"      => TOKYO_NIGHT.fetch(:green),
      "color-rating-excellent" => TOKYO_NIGHT.fetch(:green),
      "color-ttb-main"         => TOKYO_NIGHT.fetch(:green),
      "color-ttb-extras"       => TOKYO_NIGHT.fetch(:cyan),
      "color-ttb-completionist" => TOKYO_NIGHT.fetch(:pink),
      "color-ttb-footage"      => TOKYO_NIGHT.fetch(:fg),
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
      TOKYO_NIGHT
    end

    def self.section_accent(section)
      SECTION_ACCENTS.fetch(section.to_s, BLUE_ACCENT)
    end

    def self.section_bg(section)
      SECTION_BGS.fetch(section.to_s, TOKYO_NIGHT.fetch(:bg))
    end

    def self.semantic
      SEMANTIC
    end

    # L3 — derived pane border per section (35% accent + section bg).
    # Delegates to `Pito::Theme::Sections` so the derivation lives in one
    # place.
    def self.section_border(section)
      Pito::Theme::Sections.section_border(section)
    end

    # L4 — derived effect tokens.
    def self.color_link_hover(section)
      Pito::Theme::Sections.mix(section_accent(section), 80, "#ffffff")
    end

    def self.color_focus_ring(section)
      # 40% accent on a transparent base ≈ accent at 40% opacity. We
      # approximate by mixing against bg for the hex form; consumers
      # that need true alpha use the CSS `color-mix(... transparent)`
      # form directly.
      Pito::Theme::Sections.mix(section_accent(section), 40, section_bg(section))
    end

    # ----- Export -----------------------------------------------------

    # Build the canonical `:root { ... }` block that ships as
    # `app/assets/tailwind/_theme.css`.
    #
    # NOTE: CSS variable names retain the `--dracula-*` prefix for backward
    # compatibility. The values are Tokyo Night hex codes.
    def self.export_css
      lines = [ ":root {" ]
      lines << "  /* L1 — Tokyo Night palette atoms (CSS var names kept as --dracula-* for compat) */"
      TOKYO_NIGHT.each do |name, hex|
        lines << "  --dracula-#{name.to_s.tr('_', '-')}: #{hex};"
      end
      lines << "  --blue-accent: #{BLUE_ACCENT};"
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
  end
end
