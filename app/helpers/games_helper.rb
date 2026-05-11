# Phase 27 — Game tile + show-page formatting helpers.
#
# Two helpers live here:
#
#   * `format_game_rating(rating)` — zero-pads an IGDB rating into a
#     two-digit string (`5 → "05"`, `93 → "93"`). Returns `""` for nil
#     so callers can safely interpolate without conditional guards.
#     Ratings >= 100 still render the full number; the zero-pad is a
#     minimum-width contract, not a truncation.
#
#   * `game_meta_line(game)` — builds the second-line metadata string
#     for the tile (`<NN>/100 · <YYYY>`). Drops parts gracefully when
#     either side is missing — see the helper spec for the full
#     truth table. Returns `""` when both rating and year are absent
#     so the tile can `if line.present?` to omit the row.
#
#     2026-05-11 polish (Fix 5): the star glyph is gone from the
#     rating segment app-wide. Tiles + the list-mode rating column
#     now render `<NN>/100` (rating out of one hundred). The
#     `STAR_GLYPH` constant is preserved for any remaining caller.
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

  # Compose the tile's second-line metadata string.
  #
  # The target layout (post 2026-05-11 polish) is:
  #
  #   <NN>/100 · <YYYY>
  #
  # Missing pieces drop out cleanly:
  #
  #   rating only → "93/100"
  #   year only   → "2018"
  #   both        → "93/100 · 2018"
  #   neither     → ""
  def game_meta_line(game)
    rating_part = rating_segment(game)
    year_part   = game.release_year.presence&.to_s

    parts = [ rating_part, year_part ].compact_blank
    parts.join(" #{MIDDLE_DOT} ")
  end

  # Render the rating cell / tile rating as `<NN>/100`. Returns `""`
  # when `igdb_rating` is blank so callers can fall back to an em-dash.
  # Coerces via `.to_i` (matches the show-page treatment) — IGDB rating
  # is a `decimal(5,2)` in storage; the display is integer-out-of-100.
  def game_rating_display(game)
    return "" if game.igdb_rating.blank?

    "#{game.igdb_rating.to_i}/100"
  end

  private

  def rating_segment(game)
    return nil if game.igdb_rating.blank?

    game_rating_display(game)
  end
end
