# Filter row helper for the /games screen.
#
# URL contract:
#   - `/games` (no `?filters=` param) ≡ all chips CHECKED ≡ full list.
#   - `/games?filters=<csv>` ≡ the CSV is the SET OF CHECKED chips.
#   - `/games?filters=` (empty CSV) ≡ every chip OFF ≡ empty listing.
#
# Surface:
#   parse_checked_tokens(raw)        → checked-token set.
#   serialize_checked_tokens(tokens) → CSV in TOKEN_UNIVERSE order.
#   games_path_with_checked(tokens)  → canonical URL for the token set.
#   TOKEN_UNIVERSE                   → ordered array of every valid token.
#   chip_label(token)                → on-screen label for a token.
#
# No side-effects, no DB access.
module Games
  module FiltersHelper
    # Two axes: lifecycle + engagement.
    TOKEN_UNIVERSE = %w[released scheduled played].freeze

    STATUS_TOKENS    = %w[released scheduled].freeze
    OWNERSHIP_TOKENS = [].freeze
    PLATFORM_TOKENS  = [].freeze

    # `played` is OFF by default — the engagement axis is opt-in.
    DEFAULT_CHECKED_TOKENS = (TOKEN_UNIVERSE - %w[played]).freeze

    # Legacy token aliases — old ownership/platform tokens in bookmarked
    # URLs are silently dropped (not in TOKEN_UNIVERSE so filtered out).
    LEGACY_TOKEN_ALIASES = { "wishlist" => "not_owned" }.freeze

    # Parse a `?filters=` raw value into the checked-token set.
    def parse_checked_tokens(raw)
      return DEFAULT_CHECKED_TOKENS.dup if raw.nil?

      tokens = tokens_for(raw)
      keep = tokens.select { |t| TOKEN_UNIVERSE.include?(t) }.uniq
      TOKEN_UNIVERSE.select { |t| keep.include?(t) }
    end

    # Serialise the checked-token set into a comma-separated string.
    def serialize_checked_tokens(tokens)
      Array(tokens).map(&:to_s).select { |t| TOKEN_UNIVERSE.include?(t) }
                   .then { |kept| TOKEN_UNIVERSE.select { |t| kept.include?(t) } }
                   .join(",")
    end

    # Build the canonical URL for a given checked-token set.
    def games_path_with_checked(tokens, path: "/games")
      arr = Array(tokens).map(&:to_s).select { |t| TOKEN_UNIVERSE.include?(t) }.uniq
      ordered = TOKEN_UNIVERSE.select { |t| arr.include?(t) }
      return path if ordered == DEFAULT_CHECKED_TOKENS
      csv = serialize_checked_tokens(arr)
      "#{path}?filters=#{csv}"
    end

    # On-screen label for a filter token.
    CHIP_LABELS = {}.freeze

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
      list.map { |t| t.to_s.downcase.strip }
          .map { |t| LEGACY_TOKEN_ALIASES.fetch(t, t) }
          .reject(&:empty?).uniq
    end
  end
end
