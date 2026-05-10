require "rails_helper"

# Phase 13.3 — Loading-state coverage. Driven by rack_test so the
# Stimulus controllers don't actually fire — the assertions key on
# the rendered HTML / `data-controller` attributes that announce
# the polling controller. Live polling behavior is exercised by
# manual playbook §9 + §11.
RSpec.describe "Analytics loading states", type: :system do
  before { driven_by(:rack_test) }

  let(:connection) { create(:youtube_connection) }
  let(:channel) { create(:channel, youtube_connection: connection) }

  it "renders the 'syncing...' notice flash after a refresh click" do
    visit channel_analytics_path(channel)
    click_button "[refresh now]"
    expect(page.body).to include("syncing")
  end

  it "wires the analytics-chart Stimulus controller on every chart partial" do
    create(:channel_daily, channel: channel, date: Date.current, views: 100)
    visit channel_analytics_path(channel)
    expect(page.body).to include('data-controller="analytics-chart"')
  end

  it "renders the analytics-chart marker when the channel daily chart has data" do
    create(:channel_daily, channel: channel, date: Date.current, views: 100)
    visit channel_analytics_path(channel)
    expect(page.body).to include("analytics-chart--channel-daily")
  end
end
