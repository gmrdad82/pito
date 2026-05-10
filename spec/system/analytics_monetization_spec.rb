require "rails_helper"

RSpec.describe "Analytics monetization gate", type: :system do
  before { driven_by(:rack_test) }

  let(:connection) { create(:youtube_connection) }
  let(:channel) { create(:channel, youtube_connection: connection) }

  it "hides revenue cards when MONETIZATION_ENABLED is false" do
    create(:channel_window_summary, channel: channel, window: "28d",
                                    views: 100, estimated_revenue: 12.50, cpm: 0.5)
    visit channel_analytics_path(channel)
    expect(page).not_to have_text("estimated revenue")
    expect(page).not_to have_text("cpm")
  end

  it "renders the 'monetization not connected' caption when disabled" do
    create(:channel_window_summary, channel: channel, window: "28d", views: 100)
    visit channel_analytics_path(channel)
    expect(page).to have_text("monetization not connected.")
    expect(page).to have_text("[enable monetization]")
  end

  it "renders revenue cards when MONETIZATION_ENABLED is true" do
    AppSetting.set("monetization_enabled", "yes")
    create(:channel_window_summary, channel: channel, window: "28d",
                                    views: 100, estimated_revenue: 12.50, cpm: 0.5)
    visit channel_analytics_path(channel)
    expect(page).to have_text("estimated revenue")
    expect(page).to have_text("cpm")
  ensure
    AppSetting.set("monetization_enabled", "no") if AppSetting.exists?(key: "monetization_enabled")
  end
end
