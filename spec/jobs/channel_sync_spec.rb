require "rails_helper"

RSpec.describe ChannelSync, type: :job do
  describe "#perform" do
    context "happy path" do
      let!(:channel) { create(:channel) }

      it "flips syncing true then false and sets last_synced_at" do
        before_synced = channel.last_synced_at

        described_class.new.perform(channel.id)

        channel.reload
        expect(channel.syncing).to be(false)
        expect(channel.last_synced_at).to be_present
        expect(channel.last_synced_at).not_to eq(before_synced)
      end
    end

    context "when the channel was deleted before perform runs" do
      it "returns without raising" do
        missing_id = 999_999
        expect { described_class.new.perform(missing_id) }.not_to raise_error
      end
    end

    context "when the channel is destroyed mid-flight" do
      let!(:channel) { create(:channel) }

      it "ensure block does not raise" do
        # Simulate mid-flight delete: stub update! to delete the row before raising/continuing
        allow(Channel).to receive(:find_by).and_call_original

        # First find_by inside perform returns the channel
        # Inside the syncing=true update we destroy the row to simulate mid-flight delete
        allow_any_instance_of(Channel).to receive(:update!) do |c, attrs|
          c.update_columns(attrs)
          Channel.where(id: c.id).delete_all
          true
        end

        expect { described_class.new.perform(channel.id) }.not_to raise_error
        expect(Channel.exists?(id: channel.id)).to be(false)
      end
    end
  end
end
