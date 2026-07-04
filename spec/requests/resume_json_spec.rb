# frozen_string_literal: true

require "rails_helper"

# GET /resume.json — the conversation picker for non-browser clients
# (pito-tui): the same recency groups the sidebar renders, as data.

RSpec.describe "GET /resume.json", type: :request do
  def login!
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
  end

  it "returns recency groups with uuid/title/display_name/last_activity_at rows" do
    login!
    named = Conversation.create!(title: "android")

    get "/resume", headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.keys).to match_array(%w[recent older])

    row = (body["recent"] + body["older"]).find { |r| r["uuid"] == named.uuid }
    expect(row).to be_present
    expect(row["title"]).to eq("android")
    expect(row["display_name"]).to eq("android")
    expect(row.keys).to match_array(%w[uuid title display_name last_activity_at])
  end

  it "rejects anonymous with 401" do
    get "/resume", headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body["error"]).to eq("unauthenticated")
  end
end
