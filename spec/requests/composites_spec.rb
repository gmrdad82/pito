require "rails_helper"

RSpec.describe "Composites", type: :request do
  describe "GET /composites/:filename.jpg" do
    let(:filename) { "custom-42" }
    let(:fixture_path) { Rails.root.join("spec/fixtures/files/cover_tile.jpg") }

    after do
      target = Pito::AssetsRoot.path("composites", "#{filename}.jpg")
      File.delete(target) if File.exist?(target)
    end

    it "serves the JPEG bytes when the file exists" do
      target = Pito::AssetsRoot.path("composites", "#{filename}.jpg")
      FileUtils.mkdir_p(target.dirname)
      FileUtils.cp(fixture_path, target)

      get "/composites/#{filename}.jpg"
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("image/jpeg")
    end

    it "returns 404 when the file does not exist" do
      get "/composites/missing-9999.jpg"
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 on path-traversal candidates" do
      # The router constraint excludes slashes / dots so `..%2F..` URL-
      # decoded forms never match the route. The controller's
      # FILENAME_REGEX guard re-applies as defense-in-depth.
      get "/composites/foo..bar.jpg"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /composites/:filename.jpg without auth", :unauthenticated do
    it "redirects to login" do
      get "/composites/custom-1.jpg"
      expect(response).to redirect_to(login_path)
    end
  end
end
