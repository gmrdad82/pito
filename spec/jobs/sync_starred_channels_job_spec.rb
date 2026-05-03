require "rails_helper"

RSpec.describe SyncStarredChannelsJob, type: :job do
  describe "#perform" do
    it "enqueues one ChannelSync per starred channel" do
      starred_a = create(:channel, :starred)
      starred_b = create(:channel, :starred)
      _plain    = create(:channel)

      ChannelSync.clear

      described_class.new.perform

      enqueued_args = ChannelSync.jobs.map { |j| j["args"].first }
      expect(enqueued_args).to contain_exactly(starred_a.id, starred_b.id)
    end

    it "does not enqueue for non-starred channels" do
      _plain = create(:channel)

      ChannelSync.clear

      described_class.new.perform

      expect(ChannelSync.jobs).to be_empty
    end
  end
end
