require "rails_helper"

# Phase 14 §3 / Phase 27 follow-up (2026-05-17) — Bundles request spec.
# After the 2026-05-17 simplification a Bundle has only `name`; the
# `seed_from_igdb` action + the `bundle_type` / `igdb_source_*` form
# fields are gone. The `games_pane` member action (replacement for the
# old Collection games-pane) is new.
RSpec.describe "Bundles", type: :request do
  describe "GET /bundles" do
    it "returns 200 and renders the index" do
      get bundles_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("bundles")
    end

    it "shows the empty state copy when no bundles exist" do
      get bundles_path
      expect(response.body).to include("no bundles yet")
      expect(response.body).to include("[ add bundle ]")
    end

    it "lists existing bundles as tiles" do
      create(:bundle, name: "Soulslikes")
      get bundles_path
      expect(response.body).to include("Soulslikes")
      expect(response.body).to include("bundles-grid")
    end

    it "renders the em-dash fallback when composite_cover_path is blank" do
      create(:bundle, name: "Untiled")
      get bundles_path
      expect(response.body).to include("Untiled")
      expect(response.body).to include("—")
    end
  end

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
      bundle.update_columns(composite_cover_path: "composites/bundle-#{bundle.id}.jpg")
      get bundle_path(bundle)
      expect(response.body).to include("/composites/bundle-#{bundle.id}.jpg")
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

  describe "GET /bundles/new" do
    it "renders the new form" do
      get new_bundle_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("new bundle")
    end

    it "wraps the new form in a .pane.pane--standalone" do
      get new_bundle_path
      html = Nokogiri::HTML.fragment(response.body)
      pane = html.at_css("div.pane.pane--standalone")
      expect(pane).not_to be_nil
      expect(pane.at_css('input[name="bundle[name]"]')).not_to be_nil
    end
  end

  describe "POST /bundles" do
    it "creates a bundle from name only" do
      expect {
        post bundles_path, params: { bundle: { name: "Soulslikes" } }
      }.to change(Bundle, :count).by(1)

      bundle = Bundle.last
      expect(bundle.name).to eq("Soulslikes")
      expect(response).to redirect_to(bundle_path(bundle))
    end

    it "rejects a blank name" do
      post bundles_path, params: { bundle: { name: "" } }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "silently drops smuggled non-permitted attributes" do
      post bundles_path, params: {
        bundle: { name: "X", composite_cover_path: "../../etc/passwd" }
      }
      expect(Bundle.last.composite_cover_path).to be_nil
    end
  end

  describe "GET /bundles/:id/edit" do
    let(:bundle) { create(:bundle, name: "Old") }

    it "wraps the edit form in a .pane.pane--standalone" do
      get edit_bundle_path(bundle)
      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML.fragment(response.body)
      pane = html.at_css("div.pane.pane--standalone")
      expect(pane).not_to be_nil
      expect(pane.at_css('input[name="bundle[name]"]')).not_to be_nil
    end
  end

  describe "PATCH /bundles/:id" do
    let(:bundle) { create(:bundle, name: "Old") }

    it "updates the name" do
      patch bundle_path(bundle), params: { bundle: { name: "New" } }
      expect(bundle.reload.name).to eq("New")
      expect(response).to redirect_to(bundle_path(bundle))
    end

    it "silently drops smuggled composite_cover_path" do
      patch bundle_path(bundle), params: {
        bundle: { name: "x", composite_cover_path: "../../etc/passwd" }
      }
      expect(bundle.reload.composite_cover_path).to be_nil
    end

    it "rejects a blank name update" do
      patch bundle_path(bundle), params: { bundle: { name: "" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE /bundles/:id" do
    it "redirects through the action-confirmation screen" do
      bundle = create(:bundle)
      delete bundle_path(bundle)
      expect(response).to redirect_to(deletions_path(type: "bundle", ids: bundle.id))
    end
  end

  describe "deletion-flow integration via /deletions/bundle/:ids" do
    let!(:bundle) { create(:bundle, name: "DelMe") }

    it "GET /deletions/bundle/:ids renders the action screen" do
      get deletions_path(type: "bundle", ids: bundle.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("DelMe")
    end

    it "POST /deletions/bundle/:ids enqueues the bulk delete and cleans up" do
      post deletions_path(type: "bundle", ids: bundle.id)
      expect(response).to have_http_status(:ok).or have_http_status(:found)
      expect(BulkOperation.count).to eq(1)
    end
  end

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
