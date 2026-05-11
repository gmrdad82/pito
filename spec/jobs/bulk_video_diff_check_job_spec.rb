require "rails_helper"

RSpec.describe BulkVideoDiffCheckJob, type: :job do
  let(:user) { create(:user) }
  let(:youtube_connection) { create(:youtube_connection, user: user) }
  let(:connected_channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv",
           youtube_connection: youtube_connection)
  end
  let(:lonely_channel) do
    create(:channel,
           channel_url: "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuw",
           youtube_connection: nil)
  end

  before do
    VideoDiffCheckJob.jobs.clear if defined?(VideoDiffCheckJob.jobs)
  end

  it "is a no-op when no Video has a connected channel" do
    create(:video, channel: lonely_channel)

    expect {
      described_class.new.perform
    }.not_to change(VideoDiffCheckJob.jobs, :size)
  end

  it "enqueues one VideoDiffCheckJob per connected video" do
    v1 = create(:video, channel: connected_channel)
    v2 = create(:video, channel: connected_channel)

    described_class.new.perform

    enqueued_ids = VideoDiffCheckJob.jobs.map { |j| j["args"].first }
    expect(enqueued_ids).to contain_exactly(v1.id, v2.id)
  end

  it "ignores videos on channels without an OAuth connection" do
    connected_video = create(:video, channel: connected_channel)
    create(:video, channel: lonely_channel)

    described_class.new.perform

    enqueued_ids = VideoDiffCheckJob.jobs.map { |j| j["args"].first }
    expect(enqueued_ids).to contain_exactly(connected_video.id)
  end

  it "staggers enqueues across the configured window" do
    3.times { create(:video, channel: connected_channel) }

    described_class.new.perform

    # First job runs immediately (offset 0 — Sidekiq doesn't carry
    # `at` for zero-delay enqueues); the trailing jobs carry
    # increasing `at` timestamps spread across the configured window.
    later_offsets = VideoDiffCheckJob.jobs.filter_map { |j| j["at"] }
    expect(later_offsets.size).to eq(2)
    expect(later_offsets).to eq(later_offsets.sort)
  end

  it "returns the count of enqueued jobs" do
    create(:video, channel: connected_channel)
    create(:video, channel: connected_channel)

    expect(described_class.new.perform).to eq(2)
  end
end
