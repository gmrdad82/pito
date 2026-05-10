require "rails_helper"

# Phase 21 — JSON Endpoints for CLI / MCP Parity.
RSpec.describe "notifications/show.json.jbuilder", type: :view do
  let(:notification) { create(:notification, :video_published) }

  before { assign(:notification, notification) }

  let(:json) { JSON.parse(render) }

  it "carries the expected top-level keys" do
    expect(json.keys).to match_array(%w[notification payload])
  end

  it "wraps the summary under :notification" do
    expect(json["notification"]["id"]).to eq(notification.id)
  end

  it "wraps the formatter output under :payload" do
    expect(json["payload"]).to include("title", "severity")
  end
end
