require "rails_helper"

RSpec.describe "Bundles", type: :request do
  describe "GET /bundles" do
    # Phase 14 §3 — Steam-shelf revamp. The table-shape was replaced
    # with a wrapping tile grid. Empty-state copy and the existence of
    # tile rows is what the spec asserts; the grid layout is verified
    # via the `bundles-grid` class on the wrapping container.
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

    it "renders [no cover] em-dash fallback when composite_cover_path is blank" do
      create(:bundle, name: "Untiled")
      get bundles_path
      expect(response.body).to include("Untiled")
      expect(response.body).to include("—")
    end
  end

  describe "GET /bundles/:id" do
    let(:bundle) { create(:bundle, bundle_type: :custom, name: "Test bundle") }

    it "returns 200" do
      get bundle_path(bundle)
      expect(response).to have_http_status(:ok)
    end

    it "renders the [no cover] placeholder when path is blank" do
      get bundle_path(bundle)
      expect(response.body).to include("[no cover]")
    end

    it "renders the composite cover image when path is present" do
      bundle.update_columns(composite_cover_path: "composites/custom-#{bundle.id}.jpg")
      get bundle_path(bundle)
      expect(response.body).to include("/composites/custom-#{bundle.id}.jpg")
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

    # Layout revamp (2026-05-10) — left pane uses `pane--narrow`
    # (cover hugs ~280px) and right pane uses `pane--wide` (904px so the
    # member table + add-member form get breathing room). Mirrors
    # /games/:id.
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
  end

  describe "POST /bundles" do
    it "creates a custom bundle" do
      expect {
        post bundles_path, params: {
          bundle: { bundle_type: "custom", name: "Soulslikes" }
        }
      }.to change(Bundle, :count).by(1)

      bundle = Bundle.last
      expect(bundle.name).to eq("Soulslikes")
      expect(bundle.type_custom?).to be(true)
      expect(response).to redirect_to(bundle_path(bundle))
    end

    it "creates an IGDB-seeded series bundle" do
      expect {
        post bundles_path, params: {
          bundle: { bundle_type: "series", name: "Zelda",
                    igdb_source_type: "franchise", igdb_source_id: "1" }
        }
      }.to change(Bundle, :count).by(1)

      bundle = Bundle.last
      expect(bundle.type_series?).to be(true)
      expect(bundle.igdb_source_franchise?).to be(true)
      expect(bundle.igdb_source_id).to eq(1)
    end

    it "rejects a custom bundle with an igdb_source_type set" do
      post bundles_path, params: {
        bundle: { bundle_type: "custom", name: "x",
                  igdb_source_type: "franchise" }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects a series bundle missing igdb_source_id" do
      post bundles_path, params: {
        bundle: { bundle_type: "series", name: "x",
                  igdb_source_type: "franchise" }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /bundles/:id" do
    let(:bundle) { create(:bundle, bundle_type: :custom, name: "Old") }

    it "updates the name" do
      patch bundle_path(bundle), params: { bundle: { name: "New" } }
      expect(bundle.reload.name).to eq("New")
      expect(response).to redirect_to(bundle_path(bundle))
    end

    it "silently drops smuggled bundle_type changes" do
      patch bundle_path(bundle), params: {
        bundle: { name: "x", bundle_type: "series" }
      }
      expect(bundle.reload.type_custom?).to be(true)
    end

    it "silently drops smuggled igdb_source_type / id changes" do
      patch bundle_path(bundle), params: {
        bundle: { name: "x",
                  igdb_source_type: "franchise",
                  igdb_source_id: "42" }
      }
      bundle.reload
      expect(bundle.igdb_source_type).to be_nil
      expect(bundle.igdb_source_id).to be_nil
    end

    it "silently drops smuggled composite_cover_path" do
      patch bundle_path(bundle), params: {
        bundle: { name: "x", composite_cover_path: "../../etc/passwd" }
      }
      expect(bundle.reload.composite_cover_path).to be_nil
    end
  end

  describe "DELETE /bundles/:id" do
    it "redirects through the action-confirmation screen" do
      bundle = create(:bundle, bundle_type: :custom)
      delete bundle_path(bundle)
      expect(response).to redirect_to(deletions_path(type: "bundle", ids: bundle.id))
    end
  end

  describe "deletion-flow integration via /deletions/bundle/:ids" do
    let!(:bundle) { create(:bundle, bundle_type: :custom, name: "DelMe") }

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

  describe "POST /bundles/:id/seed_from_igdb" do
    it "rejects custom bundles with no IGDB source" do
      bundle = create(:bundle, bundle_type: :custom)
      post seed_from_igdb_bundle_path(bundle)
      expect(response).to redirect_to(bundle_path(bundle))
      follow_redirect!
      expect(response.body).to include("no IGDB source")
    end

    it "seeds members from IGDB and enqueues GameIgdbSync for newly-created games" do
      bundle = create(:bundle, :series)
      client = instance_double(Igdb::Client)
      allow(Igdb::Client).to receive(:new).and_return(client)
      allow(client).to receive(:fetch_games_for_franchise)
        .and_return([
          { "id" => 7346, "name" => "Zelda BotW" },
          { "id" => 113112, "name" => "Zelda TotK" }
        ])

      GameIgdbSync.clear
      expect {
        post seed_from_igdb_bundle_path(bundle)
      }.to change(BundleMember, :count).by(2)

      bundle.reload
      expect(bundle.games.pluck(:igdb_id)).to contain_exactly(7346, 113112)
      enqueued = GameIgdbSync.jobs.map { |j| j["args"].first }
      expect(enqueued.size).to eq(2)
    end

    it "is idempotent — re-running adds only new members" do
      bundle = create(:bundle, :series)
      g_existing = create(:game, igdb_id: 7346)
      bundle.bundle_members.create!(game: g_existing)

      client = instance_double(Igdb::Client)
      allow(Igdb::Client).to receive(:new).and_return(client)
      allow(client).to receive(:fetch_games_for_franchise)
        .and_return([
          { "id" => 7346, "name" => "Zelda BotW" },
          { "id" => 113112, "name" => "Zelda TotK" }
        ])

      expect {
        post seed_from_igdb_bundle_path(bundle)
      }.to change(BundleMember, :count).by(1)
    end

    it "handles IGDB API failure gracefully" do
      bundle = create(:bundle, :series)
      client = instance_double(Igdb::Client)
      allow(Igdb::Client).to receive(:new).and_return(client)
      allow(client).to receive(:fetch_games_for_franchise)
        .and_raise(Igdb::Client::ServerError.new("500"))

      post seed_from_igdb_bundle_path(bundle)
      bundle.reload
      expect(bundle.last_error).to include("seed:")
      expect(response).to redirect_to(bundle_path(bundle))
    end

    it "dispatches collection bundles to fetch_games_for_collection" do
      bundle = create(:bundle, :collection)
      client = instance_double(Igdb::Client)
      allow(Igdb::Client).to receive(:new).and_return(client)
      allow(client).to receive(:fetch_games_for_collection).and_return([])

      post seed_from_igdb_bundle_path(bundle)
      expect(client).to have_received(:fetch_games_for_collection)
    end

    it "dispatches genre bundles to fetch_games_for_genre" do
      bundle = create(:bundle, :genre)
      client = instance_double(Igdb::Client)
      allow(Igdb::Client).to receive(:new).and_return(client)
      allow(client).to receive(:fetch_games_for_genre).and_return([])

      post seed_from_igdb_bundle_path(bundle)
      expect(client).to have_received(:fetch_games_for_genre)
    end
  end
end
