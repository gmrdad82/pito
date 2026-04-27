require "rails_helper"

RSpec.describe "Settings", type: :request do
  let(:search_engine) { instance_double(Search::MeilisearchEngine, healthy?: true, index_stats: {}) }

  before do
    allow(Search).to receive(:engine).and_return(search_engine)
  end

  describe "GET /settings" do
    it "returns 200" do
      get settings_path
      expect(response).to have_http_status(:ok)
    end

    it "shows the OAuth form fields" do
      get settings_path
      expect(response.body).to include("client ID")
      expect(response.body).to include("client secret")
      expect(response.body).to include("redirect URI")
    end

    it "displays existing values" do
      AppSetting.set("youtube_client_id", "test-client-id")
      get settings_path
      expect(response.body).to include("test-client-id")
    end

    it "shows the theme selector" do
      get settings_path
      expect(response.body).to include("appearance")
      expect(response.body).to include("light")
      expect(response.body).to include("dark")
      expect(response.body).to include("auto (system)")
    end
  end

  describe "PATCH /settings" do
    it "saves new settings and redirects" do
      patch settings_path, params: {
        settings: {
          youtube_client_id: "my-client-id",
          youtube_client_secret: "my-secret",
          youtube_redirect_uri: "http://localhost:3000/oauth/callback"
        }
      }
      expect(response).to redirect_to(settings_path)
      expect(AppSetting.get("youtube_client_id")).to eq("my-client-id")
      expect(AppSetting.get("youtube_client_secret")).to eq("my-secret")
      expect(AppSetting.get("youtube_redirect_uri")).to eq("http://localhost:3000/oauth/callback")
    end

    it "updates existing settings" do
      AppSetting.set("youtube_client_id", "old-id")
      patch settings_path, params: {
        settings: { youtube_client_id: "new-id", youtube_client_secret: "", youtube_redirect_uri: "" }
      }
      expect(AppSetting.get("youtube_client_id")).to eq("new-id")
    end

    it "does not blank out existing settings when value is empty" do
      AppSetting.set("youtube_client_secret", "keep-this")
      patch settings_path, params: {
        settings: { youtube_client_id: "new-id", youtube_client_secret: "", youtube_redirect_uri: "" }
      }
      expect(AppSetting.get("youtube_client_secret")).to eq("keep-this")
    end

    it "shows flash notice after save" do
      patch settings_path, params: {
        settings: { youtube_client_id: "x", youtube_client_secret: "", youtube_redirect_uri: "" }
      }
      follow_redirect!
      expect(response.body).to include("settings saved.")
    end
  end

  describe "GET /settings search section" do
    let(:engine) { instance_double(Search::MeilisearchEngine) }

    before do
      allow(Search).to receive(:engine).and_return(engine)
    end

    it "shows search engine status when healthy" do
      allow(engine).to receive(:healthy?).and_return(true)
      allow(engine).to receive(:index_stats).and_return({ "channels_test" => 10, "videos_test" => 50 })
      get settings_path
      expect(response.body).to include("meilisearch")
      expect(response.body).to include("connected")
    end

    it "shows disconnected when unhealthy" do
      allow(engine).to receive(:healthy?).and_return(false)
      allow(engine).to receive(:index_stats).and_return({})
      get settings_path
      expect(response.body).to include("disconnected")
    end
  end

  describe "POST /settings/reindex" do
    it "enqueues ReindexAllJob and redirects" do
      post settings_reindex_path
      expect(response).to redirect_to(settings_path)
      follow_redirect!
      expect(response.body).to include("reindex started")
    end

    it "enqueues the job" do
      expect { post settings_reindex_path }.to have_enqueued_job(ReindexAllJob)
    end
  end

  describe "PATCH /settings/theme" do
    it "sets theme to dark" do
      patch settings_theme_path, params: { theme: "dark" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(AppSetting.get("theme")).to eq("dark")
    end

    it "sets theme to light" do
      patch settings_theme_path, params: { theme: "light" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(AppSetting.get("theme")).to eq("light")
    end

    it "sets theme to auto" do
      patch settings_theme_path, params: { theme: "auto" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(AppSetting.get("theme")).to eq("auto")
    end

    it "rejects invalid theme values" do
      patch settings_theme_path, params: { theme: "neon" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
