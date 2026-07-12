# frozen_string_literal: true

require "rails_helper"

# GET /notifications.json — the notifications panel for non-browser clients
# (pito-tui): the same keyset page NotificationsController#index renders as a
# Turbo Stream, as data.

RSpec.describe "GET /notifications.json", type: :request do
  def login!
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
  end

  it "returns rows with id/message/read/created_at and a null next_cursor when everything fits one page" do
    login!
    unread = create(:notification, message: "Hello from test")
    read   = create(:notification, :read, message: "Already seen")

    get "/notifications", headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.keys).to match_array(%w[rows next_cursor])
    expect(body["next_cursor"]).to be_nil

    unread_row = body["rows"].find { |r| r["id"] == unread.id }
    read_row   = body["rows"].find { |r| r["id"] == read.id }
    expect(unread_row.keys).to match_array(%w[id message read created_at])
    expect(unread_row["message"]).to eq("Hello from test")
    expect(unread_row["read"]).to eq(false)
    expect(read_row["read"]).to eq(true)
    expect(unread_row["created_at"]).to eq(unread.created_at.iso8601)
  end

  it "ignores a limit param and keeps the server's PAGE_SIZE" do
    login!
    create_list(:notification, 3)

    get "/notifications", params: { limit: 1 }, headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["rows"].size).to eq(3)
  end

  it "pages via after= and exhausts with a null next_cursor" do
    stub_const("Notification::PAGE_SIZE", 2)
    login!
    create_list(:notification, 3)

    get "/notifications", headers: { "Accept" => "application/json" }
    first_page = response.parsed_body
    expect(first_page["rows"].size).to eq(2)
    expect(first_page["next_cursor"]).to be_present

    get "/notifications", params: { after: first_page["next_cursor"] }, headers: { "Accept" => "application/json" }
    second_page = response.parsed_body
    expect(second_page["rows"].size).to eq(1)
    expect(second_page["next_cursor"]).to be_nil

    first_ids  = first_page["rows"].map { |r| r["id"] }
    second_ids = second_page["rows"].map { |r| r["id"] }
    expect(first_ids & second_ids).to be_empty
  end

  it "rejects anonymous with 401" do
    get "/notifications", headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body["error"]).to eq("unauthenticated")
  end
end
