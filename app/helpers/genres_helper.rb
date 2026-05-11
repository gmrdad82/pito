module GenresHelper
  # Phase 27 follow-up (2026-05-11) — display-label helper for IGDB
  # genre names in `/games` shelves and listing-layer chrome.
  #
  # Convention: pito copy is lowercase everywhere EXCEPT brand names
  # and explicit acronyms. So "Adventure" reads as "adventure" in a
  # shelf <h3>, "Shooter" as "shooter", but "Role-playing (RPG)" as
  # "RPG" (acronym preserved). The URL slug + the underlying `Genre`
  # record stay canonical; this is purely a cosmetic shortener for the
  # high-density shelf surface.
  #
  # Why downcase-by-default — the IGDB taxonomy mixes title-case and
  # parenthesized-acronym names ("Adventure", "First-person Shooter",
  # "Role-playing (RPG)") that look inconsistent next to pito's
  # otherwise-lowercase chrome ("genres", "custom collections", "all
  # games"). Downcasing every label and forcing acronyms back to
  # uppercase gives one rule that scales as IGDB ships new genres
  # without per-genre maintenance.
  #
  # Map structure: `GENRE_SHORT_NAMES` collapses a few IGDB long-form
  # names that DO have an acronym ("Role-playing (RPG)" → "RPG") or
  # naturally read better in a short form ("Massively Multiplayer
  # Online" → "MMO"). `ACRONYM_LABELS` is the small allowlist of
  # already-short labels that stay UPPERCASE (skip the downcase step).
  # Unrecognized names go through the downcase rule.
  #
  # Game show / game edit pages keep using the canonical long name
  # (the user is editing the underlying record, full name is
  # informational).
  GENRE_SHORT_NAMES = {
    "Role-playing (RPG)"                 => "RPG",
    "Real Time Strategy (RTS)"           => "RTS",
    "Turn-based strategy (TBS)"          => "TBS",
    "Massively Multiplayer Online"       => "MMO",
    "Massively Multiplayer Online (MMO)" => "MMO",
    "Hack and slash/Beat 'em up"         => "hack & slash",
    "Card & Board Game"                  => "card / board",
    "Quiz/Trivia"                        => "trivia",
    "Visual Novel"                       => "visual novel"
  }.freeze

  # Labels that stay UPPERCASE after lookup / downcase. Limited to
  # acronyms the user already reads as a unit. "FPS" / "MMO" are NOT
  # in here because the user explicitly chose "shooter" over "FPS" in
  # the 2026-05-11 direction; only "RPG" survives as an upper-case
  # acronym for now. Extending the list later is non-breaking.
  ACRONYM_LABELS = %w[RPG].freeze

  # Returns the short-form display label for a genre, applying the
  # lowercase rule + the acronym allowlist.
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

    label = GENRE_SHORT_NAMES.fetch(name, name)
    ACRONYM_LABELS.include?(label) ? label : label.downcase
  end
end
