# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightlySyncJob, type: :job do
  include ActiveJob::TestHelper

  let!(:active_connection)  { create(:youtube_connection) }
  let!(:reauth_connection)  { create(:youtube_connection, :needs_reauth) }

  let!(:channel_a) do
    create(:channel,
           youtube_connection: active_connection,
           youtube_channel_id: "UCaaa111",
           title: "Alpha")
  end

  let!(:channel_b) do
    create(:channel,
           youtube_connection: active_connection,
           youtube_channel_id: "UCbbb222",
           title: "Beta")
  end

  let!(:reauth_channel) do
    create(:channel,
           youtube_connection: reauth_connection,
           youtube_channel_id: "UCreauth")
  end

  let!(:disconnected_channel) { create(:channel, :orphan) }

  describe "#perform" do
    subject(:job) { described_class.new }

    it "enqueues ChannelSync for each connected (non-reauth) channel" do
      expect {
        job.perform
      }.to have_enqueued_job(ChannelSync).with(channel_a.id)
         .and have_enqueued_job(ChannelSync).with(channel_b.id)
    end

    it "does not enqueue ChannelSync for reauth or disconnected channels" do
      job.perform

      channel_sync_ids = enqueued_jobs
        .select { |j| j["job_class"] == "ChannelSync" }
        .map { |j| j["arguments"]&.first }

      expect(channel_sync_ids).not_to include(reauth_channel.id)
      expect(channel_sync_ids).not_to include(disconnected_channel.id)
    end

    it "enqueues VideoSyncJob for each connected (non-reauth) channel" do
      expect {
        job.perform
      }.to have_enqueued_job(VideoSyncJob).with(channel_a.id)
         .and have_enqueued_job(VideoSyncJob).with(channel_b.id)
    end

    it "does not enqueue VideoSyncJob for reauth or disconnected channels" do
      job.perform

      video_sync_ids = enqueued_jobs
        .select { |j| j["job_class"] == "VideoSyncJob" }
        .map { |j| j["arguments"]&.first }

      expect(video_sync_ids).not_to include(reauth_channel.id)
      expect(video_sync_ids).not_to include(disconnected_channel.id)
    end

    it "does not enqueue the retired NightlyVideoSyncJob" do
      job.perform

      job_classes = enqueued_jobs.map { |j| j["job_class"] }
      expect(job_classes).not_to include("NightlyVideoSyncJob")
    end

    it "enqueues GameIgdbNightlyRefresh" do
      expect {
        job.perform
      }.to have_enqueued_job(GameIgdbNightlyRefresh)
    end

    it "enqueues exactly one GameIgdbNightlyRefresh regardless of channel count" do
      job.perform
      count = enqueued_jobs.count { |j| j["job_class"] == "GameIgdbNightlyRefresh" }
      expect(count).to eq(1)
    end

    context "when there are no connected channels" do
      before { active_connection.update!(needs_reauth: true) }

      it "still enqueues GameIgdbNightlyRefresh exactly once" do
        job.perform
        count = enqueued_jobs.count { |j| j["job_class"] == "GameIgdbNightlyRefresh" }
        expect(count).to eq(1)
      end

      it "does not enqueue ChannelSync for any channel" do
        job.perform
        count = enqueued_jobs.count { |j| j["job_class"] == "ChannelSync" }
        expect(count).to eq(0)
      end

      it "does not enqueue VideoSyncJob for any channel" do
        job.perform
        count = enqueued_jobs.count { |j| j["job_class"] == "VideoSyncJob" }
        expect(count).to eq(0)
      end
    end

    context "when igdb: false (the 13:00 igdb-skipped recurring run)" do
      it "enqueues ChannelSync for each connected (non-reauth) channel" do
        expect {
          job.perform(igdb: false)
        }.to have_enqueued_job(ChannelSync).with(channel_a.id)
           .and have_enqueued_job(ChannelSync).with(channel_b.id)
      end

      it "enqueues VideoSyncJob for each connected (non-reauth) channel" do
        expect {
          job.perform(igdb: false)
        }.to have_enqueued_job(VideoSyncJob).with(channel_a.id)
           .and have_enqueued_job(VideoSyncJob).with(channel_b.id)
      end

      it "does not enqueue GameIgdbNightlyRefresh" do
        job.perform(igdb: false)

        job_classes = enqueued_jobs.map { |j| j["job_class"] }
        expect(job_classes).not_to include("GameIgdbNightlyRefresh")
      end
    end

    context "solid_queue recurring.yml kwargs round-trip" do
      it "delivers a recurring-task Hash arg as the igdb: keyword, not a positional Hash" do
        # config/recurring.yml's 13:00 entry configures `args: [{ igdb: false }]`.
        # SolidQueue reconstructs the job with `Hash.ruby2_keywords_hash(...)` (not a
        # real keyword splat) before calling `perform_now` — this pins that exact
        # round-trip so `igdb: false` keeps landing as a keyword arg on `#perform`
        # rather than silently becoming a positional Hash (which `perform(igdb: true)`
        # would not accept, or would ignore).
        job = NightlySyncJob.new(*[ Hash.ruby2_keywords_hash({ igdb: false }) ])

        job.perform_now

        job_classes = enqueued_jobs.map { |j| j["job_class"] }
        expect(job_classes).not_to include("GameIgdbNightlyRefresh")
      end
    end
  end
end
