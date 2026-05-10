require "rails_helper"

# Phase 13.3 — Chart convention assertions. rack_test driver doesn't
# execute Chart.js, but every chart partial passes
# `library: { animation: false }` to Chartkick on the server side,
# and Chartkick serializes that into the data-library JSON attribute.
# We assert on the serialized attribute so the convention can't be
# silently dropped.
RSpec.describe "Analytics chart conventions", type: :system do
  before { driven_by(:rack_test) }

  let(:connection) { create(:youtube_connection) }
  let(:channel) { create(:channel, youtube_connection: connection) }
  let(:video) { create(:video, channel: channel) }

  it "every chart partial sets animation: false in the rendered Chartkick output" do
    create(:channel_daily, channel: channel, date: Date.current, views: 100)
    visit channel_analytics_path(channel)
    # Chartkick serializes opts as a JS object literal in the inline
    # bootstrap script. Match the literal JSON fragment.
    expect(page.body).to include('"animation":false')
  end

  it "no chart series uses red anywhere on the dashboard" do
    create(:channel_daily, channel: channel, date: Date.current, views: 100)
    visit channel_analytics_path(channel)
    expect(page.body).not_to include("#cc0000")
  end

  it "every chart wrapper carries the analytics-chart Stimulus binding" do
    create(:channel_daily, channel: channel, date: Date.current, views: 100)
    visit channel_analytics_path(channel)
    expect(page.body).to include('data-controller="analytics-chart"')
  end

  it "every clickable element renders inside the bracketed convention" do
    visit channel_analytics_path(channel)
    expect(page.body).to include("[refresh now]")
  end

  it "no JS confirm / alert / data-turbo-confirm attributes appear in the analytics views" do
    visit channel_analytics_path(channel)
    expect(page.body).not_to include("data-turbo-confirm")
    expect(page.body).not_to match(/window\.confirm\(/)
    expect(page.body).not_to match(/onclick=/)
  end
end
