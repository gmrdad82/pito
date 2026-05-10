require "rails_helper"

RSpec.describe Analytics::CrossVideoLocals do
  subject(:locals) { described_class.new }

  describe "#when_to_publish" do
    let(:channel) { create(:channel) }

    it "buckets videos by published_at day-of-week + hour" do
      v1 = create(:video, :public, channel: channel, published_at: Time.zone.local(2026, 5, 4, 14, 0))
      v2 = create(:video, :public, channel: channel, published_at: Time.zone.local(2026, 5, 5, 9, 0))
      create(:video_window_summary, video: v1, window: "7d", views: 100)
      create(:video_window_summary, video: v2, window: "7d", views: 200)

      result = locals.when_to_publish
      expect(result.keys.size).to be >= 2
      expect(result.values).to all(be_a(Integer))
    end

    it "computes median first-7-days views per bucket" do
      v1 = create(:video, :public, channel: channel, published_at: Time.zone.local(2026, 5, 4, 14, 0))
      v2 = create(:video, :public, channel: channel, published_at: Time.zone.local(2026, 5, 4, 14, 30))
      v3 = create(:video, :public, channel: channel, published_at: Time.zone.local(2026, 5, 4, 14, 50))
      create(:video_window_summary, video: v1, window: "7d", views: 100)
      create(:video_window_summary, video: v2, window: "7d", views: 200)
      create(:video_window_summary, video: v3, window: "7d", views: 1000)

      result = locals.when_to_publish
      bucket_value = result.values.find { |v| v == 200 }
      expect(bucket_value).to eq(200)
    end

    it "uses median, not mean, to resist outliers" do
      v1 = create(:video, :public, channel: channel, published_at: Time.zone.local(2026, 5, 4, 14, 0))
      v2 = create(:video, :public, channel: channel, published_at: Time.zone.local(2026, 5, 4, 14, 30))
      v3 = create(:video, :public, channel: channel, published_at: Time.zone.local(2026, 5, 4, 14, 50))
      create(:video_window_summary, video: v1, window: "7d", views: 10)
      create(:video_window_summary, video: v2, window: "7d", views: 20)
      create(:video_window_summary, video: v3, window: "7d", views: 10_000)

      result = locals.when_to_publish
      mean = (10 + 20 + 10_000) / 3 # 3343
      median = 20
      expect(result.values).to include(median)
      expect(result.values).not_to include(mean)
    end
  end

  describe "#best_duration" do
    it "buckets videos by duration ranges and returns one value per bucket" do
      short_video = create(:video, duration_seconds: 30)
      mid_video   = create(:video, duration_seconds: 240)
      long_video  = create(:video, duration_seconds: 1200)
      create(:video_window_summary, video: short_video, window: "28d", estimated_minutes_watched: 100)
      create(:video_window_summary, video: mid_video,   window: "28d", estimated_minutes_watched: 400)
      create(:video_window_summary, video: long_video,  window: "28d", estimated_minutes_watched: 900)

      result = locals.best_duration
      expect(result.keys).to eq([ "0-60s", "1-5min", "5-15min", "15min+" ])
      expect(result["0-60s"]).to eq(100)
      expect(result["1-5min"]).to eq(400)
      expect(result["15min+"]).to eq(900)
    end

    it "computes median estimated_minutes_watched per bucket from video_window_summary 28d" do
      v1 = create(:video, duration_seconds: 200)
      v2 = create(:video, duration_seconds: 220)
      v3 = create(:video, duration_seconds: 250)
      create(:video_window_summary, video: v1, window: "28d", estimated_minutes_watched: 100)
      create(:video_window_summary, video: v2, window: "28d", estimated_minutes_watched: 200)
      create(:video_window_summary, video: v3, window: "28d", estimated_minutes_watched: 9000)

      result = locals.best_duration
      expect(result["1-5min"]).to eq(200)
    end
  end

  describe "#topics_that_work" do
    it "groups videos by category_id" do
      v1 = create(:video, category_id: "20")
      v2 = create(:video, category_id: "22")
      create(:video_window_summary, video: v1, window: "28d", views: 1000)
      create(:video_window_summary, video: v2, window: "28d", views: 500)

      result = locals.topics_that_work
      expect(result.keys).to contain_exactly("20", "22")
    end

    it "computes median first-28-days views per category" do
      v1 = create(:video, category_id: "20")
      v2 = create(:video, category_id: "20")
      v3 = create(:video, category_id: "20")
      create(:video_window_summary, video: v1, window: "28d", views: 100)
      create(:video_window_summary, video: v2, window: "28d", views: 500)
      create(:video_window_summary, video: v3, window: "28d", views: 100_000)

      result = locals.topics_that_work
      expect(result["20"]).to eq(500)
    end
  end

  describe "#thumbnail_decay" do
    it "computes per-video CTR over time from video_window_summary" do
      video = create(:video, title: "decaying")
      create(:video_window_summary, video: video, window: "90d", video_thumbnail_impressions_click_rate: 0.05)
      create(:video_window_summary, video: video, window: "28d", video_thumbnail_impressions_click_rate: 0.04)
      create(:video_window_summary, video: video, window: "7d",  video_thumbnail_impressions_click_rate: 0.02)

      result = locals.thumbnail_decay
      expect(result["decaying"]).to be < 0
    end

    it "flags videos whose CTR drop crosses the threshold (declining)" do
      v_decline = create(:video, title: "down")
      v_steady  = create(:video, title: "steady")
      create(:video_window_summary, video: v_decline, window: "90d", video_thumbnail_impressions_click_rate: 0.1)
      create(:video_window_summary, video: v_decline, window: "7d",  video_thumbnail_impressions_click_rate: 0.05)
      create(:video_window_summary, video: v_steady,  window: "90d", video_thumbnail_impressions_click_rate: 0.05)
      create(:video_window_summary, video: v_steady,  window: "7d",  video_thumbnail_impressions_click_rate: 0.05005)

      result = locals.thumbnail_decay
      expect(result.keys).to include("down")
      expect(result.keys).not_to include("steady")
    end
  end
end
