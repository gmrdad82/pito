require "rails_helper"

RSpec.describe "API: Footages (importer)", type: :request do
  let!(:project) { create(:project) }

  describe "GET /api/projects/:project_id/footages" do
    let!(:footage) { create(:footage, project: project) }

    it "returns the project's footages as JSON" do
      get api_project_footages_path(project)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.size).to eq(1)
      expect(body.first["id"]).to eq(footage.id)
      expect(body.first["has_commentary_track"]).to eq("no")
    end
  end

  describe "POST /api/projects/:project_id/footages" do
    let(:base_attrs) do
      {
        kind: "a_roll",
        source: "obs",
        local_path: "/tmp/footage/new-clip.mp4",
        filename: "new-clip.mp4",
        bit_depth: 8,
        has_commentary_track: "no"
      }
    end

    it "creates a footage row from JSON" do
      expect {
        post api_project_footages_path(project),
             params: { footage: base_attrs }.to_json,
             headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      }.to change(Footage, :count).by(1)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["filename"]).to eq("new-clip.mp4")
      expect(body["has_commentary_track"]).to eq("no")
    end

    it "rejects invalid yes/no values" do
      bad = base_attrs.merge(has_commentary_track: true)
      post api_project_footages_path(project),
           params: { footage: bad }.to_json,
           headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "denormalizes tenant_id from project" do
      post api_project_footages_path(project),
           params: { footage: base_attrs }.to_json,
           headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      footage = Footage.last
      expect(footage.tenant_id).to eq(project.tenant_id)
    end
  end
end
