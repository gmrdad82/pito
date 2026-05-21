# Phase 27 v2 spec 06 — Filter row chip (checkbox-style).
#
# Rewritten from the 01b "click toggles a token in/out of `?filters=`"
# contract to the v2 "click toggles CHECKED state via Stimulus" contract.
# The chip still renders as a bracketed `[ ] label` / `[x] label` link;
# the difference is:
#
#   - `href` now points at the canonical URL for the post-toggle state,
#     so JS-off users still navigate to the right URL (the listing
#     re-renders via a full request — accepted JS-off fallback).
#   - With JS on, the `games-filter` Stimulus controller intercepts the
#     click, flips the chip's checked state, applies the `played` →
#     `released + owned + at-least-one-platform` cascade when the
#     clicked chip is `played` AND checking it, mutates the URL via
#     `history.replaceState`, and refreshes the Turbo Frame.
#   - The `data-implied` attribute carries the cascade target tokens
#     (only `played` populates it).
class Game::FilterChipComponent < ViewComponent::Base
  include Games::FiltersHelper

  # Cascade implications: which tokens auto-check when this chip is
  # checked. Only `played` has an implication list per the v2 spec
  # (a played game is, by definition, released + owned; the Stimulus
  # side also force-checks every platform chip when zero are checked
  # — that branch is decided in JS, not declared here, to keep the
  # data attribute simple and stable).
  IMPLICATIONS = {
    "played" => %w[released owned]
  }.freeze

  def initialize(token:, checked:, checked_tokens:, request_path: "/games")
    unless TOKEN_UNIVERSE.include?(token.to_s)
      raise ArgumentError,
            "FilterChipComponent token must be canonical: got #{token.inspect}"
    end
    raise ArgumentError, "FilterChipComponent request_path must be present" if request_path.to_s.empty?

    @token          = token.to_s
    @checked        = checked ? true : false
    @checked_tokens = Array(checked_tokens).map(&:to_s)
    @request_path   = request_path
  end

  attr_reader :token, :checked_tokens, :request_path

  def checked?
    @checked
  end

  def label
    chip_label(token)
  end

  # The href reflects the post-toggle URL so JS-off users get the
  # right page on click. When this chip is currently CHECKED, toggling
  # removes it from the set; when UNCHECKED, toggling adds it.
  # Cascade implications are NOT baked into the href (the Stimulus
  # controller is the only place the cascade fires; JS-off users get
  # the literal chip flip, which is the v2 spec's accepted fallback).
  def href
    next_tokens =
      if checked?
        checked_tokens - [ token ]
      else
        (checked_tokens + [ token ]).uniq
      end
    games_path_with_checked(next_tokens, path: request_path)
  end

  def css_classes
    classes = [ "filter-chip" ]
    classes << "chip--active" if checked?
    classes.join(" ")
  end

  # Stimulus data attributes. The controller reads `data-filter-token`
  # to know which chip flipped; `data-implied` carries the cascade
  # target tokens (only `played` populates it; absent for every other
  # chip).
  def data_attributes
    attrs = {
      filter_token:         token,
      games_filter_target:  "chip",
      action:               "click->games-filter#toggle"
    }
    if IMPLICATIONS[token]
      attrs[:implied] = IMPLICATIONS[token].join(",")
    end
    attrs
  end
end
