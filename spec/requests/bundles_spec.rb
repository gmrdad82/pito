require "rails_helper"

# Phase 14 §3 / Phase 27 follow-up (2026-05-17) — Bundles request spec.
# After the 2026-05-17 simplification a Bundle has only `name`; the
# `seed_from_igdb` action + the `bundle_type` / `igdb_source_*` form
# fields are gone. The `games_pane` member action (replacement for the
# old Collection games-pane) is new.
RSpec.describe "Bundles", type: :request do
  describe "GET /bundles/:id" do
    let(:bundle) { create(:bundle, name: "Test bundle") }

    it "returns 200" do
      get bundle_path(bundle)
      expect(response).to have_http_status(:ok)
    end

    it "renders the [no cover] placeholder when path is blank" do
      get bundle_path(bundle)
      expect(response.body).to include("[no cover]")
    end

    it "renders the composite cover image when path is present" do
      bundle.update_columns(composite_cover_path: "covers/bundles/#{bundle.id}/composite.jpg")
      get bundle_path(bundle)
      expect(response.body).to include("/covers/bundles/#{bundle.id}/composite.jpg")
    end

    it "renders the member list with each game's title" do
      g = create(:game, :synced, title: "Sekiro")
      bundle.bundle_members.create!(game: g)

      get bundle_path(bundle)
      expect(response.body).to include("Sekiro")
    end

    it "returns 404 when the bundle does not exist" do
      get "/bundles/999999"
      expect(response).to have_http_status(:not_found)
    end

    # Layout — left pane uses `pane--narrow` (cover hugs ~280px) and
    # right pane uses `pane--wide` (904px so the member table +
    # add-member form get breathing room). Mirrors /games/:id.
    it "uses the narrow + wide pane modifiers for the cover / members split" do
      get bundle_path(bundle)
      expect(response.body).to include("pane pane--narrow")
      expect(response.body).to include("pane pane--wide")
    end
  end

  # DELETE /bundles/:id — covered in `spec/requests/bundles_destroy_spec.rb`.
  # The legacy `/deletions/bundle/:ids` action-confirmation flow was
  # retired on 2026-05-18 in favor of the per-bundle on-page
  # `ConfirmModalComponent` + direct `DELETE /bundles/:id` (Turbo
  # Stream branch tears down the tile + modal, HTML branch redirects
  # back to /games for the JS-off fallback).

  # Phase 27 follow-up (2026-05-17) — replacement for the old
  # `Collections#games_pane` modal Turbo Frame.
  describe "GET /bundles/:id/games_pane" do
    let(:bundle) { create(:bundle, name: "Soulslikes") }

    it "renders the empty-state copy when the bundle has no members" do
      get games_pane_bundle_path(bundle)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("no games in this bundle yet")
    end

    it "renders the bundle's member games in alphabetical title order" do
      gamma = create(:game, :synced, title: "AlphabeticalGamma")
      alpha = create(:game, :synced, title: "AlphabeticalAlpha")
      beta  = create(:game, :synced, title: "AlphabeticalBeta")
      bundle.bundle_members.create!(game: gamma)
      bundle.bundle_members.create!(game: alpha)
      bundle.bundle_members.create!(game: beta)

      get games_pane_bundle_path(bundle)
      expect(response).to have_http_status(:ok)
      # Unique title prefixes so substring matches do not collide with
      # incidental text elsewhere on the page (CSS, alt attributes, etc.).
      expect(response.body.index("AlphabeticalAlpha")).to be < response.body.index("AlphabeticalBeta")
      expect(response.body.index("AlphabeticalBeta")).to be < response.body.index("AlphabeticalGamma")
    end

    it "renders inside the `bundles_modal_frame` Turbo Frame" do
      get games_pane_bundle_path(bundle)
      expect(response.body).to include('id="bundles_modal_frame"')
    end

    it "returns 404 when the bundle does not exist" do
      get "/bundles/999999/games_pane"
      expect(response).to have_http_status(:not_found)
    end
  end
end
