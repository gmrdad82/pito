require "rails_helper"
require "ostruct"

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

  # 2026-05-18 — `:bundle_add` omnisearch endpoint that backs the
  # bundle modal's `[+]` "add member" trigger. Returns local games
  # (Meilisearch / Postgres ILIKE fallback, with this bundle's
  # existing members filtered out) AND IGDB hits as separate sections.
  # The local section gives each row an `[add]` POSTing to
  # `/bundles/:id/members`; the IGDB section gives each row an `[add]`
  # POSTing to `/bundles/:id/members/from_igdb` (creates a stub Game,
  # adds to bundle, kicks async sync).
  describe "GET /bundles/:id/search" do
    let(:bundle) { create(:bundle, name: "Fighters") }

    before do
      # Force the Meilisearch HTTP call to fail so the controller path
      # exercises the Postgres ILIKE fallback in
      # `Meilisearch::SearchGames`. Mirrors the real-world case the
      # user reported (empty / stale Meilisearch index).
      stub_request(:post, %r{/indexes/games_test/search}).to_return(status: 500, body: "boom")
      # Stub IGDB so we don't hit the live API. Two payload shapes:
      # one with a hit, one with no hits.
      allow(Rails.application.credentials).to receive(:igdb).and_return(
        OpenStruct.new(client_id: "id", client_secret: "secret")
      )
      stub_request(:post, %r{id\.twitch\.tv/oauth2/token})
        .to_return(status: 200, body: { access_token: "T", expires_in: 5_184_000 }.to_json)
    end

    it "renders local matches with [add] buttons pointing at /bundles/:id/members" do
      create(:game, title: "Street Fighter 6")
      stub_request(:post, "https://api.igdb.com/v4/games").to_return(status: 200, body: "[]")

      get search_bundle_path(bundle), params: { q: "street" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Street Fighter 6")
      expect(response.body).to include(bundle_members_path(bundle_id: bundle.id))
    end

    it "renders IGDB hits with [add] buttons pointing at /from_igdb (not muted 'in igdb only' text)" do
      igdb_payload = [ { "id" => 7346, "name" => "Tekken 8", "first_release_date" => 1704067200 } ]
      stub_request(:post, "https://api.igdb.com/v4/games")
        .to_return(status: 200, body: igdb_payload.to_json)

      get search_bundle_path(bundle), params: { q: "tekken" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Tekken 8")
      expect(response.body).to include(from_igdb_bundle_members_path(bundle_id: bundle.id))
      # Per-row IGDB `[add]` button replaces the prior "in igdb only" text.
      expect(response.body).to match(/\[<span class="bl">add<\/span>\]/)
      expect(response.body).not_to include("in igdb only")
    end

    it "filters out local games that already belong to the bundle" do
      already_in = create(:game, title: "Street Fighter 4")
      _free      = create(:game, title: "Street Fighter 6")
      bundle.bundle_members.create!(game_id: already_in.id)
      stub_request(:post, "https://api.igdb.com/v4/games").to_return(status: 200, body: "[]")

      get search_bundle_path(bundle), params: { q: "street" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Street Fighter 6")
      expect(response.body).not_to include("Street Fighter 4")
    end
  end
end
