require "rails_helper"

# Phase 7 Path A2 (literal full retract). VideoDecorator collapses
# around the surviving columns: id, youtube_video_id, channel_id,
# channel_url, star, last_synced_at, plus aggregate stats and `trend`.
# `formatted_duration` / `formatted_privacy` / `formatted_published_at`
# are gone with the columns they read.
RSpec.describe VideoDecorator do
  let(:channel) { create(:channel) }
  let(:video) { create(:video, channel: channel) }
  let(:decorator) { described_class.new(video) }

  describe "#as_summary_json" do
    let(:json) { decorator.as_summary_json }

    it "includes expected post-A2 keys" do
      expect(json).to include(
        :id, :youtube_video_id, :channel_id, :channel_url, :star,
        :views, :likes, :comments, :watch_time_minutes,
        :last_synced_at, :trend
      )
    end

    it "does NOT include legacy metadata keys" do
      [
        :title, :description, :tags, :privacy_status,
        :duration_seconds, :published_at, :thumbnail_url,
        :category_id, :default_language
      ].each do |k|
        expect(json).not_to have_key(k), "unexpected key #{k.inspect} in summary JSON"
      end
    end

    it "includes channel url" do
      expect(json[:channel_url]).to eq(channel.channel_url)
    end

    it "uses Rust-aligned key names (no total_ prefix)" do
      expect(json).not_to include(:total_views, :total_likes, :total_comments, :total_watch_time)
    end

    it "exposes watch_time_minutes as a Float (Rust f64)" do
      expect(json[:watch_time_minutes]).to be_a(Float)
    end

    it "carries a nullable trend field" do
      expect(json).to have_key(:trend)
      expect(json[:trend]).to be_nil
    end
  end

  describe "#as_detail_json" do
    before { create(:video_stat, video: video, date: Date.current, views: 100) }

    let(:json) { decorator.as_detail_json }

    it "includes the surviving detail field (stats)" do
      expect(json).to include(:stats)
    end

    it "includes stats array" do
      expect(json[:stats]).to be_an(Array)
      expect(json[:stats].first).to include(:date, :views)
    end
  end
end
