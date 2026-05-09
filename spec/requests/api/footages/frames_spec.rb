require "rails_helper"

# Phase 7.5 §06 — Bulk frame upload from the importer (PATCH).
#
# Bearer-authenticated; CLI integration tests do NOT anchor this URL —
# the importer dispatch lands later. The wire shape is multipart, with
# parts keyed by `frames[<HH-MM-SS>][master|thumb]`.
RSpec.describe "API: Footage frames bulk upload", type: :request do
  let(:tmp_root) { Dir.mktmpdir("pito-assets-api-frames-spec") }
  let(:auth_tenant) { Tenant.first || create(:tenant) }
  let(:auth_user)   { User.first   || create(:user, tenant: auth_tenant) }
  let(:auth_pair) do
    ApiToken.generate!(
      tenant: auth_tenant, user: auth_user, name: "frames-spec",
      scopes: [ Scopes::PROJECT_READ, Scopes::PROJECT_WRITE ]
    )
  end
  let(:auth_token) { auth_pair.last }
  let(:auth_headers) { { "Authorization" => "Bearer #{auth_token}" } }

  let!(:project) { create(:project, tenant: auth_tenant) }
  let!(:footage) { create(:footage, project: project, tenant: auth_tenant, duration_seconds: 240) }

  let(:jpeg_bytes) { "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00".b }

  around do |example|
    prev = ENV["PITO_ASSETS_PATH"]
    ENV["PITO_ASSETS_PATH"] = tmp_root
    example.run
  ensure
    ENV["PITO_ASSETS_PATH"] = prev
    FileUtils.remove_entry(tmp_root) if File.exist?(tmp_root)
  end

  def upload(bytes, filename: "frame.jpg")
    file = Tempfile.new([ filename, ".jpg" ], binmode: true)
    file.write(bytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "image/jpeg", true, original_filename: filename)
  end

  describe "PATCH /api/footages/:id/frames" do
    it "writes master + thumb files under the assets root and stamps frames_extracted_at" do
      params = {
        frames: {
          "00-01-00" => { master: upload(jpeg_bytes), thumb: upload(jpeg_bytes) }
        }
      }

      expect {
        patch frames_api_footage_path(footage), params: params, headers: auth_headers
      }.to change { footage.reload.frames_extracted_at }.from(nil)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["frames_uploaded"]).to eq(2)
      expect(body["footage_id"]).to eq(footage.id)

      master_path = Pito::AssetsRoot.path("footage_thumbs", footage.id.to_s, "m", "00-01-00.jpg")
      thumb_path  = Pito::AssetsRoot.path("footage_thumbs", footage.id.to_s, "t", "00-01-00.jpg")
      expect(File.exist?(master_path)).to be(true)
      expect(File.exist?(thumb_path)).to be(true)
      expect(File.binread(master_path)).to eq(jpeg_bytes)
    end

    it "does not stamp frames_extracted_at when the payload contains no valid parts" do
      params = { frames: {} }

      patch frames_api_footage_path(footage), params: params, headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["frames_uploaded"]).to eq(0)
      expect(footage.reload.frames_extracted_at).to be_nil
    end

    it "rejects path-traversal attempts in the timestamp key" do
      params = {
        frames: {
          "../etc/passwd" => { master: upload(jpeg_bytes) }
        }
      }

      patch frames_api_footage_path(footage), params: params, headers: auth_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["frames_uploaded"]).to eq(0)
      # Nothing was written under the assets root.
      expect(Dir.glob("#{tmp_root}/footage_thumbs/**/*.jpg")).to be_empty
    end

    it "rejects timestamp keys that contain a hidden traversal segment" do
      params = {
        frames: {
          "00-../00" => { master: upload(jpeg_bytes) }
        }
      }
      patch frames_api_footage_path(footage), params: params, headers: auth_headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["frames_uploaded"]).to eq(0)
    end

    it "returns 401 when the request has no bearer token" do
      params = { frames: { "00-01-00" => { master: upload(jpeg_bytes) } } }
      patch frames_api_footage_path(footage), params: params
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 403 when the token lacks the project:write scope" do
      ro_pair = ApiToken.generate!(
        tenant: auth_tenant, user: auth_user, name: "frames-ro",
        scopes: [ Scopes::PROJECT_READ ]
      )
      ro_token = ro_pair.last

      patch frames_api_footage_path(footage),
            params: { frames: { "00-01-00" => { master: upload(jpeg_bytes) } } },
            headers: { "Authorization" => "Bearer #{ro_token}" }

      expect(response).to have_http_status(:forbidden)
    end

    it "returns 404 when the footage row is missing" do
      patch "/api/footages/999999/frames",
            params: { frames: {} },
            headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
