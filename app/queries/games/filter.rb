# /games filter query object — locked semantics per ADR 0013
# (2026-05-17). Four orthogonal axes combined with within-axis OR and
# cross-axis AND, with per-platform binding when the platform axis
# intersects with ownership or engagement.
#
# Canonical source: `docs/decisions/0013-games-filter-semantics.md`.
#
# AXES (4):
#   1. Lifecycle  = {released, scheduled}  — released XOR scheduled per
#      game (no game is both).
#   2. Ownership  = {owned, wishlist}      — `wishlist` ≡ NOT owned
#      globally (anywhere).
#   3. Engagement = {played}               — single chip. Per-platform
#      via `games.played_platform_id`.
#   4. Platform   = {ps, switch, steam}  — multi-select; tokens
#      expand to multiple IGDB platform slugs via
#      `TOKEN_TO_PLATFORM_SLUGS`.
#
# LOGICAL COMBINATORS:
#   - Within axis: OR.
#   - Across axes: AND.
#   - Per-platform binding when platform + ownership/engagement
#     intersect (see ADR rules above).
#
# EDGE CASES:
#   - `released + scheduled` BOTH checked → lifecycle axis inactive
#     (every game passes the lifecycle axis — rule e).
#   - `owned + wishlist` BOTH checked → ownership universe covered
#     (rule f). When NO platform is set, the axis is inactive. When a
#     platform IS set, per-platform binding kicks in:
#     (owned-on-platform OR not-owned-globally with platform available).
#   - `played` requires released + owned in the cascade UI; the filter
#     itself does NOT enforce the cascade — a hand-edited URL like
#     `?filters=played` (no other tokens) returns all played games
#     (the UI is the only cascade enforcer).
#   - Empty token set (`?filters=`) → `Game.none` (intentional empty).
#   - Nil token set (`/games` with no `?filters=`) → the FULL universe
#     (every chip checked) → no narrowing → all games.
#
# Public surface preserved from the prior implementation:
#   - `.new(scope:, tokens:)`
#   - `#checked_tokens`, `#active_tokens` (alias), `#dropped_tokens`,
#     `#contradiction?` (always false in v2), `#results`
#   - Constants: `TOKEN_UNIVERSE`, `CANONICAL_TOKENS` (alias),
#     `STATUS_TOKENS`, `OWNERSHIP_TOKENS`, `PLATFORM_TOKENS`,
#     `TOKEN_TO_PLATFORM_SLUGS`.
module Games
  class Filter
    LIFECYCLE_TOKENS  = %w[released scheduled].freeze
    OWNERSHIP_TOKENS  = %w[owned wishlist].freeze
    ENGAGEMENT_TOKENS = %w[played].freeze
    PLATFORM_TOKENS   = %w[ps switch steam].freeze

    # Legacy alias — prior implementation surfaced `STATUS_TOKENS` to
    # callers (helper module, request specs). Kept as an alias of
    # `LIFECYCLE_TOKENS` (same content) so external imports survive.
    STATUS_TOKENS = LIFECYCLE_TOKENS

    # Chip-token → DB platform-slug expansion. Chip tokens are the
    # canonical surface vocabulary; the DB stores FriendlyId-generated
    # `platforms.slug` values that don't always match the token
    # one-for-one. See ADR 0013 + design.md ### Platform Chips for the
    # collapse-family rationale.
    TOKEN_TO_PLATFORM_SLUGS = {
      "ps"     => %w[ps5 ps4--1].freeze,
      "switch" => %w[switch switch-2].freeze,
      "steam"  => %w[win linux mac dos web steam].freeze
    }.freeze

    # Every canonical token in render order. The helper module mirrors
    # this constant; keeping a copy here so callers that consume the
    # query object directly (request specs, the Stimulus controller's
    # `data-universe` JSON) have a single import surface.
    TOKEN_UNIVERSE = (
      LIFECYCLE_TOKENS + OWNERSHIP_TOKENS + ENGAGEMENT_TOKENS + PLATFORM_TOKENS
    ).freeze

    # Legacy alias — prior code-paths referenced `CANONICAL_TOKENS`.
    CANONICAL_TOKENS = TOKEN_UNIVERSE

    # Default-checked set for bare `/games` (no `?filters=` param).
    # User-locked 2026-05-17: the `played` chip is OFF by default so
    # the full-list view doesn't narrow to played-only games. Bare
    # `/games` therefore matches the universe MINUS the engagement
    # axis (`played`). Explicit `?filters=...,played` opts back in.
    DEFAULT_CHECKED_TOKENS = (TOKEN_UNIVERSE - ENGAGEMENT_TOKENS).freeze

    attr_reader :scope, :raw_tokens

    def initialize(scope: Game.all, tokens: nil)
      @scope      = scope
      @raw_tokens = tokens
    end

    # The canonical, de-duped, recognised tokens currently CHECKED.
    # Nil input (bare `/games`) is treated as the
    # `DEFAULT_CHECKED_TOKENS` set — universe MINUS `played`
    # (user-locked 2026-05-17). The engagement axis stays opt-in.
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

    # Backwards-compatible alias — some callers still ask for
    # `active_tokens`. The v2 semantic is "checked", but the surface
    # name carries forward.
    def active_tokens
      checked_tokens
    end

    # Tokens that fell outside the canonical whitelist.
    def dropped_tokens
      @dropped_tokens ||= if raw_tokens.nil?
        []
      else
        normalised_raw.reject { |t| TOKEN_UNIVERSE.include?(t) }
      end
    end

    # 01b carried a `contradiction?` predicate for the C-3
    # `owned + not_owned` simultaneous-check case. v2 has no
    # `not_owned` chip (and `owned + wishlist` is rule (f), NOT a
    # contradiction). Method survives to keep the controller /
    # component signature stable.
    def contradiction?
      false
    end

    # Filtered `ActiveRecord::Relation`. Memoised — repeated calls
    # produce the same SQL fingerprint.
    def results
      @results ||= build_results
    end

    private

    def normalised_raw
      @normalised_raw ||= Array(raw_tokens).map { |t| t.to_s.downcase.strip }
                                            .reject(&:empty?).uniq
    end

    def build_results
      # Empty-CSV path — explicit `?filters=` with zero recognised
      # tokens collapses to none.
      return Game.none if checked_tokens.empty?

      # No early-return for "all chips checked" / "default set." Each
      # axis pass-through below already no-ops when its own chips
      # cover the universe (lifecycle both checked → no `case` match;
      # ownership both checked with no platform → no narrowing;
      # platform all checked → `platform_active` is false). The one
      # axis that MUST narrow whenever its chip is checked is the
      # single-chip engagement axis — a blanket early-return here
      # silently bypassed it, so `?filters=...,played` (with every
      # other chip also checked) returned the full universe instead
      # of `played_at IS NOT NULL`. Let the natural axis logic run.
      rel = scope

      # AXIS 1: Lifecycle. Zero checks → axis inactive (no constraint
      # — the cascade UI guarantees validity at the UI level, but a
      # hand-edited URL with zero lifecycle chips simply doesn't
      # constrain this axis). Both checked → axis inactive (rule e).
      # Exactly one checked → narrow.
      lifecycle_checked = checked_tokens & LIFECYCLE_TOKENS
      case lifecycle_checked
      when [ "released" ]
        rel = rel.where(id: Game.released.select(:id))
      when [ "scheduled" ]
        rel = rel.where(id: Game.scheduled.select(:id))
      end

      # AXIS 4: Platform — compute expanded DB slugs early because
      # ownership and engagement axes bind to the platform set. Zero
      # checks → axis inactive (no platform constraint). All three
      # checked → axis inactive (every platform-family covered).
      platform_tokens = checked_tokens & PLATFORM_TOKENS
      platform_slugs  = expand_platform_slugs(platform_tokens)
      platform_active = platform_tokens.any? && platform_tokens != PLATFORM_TOKENS

      # Platform axis: games AVAILABLE on any platform in the expanded
      # slug set (IGDB-reported availability via `:platforms_available`).
      if platform_active
        rel = rel.where(id: Game.on_platform(platform_slugs).select(:id))
      end

      # AXIS 2: Ownership. Zero checks → axis inactive. Rule (f) —
      # both checked covers the ownership universe (axis inactive).
      # With a platform set AND both ownership chips checked, the
      # per-platform binding gives a union: (owned-on-platform) ∪
      # (not-owned-globally). The not-owned-globally branch rides on
      # the platform-availability constraint already applied above.
      ownership_checked = checked_tokens & OWNERSHIP_TOKENS
      case ownership_checked
      when [ "owned" ]
        rel = if platform_active
                rel.where(id: Game.owned_on(platform_slugs).select(:id))
        else
                rel.where(id: Game.owned.select(:id))
        end
      when [ "wishlist" ]
        # wishlist is ALWAYS global — "doesn't own ANYWHERE". The
        # platform-availability binding (if any) is already applied
        # above via the platform axis.
        rel = rel.where(id: Game.wishlist.select(:id))
      when %w[owned wishlist], %w[wishlist owned]
        # Both checked — rule (f). With no platform, no narrowing
        # (every game passes ownership). With a platform set, union
        # (owned-on-platform) ∪ (not-owned-globally).
        if platform_active
          owned_on_ids = Game.owned_on(platform_slugs).select(:id)
          wishlist_ids = Game.wishlist.select(:id)
          rel = rel.where(id: owned_on_ids).or(rel.where(id: wishlist_ids))
        end
      end

      # AXIS 3: Engagement (played). Single chip. When platform set,
      # binds to `played_platform_id` in the expanded slug set. Not
      # checked → axis inactive (no engagement constraint).
      if checked_tokens.include?("played")
        rel = rel.where(id: Game.played.select(:id))
        if platform_active
          played_platform_ids = Platform.where(slug: platform_slugs).pluck(:id)
          rel = if played_platform_ids.empty?
                  rel.where("1 = 0")
          else
                  rel.where(played_platform_id: played_platform_ids)
          end
        end
      end

      rel
    end

    # Expand the checked platform tokens to a flat list of DB slugs.
    # When all platform chips are checked we return the full union so
    # callers that want availability filtering can still pass the
    # complete set (the build_results path skips the axis when all
    # checked, but this helper stays general).
    def expand_platform_slugs(platform_tokens)
      platform_tokens.flat_map { |t| TOKEN_TO_PLATFORM_SLUGS.fetch(t, [ t ]) }.uniq
    end
  end
end
