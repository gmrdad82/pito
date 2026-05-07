require "rails_helper"

RSpec.describe "API: Footages (importer)", type: :request do
  # Phase 3 — Step B. Api::* endpoints now require a bearer token. Mint
  # one with both project scopes so the existing happy-path examples
  # stay green; the per-scope reject matrix lives in
  # spec/requests/api/auth_concern_spec.rb.
  let(:auth_tenant) { Tenant.first || create(:tenant) }
  let(:auth_user)   { User.first   || create(:user, tenant: auth_tenant) }
  let(:auth_pair) do
    ApiToken.generate!(
      tenant: auth_tenant, user: auth_user, name: "footages-spec",
      scopes: [ Scopes::PROJECT_READ, Scopes::PROJECT_WRITE ]
    )
  end
  let(:auth_token) { auth_pair.last }
  let(:auth_headers_only) { { "Authorization" => "Bearer #{auth_token}" } }
  let(:json_headers) do
    {
      "CONTENT_TYPE" => "application/json",
      "ACCEPT"       => "application/json",
      "Authorization" => "Bearer #{auth_token}"
    }
  end

  let!(:project) { create(:project) }

  describe "GET /api/projects/:project_id/footages" do
    let!(:footage) { create(:footage, project: project, fps: BigDecimal("60.0")) }

    it "returns the project's footages as JSON" do
      get api_project_footages_path(project), headers: auth_headers_only
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.size).to eq(1)
      expect(body.first["id"]).to eq(footage.id)
      expect(body.first["has_commentary_track"]).to eq("no")
    end

    it "serializes fps as a JSON number (matching Rust CLI's Option<f64>)" do
      get api_project_footages_path(project), headers: auth_headers_only
      body = JSON.parse(response.body)
      expect(body.first["fps"]).to be_a(Numeric)
      expect(body.first["fps"]).to eq(60.0)
    end

    it "serializes fps as null when nil" do
      footage.update!(fps: nil)
      get api_project_footages_path(project), headers: auth_headers_only
      body = JSON.parse(response.body)
      expect(body.first["fps"]).to be_nil
    end

    it "serializes filesize_bytes as null for rows the importer hasn't probed" do
      get api_project_footages_path(project), headers: auth_headers_only
      body = JSON.parse(response.body)
      expect(body.first).to have_key("filesize_bytes")
      expect(body.first["filesize_bytes"]).to be_nil
    end

    it "serializes filesize_bytes as the raw integer (not the human string)" do
      footage.update!(filesize_bytes: 12_345)
      get api_project_footages_path(project), headers: auth_headers_only
      body = JSON.parse(response.body)
      expect(body.first["filesize_bytes"]).to eq(12_345)
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
             headers: json_headers
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
           headers: json_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "denormalizes tenant_id from project" do
      post api_project_footages_path(project),
           params: { footage: base_attrs }.to_json,
           headers: json_headers
      footage = Footage.last
      expect(footage.tenant_id).to eq(project.tenant_id)
    end

    it "persists filesize_bytes from the create payload (round-trip)" do
      attrs = base_attrs.merge(filesize_bytes: 1234)
      post api_project_footages_path(project),
           params: { footage: attrs }.to_json,
           headers: json_headers
      expect(response).to have_http_status(:created)
      expect(Footage.last.filesize_bytes).to eq(1234)
      body = JSON.parse(response.body)
      expect(body["filesize_bytes"]).to eq(1234)
    end
  end

  # Phase 5.5 — symmetric member actions under `/api/`. The Rust importer's
  # PATCH and DELETE land here so the surface stays consistent with collection
  # actions; the HTML edit/destroy flow stays at top-level
  # `/footages/:id` (no `.json`) and is tested in
  # `spec/requests/footages_spec.rb`.
  describe "PATCH /api/footages/:id" do
    let!(:footage) { create(:footage, project: project, fps: BigDecimal("30.0")) }

    it "updates probed metadata from JSON" do
      patch api_footage_path(footage),
            params: {
              footage: {
                resolution: "3840x2160",
                fps: 59.94,
                bit_depth: 10,
                audio_track_count: 2,
                has_commentary_track: "yes"
              }
            }.to_json,
            headers: json_headers
      expect(response).to have_http_status(:ok)
      footage.reload
      expect(footage.resolution).to eq("3840x2160")
      expect(footage.fps.to_f).to eq(59.94)
      expect(footage.bit_depth).to eq(10)
      expect(footage.audio_track_count).to eq(2)
      expect(footage.has_commentary_track).to be true
    end

    it "serializes fps as a JSON number on the response" do
      patch api_footage_path(footage),
            params: { footage: { fps: 24.0 } }.to_json,
            headers: json_headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["fps"]).to be_a(Numeric)
      expect(body["fps"]).to eq(24.0)
    end

    it "rejects invalid yes/no values for has_commentary_track" do
      patch api_footage_path(footage),
            params: {
              footage: { audio_track_count: 2, has_commentary_track: true }
            }.to_json,
            headers: json_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "persists filesize_bytes from the JSON update payload (round-trip)" do
      patch api_footage_path(footage),
            params: { footage: { filesize_bytes: 5678 } }.to_json,
            headers: json_headers
      expect(response).to have_http_status(:ok)
      expect(footage.reload.filesize_bytes).to eq(5678)
      body = JSON.parse(response.body)
      expect(body["filesize_bytes"]).to eq(5678)
    end

    it "rejects requests without a bearer token" do
      patch api_footage_path(footage),
            params: { footage: { resolution: "1280x720" } }.to_json,
            headers: { "CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects tokens missing the project:write scope" do
      ro_pair = ApiToken.generate!(
        tenant: auth_tenant, user: auth_user, name: "footages-ro",
        scopes: [ Scopes::PROJECT_READ ]
      )
      ro_token = ro_pair.last
      patch api_footage_path(footage),
            params: { footage: { resolution: "1280x720" } }.to_json,
            headers: {
              "CONTENT_TYPE" => "application/json",
              "ACCEPT" => "application/json",
              "Authorization" => "Bearer #{ro_token}"
            }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /api/footages/:id" do
    let!(:footage) { create(:footage, project: project) }

    it "destroys the footage and returns 204" do
      expect {
        delete api_footage_path(footage), headers: auth_headers_only
      }.to change(Footage, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it "rejects requests without a bearer token" do
      delete api_footage_path(footage)
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects tokens missing the project:write scope" do
      ro_pair = ApiToken.generate!(
        tenant: auth_tenant, user: auth_user, name: "footages-ro",
        scopes: [ Scopes::PROJECT_READ ]
      )
      ro_token = ro_pair.last
      delete api_footage_path(footage),
             headers: { "Authorization" => "Bearer #{ro_token}" }
      expect(response).to have_http_status(:forbidden)
    end
  end
end
