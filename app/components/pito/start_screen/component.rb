# frozen_string_literal: true

module Pito
  module StartScreen
    class Component < ViewComponent::Base
      attr_reader :repo_url, :license_url, :tip, :badge_class, :badge_text, :exclamation_class, :channels

      # The PITO block-art, one string per row. Rendered as per-GLYPH cells (each
      # non-space char its own span) so pito--logo-reveal can flicker them in
      # randomly (broken-neon). `█` glyphs are pito-blue; the box-drawing
      # connectors ride text-fg-dim; spaces stay literal (the <pre> keeps spacing).
      LOGO_LINES = [
        "██████╗ ██╗████████╗ ██████╗ ",
        "██╔══██╗██║╚══██╔══╝██╔═══██╗",
        "██████╔╝██║   ██║   ██║   ██║",
        "██╔═══╝ ██║   ██║   ██║   ██║",
        "██║     ██║   ██║   ╚██████╔╝",
        "╚═╝     ╚═╝   ╚═╝    ╚═════╝ "
      ].freeze

      def logo_lines = LOGO_LINES

      # Per-glyph colour: solid blocks are pito-blue, connectors are muted.
      def logo_cell_class(char) = char == "█" ? "text-pito" : "text-fg-dim"

      # The logo as rows (each a `logoRow` target for the home-transition fade)
      # of per-GLYPH `.pito-logo__cell` spans, joined by newlines for the <pre>.
      # Built here (not ERB) so no template whitespace corrupts the art alignment.
      def logo_html
        rows = logo_lines.map do |line|
          cells = line.chars.map do |ch|
            ch == " " ? " " : tag.span(ch, class: "pito-logo__cell #{logo_cell_class(ch)}")
          end
          tag.span(safe_join(cells), data: { "pito--home-transition-target": "logoRow" })
        end
        safe_join(rows, "\n")
      end

      def initialize(repo_url:, license_url:,
                     tips_key: "pito.copy.start_screen.tips",
                     badge_text: nil,
                     badge_text_key: "pito.start_screen.tip_prefix",
                     badge_class: "font-bold text-yellow",
                     exclamation_class: "text-orange",
                     channels: [])
        @repo_url          = repo_url
        @license_url       = license_url
        @badge_text        = badge_text || I18n.t(badge_text_key)
        @badge_class       = badge_class
        @exclamation_class = exclamation_class
        @tip               = Pito::Copy.render(tips_key)
        # Coerce nil → [] (the keyword default only applies when the arg is
        # omitted, not when a caller passes an explicit nil — e.g. the not_found
        # path renders with `channels: @channels` before any before_action has
        # loaded `@channels`). Guards `@channels.any?` in the template.
        @channels          = channels || []
      end
    end
  end
end
