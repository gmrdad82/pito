# /games filter query object.
#
# AXES (2):
#   1. Lifecycle  = {released, scheduled}  — released XOR scheduled per
#      game (no game is both).
#   2. Engagement = {played}               — single chip; games with
#      `played_at` non-null.
#
# LOGICAL COMBINATORS:
#   - Within axis: OR.
#   - Across axes: AND.
#
# EDGE CASES:
#   - `released + scheduled` BOTH checked → lifecycle axis inactive
#     (every game passes the lifecycle axis).
#   - Empty token set (`?filters=`) → `Game.none` (intentional empty).
#   - Nil token set (`/games` with no `?filters=`) → the FULL universe
#     (every chip checked) → no narrowing → all games.
#
# Public surface:
#   - `.new(scope:, tokens:)`
#   - `#checked_tokens`, `#active_tokens`, `#dropped_tokens`,
#     `#contradiction?`, `#results`
#   - Constants: `TOKEN_UNIVERSE`, `CANONICAL_TOKENS`, `STATUS_TOKENS`,
#     `LIFECYCLE_TOKENS`, `ENGAGEMENT_TOKENS`.
module Games
  class Filter
    LIFECYCLE_TOKENS  = %w[released scheduled].freeze
    ENGAGEMENT_TOKENS = %w[played].freeze

    # Legacy aliases kept so external callers (MCP tools, specs) survive.
    STATUS_TOKENS    = LIFECYCLE_TOKENS
    OWNERSHIP_TOKENS = [].freeze
    PLATFORM_TOKENS  = [].freeze

    TOKEN_UNIVERSE = (LIFECYCLE_TOKENS + ENGAGEMENT_TOKENS).freeze

    # Legacy alias.
    CANONICAL_TOKENS = TOKEN_UNIVERSE

    # Default-checked set for bare `/games` (no `?filters=` param).
    # `played` is OFF by default so the full-list view doesn't narrow
    # to played-only games.
    DEFAULT_CHECKED_TOKENS = (TOKEN_UNIVERSE - ENGAGEMENT_TOKENS).freeze

    attr_reader :scope, :raw_tokens

    def initialize(scope: Game.all, tokens: nil, primaries_only: false)
      @scope  = scope
      @raw_tokens = tokens
      # primaries_only kept in signature for backwards-compat; no longer used.
    end

    # The canonical, de-duped, recognised tokens currently CHECKED.
    def checked_tokens
      @checked_tokens ||= begin
        if raw_tokens.nil?
          DEFAULT_CHECKED_TOKENS.dup
        else
          arr = normalised_raw.select { |t| TOKEN_UNIVERSE.include?(t) }.uniq
          TOKEN_UNIVERSE.select { |t| arr.include?(t) }
        end
      end
    end

    def active_tokens
      checked_tokens
    end

    def dropped_tokens
      @dropped_tokens ||= if raw_tokens.nil?
        []
      else
        normalised_raw.reject { |t| TOKEN_UNIVERSE.include?(t) }
      end
    end

    def contradiction?
      false
    end

    def results
      @results ||= build_results
    end

    private

    def normalised_raw
      @normalised_raw ||= Array(raw_tokens).map { |t| t.to_s.downcase.strip }
                                            .reject(&:empty?).uniq
    end

    def build_results
      return Game.none if checked_tokens.empty?

      rel = scope

      # AXIS 1: Lifecycle. Both checked → axis inactive. One checked → narrow.
      lifecycle_checked = checked_tokens & LIFECYCLE_TOKENS
      case lifecycle_checked
      when [ "released" ]
        rel = rel.where(id: Game.released.select(:id))
      when [ "scheduled" ]
        rel = rel.where(id: Game.scheduled.select(:id))
      end

      # AXIS 2: Engagement (played). Single chip.
      if checked_tokens.include?("played")
        rel = rel.where(id: Game.played.select(:id))
      end

      rel
    end
  end
end
