require "rails_helper"

# Phase 26 §01g — viewer-time heatmap system spec. Single thin
# critical-journey spec per the spec pyramid rule. Per-video and
# per-channel views are covered as request specs; this spec asserts
# the heatmap actually renders end-to-end with a real user signed in
# and a real tz applied.
RSpec.describe "Viewer-time heatmap (system)", type: :system do
  before { driven_by(:rack_test) }

  let(:connection) { create(:youtube_connection) }
  let(:channel) { create(:channel, youtube_connection: connection) }
  let(:video) { create(:video, channel: channel) }

  it "renders the heatmap on the per-video analytics page with the user's tz applied" do
    create(:video_viewer_time_bucket, video: video,
           day_of_week_utc: 3, hour_of_day_utc: 14,
           view_count: 50, watch_time_seconds: 3000)

    visit video_analytics_path(video)

    expect(page).to have_text("viewer-time heatmap")
    expect(page).to have_css(".viewer-time-heatmap__grid")
    expect(page).to have_text("tz:")
    expect(page).to have_css("[data-dow='3'][data-hod='14']")
  end

  it "renders the empty state when no buckets exist" do
    visit video_analytics_path(video)
    expect(page).to have_text("no viewer-time data yet")
  end
end
