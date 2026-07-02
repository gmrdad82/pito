# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Achievements::TopShiniesPerMetric do
  let(:channel) { create(:channel) }

  def unlock!(metric, threshold, at:)
    create(:achievement, achievable: channel, metric:, threshold:, unlocked_at: at)
  end

  it "returns one achievement per metric — the highest threshold in the lane" do
    unlock!("views", 100,  at: 3.days.ago)
    top = unlock!("views", 1000, at: 2.days.ago)

    expect(described_class.call(channel.achievements)).to eq([ top ])
  end

  it "orders lanes by most-recently-advanced first" do
    older = unlock!("views", 1000, at: 5.days.ago)
    newer = unlock!("subs",  100,  at: 1.day.ago)

    expect(described_class.call(channel.achievements)).to eq([ newer, older ])
  end

  it "returns [] for no achievements" do
    expect(described_class.call(channel.achievements)).to eq([])
  end
end
