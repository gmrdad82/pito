require "rails_helper"

RSpec.describe "Collections", type: :request do
  describe "GET /collections" do
    it "returns 200" do
      get collections_path
      expect(response).to have_http_status(:ok)
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
