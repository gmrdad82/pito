# frozen_string_literal: true

require "rails_helper"

# POST /session — the JSON login for non-browser clients (pito-tui).
# TOTP-only (pito has no passwords): a valid code mints the SAME encrypted
# session cookie the chatbox /authenticate flow does; the client keeps a
# cookie jar and presents it on every request and the cable handshake.

RSpec.describe "Session JSON endpoints", type: :request do
  def enroll!
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    seed
  end

  describe "POST /session" do
    it "mints the session cookie and responds 201 on a valid code" do
      seed = enroll!

      post "/session", params: { otp: ROTP::TOTP.new(seed).now }, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to eq("authenticated" => true)

      # The cookie is live: an auth-gated JSON endpoint now answers 200.
      get "/resume", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
    end

    it "responds 401 with the invalid status and a printable message on a bad code" do
      enroll!

      post "/session", params: { otp: "000000" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      body = response.parsed_body
      expect(body["authenticated"]).to be(false)
      expect(body["error"]).to eq("invalid")
      expect(body["message"]).to be_present
    end

    it "responds 401 with the throttled status once the per-IP budget is spent" do
      enroll!
      allow(SessionThrottle).to receive(:exhausted?).and_return(true)

      post "/session", params: { otp: "000000" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("throttled")
    end

    it "does not mint a cookie on failure" do
      enroll!
      post "/session", params: { otp: "000000" }, as: :json

      get "/resume", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /logout (JSON)" do
    it "clears the session and responds 204 No Content" do
      seed = enroll!
      post "/session", params: { otp: ROTP::TOTP.new(seed).now }, as: :json

      delete "/logout", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:no_content)

      get "/resume", headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
