require "rails_helper"

# Phase 12 — video schema expansion. Decorator surfaces the new
# writable subset + pre-publish checklist state. Boundary booleans
# serialize as `"yes"` / `"no"` strings (CLAUDE.md hard rule).
RSpec.describe VideoDecorator do
  let(:channel) { create(:channel) }
  let(:video) { create(:video, channel: channel, title: "MyVideo", description: "desc", tags: [ "a", "b" ]) }
  let(:decorator) { described_class.new(video) }

  describe "#as_summary_json" do
    let(:json) { decorator.as_summary_json }

    it "includes the post-12 row keys" do
      expect(json).to include(
        :id, :youtube_video_id, :channel_id, :channel_url,
        :title, :privacy_status, :published_at, :imported,
        :star, :views, :likes, :comments, :watch_time_minutes,
        :last_synced_at, :trend
      )
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

    it "serializes star as yes/no" do
      starred = create(:video, :starred, channel: channel)
      expect(described_class.new(starred).as_summary_json[:star]).to eq("yes")
    end

    it "serializes imported as yes/no" do
      imported = create(:video, :imported, channel: channel)
      expect(described_class.new(imported).as_summary_json[:imported]).to eq("yes")
    end
  end

  describe "#as_detail_json" do
    before { create(:video_stat, video: video, date: Date.current, views: 100) }

    let(:json) { decorator.as_detail_json }

    it "includes the writable subset" do
      expect(json).to include(
        :description, :tags, :category_id, :thumbnail_url,
        :publish_at, :duration_seconds, :project_id,
        :self_declared_made_for_kids, :made_for_kids_effective,
        :contains_synthetic_media, :etag, :last_sync_error
      )
    end

    it "includes the pre-publish checklist state" do
      expect(json).to include(
        :pre_publish_checked_at,
        :pre_publish_game_ok, :pre_publish_age_ok,
        :pre_publish_paid_promotion_ok, :pre_publish_end_screen_ok
      )
    end

    it "exposes studio_url" do
      expect(json[:studio_url]).to eq(video.studio_url)
    end

    it "serializes pre-publish booleans as yes/no strings" do
      v = create(:video, :pre_publish_complete, channel: channel)
      detail = described_class.new(v).as_detail_json
      expect(detail[:pre_publish_game_ok]).to eq("yes")
      expect(detail[:pre_publish_age_ok]).to eq("yes")
      expect(detail[:pre_publish_paid_promotion_ok]).to eq("yes")
      expect(detail[:pre_publish_end_screen_ok]).to eq("yes")
    end

    it "serializes self_declared_made_for_kids as yes/no" do
      v = create(:video, channel: channel, self_declared_made_for_kids: true)
      expect(described_class.new(v).as_detail_json[:self_declared_made_for_kids]).to eq("yes")
    end

    it "serializes made_for_kids_effective as yes/no" do
      v = create(:video, channel: channel)
      expect(described_class.new(v).as_detail_json[:made_for_kids_effective]).to eq("no")
    end

    it "serializes contains_synthetic_media as yes/no" do
      v = create(:video, channel: channel, contains_synthetic_media: true)
      expect(described_class.new(v).as_detail_json[:contains_synthetic_media]).to eq("yes")
    end

    it "includes the surviving stats list" do
      expect(json).to include(:stats)
      expect(json[:stats]).to be_an(Array)
      expect(json[:stats].first).to include(:date, :views)
    end

    it "exposes tags as an array" do
      expect(json[:tags]).to eq([ "a", "b" ])
    end
  end
end
