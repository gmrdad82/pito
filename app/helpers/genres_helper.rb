module GenresHelper
  # Phase 27 v2 spec 05 — display-label helper for IGDB genre names on
  # the `/games` shelves and listing-layer chrome.
  #
  # The spec's locked table maps IGDB-canonical genre names to a short
  # label suitable for the dense shelf `<h3>` heading (e.g.
  # "Role-playing (RPG)" → "RPG", "Shooter" → "FPS",
  # "Japanese Role-Playing Game (JRPG)" → "JRPG", "Simulator" → "Sim",
  # "MOBA" → "MOBA"). Unrecognised names fall through to the IGDB
  # canonical `name` unchanged. The mapping intentionally preserves
  # mixed-case acronyms (RPG, JRPG, FPS, MOBA, RTS, TBS, VN); other
  # labels carry the spec's locked short form (Sim, Sport, Indie, etc).
  #
  # Game show / game edit pages keep using the canonical long name (the
  # user is editing the underlying record, the full name is the
  # informational source of truth).
  SHORT_NAMES = {
    "Role-playing (RPG)"                => "RPG",
    "Japanese Role-Playing Game (JRPG)" => "JRPG",
    "Shooter"                           => "FPS",
    "First-person Shooter"              => "FPS",
    "MOBA"                              => "MOBA",
    "Real Time Strategy (RTS)"          => "RTS",
    "Turn-based strategy (TBS)"         => "TBS",
    "Simulator"                         => "Sim",
    "Sport"                             => "Sport",
    "Racing"                            => "Racing",
    "Fighting"                          => "Fighting",
    "Adventure"                         => "Adventure",
    "Platform"                          => "Platformer",
    "Puzzle"                            => "Puzzle",
    "Strategy"                          => "Strategy",
    "Pinball"                           => "Pinball",
    "Arcade"                            => "Arcade",
    "Music"                             => "Music",
    "Hack and slash/Beat 'em up"        => "Hack/Slash",
    "Quiz/Trivia"                       => "Quiz",
    "Tactical"                          => "Tactical",
    "Visual Novel"                      => "VN",
    "Indie"                             => "Indie",
    "Card & Board Game"                 => "Card",
    "Point-and-click"                   => "Adventure"
  }.freeze

  # Returns the short-form display label for a genre.
  #
  # Accepts either a `Genre` model instance (reads `#name`) or a plain
  # string. Nil-safe: returns `nil` when the argument is `nil` or the
  # extracted name is blank, so callers can chain `.presence` or pass
  # the result to view helpers without guarding.
  #
  # Unknown / unmapped names return the input unchanged (the IGDB
  # canonical `Genre#name`).
  def genre_short_name(genre)
    return nil if genre.nil?

    name = genre.respond_to?(:name) ? genre.name : genre
    name = name.to_s
    return nil if name.empty?

    SHORT_NAMES.fetch(name, name)
  end
end
