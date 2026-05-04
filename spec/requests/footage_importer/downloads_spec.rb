require "rails_helper"

RSpec.describe "FootageImporter::Downloads", type: :request do
  describe "GET /footage/importer/download (development path)" do
    let(:dev_path) { FootageImporter::DownloadsController::DEV_BINARY_PATH }

    context "when the binary is missing" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(dev_path).and_return(false)
      end

      it "returns 503 with a JSON error body" do
        get footage_importer_download_path
        expect(response).to have_http_status(:service_unavailable)
        body = JSON.parse(response.body)
        expect(body["error"]).to eq("pito_cli_unbuilt")
      end
    end

    context "when the binary is present" do
      let(:tmp) { Tempfile.new([ "pito-fake", ".bin" ]) }

      before do
        tmp.write("FAKE_BINARY")
        tmp.close
        stub_const("FootageImporter::DownloadsController::DEV_BINARY_PATH", tmp.path)
      end

      after { tmp.unlink rescue nil }

      it "streams the local binary with the canonical Content-Disposition" do
        get footage_importer_download_path
        expect(response).to have_http_status(:ok)
        expect(response.headers["Content-Disposition"]).to include('filename="pito"')
      end
    end
  end

  describe "GET /footage/importer/download (production path)", :webmock do
    before do
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig)
        .with(:github, anything, :token).and_return("ghp_fake_token")
    end

    let(:releases_url) { "https://api.github.com/repos/gmrdad82/pito/releases" }
    let(:asset_api_url) { "https://api.github.com/repos/gmrdad82/pito/releases/assets/123" }

    let(:releases_payload) do
      [
        {
          "tag_name" => "pito-abc1234",
          "created_at" => "2026-05-04T01:00:00Z",
          "assets" => [ { "name" => "pito", "url" => asset_api_url } ]
        }
      ]
    end

    it "fetches the latest pito-* release and streams the asset" do
      stub_request(:get, releases_url)
        .with(headers: { "Authorization" => "Bearer ghp_fake_token" })
        .to_return(status: 200, body: releases_payload.to_json, headers: { "Content-Type" => "application/json" })

      stub_request(:get, asset_api_url)
        .with(headers: { "Authorization" => "Bearer ghp_fake_token", "Accept" => "application/octet-stream" })
        .to_return(status: 200, body: "FAKE_BINARY", headers: { "Content-Type" => "application/octet-stream" })

      get footage_importer_download_path

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include('filename="pito"')
      expect(response.body).to eq("FAKE_BINARY")
    end

    it "returns 404 when no pito-* release exists" do
      stub_request(:get, releases_url).to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })
      get footage_importer_download_path
      expect(response).to have_http_status(:not_found)
    end
  end
end
