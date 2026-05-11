require "rails_helper"

RSpec.describe "Collections", type: :request do
  describe "GET /collections" do
    it "returns 200" do
      get collections_path
      expect(response).to have_http_status(:ok)
    end

    # Keyboard-navigation opt-in (2026-05-10): each collection row
    # carries `data-keyboard-row` + `data-keyboard-row-id` so the
    # global keyboard controller's `j`/`k` highlight resolves against
    # the row's collection id. Mirrors the channels / videos / projects
    # pattern.
    context "with collections (keyboard-row markup)" do
      let!(:collection_a) { create(:collection, name: "Alpha") }
      let!(:collection_b) { create(:collection, name: "Bravo") }

      it "tags each collection row with data-keyboard-row + data-keyboard-row-id" do
        get collections_path
        html = Nokogiri::HTML.fragment(response.body)
        rows = html.css("tbody tr[data-keyboard-row]")
        expect(rows.size).to eq(2)
        ids = rows.map { |r| r["data-keyboard-row-id"] }.sort
        expect(ids).to eq([ collection_a.id.to_s, collection_b.id.to_s ].sort)
      end
    end

    context "without collections (keyboard-row markup)" do
      it "leaves the empty-state body without keyboard-row markup" do
        get collections_path
        expect(response.body).not_to include("data-keyboard-row")
      end
    end
  end

  describe "POST /collections" do
    it "default-creates a collection" do
      expect {
        post collections_path
      }.to change(Collection, :count).by(1)
      expect(Collection.last.name).to eq("Untitled collection")
    end
  end

  describe "PATCH /collections/:id" do
    let!(:collection) { create(:collection) }

    it "renames" do
      patch collection_path(collection), params: { collection: { name: "Action games" } }
      expect(collection.reload.name).to eq("Action games")
    end
  end

  describe "DELETE /collections/:id" do
    let!(:collection) { create(:collection) }

    it "destroys the collection" do
      expect {
        delete collection_path(collection)
      }.to change(Collection, :count).by(-1)
    end
  end

  # Phase 27 follow-up (2026-05-11) — Collections modal pane.
  # `GET /collections/:id/games_pane` returns a Turbo Frame fragment
  # listing the games in the collection. Used by the `/games`
  # collections shelf modal trigger.
  describe "GET /collections/:id/games_pane" do
    let!(:collection) { create(:collection, name: "Retro") }
    let!(:chrono)     { create(:game, :synced, title: "Chrono Trigger", collection: collection) }
    let!(:bound)      { create(:game, :synced, title: "EarthBound",     collection: collection) }

    it "returns 200" do
      get games_pane_collection_path(collection)
      expect(response).to have_http_status(:ok)
    end

    it "renders the turbo-frame wrapper with id collections_modal_frame" do
      get games_pane_collection_path(collection)
      expect(response.body).to include('id="collections_modal_frame"')
    end

    it "renders each game's cover component linked to the game show page" do
      get games_pane_collection_path(collection)
      html = Nokogiri::HTML.fragment(response.body)
      hrefs = html.css("a[data-tile-game-id]").map { |a| a["href"] }
      expect(hrefs).to include(game_path(chrono))
      expect(hrefs).to include(game_path(bound))
    end

    it "lists games alphabetical case-insensitive" do
      get games_pane_collection_path(collection)
      html = Nokogiri::HTML.fragment(response.body)
      ids = html.css("a[data-tile-game-id]").map { |a| a["data-tile-game-id"].to_i }
      expect(ids).to eq([ chrono.id, bound.id ].sort_by { |id| Game.find(id).title.downcase })
    end

    it "renders the empty-state message when the collection has no games" do
      empty = create(:collection, name: "Empty")
      get games_pane_collection_path(empty)
      expect(response.body).to include("no games in this collection yet")
    end

    it "404s when the slug does not resolve to a collection" do
      get "/collections/nope-not-a-real-slug/games_pane"
      expect(response).to have_http_status(:not_found)
    end

    it "renders without the application layout (modal fragment)" do
      get games_pane_collection_path(collection)
      # No nav bar / footer chrome.
      expect(response.body).not_to include("<nav")
    end

    it "resolves a collection by numeric id (FriendlyId :finders module)" do
      get games_pane_collection_path(collection.id)
      expect(response).to have_http_status(:ok)
    end
  end
end
