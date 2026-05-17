# Phase 27 v2 spec 06 — Filter row query object.
#
# Rewritten from the 01b "tokens are NARROWING scopes" contract to the
# v2 "tokens are CHECKED chips" contract.
#
#   INPUT: `checked_tokens` (Array<String|Symbol>). May be nil.
#     - nil           → universe is implied (every chip checked, every
#                       group "all checked" → no narrowing → full list).
#     - empty Array   → every group has zero checks → final relation
#                       collapses to `Game.none` (intentional edge —
#                       the v2 spec calls this out as the "empty CSV"
#                       state).
#     - subset Array  → partition by group; apply per-group narrowing.
#
#   GROUPS: status (`released`, `scheduled`), ownership (`owned`,
#   `wishlist`, `played`), platform (`ps5`, `switch2`, `steam` — GoG
#   and Epic collapsed into Steam per the 2026-05-17 PC store collapse).
#
#   PER-GROUP RULE:
#     - All chips in the group checked → no narrowing for that group.
#     - Strict subset checked          → results are the UNION of the
#                                        sub-scopes within the group.
#     - Zero chips in the group checked → that group contributes
#                                        `Game.none` (i.e. the
#                                        intersection collapses).
#
#   CROSS-GROUP RULE: AND. The final relation is the intersection of
#   each group's contribution.
#
# Platform-precedence (preserved verbatim from 01b §2):
#   - When `owned` is in the checked set → platform tokens narrow via
#     `Game.owned_on(slug)` (the user actually owns the game on that
#     platform).
#   - Otherwise → platform tokens narrow via `Game.on_platform(slug)`
#     (released-or-scheduled on that platform; ownership-agnostic).
#
# Cascade note: this query object does NOT enforce the Stimulus-side
# `played` ⇒ `released + owned + at-least-one-platform` cascade. If a
# user hand-edits the URL to `?filters=played` (no implied chips), the
# query returns `Game.none` because the status group has zero checks
# and the ownership group only has `played` checked but the platform
# group has zero checks. The Stimulus controller is the only place
# the cascade fires; the query is intentionally simple.
module Games
  class Filter
    STATUS_TOKENS    = %w[released scheduled].freeze
    OWNERSHIP_TOKENS = %w[owned wishlist played].freeze
    # Phase 27 v2 spec 06 (2026-05-17 PC store collapse) — `gog` and
    # `epic` were retired; the three PC stores converge on `steam`.
    PLATFORM_TOKENS  = %w[ps5 switch2 steam].freeze

    # The universe — every canonical token. The helper module mirrors
    # this constant; keeping a copy here so callers that consume the
    # query object directly (request specs, the Stimulus controller's
    # `data-universe` JSON) have a single import surface.
    TOKEN_UNIVERSE = (STATUS_TOKENS + OWNERSHIP_TOKENS + PLATFORM_TOKENS).freeze

    # Legacy alias — Phase 27 §01b code-paths (the
    # `Games::FilterChipComponent` argument validation, the
    # `Games::FiltersHelper#parse_filter_tokens` fall-through, the
    # 01b request spec) referenced `CANONICAL_TOKENS`. The v2 token
    # universe is a STRICT SUBSET of the 01b set (drops `recorded`,
    # `not_owned`, `xbox`; adds `wishlist`, `played`); kept as an
    # alias of `TOKEN_UNIVERSE` so the alias point survives.
    CANONICAL_TOKENS = TOKEN_UNIVERSE

    attr_reader :scope, :raw_tokens

    def initialize(scope: Game.all, tokens: nil)
      @scope      = scope
      @raw_tokens = tokens  # nil retained as nil; Array passes through
    end

    # The canonical, de-duped, recognised tokens currently CHECKED.
    # Nil input is treated as "every chip checked" (universe).
    def checked_tokens
      @checked_tokens ||= begin
        if raw_tokens.nil?
          TOKEN_UNIVERSE.dup
        else
          arr = normalised_raw.select { |t| TOKEN_UNIVERSE.include?(t) }.uniq
          TOKEN_UNIVERSE.select { |t| arr.include?(t) }
        end
      end
    end

    # Backwards-compatible alias — some 01b callers still ask for
    # `active_tokens`. The v2 semantic is "checked", but the surface
    # name carries forward.
    def active_tokens
      checked_tokens
    end

    # Tokens that fell outside the canonical whitelist (kept for the
    # dev-mode warning carryover; the v2 filter row no longer renders
    # the warning but the request spec asserts unknowns are dropped
    # silently from the URL).
    def dropped_tokens
      @dropped_tokens ||= if raw_tokens.nil?
        []
      else
        normalised_raw.reject { |t| TOKEN_UNIVERSE.include?(t) }
      end
    end

    # 01b carried a `contradiction?` predicate for the C-3
    # `owned + not_owned` simultaneous-check case. v2 has no
    # `not_owned` chip, so the contradiction can never arise. The
    # method survives to keep the controller / component signature
    # stable, but always returns false.
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

    # The empty-CSV case (`raw_tokens == []` and `checked_tokens` ends
    # up empty) collapses every group to "zero checks" → final
    # relation is `Game.none`. The "nil tokens" case lands in
    # checked_tokens == TOKEN_UNIVERSE; every group is all-checked;
    # no narrowing applies.
    def build_results
      status_rel    = group_relation(STATUS_TOKENS,    method(:status_scope_for))
      ownership_rel = ownership_group_relation
      platform_rel  = platform_group_relation

      rel = scope
      rel = rel.where(id: status_rel.select(:id))    if status_rel
      rel = rel.where(id: ownership_rel.select(:id)) if ownership_rel
      rel = rel.where(id: platform_rel.select(:id))  if platform_rel
      rel
    end

    # Apply per-group narrowing rule. Returns:
    #   nil           when every chip in the group is checked
    #                 (no narrowing needed; caller skips the AND).
    #   Game.none     when zero chips in the group are checked
    #                 (intersection collapses).
    #   Relation      union of checked sub-scopes otherwise.
    #
    # Sub-scopes are normalised to `Game.where(id: scope.select(:id))`
    # before unioning so `.or` sees structurally compatible relations
    # (avoids ActiveRecord's "incompatible :distinct" /
    # "incompatible :joins" gotcha when mixing scopes with different
    # internals).
    def group_relation(group_tokens, scope_resolver)
      checked = checked_tokens & group_tokens
      return nil if checked == group_tokens
      return Game.none if checked.empty?

      checked.map { |t| Game.where(id: scope_resolver.call(t).select(:id)) }
             .reduce { |a, b| a.or(b) }
    end

    def status_scope_for(token)
      case token
      when "released"  then Game.released
      when "scheduled" then Game.scheduled
      end
    end

    # The ownership group routes through dedicated relations: `owned`
    # and `wishlist` are simple scopes; `played` is the `played_at`
    # column predicate.
    def ownership_group_relation
      group_relation(OWNERSHIP_TOKENS, method(:ownership_scope_for))
    end

    def ownership_scope_for(token)
      case token
      when "owned"    then Game.owned_rollup
      when "wishlist" then Game.wishlist
      when "played"   then Game.played
      end
    end

    # The platform group switches narrowing mode based on whether
    # `owned` is in the checked set (the spec's preserved 01b
    # platform-precedence rule):
    #   - `owned` checked → `Game.owned_on(slug)` per platform.
    #   - `owned` NOT checked → `Game.on_platform(slug)` per platform.
    # Either way the platform sub-scopes union together (OR within the
    # group).
    def platform_group_relation
      checked = checked_tokens & PLATFORM_TOKENS
      return nil if checked == PLATFORM_TOKENS
      return Game.none if checked.empty?

      checked.map { |slug| Game.where(id: platform_scope_for(slug).select(:id)) }
             .reduce { |a, b| a.or(b) }
    end

    def platform_scope_for(slug)
      if checked_tokens.include?("owned")
        Game.owned_on(slug)
      else
        Game.on_platform(slug)
      end
    end
  end
end
