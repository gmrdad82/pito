require "rails_helper"

# Phase 21 — JSON Endpoints for CLI / MCP Parity.
RSpec.describe "notifications/index.json.jbuilder", type: :view do
  let(:notification) do
    create(:notification, :video_published)
  end

  before do
    assign(:page, 1)
    assign(:total_pages, 3)
    assign(:total, 124)
    assign(:filter, "unread")
    assign(:kind, nil)
    assign(:severity, nil)
    assign(:unread_count, 17)
    assign(:has_failures, true)
    assign(:notifications, [ notification ])
  end

  let(:json) { JSON.parse(render) }

  it "carries the expected top-level keys" do
    expect(json.keys).to match_array(
      %w[page total_pages total per_page filter kind severity
         unread_count has_failures notifications]
    )
  end

  it "echoes pagination fields" do
    expect(json["page"]).to eq(1)
    expect(json["total"]).to eq(124)
    expect(json["per_page"]).to eq(NotificationsController::PER_PAGE)
  end

  it "serializes has_failures as yes/no" do
    expect(json["has_failures"]).to eq("yes")
  end

  it "renders notifications as a list of summary hashes" do
    expect(json["notifications"].first.keys).to match_array(
      %w[id kind severity event_type title body url fires_at
         in_app_read_at read discord_delivered_at slack_delivered_at
         retry_count last_error created_at]
    )
  end
end
