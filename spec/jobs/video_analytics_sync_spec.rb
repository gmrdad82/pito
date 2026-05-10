require "rails_helper"

# Phase 13.2 — Analytics sync engine. Per-video job spec.
RSpec.describe VideoAnalyticsSync do
  let(:user)       { create(:user) }
  let(:connection) { create(:youtube_connection, user: user) }
  let(:channel)    { create(:channel, :connected, youtube_connection: connection) }
  let(:active_video) { create(:video, channel: channel, youtube_video_id: "videoact", published_at: 30.days.ago) }
  let(:inactive_video) { create(:video, channel: channel, youtube_video_id: "videoiac", published_at: 200.days.ago) }
  let(:client_double) { instance_double(Youtube::AnalyticsClient) }

  before do
    allow(Youtube::AnalyticsClient).to receive(:new).and_return(client_double)
    allow(client_double).to receive(:today_pt).and_return(Date.new(2026, 5, 10))

    allow(client_double).to receive(:video_daily).and_return(
      column_headers: [ { name: "day" }, { name: "views" }, { name: "estimatedMinutesWatched" } ],
      rows: [
        [ "2026-05-07", 100, 20 ],
        [ "2026-05-08", 150, 30 ],
        [ "2026-05-09", 200, 40 ]
      ]
    )
    allow(client_double).to receive(:video_window_summary).and_return(
      column_headers: [ { name: "views" }, { name: "averageViewPercentage" } ],
      rows: [ [ 5000, 0.42 ] ]
    )
    allow(client_double).to receive(:video_by_country).and_return(
      column_headers: [ { name: "country" }, { name: "views" }, { name: "estimatedMinutesWatched" } ],
      rows: [ [ "US", 500, 100 ], [ "DE", 300, 60 ] ]
    )
    allow(client_double).to receive(:video_by_device_type).and_return(
      column_headers: [ { name: "deviceType" }, { name: "views" } ],
      rows: [ [ "MOBILE", 600 ], [ "DESKTOP", 400 ] ]
    )
    allow(client_double).to receive(:video_by_operating_system).and_return(
      column_headers: [ { name: "operatingSystem" }, { name: "views" } ],
      rows: [ [ "ANDROID", 500 ], [ "IOS", 300 ] ]
    )
    allow(client_double).to receive(:video_by_traffic_source).and_return(
      column_headers: [ { name: "insightTrafficSourceType" }, { name: "views" } ],
      rows: [ [ "YT_SEARCH", 400 ], [ "EXT_URL", 200 ] ]
    )
    allow(client_double).to receive(:video_by_subscribed_status).and_return(
      column_headers: [ { name: "subscribedStatus" }, { name: "views" } ],
      rows: [ [ "SUBSCRIBED", 700 ], [ "UNSUBSCRIBED", 300 ] ]
    )
    allow(client_double).to receive(:video_demographics).and_return(
      column_headers: [ { name: "ageGroup" }, { name: "gender" }, { name: "viewerPercentage" } ],
      rows: [ [ "AGE_18_24", "MALE", 0.4 ], [ "AGE_25_34", "FEMALE", 0.3 ] ]
    )
  end

  describe "happy path — active video" do
    it "fetches V1 and upserts VideoDaily rows" do
      expect {
        described_class.new.perform(active_video.id)
      }.to change { VideoDaily.where(video_id: active_video.id).count }.by(3)
    end

    it "fetches V2 for each window and upserts VideoWindowSummary rows" do
      expect {
        described_class.new.perform(active_video.id)
      }.to change { VideoWindowSummary.where(video_id: active_video.id).count }.by(4)
    end

    it "fetches V3 and upserts VideoDailyByCountry rows" do
      expect {
        described_class.new.perform(active_video.id)
      }.to change { VideoDailyByCountry.where(video_id: active_video.id).count }.by(2)
    end

    it "fetches V4 (deviceType) and upserts VideoDailyByDeviceType rows" do
      expect {
        described_class.new.perform(active_video.id)
      }.to change { VideoDailyByDeviceType.where(video_id: active_video.id).count }.by(2)
    end

    it "fetches V4 (operatingSystem) and upserts VideoDailyByOperatingSystem rows" do
      expect {
        described_class.new.perform(active_video.id)
      }.to change { VideoDailyByOperatingSystem.where(video_id: active_video.id).count }.by(2)
    end

    it "fetches V5 and upserts VideoDailyByTrafficSource rows" do
      expect {
        described_class.new.perform(active_video.id)
      }.to change { VideoDailyByTrafficSource.where(video_id: active_video.id).count }.by(2)
    end

    it "fetches V6 and upserts VideoDailyBySubscribedStatus rows" do
      expect {
        described_class.new.perform(active_video.id)
      }.to change { VideoDailyBySubscribedStatus.where(video_id: active_video.id).count }.by(2)
    end

    it "fetches V8 and upserts VideoDailyByAgeGroupGender rows" do
      expect {
        described_class.new.perform(active_video.id)
      }.to change { VideoDailyByAgeGroupGender.where(video_id: active_video.id).count }.by(2)
    end
  end

  describe "happy path — inactive video" do
    it "fetches V1 only and skips V2-V8 for inactive videos" do
      described_class.new.perform(inactive_video.id)
      expect(client_double).to have_received(:video_daily).once
      expect(client_double).not_to have_received(:video_window_summary)
      expect(client_double).not_to have_received(:video_by_country)
      expect(client_double).not_to have_received(:video_demographics)
    end
  end

  describe "auth failure handling" do
    it "exits early when the connection's needs_reauth is true" do
      connection.update_columns(needs_reauth: true)
      expect(client_double).not_to receive(:video_daily)
      described_class.new.perform(active_video.id)
    end

    it "sets connection.needs_reauth on AuthError and exits cleanly" do
      allow(client_double).to receive(:video_daily) do
        connection.update_columns(needs_reauth: true)
        raise Youtube::AnalyticsClient::AuthError, "401"
      end
      expect {
        described_class.new.perform(active_video.id)
      }.not_to raise_error
      expect(connection.reload.needs_reauth).to be true
    end
  end

  describe "idempotency (one case per slice)" do
    it "VideoDaily rows do not duplicate on re-run" do
      described_class.new.perform(active_video.id)
      expect {
        described_class.new.perform(active_video.id)
      }.not_to change { VideoDaily.where(video_id: active_video.id).count }
    end

    it "VideoDailyByCountry rows do not duplicate on re-run" do
      described_class.new.perform(active_video.id)
      expect {
        described_class.new.perform(active_video.id)
      }.not_to change { VideoDailyByCountry.where(video_id: active_video.id).count }
    end

    it "VideoDailyByDeviceType rows do not duplicate on re-run" do
      described_class.new.perform(active_video.id)
      expect {
        described_class.new.perform(active_video.id)
      }.not_to change { VideoDailyByDeviceType.where(video_id: active_video.id).count }
    end

    it "VideoDailyBySubscribedStatus rows do not duplicate on re-run" do
      described_class.new.perform(active_video.id)
      expect {
        described_class.new.perform(active_video.id)
      }.not_to change { VideoDailyBySubscribedStatus.where(video_id: active_video.id).count }
    end

    it "VideoDailyByAgeGroupGender rows do not duplicate on re-run" do
      described_class.new.perform(active_video.id)
      expect {
        described_class.new.perform(active_video.id)
      }.not_to change { VideoDailyByAgeGroupGender.where(video_id: active_video.id).count }
    end
  end

  describe "edge — empty response" do
    it "writes no rows when the API returns no data" do
      allow(client_double).to receive(:video_daily).and_return(column_headers: [ { name: "day" } ], rows: [])
      expect {
        described_class.new.perform(active_video.id)
      }.not_to change { VideoDaily.where(video_id: active_video.id).count }
    end
  end
end
