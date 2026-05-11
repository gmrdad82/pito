# Phase 27 — Game tile + show-page formatting helpers.
#
# Three helpers live here:
#
#   * `format_game_rating(rating)` — zero-pads an IGDB rating into a
#     two-digit string (`5 → "05"`, `93 → "93"`). Returns `""` for nil
#     so callers can safely interpolate without conditional guards.
#     Ratings >= 100 still render the full number; the zero-pad is a
#     minimum-width contract, not a truncation.
#
#   * `game_meta_line(game)` — builds the legacy plain-text second-line
#     metadata string `<NN> · <YYYY>`. Used as the tile's native
#     `title=` attribute (screen readers + tooltip-on-truncation) and
#     by any caller that needs a flat string. The visual tile renders
#     the colored badge directly via `Games::RatingBadgeComponent` —
#     this helper is the inert text fallback.
#
#     2026-05-11 polish (Fix 2): the `/100` suffix was retired
#     everywhere; the colored bold rating badge is the single visual
#     surface for ratings. This helper still emits the integer rating
#     so the title attribute reads cleanly.
#
#   * `game_rating_display(game)` — legacy `<NN>/100` string builder,
#     preserved for back-compat in any caller that still expects the
#     suffix. New surfaces should render the badge component instead.
#
#     2026-05-11 polish (Fix 5): the star glyph is gone from every
#     rating surface.
module GamesHelper
  STAR_GLYPH = "★" # ★
  MIDDLE_DOT = "·" # ·

  # Zero-pad a numeric rating to two digits. The IGDB rating is a
  # decimal in storage (`igdb_rating` is `decimal(5,2)`); tile callers
  # already coerce via `.to_i` upstream, but this helper accepts any
  # numeric and rounds defensively.
  #
  # Examples:
  #   format_game_rating(nil)   # => ""
  #   format_game_rating(5)     # => "05"
  #   format_game_rating(93)    # => "93"
  #   format_game_rating(100)   # => "100"
  #   format_game_rating(8.7)   # => "09"
  def format_game_rating(rating)
    return "" if rating.nil?

    format("%02d", rating.to_i)
  end

  # Compose the tile's plain-text second-line metadata string.
  #
  # Layout (post 2026-05-11 Fix 2):
  #
  #   <NN> · <YYYY>
  #
  # Missing pieces drop out cleanly:
  #
  #   rating only → "93"
  #   year only   → "2018"
  #   both        → "93 · 2018"
  #   neither     → ""
  def game_meta_line(game)
    rating_part = game.igdb_rating.present? ? game.igdb_rating.to_i.to_s : nil
    year_part   = game.release_year.presence&.to_s

    parts = [ rating_part, year_part ].compact_blank
    parts.join(" #{MIDDLE_DOT} ")
  end

  # Legacy `<NN>/100` rating string. Preserved for back-compat — the
  # visual surfaces now use `Games::RatingBadgeComponent` instead.
  # Returns `""` when `igdb_rating` is blank so callers can fall back
  # to an em-dash.
  def game_rating_display(game)
    return "" if game.igdb_rating.blank?

    "#{game.igdb_rating.to_i}/100"
  end
end
