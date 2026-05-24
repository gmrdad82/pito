# Phase 27 v2 spec 06 — Filter row (single compact row).
#
# Rewritten from the 01b two-row + `[clear all]` link + display-mode
# right-slot layout to a single compact band. Left side carries the
# status + ownership chips; right side carries the platform chips.
#
# Phase 29 (2026-05-25) — `wishlist` token retired; replaced by
# `not_owned` chip (label: "not owned").
#
#   [ ] released [ ] scheduled [ ] owned [ ] not owned [ ] played    [ ] PS [ ] Switch [ ] Steam
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
class Game::FilterRowComponent < ViewComponent::Base
  include Games::FiltersHelper

  # Render order — left side first, then right side. Mirrors the
  # spec's locked layout.
  LEFT_TOKENS  = (STATUS_TOKENS + OWNERSHIP_TOKENS).freeze
  RIGHT_TOKENS = PLATFORM_TOKENS

  # `checked_tokens:` is the SET of currently-checked chips (Array of
  # canonical token strings). When omitted, defaults to the
  # `DEFAULT_CHECKED_TOKENS` set (universe MINUS `played`,
  # user-locked 2026-05-17) — the bare-`/games` full-list state.
  def initialize(checked_tokens: nil, request_path: "/games", query_string_overrides: {})
    @checked_tokens = if checked_tokens.nil?
      DEFAULT_CHECKED_TOKENS.dup
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
    Game::FilterChipComponent.new(
      token:          token,
      checked:        checked_tokens.include?(token),
      checked_tokens: checked_tokens,
      request_path:   request_path
    )
  end

  # JSON-encoded universe + request path. Consumed by the
  # `games-filter` Stimulus controller via `data-games-filter-...-value`
  # attributes so the controller can decide when the URL collapses to
  # `/games` (default-checked set, universe minus `played`) vs
  # `/games?filters=<csv>` (anything else).
  def universe_json
    TOKEN_UNIVERSE.to_json
  end

  # JSON-encoded default-checked set. The Stimulus controller compares
  # the current chip state against this set to decide whether to emit
  # the bare `/games` URL (default match) or `/games?filters=<csv>`
  # (any other state, including the explicit-universe with `played`
  # checked).
  def default_checked_json
    DEFAULT_CHECKED_TOKENS.to_json
  end
end
