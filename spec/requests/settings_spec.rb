require "rails_helper"

RSpec.describe "Settings", type: :request do
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
end
