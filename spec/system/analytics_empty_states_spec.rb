require "rails_helper"

RSpec.describe "Analytics empty states", type: :system do
  before { driven_by(:rack_test) }

  it "renders empty-state on the top-level analytics page when no syncs have run" do
    visit "/analytics"
    expect(page).to have_text("no analytics yet. add a youtube channel to start syncing.")
  end

  it "renders empty-state on the per-channel analytics page when no rows exist" do
    connection = create(:youtube_connection)
    channel = create(:channel, youtube_connection: connection)
    visit channel_analytics_path(channel)
    expect(page).to have_text("no data for this window. data syncs nightly; refresh to start syncing now.")
  end

  it "renders empty-state on the per-video analytics page when no rows exist" do
    connection = create(:youtube_connection)
    channel = create(:channel, youtube_connection: connection)
    video = create(:video, channel: channel)
    visit video_analytics_path(video)
    expect(page).to have_text("no data for this window. data syncs nightly; refresh to start syncing now.")
  end

  it "the empty-state's [refresh now] button enqueues the right job on per-channel" do
    connection = create(:youtube_connection)
    channel = create(:channel, youtube_connection: connection)
    visit channel_analytics_path(channel)
    expect {
      click_button "[refresh now]"
    }.to change(ChannelAnalyticsSync.jobs, :size).by(1)
  end

  it "the retention-curve empty-state shows the dedicated [refresh retention now] button" do
    connection = create(:youtube_connection)
    channel = create(:channel, youtube_connection: connection)
    video = create(:video, channel: channel)
    visit video_analytics_path(video)
    expect(page).to have_text("retention data is refreshed weekly")
    expect(page).to have_text("[refresh retention now]")
  end
end
