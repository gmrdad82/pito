# frozen_string_literal: true

require "rails_helper"

# G84: HTML documents are never cached — the Android WebView re-served a
# cached page on pull-to-refresh, keeping the OLD fingerprinted CSS link
# alive across a server update. Assets stay long-cached (fingerprinted).

RSpec.describe "HTML response caching", type: :request do
  it "sends Cache-Control: no-store on HTML pages" do
    get "/"
    expect(response.headers["Cache-Control"]).to eq("no-store")
  end

  it "leaves JSON responses on their own cache policy" do
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post "/session", params: { otp: ROTP::TOTP.new(seed).now }, as: :json

    get "/version", headers: { "Accept" => "application/json" }
    expect(response.headers["Cache-Control"].to_s).not_to eq("no-store")
  end

  it "keeps the Android path-configuration publicly cacheable (G47 contract)" do
    get "/configurations/android_v1.json"
    expect(response.headers["Cache-Control"]).to include("public")
    expect(response.headers["Cache-Control"]).to include("max-age=3600")
  end
end
