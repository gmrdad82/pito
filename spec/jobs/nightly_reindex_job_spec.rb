# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightlyReindexJob, type: :job do
  include ActiveJob::TestHelper

  describe "#perform" do
    subject(:job) { described_class.new }

    let!(:game_a)  { create(:game) }
    let!(:game_b)  { create(:game) }
    let!(:channel) { create(:channel) }
    let!(:video_a) { create(:video, channel: channel) }
    let!(:video_b) { create(:video, channel: channel) }

    it "enqueues GameEmbedIndexJob for every game" do
      expect {
        job.perform
      }.to have_enqueued_job(GameEmbedIndexJob).with(game_a.id)
         .and have_enqueued_job(GameEmbedIndexJob).with(game_b.id)
    end

    it "enqueues VideoEmbedIndexJob for every video" do
      expect {
        job.perform
      }.to have_enqueued_job(VideoEmbedIndexJob).with(video_a.id)
         .and have_enqueued_job(VideoEmbedIndexJob).with(video_b.id)
    end

    it "enqueues exactly N_games + N_videos index jobs" do
      job.perform
      game_jobs  = enqueued_jobs.count { |j| j["job_class"] == "GameEmbedIndexJob" }
      video_jobs = enqueued_jobs.count { |j| j["job_class"] == "VideoEmbedIndexJob" }

      expect(game_jobs).to eq(Game.count)
      expect(video_jobs).to eq(Video.count)
    end

    it "is a no-op (enqueues nothing) when there are no games or videos" do
      Game.destroy_all
      Video.destroy_all

      job.perform
      expect(enqueued_jobs).to be_empty
    end
  end
end
