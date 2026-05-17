# Phase 27 v2 spec 06 — Filter row (single compact row).
#
# Rewritten from the 01b two-row + `[clear all]` link + display-mode
# right-slot layout to a single compact band. Left side carries the
# status + ownership chips; right side carries the platform chips.
#
#   [ ] released [ ] scheduled [ ] owned [ ] wishlist [ ] played    [ ] PS5 [ ] Switch2 [ ] Steam
#
# Default state — every chip CHECKED, URL `/games` (no `?filters=`
# param) — communicates "showing the full list, nothing narrowed".
# Un-checking a chip narrows. Re-checking everything collapses back to
# `/games`.
#
# Phase 27 v2 spec 06 (2026-05-17 PC store collapse) — `GoG` + `Epic`
# chips retired; PC = Steam everywhere.
#
# `[clear all]` is GONE — the canonical clear action is re-checking
# every chip via the user. The contradiction notice is also GONE (v2
# has no `not_owned` chip; the contradiction cannot arise).
#
# The component mounts the `games-filter` Stimulus controller on the
# outer wrapper so a single controller instance manages every chip.
class Games::FilterRowComponent < ViewComponent::Base
  include Games::FiltersHelper

  # Render order — left side first, then right side. Mirrors the
  # spec's locked layout.
  LEFT_TOKENS  = (STATUS_TOKENS + OWNERSHIP_TOKENS).freeze
  RIGHT_TOKENS = PLATFORM_TOKENS

  # `checked_tokens:` is the SET of currently-checked chips (Array of
  # canonical token strings). When omitted, defaults to the full
  # universe (all chips checked, full-list state).
  def initialize(checked_tokens: nil, request_path: "/games", query_string_overrides: {})
    @checked_tokens = if checked_tokens.nil?
      TOKEN_UNIVERSE.dup
    else
      Array(checked_tokens).map(&:to_s)
    end
    @request_path           = request_path
    @query_string_overrides = (query_string_overrides || {}).to_h
  end

  attr_reader :checked_tokens, :request_path, :query_string_overrides

  def left_tokens
    LEFT_TOKENS
  end

  def right_tokens
    RIGHT_TOKENS
  end

  def chip_for(token)
    Games::FilterChipComponent.new(
      token:          token,
      checked:        checked_tokens.include?(token),
      checked_tokens: checked_tokens,
      request_path:   request_path
    )
  end

  # JSON-encoded universe + request path. Consumed by the
  # `games-filter` Stimulus controller via `data-games-filter-...-value`
  # attributes so the controller can decide when the URL collapses to
  # `/games` (universe checked) vs `/games?filters=<csv>` (subset).
  def universe_json
    TOKEN_UNIVERSE.to_json
  end
end
