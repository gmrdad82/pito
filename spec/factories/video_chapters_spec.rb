require "rails_helper"

# Phase 11 §01a — Video edit page polish. Factory smoke.
RSpec.describe "video_chapter factory" do
  it "builds a valid record" do
    expect(FactoryBot.build(:video_chapter)).to be_valid
  end

  it "creates a persisted record" do
    expect(FactoryBot.create(:video_chapter)).to be_persisted
  end
end
