# Phase 27 §01b — Filter row query object.
#
# `Games::Filter.new(scope:, tokens:).results` returns an
# `ActiveRecord::Relation` narrowed by a comma-separated list of
# canonical filter-row tokens.
#
# Token vocabulary (the only canonical strings):
#
#   recorded released scheduled
#   owned not_owned
#   ps5 switch2 steam gog epic
#
# Composition rules (locked by spec §"Composition rules"):
#
#   1. Partition tokens into Status / Ownership / Platform / Unknown.
#   2. Buckets AND together; multiple tokens within Status OR together,
#      multiple tokens within Platform OR together.
#   3. Platform-bucket semantics flip on the Ownership bucket state:
#        - empty       → P-1: scope.on_platform(slug)
#        - [owned]     → P-2: scope.owned_on(slug)
#        - [not_owned] → C-1: scope.not_owned.on_platform(slug)
#        - both        → C-3 contradiction → Game.none
#   4. Unknown tokens are dropped (never echoed in chip hrefs); the
#      caller exposes them via `#dropped_tokens` for the request spec.
#   5. Token order does not affect the result set.
#
# The query is composable with `.where` chains downstream (`#results`
# returns a relation, not an array), and `#results` is memoised so
# calling it twice produces the same SQL fingerprint.
module Games
  class Filter
    STATUS_TOKENS    = %w[recorded released scheduled].freeze
    OWNERSHIP_TOKENS = %w[owned not_owned].freeze
    # 2026-05-11 polish — `xbox` joins the platform token set. The
    # platforms canonical agent added Xbox to the seeded reference rows
    # (slug `xbox`, name `Xbox`), so the filter row recognises it as a
    # first-class chip alongside the original five.
    PLATFORM_TOKENS  = %w[ps5 switch2 steam gog epic xbox].freeze
    CANONICAL_TOKENS = (STATUS_TOKENS + OWNERSHIP_TOKENS + PLATFORM_TOKENS).freeze

    attr_reader :scope, :raw_tokens

    def initialize(scope: Game.all, tokens: [])
      @scope      = scope
      @raw_tokens = Array(tokens)
    end

    # The canonical, de-duped, recognised tokens currently active.
    def active_tokens
      @active_tokens ||= normalised_tokens.select { |t| CANONICAL_TOKENS.include?(t) }.uniq
    end

    # The tokens that were dropped because they were not canonical.
    def dropped_tokens
      @dropped_tokens ||= normalised_tokens.reject { |t| CANONICAL_TOKENS.include?(t) }
    end

    # True when both `owned` and `not_owned` are active simultaneously.
    def contradiction?
      ownership_tokens.size == 2
    end

    # The filtered `ActiveRecord::Relation`. Memoised — repeated calls
    # produce the same SQL fingerprint.
    def results
      @results ||= build_results
    end

    private

    def normalised_tokens
      @normalised_tokens ||= raw_tokens.map { |t| t.to_s.downcase.strip }.reject(&:empty?).uniq
    end

    def status_tokens
      active_tokens & STATUS_TOKENS
    end

    def ownership_tokens
      active_tokens & OWNERSHIP_TOKENS
    end

    def platform_tokens
      active_tokens & PLATFORM_TOKENS
    end

    def build_results
      # C-3 contradiction wins regardless of any other tokens.
      return scope.none if contradiction?

      rel = scope
      rel = apply_status(rel)
      rel = apply_combined_ownership_and_platform(rel)
      rel
    end

    # Status bucket OR-composes: `recorded OR released OR scheduled`.
    #
    # P27 reviewer follow-up (non-blocking concern #3, 2026-05-11) —
    # the previous implementation materialised each bucket's `.ids` to
    # Ruby and unioned them in memory before issuing the outer
    # `where(id: ids)`. That worked for small libraries but doesn't
    # scale (the union grows with the library size, each `.ids` is a
    # full SELECT round-trip, and the outer `IN (?, ?, ...)` list
    # explodes once the union crosses a few thousand rows). The new
    # shape uses `Game.<scope>.select(:id)` so each branch is a
    # subquery; the union is composed via `.or` so the DB does the
    # work and the outer relation stays a single composable
    # `ActiveRecord::Relation`.
    def apply_status(rel)
      return rel if status_tokens.empty?

      union_rel = status_tokens.map { |t| status_scope_for(t) }.reduce { |a, b| a.or(b) }
      rel.where(id: union_rel.select(:id))
    end

    def status_scope_for(token)
      case token
      when "recorded"  then Game.recorded
      when "released"  then Game.released
      when "scheduled" then Game.scheduled
      end
    end

    # Ownership + Platform combinator. Platform tokens map to a
    # relation whose shape depends on the Ownership bucket state.
    # Multiple platforms OR together.
    #
    # Phase 28 §01a — the `owned` token swaps from the row-level
    # `Game.owned` to `Game.owned_rollup` (architect lean #7 locked):
    # a primary with an unowned base but an owned Deluxe edition now
    # appears in the `owned` filter, matching the "logical title"
    # framing of multi-version grouping.
    #
    # P27 reviewer follow-up (non-blocking concern #3, 2026-05-11) —
    # platform-OR combination no longer materialises `.ids` arrays to
    # Ruby. Each platform branch is a subquery passed through
    # `.where(id: rel.select(:id))`; multiple platforms are unioned
    # via repeated `.or` then handed to the outer relation as a
    # single subquery. The ownership-only branches use the same
    # subquery shape for consistency (the `owned_rollup` `.merge`
    # bug the previous comment warned about does not apply when the
    # rollup is consumed through `where(id: rel.select(:id))` — the
    # outer relation's other conditions are preserved verbatim).
    def apply_combined_ownership_and_platform(rel)
      if platform_tokens.empty?
        case ownership_tokens
        when [ "owned" ]
          rel.where(id: Game.owned_rollup.select(:id))
        when [ "not_owned" ]
          rel.merge(Game.not_owned)
        else
          rel
        end
      else
        union_rel = platform_tokens
                      .map { |slug| platform_relation_for(slug) }
                      .reduce { |a, b| a.or(b) }
        rel.where(id: union_rel.select(:id))
      end
    end

    def platform_relation_for(slug)
      if ownership_tokens == [ "owned" ]
        # P-2: owned specifically on this platform.
        Game.owned_on(slug)
      elsif ownership_tokens == [ "not_owned" ]
        # C-1: zero ownership rows AND released/scheduled on this platform.
        Game.not_owned.on_platform(slug)
      else
        # P-1: released or scheduled on this platform regardless of
        # ownership state.
        Game.on_platform(slug)
      end
    end
  end
end
