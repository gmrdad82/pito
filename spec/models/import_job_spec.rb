require "rails_helper"

# Phase 22 §4.1 — ImportJob model.
RSpec.describe ImportJob, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  describe "associations" do
    it { is_expected.to belong_to(:channel) }
    it { is_expected.to belong_to(:enqueued_by).class_name("User") }
  end

  describe "enum status" do
    it "defines the four lifecycle states" do
      expect(described_class.statuses.keys).to eq(%w[queued running completed failed])
    end
  end

  describe "validations" do
    it { is_expected.to validate_numericality_of(:total_videos).only_integer.is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:imported_videos).only_integer.is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:failed_videos).only_integer.is_greater_than_or_equal_to(0) }
  end

  describe "scopes" do
    let(:channel) { create(:channel) }
    let!(:queued_job)   { create(:import_job, channel: channel) }
    let!(:running_job)  { create(:import_job, :running, channel: channel) }
    let!(:done_job)     { create(:import_job, :completed, channel: channel) }
    let!(:failed_job)   { create(:import_job, :failed, channel: channel) }

    describe ".in_flight" do
      it "returns queued and running rows" do
        expect(described_class.in_flight).to contain_exactly(queued_job, running_job)
      end
    end

    describe ".for_channel" do
      it "scopes to the given channel" do
        other_channel = create(:channel)
        other_job = create(:import_job, channel: other_channel)
        expect(described_class.for_channel(channel)).to include(queued_job, running_job)
        expect(described_class.for_channel(channel)).not_to include(other_job)
      end
    end

    describe ".recent" do
      it "orders by created_at desc" do
        expect(described_class.recent.first).to eq(failed_job)
      end
    end
  end

  describe "callbacks" do
    let(:channel) { create(:channel) }
    let(:user)    { create(:user) }

    it "stamps started_at when transitioning to running" do
      job = create(:import_job, channel: channel, enqueued_by: user)
      expect(job.started_at).to be_nil

      job.update!(status: :running)
      expect(job.started_at).to be_within(2.seconds).of(Time.current)
    end

    it "does not overwrite an existing started_at" do
      previously = 2.hours.ago
      job = create(:import_job, channel: channel, enqueued_by: user, started_at: previously)
      job.update!(status: :running)
      expect(job.started_at).to be_within(1.second).of(previously)
    end

    it "stamps completed_at when transitioning to completed" do
      job = create(:import_job, :running, channel: channel, enqueued_by: user)
      job.update!(status: :completed)
      expect(job.completed_at).to be_within(2.seconds).of(Time.current)
    end

    it "stamps completed_at when transitioning to failed" do
      job = create(:import_job, :running, channel: channel, enqueued_by: user)
      job.update!(status: :failed, error_payload: { "code" => "boom" })
      expect(job.completed_at).to be_within(2.seconds).of(Time.current)
    end
  end

  describe "#progress_fraction" do
    it "returns 0.0 when total_videos is 0" do
      job = build(:import_job, total_videos: 0, imported_videos: 0)
      expect(job.progress_fraction).to eq(0.0)
    end

    it "returns imported/total" do
      job = build(:import_job, total_videos: 10, imported_videos: 3)
      expect(job.progress_fraction).to be_within(0.001).of(0.3)
    end

    it "caps at 1.0 when imported > total (defensive)" do
      job = build(:import_job, total_videos: 5, imported_videos: 7)
      expect(job.progress_fraction).to eq(1.0)
    end
  end

  describe "#in_flight?" do
    it "is true for queued" do
      expect(build(:import_job, status: :queued)).to be_in_flight
    end

    it "is true for running" do
      expect(build(:import_job, status: :running)).to be_in_flight
    end

    it "is false for completed" do
      expect(build(:import_job, status: :completed)).not_to be_in_flight
    end

    it "is false for failed" do
      expect(build(:import_job, status: :failed)).not_to be_in_flight
    end
  end

  describe "#candidate_videos" do
    let(:channel) { create(:channel) }
    let(:user)    { create(:user) }

    it "returns channel videos created between started_at and completed_at" do
      started  = 5.minutes.ago
      finished = 1.minute.ago

      before_video  = travel_to(started - 10.minutes) { create(:video, channel: channel) }
      during_video1 = travel_to(started + 1.minute)   { create(:video, channel: channel) }
      during_video2 = travel_to(finished - 30.seconds) { create(:video, channel: channel) }
      after_video   = travel_to(finished + 10.minutes) { create(:video, channel: channel) }

      job = create(:import_job,
                   channel: channel,
                   enqueued_by: user,
                   status: :completed,
                   started_at: started,
                   completed_at: finished)

      expect(job.candidate_videos).to contain_exactly(during_video1, during_video2)
      expect(job.candidate_videos).not_to include(before_video, after_video)
    end

    it "scopes to the import job's channel" do
      other_channel = create(:channel)
      _other_channel_video = create(:video, channel: other_channel)
      mine = create(:video, channel: channel)

      job = create(:import_job, :completed,
                   channel: channel,
                   enqueued_by: user,
                   started_at: 10.minutes.ago,
                   completed_at: Time.current)

      expect(job.candidate_videos).to include(mine)
      expect(job.candidate_videos.map(&:channel_id).uniq).to eq([ channel.id ])
    end
  end
end
