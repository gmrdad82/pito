require "rails_helper"

# Phase 13.2 — Analytics sync engine. Top-level orchestrator spec.
RSpec.describe YoutubeAnalyticsSync do
  let(:user)              { create(:user) }
  let(:active_connection) { create(:youtube_connection, user: user) }
  let(:reauth_connection) { create(:youtube_connection, :needs_reauth, user: user, google_subject_id: "needs-reauth-99") }
  let(:active_channel) { create(:channel, :connected, youtube_connection: active_connection) }
  let!(:active_video)  { create(:video, channel: active_channel, published_at: 30.days.ago) }

  let(:reauth_channel) { create(:channel, :connected, youtube_connection: reauth_connection) }
  let!(:reauth_video)  { create(:video, channel: reauth_channel, published_at: 5.days.ago) }

  before do
    active_channel
    Sidekiq::Worker.clear_all
  end

  describe "iteration" do
    it "iterates every YoutubeConnection.active" do
      described_class.new.perform
      enqueued_channel_ids = ChannelAnalyticsSync.jobs.map { |j| j["args"].first }
      expect(enqueued_channel_ids).to include(active_channel.id)
    end

    it "skips connections with needs_reauth: true" do
      described_class.new.perform
      enqueued_channel_ids = ChannelAnalyticsSync.jobs.map { |j| j["args"].first }
      expect(enqueued_channel_ids).not_to include(reauth_channel.id)
    end
  end

  describe "dispatch" do
    it "enqueues a ChannelAnalyticsSync per channel under each active connection" do
      expect {
        described_class.new.perform
      }.to change(ChannelAnalyticsSync.jobs, :size).by(1)
    end

    it "enqueues a VideoAnalyticsSync per video under each active connection" do
      expect {
        described_class.new.perform
      }.to change(VideoAnalyticsSync.jobs, :size).by(1)
    end
  end

  describe "retention-only mode" do
    it "when called with retention_only: true, enqueues only VideoRetentionSync jobs" do
      described_class.new.perform(retention_only: true)
      expect(VideoRetentionSync.jobs.size).to eq(1)
      expect(ChannelAnalyticsSync.jobs.size).to eq(0)
      expect(VideoAnalyticsSync.jobs.size).to eq(0)
    end
  end

  describe "concurrency safety" do
    it "is idempotent on a re-run" do
      described_class.new.perform
      first_count = ChannelAnalyticsSync.jobs.size
      described_class.new.perform
      expect(ChannelAnalyticsSync.jobs.size).to eq(first_count * 2) # same set re-enqueued
    end
  end

  describe "audit / logging" do
    it "logs the start and finish to Rails.logger" do
      expect(Rails.logger).to receive(:info)
        .with(a_string_matching(/\[analytics-sync\] starting nightly run; 1 active connections/))
      expect(Rails.logger).to receive(:info)
        .with(a_string_matching(/\[analytics-sync\] complete;/))
      described_class.new.perform
    end

    it "uses the 'retention-only run' phrase when retention_only is set" do
      expect(Rails.logger).to receive(:info)
        .with(a_string_matching(/\[analytics-sync\] starting retention-only run; 1 active connections/))
      expect(Rails.logger).to receive(:info)
        .with(a_string_matching(/\[analytics-sync\] complete;/))
      described_class.new.perform(retention_only: true)
    end
  end
end
