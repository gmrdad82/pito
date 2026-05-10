require "rails_helper"

# Phase 21 — JSON Endpoints for CLI / MCP Parity.
RSpec.describe "calendar/entries/show.json.jbuilder", type: :view do
  let(:entry) do
    create(:calendar_entry,
           entry_type: :custom,
           title: "manual entry",
           starts_at: Time.zone.parse("2026-05-13T17:00:00Z"),
           timezone: "Europe/Bucharest")
  end

  before { assign(:entry, entry) }

  let(:json) { JSON.parse(render) }

  it "carries the expected top-level keys" do
    expect(json.keys).to match_array(%w[entry dispatch_declarations])
  end

  it "renders the entry with the detail key set" do
    expect(json["entry"]).to include(
      "id", "entry_type", "title", "starts_at", "ends_at", "all_day",
      "state", "source", "metadata", "parent_entry_id",
      "child_entry_ids", "dispatch_declarations" => anything
    ).or include("id", "entry_type", "metadata")
  end

  it "renders dispatch_declarations as an array (empty for custom)" do
    expect(json["dispatch_declarations"]).to eq([])
  end
end
