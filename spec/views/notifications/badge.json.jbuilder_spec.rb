require "rails_helper"

# Phase 21 — JSON Endpoints for CLI / MCP Parity. Locked decision #6:
# cookie-authed badge endpoint on the existing controller, NOT under
# `/api/`.
RSpec.describe "notifications/badge.json.jbuilder", type: :view do
  before do
    assign(:unread_count, 17)
    assign(:has_failures, true)
  end

  let(:json) { JSON.parse(render) }

  it "carries exactly two keys" do
    expect(json.keys).to match_array(%w[unread_count has_failures])
  end

  it "exposes unread_count as an integer" do
    expect(json["unread_count"]).to eq(17)
  end

  it "serializes has_failures as yes/no" do
    expect(json["has_failures"]).to eq("yes")
  end

  it "serializes has_failures = false as 'no'" do
    assign(:has_failures, false)
    expect(json["has_failures"]).to eq("no")
  end
end
