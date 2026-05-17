module GenresHelper
  # Display-label helper for IGDB genre names across `/games` chrome
  # (game show, genre shelves, filter chips, …).
  #
  # Policy: render IGDB-canonical genre names VERBATIM. Cosmetic
  # renames live in `GENRE_DISPLAY_RENAMES` below and are applied at
  # display time only — the underlying `Genre#name` and the filter
  # slug system are never rewritten.
  #
  # The map starts intentionally tiny (one entry: "Role-playing (RPG)"
  # → "RPG"). Add a new pair here when, and only when, an IGDB
  # canonical name renders awkwardly in the UI. Distinct IGDB genres
  # stay distinct — "Shooter" and "First-person Shooter" (if IGDB ever
  # exposes the latter to us) are NOT collapsed.
  GENRE_DISPLAY_RENAMES = {
    "Role-playing (RPG)" => "RPG"
    # add future cosmetic renames here, one pair per line
  }.freeze

  # Returns the display label for a genre.
  #
  # Accepts either a `Genre` model instance (reads `#name`) or a plain
  # string. Nil-safe: returns `nil` when the argument is `nil` or the
  # extracted name is blank, so callers can chain `.presence` or pass
  # the result to view helpers without guarding.
  #
  # Unknown / unmapped names return the IGDB canonical name unchanged
  # — verbatim is the default; the rename map is the exception.
  def genre_display_name(genre)
    return nil if genre.nil?

    name = genre.respond_to?(:name) ? genre.name : genre
    name = name.to_s
    return nil if name.empty?

    GENRE_DISPLAY_RENAMES.fetch(name, name)
  end

  # Backwards-compatible alias for older call sites. New code should
  # prefer `genre_display_name`; this alias keeps the existing views
  # working without a sweep.
  alias_method :genre_short_name, :genre_display_name
end
