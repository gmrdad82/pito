require "rails_helper"

# Phase 21 — JSON Endpoints for CLI / MCP Parity.
RSpec.describe "calendar/schedule/show.json.jbuilder", type: :view do
  let(:entry) do
    create(:calendar_entry, title: "scheduled", starts_at: 1.day.from_now, timezone: "UTC")
  end

  before do
    assign(:page, 1)
    assign(:total_pages, 4)
    assign(:total, 187)
    assign(:selected_kinds, %w[video game])
    assign(:selected_source, nil)
    assign(:show_cancelled, false)
    assign(:install_tz, "Europe/Bucharest")
    assign(:today, Time.zone.parse("2026-05-10T18:42:00Z"))
    assign(:entries, [ entry ])
  end

  let(:json) { JSON.parse(render) }

  it "carries the expected top-level keys" do
    expect(json.keys).to match_array(
      %w[page total_pages total per_page selected_kinds selected_source
         show_cancelled install_tz today entries]
    )
  end

  it "renders entries as a list of summary hashes" do
    expect(json["entries"].first.keys).to match_array(
      %w[id entry_type title starts_at ends_at all_day timezone state
         source read_only game_id video_id channel_id project_id
         milestone_rule_id]
    )
  end

  it "serializes show_cancelled as yes/no" do
    expect(json["show_cancelled"]).to eq("no")
  end

  it "serializes today as ISO-8601" do
    expect(json["today"]).to start_with("2026-05-10T18:42:00")
  end

  it "echoes selected_kinds" do
    expect(json["selected_kinds"]).to eq(%w[video game])
  end

  it "renders selected_kinds as [] when :empty" do
    assign(:selected_kinds, :empty)
    expect(json["selected_kinds"]).to eq([])
  end

  it "renders selected_kinds as nil when not filtered" do
    assign(:selected_kinds, nil)
    expect(json["selected_kinds"]).to be_nil
  end
end
