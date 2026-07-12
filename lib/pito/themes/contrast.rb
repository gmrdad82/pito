# frozen_string_literal: true

module Pito
  module Themes
    # WCAG 2.x contrast-ratio math and per-theme auditing.
    #
    # == Enforced threshold — uniform 3.0:1 floor
    #
    # Every audited token is measured against BOTH bg_root (page) AND
    # bg_surface (cards/panels).  The enforced minimum is 3.0:1 for:
    #   - fg_default, fg_dim
    #   - the six accents: accent_yellow, accent_cyan, accent_orange,
    #     accent_red, accent_green, accent_purple
    #   - brand_pito (the ascii logo + chatbox/echo border line — a
    #     non-text UI component under WCAG 1.4.11)
    #
    # fg_faded (placeholder / disabled tone) is EXEMPT — it is never
    # relied on for readability and is deliberately not audited.
    #
    # accent_blue is intentionally EXCLUDED from the text token list: it
    # surfaces only as brand_pito, never as inline text.
    #
    # == Rationale
    #
    # 3.0:1 is the WCAG large-text bar (1.4.3) and the non-text UI
    # component bar (1.4.11).  Using it as a uniform floor lets
    # intentionally low-contrast palettes such as Solarized and Nord
    # remain largely passable with minimal nudges, instead of forcing the
    # AA 4.5:1 bar that would require changing their defining colours.
    #
    # == Aspiration (documented, not enforced)
    #
    # 4.5:1 (AA_ASPIRATION) is the WCAG AA text target we aim for on
    # primary body text (fg_default) and status colours (accent_green,
    # accent_red) wherever the palette allows.  It is NOT checked by
    # `audit`; it is provided here for reference and future tooling.
    #
    # See docs/theme-contrast-audit.md for the full findings write-up.
    module Contrast
      # ── Scoped token sets ────────────────────────────────────────────────────

      # Text tokens audited at the 3.0:1 floor.
      # accent_blue is deliberately absent — it is brand_pito, not inline text.
      TEXT_TOKENS = %i[
        fg_default
        fg_dim
        accent_yellow
        accent_cyan
        accent_orange
        accent_red
        accent_green
        accent_purple
      ].freeze

      # brand_pito is a non-text UI element (logo + border) — 3.0:1 non-text bar.
      BRAND_TOKENS = %i[brand_pito].freeze

      # The comet pair (loading-dot animation colours, derived per theme from
      # the Synthwave anchor — see Definition) are non-text UI: same 3.0 bar,
      # so a derived pair can never fade into its own background.
      COMET_TOKENS = %i[comet_a comet_b].freeze

      # Backgrounds against which text / brand tokens are evaluated.
      # bg_root = full-viewport page; bg_surface = cards, panels.
      BG_TOKENS = %i[bg_root bg_surface].freeze

      # Enforced minimum contrast ratio for ALL audited tokens (page + surface).
      # 3.0:1 = WCAG large-text bar (1.4.3) and non-text UI component bar (1.4.11).
      TEXT_TARGET  = 3.0
      BRAND_TARGET = 3.0

      # Aspirational AA target for primary text and status colours — documented
      # only, NOT enforced by `audit`.  Kept here for reference and future tooling.
      AA_ASPIRATION = 4.5

      # Mapping of (token → target) for the full audit scope.
      # fg_faded is intentionally absent — it is exempt from auditing.
      TARGETS = (
        TEXT_TOKENS.to_h  { |t| [ t, TEXT_TARGET ] }.merge(
          BRAND_TOKENS.to_h { |t| [ t, BRAND_TARGET ] },
          COMET_TOKENS.to_h { |t| [ t, BRAND_TARGET ] }
        )
      ).freeze

      # ── Value object for audit failures ─────────────────────────────────────

      # Immutable record describing a single pair that fell below its target.
      #   slug   – theme slug  (e.g. "tokyo-night")
      #   token  – foreground token name (Symbol)
      #   bg     – background token name (Symbol)
      #   ratio  – actual contrast ratio, rounded to 2 decimal places
      #   target – minimum required ratio
      Failure = Data.define(:slug, :token, :bg, :ratio, :target)

      # ── Public API ───────────────────────────────────────────────────────────

      module_function

      # Returns the WCAG relative luminance (0.0 – 1.0) for a "#rrggbb" hex colour.
      #
      # Linearisation: c <= 0.03928 ? c/12.92 : ((c+0.055)/1.055)**2.4
      # Weighted sum:  0.2126R + 0.7152G + 0.0722B
      #
      # @param hex [String] "#rrggbb" (hash required)
      # @return [Float]
      def relative_luminance(hex)
        h = hex.delete("#")
        r, g, b = [ h[0, 2], h[2, 2], h[4, 2] ].map { |x| linearise(x.to_i(16)) }
        (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
      end

      # Returns the WCAG contrast ratio between two "#rrggbb" hex colours.
      # Result is always ≥ 1.0 (the lighter of the two luminances is the numerator).
      #
      # @param hex_a [String]
      # @param hex_b [String]
      # @return [Float]
      def ratio(hex_a, hex_b)
        la = relative_luminance(hex_a)
        lb = relative_luminance(hex_b)
        hi, lo = [ la, lb ].minmax.reverse
        (hi + 0.05) / (lo + 0.05)
      end

      # Audits a single Definition against the scoped TARGETS.
      # Returns only the pairs whose ratio is **below** their target.
      # `Failure#ratio` is rounded to 2 decimal places.
      #
      # @param definition [Pito::Themes::Definition]
      # @return [Array<Failure>]
      def audit(definition)
        t = definition.tokens
        failures = []

        TARGETS.each do |token, target|
          BG_TOKENS.each do |bg|
            r = ratio(t.fetch(token), t.fetch(bg)).round(2)
            next unless r < target

            failures << Failure.new(
              slug:   definition.slug,
              token:  token,
              bg:     bg,
              ratio:  r,
              target: target
            )
          end
        end

        failures
      end

      # Audits every registered theme, returning a flat list of Failures.
      # Stable order: sorted by slug, then token, then bg.
      #
      # @return [Array<Failure>]
      def audit_all
        Registry
          .all
          .flat_map { |defn| audit(defn) }
          .sort_by  { |f| [ f.slug, f.token.to_s, f.bg.to_s ] }
      end

      # ── Private helpers ──────────────────────────────────────────────────────

      private_class_method def self.linearise(channel_int)
        c = channel_int / 255.0
        c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4
      end
    end
  end
end
