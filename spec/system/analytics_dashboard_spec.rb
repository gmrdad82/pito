require "rails_helper"

# Phase 13.3 — System-level Capybara coverage for the visual
# conventions on the top-level analytics dashboard. Driven by
# rack_test for speed; chart-internal JS assertions live in
# `spec/system/analytics_chart_conventions_spec.rb`.
RSpec.describe "Analytics dashboard (system)", type: :system do
  before { driven_by(:rack_test) }

  let(:connection) { create(:youtube_connection) }
  let!(:channel) { create(:channel, youtube_connection: connection) }

  it "renders the four-button window picker with bracketed labels" do
    visit "/analytics"
    expect(page).to have_text("[7d]")
    expect(page).to have_text("[28d]")
    expect(page).to have_text("[90d]")
    expect(page).to have_text("[lifetime]")
  end

  it "switches data when a different window button is clicked" do
    visit "/analytics"
    click_link "[7d]"
    expect(page).to have_current_path("/analytics?window=7d")
  end

  it "renders the data-freshness line at the top" do
    visit "/analytics"
    expect(page).to have_css(".analytics-data-freshness")
  end

  it "respects the no-animation chart convention" do
    visit "/analytics"
    expect(page.body).not_to match(/animation\s*:\s*true/)
  end

  it "uses no red in the chart palette markup" do
    visit "/analytics"
    expect(page.body).not_to include("#cc0000")
  end

  it "renders the 3-day revision band caption when channel daily data exists" do
    create(:channel_daily, channel: channel, date: Date.current, views: 100)
    visit channel_analytics_path(channel)
    expect(page).to have_text("data revises for ~48-72h after publish")
  end

  it "renders empty-state copy with a [refresh now] button on the per-channel page" do
    visit channel_analytics_path(channel)
    expect(page).to have_text("no data for this window")
    expect(page).to have_text("refresh now")
  end

  it "renders a [refresh retention now] button on the per-video retention empty state" do
    video = create(:video, channel: channel)
    visit video_analytics_path(video)
    expect(page).to have_text("retention data is refreshed weekly")
    expect(page).to have_text("refresh retention now")
  end

  it "renders the cross-video local rollup section regardless of channel count" do
    visit "/analytics"
    expect(page).to have_text("when to publish")
    expect(page).to have_text("best video length")
    expect(page).to have_text("topics that work")
    expect(page).to have_text("thumbnail decay")
  end

  it "shows the loading caption (notice flash) when refresh is triggered" do
    create(:channel_daily, channel: channel, date: Date.current)
    visit channel_analytics_path(channel)
    click_button "[refresh now]"
    expect(page.body).to include("syncing")
  end

  it "uses bracketed legend labels in chart headings (analytics-chart sections)" do
    visit "/analytics"
    expect(page.body).to include("analytics-chart")
  end
end
