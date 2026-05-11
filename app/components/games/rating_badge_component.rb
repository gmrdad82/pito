# 2026-05-11 polish (Fix 2) — colored bold rating badge.
#
# Renders an IGDB rating (0-100) as a bold `<span>` whose color tracks
# six discrete tiers. Replaces the legacy `<NN>/100` literal that
# appeared on the game tile (grid + shelf variants), the list-mode
# rating column, and the game show page ratings table.
#
# Tiers (inclusive lower bounds):
#
#   >= 90          excellent   green             --color-rating-excellent
#   >= 80, < 90    good        olive green       --color-rating-good
#   >= 70, < 80    fair        yellow            --color-rating-fair
#   >= 60, < 70    meh         brownish-yellow   --color-rating-meh
#   >= 50, < 60    poor        brown             --color-rating-poor
#   <  50          bad         clear red         --color-rating-bad
#   nil            —           (no color)        muted em-dash
#
# Display surface: integer only. The legacy `/100` suffix is gone
# everywhere this component lands.
#
# The CSS variables live in `app/assets/tailwind/application.css` so a
# future theme tweak edits one place. The inline `color:` style applies
# the variable at the `<span>` level — this keeps the component
# self-contained without requiring per-tier utility classes downstream.
module Games
  class RatingBadgeComponent < ViewComponent::Base
    TIERS = [
      [ 90, "excellent" ],
      [ 80, "good"      ],
      [ 70, "fair"      ],
      [ 60, "meh"       ],
      [ 50, "poor"      ]
    ].freeze

    def initialize(rating:)
      @rating = rating
    end

    # `nil` is acceptable. Decimal / BigDecimal coerce via `to_i`
    # (matches the show-page treatment — IGDB rating is `decimal(5,2)`
    # in storage and renders as integer-out-of-100). Blank also maps to
    # nil so callers can pass an empty string without a guard.
    def rating
      return nil if @rating.nil? || (@rating.respond_to?(:blank?) && @rating.blank?)

      @rating.to_i
    end

    def present?
      !rating.nil?
    end

    # Used to render an em-dash when the rating is missing. Public so
    # the template can branch without leaking `@rating` directly.
    def missing_glyph
      "—"
    end

    def tier
      r = rating
      return "missing" if r.nil?

      TIERS.each do |min, name|
        return name if r >= min
      end
      "bad"
    end

    def css_color
      "var(--color-rating-#{tier})"
    end

    def display_text
      rating.to_s
    end
  end
end
