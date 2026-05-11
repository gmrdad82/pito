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
end
