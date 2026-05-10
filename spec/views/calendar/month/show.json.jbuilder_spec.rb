require "rails_helper"

# Phase 21 — JSON Endpoints for CLI / MCP Parity.
RSpec.describe "calendar/month/show.json.jbuilder", type: :view do
  let(:entry) do
    create(:calendar_entry,
           title: "Hades 2 launch",
           starts_at: Time.zone.parse("2026-05-13T17:00:00Z"),
           timezone: "Europe/Bucharest")
  end

  before do
    assign(:year, 2026)
    assign(:month, 5)
    assign(:install_tz, "Europe/Bucharest")
    assign(:first_day, Date.new(2026, 4, 27))
    assign(:last_day, Date.new(2026, 6, 1))
    assign(:today, Date.new(2026, 5, 10))
    assign(:on_current_month, true)
    assign(:selected_kinds, %w[video game])
    assign(:buckets, { Date.new(2026, 5, 13) => [ entry ] })
    assign(:prev_year, 2026)
    assign(:prev_month, 4)
    assign(:next_year, 2026)
    assign(:next_month, 6)
    params[:state] = "scheduled"
  end

  let(:json) { JSON.parse(render) }

  it "carries the expected top-level keys" do
    expect(json.keys).to match_array(
      %w[year month install_tz first_day last_day today on_current_month
         selected_kinds show_cancelled buckets nav]
    )
  end

  it "renders buckets as a date-keyed hash" do
    expect(json["buckets"]).to have_key("2026-05-13")
    expect(json["buckets"]["2026-05-13"].first["title"]).to eq("Hades 2 launch")
  end

  it "renders on_current_month as yes/no" do
    expect(json["on_current_month"]).to eq("yes")
  end

  it "renders show_cancelled as no when state is not 'all'" do
    expect(json["show_cancelled"]).to eq("no")
  end

  it "renders nav as a { prev:, next: } pair" do
    expect(json["nav"]).to eq(
      "prev" => { "year" => 2026, "month" => 4 },
      "next" => { "year" => 2026, "month" => 6 }
    )
  end
end
