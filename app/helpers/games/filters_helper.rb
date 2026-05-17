# Phase 27 v2 spec 06 — Filter row helper.
#
# Rewritten from the 01b "tokens are NARROWING scopes" contract to the
# v2 "tokens are CHECKED chips" contract:
#
#   - URL `/games` (no `?filters=` param) ≡ all chips CHECKED ≡ show
#     the full list, every shelf, nothing narrowed.
#   - URL `/games?filters=<csv>` ≡ the CSV is the SET OF CHECKED chips.
#     Anything NOT in the CSV is OFF (un-checked) and narrows the
#     listing away from it.
#   - URL `/games?filters=` (empty CSV) ≡ every chip OFF ≡ empty
#     listing (intentional edge — see request spec).
#
# Surface (locked by spec §"Helper — Games::FiltersHelper"):
#
#   parse_checked_tokens(raw)        → checked-token set per the rule
#                                      above (nil ⇒ universe, empty
#                                      string ⇒ [], canonical CSV ⇒
#                                      that subset, unknowns dropped).
#   serialize_checked_tokens(tokens) → CSV in TOKEN_UNIVERSE order.
#   games_path_with_checked(tokens)  → "/games" when tokens equal the
#                                      universe; "/games?filters=<csv>"
#                                      otherwise.
#   TOKEN_UNIVERSE                   → frozen Array of every valid
#                                      token in render-order.
#   chip_label(token)                → canonical → on-screen label.
#
# No side-effects, no DB access, no Rails-cache access.
module Games
  module FiltersHelper
    # The eight canonical filter chips in render order. Left side
    # (status + ownership): released, scheduled, owned, wishlist,
    # played. Right side (platforms): ps5, switch2, steam.
    #
    # Phase 27 v2 spec 06 (2026-05-17 PC store collapse): `gog` and
    # `epic` chips were retired and the three PC stores converge on
    # `steam`. `xbox` was already absent (user-pinned drop). The CSV
    # serialisation follows this order so bookmarks are stable.
    TOKEN_UNIVERSE = %w[
      released scheduled owned wishlist played
      ps5 switch2 steam
    ].freeze

    # The three logical group splits the query object partitions on.
    # Repeated here as constants so the component and the controller
    # can also reason about group membership without re-importing the
    # query object's internals.
    STATUS_TOKENS    = %w[released scheduled].freeze
    OWNERSHIP_TOKENS = %w[owned wishlist played].freeze
    PLATFORM_TOKENS  = %w[ps5 switch2 steam].freeze

    # Parse a `?filters=` raw value into the checked-token set.
    #
    # Inputs:
    #   nil      → the FULL universe (10 tokens). No `?filters=` param
    #              in the URL means "all chips checked" per the v2
    #              canonicalisation rule.
    #   ""       → empty set. The user explicitly emptied the CSV
    #              (every chip OFF; listing is empty).
    #   "a,b,c"  → those tokens, intersected with TOKEN_UNIVERSE.
    #              Unknown tokens are silently dropped.
    #   Array    → treated like a pre-split CSV.
    #
    # Returns a frozen Array of canonical token strings in
    # TOKEN_UNIVERSE order (so the controller / query object see a
    # deterministic shape regardless of input order).
    def parse_checked_tokens(raw)
      # `nil` is the "no param at all" path — universe.
      return TOKEN_UNIVERSE.dup if raw.nil?

      tokens = tokens_for(raw)
      # An empty CSV (explicit `?filters=`) yields []; the universe
      # path above already short-circuited the nil case.
      keep = tokens.select { |t| TOKEN_UNIVERSE.include?(t) }.uniq
      TOKEN_UNIVERSE.select { |t| keep.include?(t) }
    end

    # Serialise the checked-token set into a CSV. Always emits the
    # tokens in TOKEN_UNIVERSE order; the caller decides whether to
    # emit `/games` (no `?filters=` param) vs `/games?filters=<csv>`.
    def serialize_checked_tokens(tokens)
      Array(tokens).map(&:to_s).select { |t| TOKEN_UNIVERSE.include?(t) }
                   .then { |kept| TOKEN_UNIVERSE.select { |t| kept.include?(t) } }
                   .join(",")
    end

    # Build the canonical URL for a given checked-token set.
    #
    #   - All tokens checked (`tokens == TOKEN_UNIVERSE`) → emit
    #     `/games` (no `?filters=` param). This is the SINGLE canonical
    #     "full list" URL.
    #   - Subset checked → emit `/games?filters=<csv>`.
    #   - Empty set → emit `/games?filters=` (the empty-CSV path; the
    #     listing renders empty by design).
    def games_path_with_checked(tokens, path: "/games")
      arr = Array(tokens).map(&:to_s).select { |t| TOKEN_UNIVERSE.include?(t) }.uniq
      return path if arr.length == TOKEN_UNIVERSE.length
      csv = serialize_checked_tokens(arr)
      "#{path}?filters=#{csv}"
    end

    # Canonical token → on-screen label. Platform tokens use
    # `Platform::PLATFORM_LABELS` short names; status / ownership
    # tokens render verbatim except for the legacy `not_owned` (which
    # is no longer in TOKEN_UNIVERSE but kept for safety in case a
    # caller passes it in).
    CHIP_LABELS = {
      "not_owned" => "not owned",
      "ps5"       => "PS5",
      "switch2"   => "Switch2",
      "steam"     => "Steam"
    }.freeze

    def chip_label(token)
      CHIP_LABELS.fetch(token.to_s, token.to_s)
    end

    private

    def tokens_for(raw)
      list =
        case raw
        when Array  then raw
        when String then raw.split(",")
        when nil    then []
        else raw.to_s.split(",")
        end
      list.map { |t| t.to_s.downcase.strip }.reject(&:empty?).uniq
    end
  end
end
