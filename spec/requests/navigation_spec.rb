require "rails_helper"

RSpec.describe "Navigation", type: :request do
  %w[/ /channels /videos /settings].each do |path|
    it "GET #{path} returns 200" do
      get path
      expect(response).to have_http_status(:ok)
    end

    it "GET #{path} includes top nav links" do
      get path
      body = response.body
      expect(body).to include("channels")
      expect(body).to include("videos")
      expect(body).to include("settings")
      expect(body).to include("pito")
    end
  end

  it "GET /channels has page-specific title" do
    get "/channels"
    expect(response.body).to include("<title>channels ~ pito</title>")
  end

  it "GET /videos has page-specific title" do
    get "/videos"
    expect(response.body).to include("<title>videos ~ pito</title>")
  end

  it "GET /settings has page-specific title" do
    get "/settings"
    expect(response.body).to include("<title>settings ~ pito</title>")
  end

  it "does not include purged nav items" do
    get "/"
    body = response.body
    expect(body).not_to include("Compare")
    expect(body).not_to include("Production")
    expect(body).not_to include("Notes")
    expect(body).not_to include("Sidekiq</a>")
  end

  describe "GET /sidekiq" do
    it "requires authentication" do
      get "/sidekiq"
      expect(response).to have_http_status(:unauthorized)
    end

    it "grants access with valid credentials" do
      username = Rails.application.credentials.dig(:sidekiq, Rails.env.to_sym, :username) || ""
      password = Rails.application.credentials.dig(:sidekiq, Rails.env.to_sym, :password) || ""
      credentials = ActionController::HttpAuthentication::Basic.encode_credentials(username, password)
      get "/sidekiq", headers: { "HTTP_AUTHORIZATION" => credentials }
      expect(response).to have_http_status(:ok).or have_http_status(:found)
    end
  end
end
