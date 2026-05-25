# Game::FilterRowComponent — single compact filter band for /games.
#
# Two axes: Lifecycle (released, scheduled) + Engagement (played).
# Default state — every chip CHECKED except `played`, URL `/games`.
# Un-checking a chip narrows the listing. Re-checking everything
# collapses back to bare `/games`.
#
# The component mounts the `games-filter` Stimulus controller on the
# outer wrapper so a single controller instance manages every chip.
class Game::FilterRowComponent < ViewComponent::Base
  include Games::FiltersHelper

  # All tokens in a single row — no left/right split needed with 3 chips.
  ALL_TOKENS = TOKEN_UNIVERSE

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

  def all_tokens
    ALL_TOKENS
  end

  def chip_for(token)
    Game::FilterChipComponent.new(
      token:          token,
      checked:        checked_tokens.include?(token),
      checked_tokens: checked_tokens,
      request_path:   request_path
    )
  end

  def universe_json
    TOKEN_UNIVERSE.to_json
  end

  def default_checked_json
    DEFAULT_CHECKED_TOKENS.to_json
  end
end
