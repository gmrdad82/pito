require "rails_helper"

RSpec.describe "Footages", type: :request do
  let!(:project) { create(:project) }
  let!(:footage) { create(:footage, project: project) }

  describe "GET /footages/:id/edit" do
    it "returns 200 (HTML)" do
      get edit_footage_path(footage)
      expect(response).to have_http_status(:ok)
    end

    it "renders the footage filename in the heading" do
      footage.update!(filename: "clip.mkv")
      get edit_footage_path(footage)
      expect(response.body).to include("clip.mkv")
    end
  end

  describe "GET /footages/:id" do
    it "returns 200 (HTML)" do
      get footage_path(footage)
      expect(response).to have_http_status(:ok)
    end

    it "returns JSON with yes/no booleans" do
      get footage_path(footage), as: :json
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["has_commentary_track"]).to eq("no")
    end

    it "serializes filesize_bytes as null for rows the importer hasn't probed" do
      get footage_path(footage), as: :json
      body = JSON.parse(response.body)
      expect(body).to have_key("filesize_bytes")
      expect(body["filesize_bytes"]).to be_nil
    end

    it "serializes filesize_bytes as the raw integer (not the human string)" do
      footage.update!(filesize_bytes: 12_345)
      get footage_path(footage), as: :json
      body = JSON.parse(response.body)
      expect(body["filesize_bytes"]).to eq(12_345)
    end
  end

  describe "PATCH /footages/:id" do
    it "accepts HTML form-encoded edit fields" do
      patch footage_path(footage), params: { footage: { description: "new description" } }
      expect(footage.reload.description).to eq("new description")
    end

    it "accepts JSON with yes/no booleans for has_commentary_track" do
      patch footage_path(footage),
            params: {
              footage: {
                audio_track_count: 2,
                has_commentary_track: "yes"
              }
            }.to_json,
            headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(footage.reload.has_commentary_track).to be true
    end

    it "rejects invalid yes/no values" do
      patch footage_path(footage),
            params: {
              footage: { audio_track_count: 2, has_commentary_track: true }
            }.to_json,
            headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "persists filesize_bytes from the JSON update payload (round-trip)" do
      patch footage_path(footage),
            params: { footage: { filesize_bytes: 5678 } }.to_json,
            headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(footage.reload.filesize_bytes).to eq(5678)
      body = JSON.parse(response.body)
      expect(body["filesize_bytes"]).to eq(5678)
    end
  end

  describe "DELETE /footages/:id" do
    it "destroys the footage" do
      expect {
        delete footage_path(footage)
      }.to change(Footage, :count).by(-1)
    end
  end
end
