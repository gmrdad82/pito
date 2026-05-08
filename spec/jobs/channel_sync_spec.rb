require "rails_helper"

RSpec.describe ChannelSync, type: :job do
  describe "#perform" do
    context "happy path" do
      let!(:channel) { create(:channel) }

      it "stamps last_synced_at on the channel" do
        described_class.new.perform(channel.id)
        channel.reload
        expect(channel.last_synced_at).to be_within(2.seconds).of(Time.current)
      end
    end

    context "when the channel was deleted before perform runs" do
      it "returns without raising" do
        missing_id = 999_999
        expect { described_class.new.perform(missing_id) }.not_to raise_error
      end
    end
  end
end
