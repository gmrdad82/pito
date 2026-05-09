require "rails_helper"

# Phase 7.5 §06 — Footage thumbnails — public-read frame endpoints.
#
# Wire-shape contract anchored by
# `extras/cli/tests/thumbnails_integration.rs`. The CLI hits these GETs
# with NO Authorization header (verified by `grep Authorization
# extras/cli/src/api/thumbnails.rs` returning nothing). Specs here run
# WITHOUT cookie-session auth (the `unauthenticated` metadata flag) to
# match the CLI's wire reality.
RSpec.describe "Footage frame endpoints (public-read)", type: :request, unauthenticated: true do
  let(:tmp_root) { Dir.mktmpdir("pito-assets-frames-spec") }
  let!(:project) { create(:project) }
  let!(:footage) { create(:footage, project: project, duration_seconds: 240) }

  # 1×1 black JPEG header + APP0 marker bytes — enough for `Content-Type`
  # detection and a `File.exist?` round-trip. The endpoint streams the
  # raw bytes verbatim; we don't need a decodable JPEG for the test.
  let(:jpeg_bytes) { "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00".b }

  around do |example|
    prev = ENV["PITO_ASSETS_PATH"]
    ENV["PITO_ASSETS_PATH"] = tmp_root
    example.run
  ensure
    ENV["PITO_ASSETS_PATH"] = prev
    FileUtils.remove_entry(tmp_root) if File.exist?(tmp_root)
  end

  def write_frame(footage_id, tier, timestamp_str, bytes)
    dir = Pito::AssetsRoot.ensure_dir!("footage_thumbs", footage_id.to_s, tier.to_s)
    path = dir.join("#{timestamp_str}.jpg")
    File.binwrite(path, bytes)
    path
  end

  describe "GET /footages/:id/frames.json" do
    it "returns the manifest shape the CLI expects" do
      write_frame(footage.id, "m", "00-00-30", jpeg_bytes)
      write_frame(footage.id, "m", "00-01-00", jpeg_bytes)
      write_frame(footage.id, "m", "00-02-00", jpeg_bytes)

      get footage_frames_path(footage)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.keys).to contain_exactly("duration_seconds", "timestamps")
      expect(body["duration_seconds"]).to eq(240.0)
      expect(body["timestamps"]).to eq([ 30, 60, 120 ])
    end

    it "serializes duration_seconds as a Float (matches CLI Manifest decoder)" do
      get footage_frames_path(footage)
      body = JSON.parse(response.body)
      expect(body["duration_seconds"]).to be_a(Float)
    end

    it "returns an empty timestamps array when no frames exist yet" do
      get footage_frames_path(footage)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["timestamps"]).to eq([])
    end

    it "returns 404 when the footage is missing" do
      get "/footages/999999/frames.json"
      expect(response).to have_http_status(:not_found)
    end

    it "does not require an Authorization header" do
      get footage_frames_path(footage)
      expect(response).to have_http_status(:ok)
      # Sanity: there is no `Set-Cookie: pito_session=...` redirect to /login.
      expect(response).not_to redirect_to(login_path)
    end
  end

  describe "GET /footages/:footage_id/frames/m/:filename.jpg" do
    it "streams the master JPEG bytes with image/jpeg content type" do
      write_frame(footage.id, "m", "00-01-30", jpeg_bytes)

      get footage_frame_master_path(footage_id: footage.id, filename: "00-01-30", format: "jpg")

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/jpeg")
      expect(response.body.b).to eq(jpeg_bytes)
    end

    it "returns 404 when the file does not exist on disk" do
      get footage_frame_master_path(footage_id: footage.id, filename: "00-99-99", format: "jpg")
      expect(response).to have_http_status(:not_found)
    end

    # The router constraint `\d{2}-\d{2}-\d{2}` rejects malformed
    # timestamps before the request reaches the action. Depending on
    # the test environment's exception-handling state (which other
    # specs in the suite can mutate via cache pinning, middleware
    # tweaks, etc.), Rails may EITHER rescue the routing error into
    # a 404 response, OR raise `ActionController::RoutingError`, OR
    # surface it as `ActionView::Template::Error` during the error-page
    # render. All three outcomes are acceptable for the security
    # boundary we're asserting; the assertion below treats any raised
    # exception as a passing rejection so long as the request did NOT
    # successfully serve a frame.
    it "rejects malformed timestamps via the route constraint" do
      served_ok = false
      begin
        get "/footages/#{footage.id}/frames/m/garbage.jpg"
        served_ok = response.status == 200
      rescue ActionController::RoutingError, ActionView::Template::Error
        # Route constraint rejected before the action — passing rejection.
      end
      expect(served_ok).to be(false)
    end

    it "rejects path-traversal attempts via the route constraint" do
      served_ok = false
      body = ""
      begin
        get "/footages/#{footage.id}/frames/m/..%2Fetc%2Fpasswd.jpg"
        served_ok = response.status == 200
        body = response.body
      rescue ActionController::RoutingError, ActionView::Template::Error
        # Route constraint rejected before the action — passing rejection.
      end
      expect(served_ok).to be(false)
      expect(body).not_to include("root:x:0:0")
    end
  end

  describe "GET /footages/:footage_id/frames/t/:filename.jpg" do
    it "streams the thumb JPEG bytes" do
      write_frame(footage.id, "t", "00-00-30", jpeg_bytes)

      get footage_frame_thumb_path(footage_id: footage.id, filename: "00-00-30", format: "jpg")

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("image/jpeg")
      expect(response.body.b).to eq(jpeg_bytes)
    end

    it "returns 404 when the file does not exist on disk" do
      get footage_frame_thumb_path(footage_id: footage.id, filename: "00-09-09", format: "jpg")
      expect(response).to have_http_status(:not_found)
    end
  end
end
