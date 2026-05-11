# Phase 27 — 01d. Display mode switcher + three modes on `/games`.
#
# Persists the authenticated user's `preferred_games_display_mode`
# enum. The `/games` switcher submits a `button_to` form (no JS)
# carrying the desired mode in `params[:mode]`. On success, redirect
# back to `/games` with `?display=<mode>` so the resolved mode shows
# immediately on the next render — the index action's mode resolver
# prefers the URL param over the persisted pref, so the round-trip
# is visually instant. (The pref is also written, so subsequent
# fresh-tab visits land on the chosen mode by default.)
#
# Single `update` action — there is no read surface here; the chosen
# mode is read directly from `Current.user` everywhere else.
class Users::GamesPreferencesController < ApplicationController
  # `params[:mode]` allowlist — anything outside this set drops back to
  # the user's persisted preference with a flash alert. The values map
  # 1:1 onto `User#preferred_games_display_mode` enum keys. Frozen so a
  # request can't mutate the constant via something exotic.
  ALLOWED_MODES = %w[grid list shelves_by_letter].freeze

  def update
    mode = params[:mode].to_s

    unless ALLOWED_MODES.include?(mode)
      redirect_to games_path, alert: "unknown display mode."
      return
    end

    Current.user.update!(preferred_games_display_mode: mode)
    redirect_to games_path(display: mode), notice: "display mode saved."
  end
end
