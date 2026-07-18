# frozen_string_literal: true

require "rails_helper"

# POST /device_tokens — the Android shell registers its FCM device token.
# First slice of push support: persistence only, no sender yet.

RSpec.describe "POST /device_tokens", type: :request do
  def login!
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
  end

  describe "authenticated" do
    before { login! }

    it "creates a row and responds 204 No Content" do
      expect {
        post "/device_tokens", params: { token: "abc123", platform: "android" }, as: :json
      }.to change(DeviceToken, :count).by(1)

      expect(response).to have_http_status(:no_content)
      device_token = DeviceToken.find_by(token: "abc123")
      expect(device_token.platform).to eq("android")
      expect(device_token.last_seen_at).to be_present
    end

    it "upserts by token: a repeat POST bumps last_seen_at without adding a row" do
      post "/device_tokens", params: { token: "abc123" }, as: :json
      device_token = DeviceToken.find_by(token: "abc123")
      device_token.update_column(:last_seen_at, 1.hour.ago)
      first_seen = device_token.last_seen_at

      expect {
        post "/device_tokens", params: { token: "abc123" }, as: :json
      }.not_to change(DeviceToken, :count)

      expect(response).to have_http_status(:no_content)
      device_token = DeviceToken.find_by(token: "abc123")
      expect(device_token.last_seen_at).to be > first_seen
    end

    it "responds 422 with errors JSON when token is missing" do
      expect {
        post "/device_tokens", params: { platform: "android" }, as: :json
      }.not_to change(DeviceToken, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_present
    end

    it "responds 422 with errors JSON when token is blank" do
      expect {
        post "/device_tokens", params: { token: "" }, as: :json
      }.not_to change(DeviceToken, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to be_present
    end
  end

  describe "unauthenticated" do
    it "rejects with 401 and does not create a row" do
      expect {
        post "/device_tokens", params: { token: "abc123" }, as: :json
      }.not_to change(DeviceToken, :count)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("unauthenticated")
    end
  end
end
