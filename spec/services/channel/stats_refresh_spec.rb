# frozen_string_literal: true

require "rails_helper"

RSpec.describe Channel::StatsRefresh do
  let(:channel) { create(:channel) }

  def video_with_likes(likes, channel: self.channel)
    video = create(:video, channel: channel)
    Pito::Stats.set(video, :likes, likes) unless likes.nil?
    video
  end

  describe ".call" do
    it "materializes channel likes as the sum of its videos' likes" do
      video_with_likes(100)
      video_with_likes(55)

      described_class.call(channel)

      expect(Pito::Stats.get(channel, :likes)).to eq(155)
    end

    it "stores 0 when the channel has no videos" do
      described_class.call(channel)
      expect(Pito::Stats.get(channel, :likes)).to eq(0)
    end

    it "ignores videos that carry no like stat" do
      video_with_likes(100)
      video_with_likes(nil)

      described_class.call(channel)

      expect(Pito::Stats.get(channel, :likes)).to eq(100)
    end

    it "excludes another channel's videos" do
      video_with_likes(999, channel: create(:channel))
      video_with_likes(50)

      described_class.call(channel)

      expect(Pito::Stats.get(channel, :likes)).to eq(50)
    end

    it "does not sum non-like stat kinds" do
      video = video_with_likes(nil)
      Pito::Stats.set(video, :views, 5_000)

      described_class.call(channel)

      expect(Pito::Stats.get(channel, :likes)).to eq(0)
    end

    it "recomputes on a subsequent call" do
      video = video_with_likes(100)
      described_class.call(channel)
      expect(Pito::Stats.get(channel, :likes)).to eq(100)

      Pito::Stats.set(video, :likes, 500)
      described_class.call(channel)
      expect(Pito::Stats.get(channel, :likes)).to eq(500)
    end
  end
end
