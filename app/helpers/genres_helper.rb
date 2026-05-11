module GenresHelper
  # Phase 27 follow-up — display-only short-form map for IGDB genre
  # names in `/games` shelves. Long canonical names like
  # "Role-playing (RPG)" render as "RPG" in shelf tiles, per-genre
  # shelf titles, and other listing-layer chrome. The URL slug + the
  # underlying `Genre` record stay canonical; this is purely a
  # cosmetic shortener for the high-density shelf surface.
  #
  # Game show / game edit pages keep using the canonical long name
  # (the user is editing the underlying record, full name is
  # informational).
  #
  # Any genre name not in the map renders as-is, so adding the map
  # is non-destructive: existing genres without an entry continue to
  # display their full name.
  GENRE_SHORT_NAMES = {
    "Role-playing (RPG)"                 => "RPG",
    "Real Time Strategy (RTS)"           => "RTS",
    "Turn-based strategy (TBS)"          => "TBS",
    "Massively Multiplayer Online"       => "MMO",
    "Massively Multiplayer Online (MMO)" => "MMO",
    "First-person shooter"               => "FPS",
    "First-person Shooter"               => "FPS",
    "Hack and slash/Beat 'em up"         => "Hack & Slash",
    "Card & Board Game"                  => "Card / Board",
    "Quiz/Trivia"                        => "Trivia",
    "Visual Novel"                       => "VN"
  }.freeze

  # Returns the short-form display name for a genre, falling back to
  # the canonical full name when no mapping is registered.
  #
  # Accepts either a `Genre` model instance (reads `#name`) or a plain
  # string. Nil-safe: returns `nil` when the argument is `nil` or the
  # extracted name is blank, so callers can chain `.presence` or pass
  # the result to view helpers without guarding.
  def genre_short_name(genre)
    return nil if genre.nil?

    name = genre.respond_to?(:name) ? genre.name : genre
    name = name.to_s
    return nil if name.empty?

    GENRE_SHORT_NAMES.fetch(name, name)
  end
end
