require "rails_helper"

# Phase 7.5 §11i — ChannelDiff model.
RSpec.describe ChannelDiff, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:channel) }
    it { is_expected.to belong_to(:resolved_by_user).class_name("User").optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:detected_at) }

    it "rejects non-Hash field_diffs" do
      diff = build(:channel_diff, field_diffs: "not a hash")
      expect(diff).not_to be_valid
      expect(diff.errors[:field_diffs]).to include("must be a Hash")
    end

    it "accepts nil resolution_payload" do
      diff = build(:channel_diff, resolution_payload: nil)
      expect(diff).to be_valid
    end

    it "rejects non-Hash resolution_payload when present" do
      diff = build(:channel_diff, resolution_payload: "stringy")
      expect(diff).not_to be_valid
      expect(diff.errors[:resolution_payload]).to include("must be a Hash when present")
    end

    it "defaults field_diffs to an empty Hash via the DB default" do
      diff = ChannelDiff.new(channel: create(:channel), detected_at: Time.current)
      expect(diff.field_diffs).to eq({})
      expect(diff).to be_valid
    end
  end

  describe "scopes" do
    let!(:open_diff)     { create(:channel_diff) }
    let!(:resolved_diff) { create(:channel_diff, :resolved) }

    it ".unresolved returns rows with resolved_at IS NULL" do
      expect(ChannelDiff.unresolved).to contain_exactly(open_diff)
    end

    it ".open is an alias of .unresolved" do
      expect(ChannelDiff.open).to contain_exactly(open_diff)
    end

    it ".resolved returns rows with resolved_at set" do
      expect(ChannelDiff.resolved).to contain_exactly(resolved_diff)
    end

    it ".recent orders by detected_at desc" do
      newer = create(:channel_diff, detected_at: 1.hour.from_now)
      expect(ChannelDiff.recent.first).to eq(newer)
    end
  end

  describe "#fields / #field_diff / #pito_value / #youtube_value" do
    let(:diff) do
      create(:channel_diff, field_diffs: {
        "title"       => { "pito" => "p", "youtube" => "y" },
        "description" => { "pito" => "pd", "youtube" => "yd" }
      })
    end

    it "exposes the differing field names sorted" do
      expect(diff.fields).to eq(%w[description title])
    end

    it "exposes the diffing field set via #diffing_fields alias" do
      expect(diff.diffing_fields).to eq(%w[description title])
    end

    it "returns the pito/youtube pair for a field" do
      expect(diff.field_diff("title")).to eq({ "pito" => "p", "youtube" => "y" })
    end

    it "returns nil for an unknown field" do
      expect(diff.field_diff("missing")).to be_nil
    end

    it "pito_value / youtube_value return the right side" do
      expect(diff.pito_value("title")).to eq("p")
      expect(diff.youtube_value("title")).to eq("y")
    end
  end

  describe "#resolved? / #open?" do
    it "open by default" do
      diff = build(:channel_diff)
      expect(diff).to be_open
      expect(diff).not_to be_resolved
    end

    it "resolved when resolved_at is present" do
      diff = build(:channel_diff, :resolved)
      expect(diff).to be_resolved
      expect(diff).not_to be_open
    end
  end

  describe "partial unique index" do
    it "allows only one open diff per channel" do
      channel = create(:channel)
      create(:channel_diff, channel: channel)

      expect {
        ChannelDiff.create!(channel: channel, detected_at: Time.current,
                            field_diffs: {})
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows a new open diff after the prior one is resolved" do
      channel = create(:channel)
      first = create(:channel_diff, channel: channel)
      first.update!(resolved_at: Time.current,
                    resolution_payload: { "auto_closed" => true })

      expect {
        create(:channel_diff, channel: channel)
      }.not_to raise_error
    end

    it "auto-closed rows keep the audit history (do not destroy)" do
      channel = create(:channel)
      first = create(:channel_diff, :auto_closed, channel: channel)
      _second = create(:channel_diff, channel: channel)

      expect(ChannelDiff.where(channel: channel).count).to eq(2)
      expect(first.reload.resolution_payload).to eq({ "auto_closed" => true })
    end
  end
end
