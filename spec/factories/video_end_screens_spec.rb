require "rails_helper"

# Phase 11 §01a — Video edit page polish. Factory smoke.
RSpec.describe "video_end_screen factory" do
  it "builds a valid record" do
    expect(FactoryBot.build(:video_end_screen)).to be_valid
  end

  it "creates a persisted record" do
    expect(FactoryBot.create(:video_end_screen)).to be_persisted
  end

  it "builds a valid :related_channel record" do
    expect(FactoryBot.build(:video_end_screen, :related_channel)).to be_valid
  end

  it "builds a valid :related_playlist record" do
    expect(FactoryBot.build(:video_end_screen, :related_playlist)).to be_valid
  end

  it "builds a valid :none record" do
    expect(FactoryBot.build(:video_end_screen, :none)).to be_valid
  end
end
