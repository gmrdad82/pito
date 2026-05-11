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

  # Phase 27 §01h — Collection composite filename round-trip.
  describe "GET /composites/collection-:id.jpg (Phase 27 §01h)" do
    let(:filename) { "collection-42" }
    let(:fixture_path) { Rails.root.join("spec/fixtures/files/cover_tile.jpg") }

    after do
      target = Pito::AssetsRoot.path("composites", "#{filename}.jpg")
      File.delete(target) if File.exist?(target)
    end

    it "serves the on-disk JPEG with image/jpeg content-type" do
      target = Pito::AssetsRoot.path("composites", "#{filename}.jpg")
      FileUtils.mkdir_p(target.dirname)
      FileUtils.cp(fixture_path, target)

      get "/composites/#{filename}.jpg"
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("image/jpeg")
    end

    it "ignores the ?v=<sha> query parameter (cache buster only)" do
      target = Pito::AssetsRoot.path("composites", "#{filename}.jpg")
      FileUtils.mkdir_p(target.dirname)
      FileUtils.cp(fixture_path, target)

      get "/composites/#{filename}.jpg?v=abc123def456"
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("image/jpeg")
    end

    it "returns 404 when the on-disk file is absent" do
      get "/composites/collection-99999.jpg"
      expect(response).to have_http_status(:not_found)
    end

    it "matches the existing FILENAME_REGEX (collection-<digits> shape)" do
      # Regex: /\A[a-z_]+-\d+\z/ — collection-<digits> passes. Anything
      # outside this shape returns 404 before reaching the disk.
      get "/composites/collection-abc.jpg"
      expect(response).to have_http_status(:not_found)
    end
  end
end
