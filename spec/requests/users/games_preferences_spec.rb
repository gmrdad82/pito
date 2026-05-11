require "rails_helper"

# Phase 27 — 01d. Display mode switcher persistence endpoint.
#
# `PATCH /users/games_preferences` writes the authenticated user's
# `preferred_games_display_mode` enum. Single caller — the `[grid]
# [list] [shelves]` switcher on `/games` (a `button_to` form, no JS).
# On success the controller redirects back to
# `/games?display=<mode>` so the resolved mode renders immediately
# AND the user's preference persists for fresh-tab visits.
RSpec.describe "Users::GamesPreferences", type: :request do
  let(:password) { "supersecret123" }
  let(:user) do
    User.first || create(:user, password: password, password_confirmation: password)
  end

  before do |example|
    next if example.metadata[:unauthenticated]
    user.update!(password: password, password_confirmation: password)
    sign_in_as(user)
  end

  describe "PATCH /users/games_preferences" do
    it "persists list mode and redirects to /games?display=list" do
      patch users_games_preferences_path, params: { mode: "list" }

      expect(user.reload.preferred_games_display_mode).to eq("list")
      expect(response).to redirect_to(games_path(display: "list"))
      expect(flash[:notice]).to be_present
    end

    it "persists shelves_by_letter mode (legacy enum-key path)" do
      patch users_games_preferences_path, params: { mode: "shelves_by_letter" }

      expect(user.reload.preferred_games_display_mode).to eq("shelves_by_letter")
      expect(response).to redirect_to(games_path(display: "shelves_by_letter"))
    end

    # 2026-05-11 polish v2 — `default` is the URL alias for the
    # canonical enum value `shelves_by_letter`. PATCH writes the
    # canonical enum but echoes the alias on the redirect so the
    # shareable URL stays readable.
    it "accepts the `default` alias and writes shelves_by_letter" do
      patch users_games_preferences_path, params: { mode: "default" }

      expect(user.reload.preferred_games_display_mode).to eq("shelves_by_letter")
      expect(response).to redirect_to(games_path(display: "default"))
    end

    it "persists grid mode (round-trip from a non-default value)" do
      user.update!(preferred_games_display_mode: :list)

      patch users_games_preferences_path, params: { mode: "grid" }

      expect(user.reload.preferred_games_display_mode).to eq("grid")
      expect(response).to redirect_to(games_path(display: "grid"))
    end

    it "ignores an unknown mode token and leaves the preference alone" do
      user.update!(preferred_games_display_mode: :list)

      patch users_games_preferences_path, params: { mode: "tilemap" }

      expect(user.reload.preferred_games_display_mode).to eq("list")
      expect(response).to redirect_to(games_path)
      expect(flash[:alert]).to be_present
    end

    it "ignores a blank mode token" do
      user.update!(preferred_games_display_mode: :list)

      patch users_games_preferences_path, params: { mode: "" }

      expect(user.reload.preferred_games_display_mode).to eq("list")
      expect(response).to redirect_to(games_path)
      expect(flash[:alert]).to be_present
    end

    it "settles on the last value across two rapid PATCHes" do
      patch users_games_preferences_path, params: { mode: "list" }
      patch users_games_preferences_path, params: { mode: "shelves_by_letter" }

      expect(user.reload.preferred_games_display_mode).to eq("shelves_by_letter")
    end
  end

  describe "unauthenticated", :unauthenticated do
    it "bounces to /login without writing anything" do
      patch users_games_preferences_path, params: { mode: "list" }

      expect(response).to redirect_to(login_path)
    end
  end

  describe "route shape" do
    it "exposes a friendly /users/games_preferences URL" do
      expect(users_games_preferences_path).to eq("/users/games_preferences")
    end
  end

  describe "yes / no boundary sweep" do
    # The preference endpoint does not carry an external Boolean. The
    # `mode` value is a path-segment-style enum string. This spec is
    # the rule-sweep backstop: assert no Boolean leaks into the wire.
    it "does not accept or echo a Boolean field on the response body" do
      patch users_games_preferences_path,
            params: { mode: "grid", enabled: true }
      # The redirect body is short; no `true`/`false` should appear.
      expect(response.body).not_to include(">true<")
      expect(response.body).not_to include(">false<")
    end
  end
end
