require "rails_helper"
require "ostruct"

# Phase 13.2 — Analytics sync engine. Per-channel job spec.
RSpec.describe ChannelAnalyticsSync do
  let(:user)       { create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel)    { create(:channel, youtube_connection: connection) }
  let!(:vid_a)     { create(:video, channel: channel, youtube_video_id: "videoaa", published_at: 30.days.ago) }
  let!(:vid_b)     { create(:video, channel: channel, youtube_video_id: "videobb", published_at: 5.days.ago) }
  let(:client_double) { instance_double(Youtube::AnalyticsClient) }

  before do
    allow(Youtube::AnalyticsClient).to receive(:new).and_return(client_double)
    allow(client_double).to receive(:today_pt).and_return(Date.new(2026, 5, 10))
    allow(client_double).to receive(:channel_daily).and_return(
      column_headers: [ { name: "day" }, { name: "views" }, { name: "estimatedMinutesWatched" } ],
      rows: [
        [ "2026-05-07", 100, 20 ],
        [ "2026-05-08", 150, 30 ],
        [ "2026-05-09", 200, 40 ]
      ]
    )
    allow(client_double).to receive(:channel_window_summary).and_return(
      column_headers: [ { name: "views" }, { name: "averageViewPercentage" } ],
      rows: [ [ 5000, 0.42 ] ]
    )
    allow(client_double).to receive(:top_videos).and_return(
      column_headers: [ { name: "video" }, { name: "views" }, { name: "estimatedMinutesWatched" }, { name: "averageViewDuration" }, { name: "averageViewPercentage" }, { name: "subscribersGained" }, { name: "likes" }, { name: "comments" } ],
      rows: [
        [ "videoaa", 1000, 200, 60, 0.4, 5, 50, 10 ],
        [ "videobb", 500,  100, 30, 0.35, 2, 20, 4 ]
      ]
    )
  end

  describe "happy path" do
    it "fetches C1 for the channel and upserts ChannelDaily rows" do
      expect {
        described_class.new.perform(channel.id)
      }.to change { ChannelDaily.where(channel_id: channel.id).count }.by(3)
    end

    it "fetches C2 for each window and upserts ChannelWindowSummary rows" do
      expect {
        described_class.new.perform(channel.id)
      }.to change { ChannelWindowSummary.where(channel_id: channel.id).count }.by(4)
    end

    it "fetches C3 for each window and upserts TopVideosWindow rows" do
      expect {
        described_class.new.perform(channel.id)
      }.to change { TopVideosWindow.where(channel_id: channel.id).count }.by(8) # 2 videos × 4 windows
    end

    it "uses today_pt - 3 to today_pt - 1 as the C1 fetch range" do
      described_class.new.perform(channel.id)
      expect(client_double).to have_received(:channel_daily).with(
        channel: channel, from: Date.new(2026, 5, 7), to: Date.new(2026, 5, 9)
      )
    end
  end

  describe "auth failure handling" do
    it "exits early when the connection's needs_reauth is true" do
      connection.update_columns(needs_reauth: true)
      expect(client_double).not_to receive(:channel_daily)
      described_class.new.perform(channel.id)
    end

    it "sets connection.needs_reauth on AuthError and exits the job cleanly" do
      allow(client_double).to receive(:channel_daily) do
        connection.update_columns(needs_reauth: true)
        raise Youtube::AnalyticsClient::AuthError, "401"
      end
      expect {
        described_class.new.perform(channel.id)
      }.not_to raise_error
      expect(connection.reload.needs_reauth).to be true
    end
  end

  describe "idempotency" do
    it "does not duplicate ChannelDaily rows on a re-run" do
      described_class.new.perform(channel.id)
      expect {
        described_class.new.perform(channel.id)
      }.not_to change { ChannelDaily.where(channel_id: channel.id).count }
    end

    it "does not duplicate ChannelWindowSummary rows on a re-run" do
      described_class.new.perform(channel.id)
      expect {
        described_class.new.perform(channel.id)
      }.not_to change { ChannelWindowSummary.where(channel_id: channel.id).count }
    end

    it "does not duplicate TopVideosWindow rows on a re-run" do
      described_class.new.perform(channel.id)
      expect {
        described_class.new.perform(channel.id)
      }.not_to change { TopVideosWindow.where(channel_id: channel.id).count }
    end

    it "rebuilds TopVideosWindow rows correctly when leaderboard membership changes" do
      described_class.new.perform(channel.id)
      first_window_ids = TopVideosWindow.where(channel_id: channel.id, window: "7d").pluck(:video_id).sort

      # Leaderboard membership shrinks — vid_b drops off.
      allow(client_double).to receive(:top_videos).and_return(
        column_headers: [ { name: "video" }, { name: "views" }, { name: "estimatedMinutesWatched" }, { name: "averageViewDuration" }, { name: "averageViewPercentage" }, { name: "subscribersGained" }, { name: "likes" }, { name: "comments" } ],
        rows: [ [ "videoaa", 2000, 400, 100, 0.5, 10, 100, 20 ] ]
      )
      described_class.new.perform(channel.id)

      after_ids = TopVideosWindow.where(channel_id: channel.id, window: "7d").pluck(:video_id).sort
      expect(after_ids).to eq([ vid_a.id ])
      expect(first_window_ids).not_to eq(after_ids)
    end
  end
end
