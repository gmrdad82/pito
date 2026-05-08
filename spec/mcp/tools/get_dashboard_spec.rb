require "rails_helper"
require_relative "../../../app/mcp/tools/get_dashboard"

RSpec.describe Mcp::Tools::GetDashboard do
  it "returns the counts-only dashboard summary (chart-sweep shape)" do
    channel = create(:channel)
    video = create(:video, channel: channel)
    create(:video_stat, video: video, date: Date.current, views: 500, likes: 25, comments: 3)
    project = create(:project)
    create(:footage, project: project)
    create(:note, project: project)

    result = described_class.call
    data = JSON.parse(result.content.first[:text])

    # Chart-sweep dispatch (2026-05-07) — the tool no longer emits
    # `summary`, `daily_views`, `views_by_channel`, or `daily_engagement`.
    # The shape is a flat counts object that the pito CLI status renderer
    # consumes directly.
    expect(data).to eq(
      "video_count" => 1,
      "channel_count" => 1,
      "project_count" => 1,
      "footage_count" => 1,
      "note_count" => 1
    )
  end

  it "returns zero counts when nothing exists" do
    result = described_class.call
    data = JSON.parse(result.content.first[:text])

    expect(data).to eq(
      "video_count" => 0,
      "channel_count" => 0,
      "project_count" => 0,
      "footage_count" => 0,
      "note_count" => 0
    )
  end
end
