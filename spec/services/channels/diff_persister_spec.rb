require "rails_helper"

# Phase 7.5 §11i — Channels::DiffPersister.
RSpec.describe Channels::DiffPersister, type: :service do
  let(:channel) { create(:channel) }
  let(:field_diffs) do
    { "title" => { "pito" => "p", "youtube" => "y" } }
  end

  describe "fresh diff" do
    it "creates a new open ChannelDiff row" do
      expect {
        described_class.call(channel: channel, field_diffs: field_diffs)
      }.to change(ChannelDiff, :count).by(1)
    end

    it "returns the persisted row" do
      diff = described_class.call(channel: channel, field_diffs: field_diffs)
      expect(diff).to be_persisted
      expect(diff.field_diffs).to eq(field_diffs)
      expect(diff.channel).to eq(channel)
      expect(diff).to be_open
    end

    it "stamps detected_at to the provided timestamp" do
      now = 5.minutes.ago
      diff = described_class.call(channel: channel, field_diffs: field_diffs, detected_at: now)
      expect(diff.detected_at).to be_within(1.second).of(now)
    end
  end

  describe "existing open row" do
    let!(:existing) do
      create(:channel_diff, channel: channel,
             field_diffs: { "title" => { "pito" => "old", "youtube" => "old-y" } },
             detected_at: 1.day.ago)
    end

    it "refreshes the existing row in place (no new row)" do
      expect {
        described_class.call(channel: channel, field_diffs: field_diffs)
      }.not_to change(ChannelDiff, :count)
    end

    it "updates field_diffs to the new payload" do
      described_class.call(channel: channel, field_diffs: field_diffs)
      expect(existing.reload.field_diffs).to eq(field_diffs)
    end

    it "refreshes detected_at to the new timestamp" do
      now = Time.current
      described_class.call(channel: channel, field_diffs: field_diffs, detected_at: now)
      expect(existing.reload.detected_at).to be_within(1.second).of(now)
    end

    it "returns the same row instance" do
      result = described_class.call(channel: channel, field_diffs: field_diffs)
      expect(result.id).to eq(existing.id)
    end
  end

  describe "empty diff (sides converged)" do
    context "with no prior open row" do
      it "returns nil without creating a row" do
        expect {
          expect(described_class.call(channel: channel, field_diffs: {})).to be_nil
        }.not_to change(ChannelDiff, :count)
      end
    end

    context "with a prior open row" do
      let!(:existing) { create(:channel_diff, channel: channel) }

      it "auto-closes the prior row with resolution_payload auto_closed=true" do
        described_class.call(channel: channel, field_diffs: {})
        existing.reload
        expect(existing.resolved_at).to be_present
        expect(existing.resolution_payload).to eq({ "auto_closed" => true })
      end

      it "returns nil" do
        expect(described_class.call(channel: channel, field_diffs: {})).to be_nil
      end

      it "does NOT delete the prior row (audit history kept)" do
        expect {
          described_class.call(channel: channel, field_diffs: {})
        }.not_to change(ChannelDiff, :count)
      end
    end
  end

  describe "race recovery" do
    it "rescues RecordNotUnique by falling back to an UPDATE" do
      # Simulate the race: first pass inserts; second pass's
      # find_by(...) misses because the index has a partial-where
      # clause that the second pass's snapshot doesn't see — but the
      # subsequent INSERT trips the partial unique index. The
      # persister catches RecordNotUnique and retries as UPDATE.
      create(:channel_diff, channel: channel,
             field_diffs: { "title" => { "pito" => "x", "youtube" => "y" } })

      # Force the simulated race by stubbing the first .find_by
      # lookup to return nil, then letting the INSERT trip the
      # partial unique index.
      lookup_count = 0
      allow(ChannelDiff).to receive(:unresolved).and_wrap_original do |orig, *args|
        lookup_count += 1
        if lookup_count == 1
          # First lookup — simulated race-loser sees no open row.
          ChannelDiff.none
        else
          orig.call(*args)
        end
      end

      # Should not raise; should produce the (now refreshed) open row.
      expect {
        described_class.call(channel: channel, field_diffs: field_diffs)
      }.not_to raise_error
    end
  end
end
