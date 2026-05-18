require "rails_helper"

RSpec.describe VideoDiff, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:video) }
    it { is_expected.to belong_to(:resolved_by_user).class_name("User").optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:detected_at) }

    it "rejects non-Hash payload" do
      diff = build(:video_diff, payload: "not a hash")
      expect(diff).not_to be_valid
      expect(diff.errors[:payload]).to include("must be a Hash")
    end

    it "accepts nil resolution_payload" do
      diff = build(:video_diff, resolution_payload: nil)
      expect(diff).to be_valid
    end

    it "rejects non-Hash resolution_payload when present" do
      diff = build(:video_diff, resolution_payload: "stringy")
      expect(diff).not_to be_valid
      expect(diff.errors[:resolution_payload]).to include("must be a Hash when present")
    end
  end

  describe "scopes" do
    let!(:open_diff)     { create(:video_diff) }
    let!(:resolved_diff) { create(:video_diff, :resolved) }

    it ".open returns unresolved diffs" do
      expect(VideoDiff.open).to contain_exactly(open_diff)
    end

    it ".resolved returns resolved diffs" do
      expect(VideoDiff.resolved).to contain_exactly(resolved_diff)
    end

    it ".recent orders by detected_at desc" do
      newer = create(:video_diff, detected_at: 1.hour.from_now)
      expect(VideoDiff.recent.first).to eq(newer)
    end
  end

  describe "#fields / #field_diff / pito_value / youtube_value" do
    let(:diff) do
      build_stubbed(:video_diff, payload: {
        "title" => { "pito" => "p", "youtube" => "y" },
        "tags"  => { "pito" => [ "a" ], "youtube" => [ "b" ] }
      })
    end

    it "exposes the differing field names" do
      expect(diff.fields).to match_array(%w[title tags])
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
      diff = build(:video_diff)
      expect(diff).to be_open
      expect(diff).not_to be_resolved
    end

    it "resolved when resolved_at is present" do
      diff = build(:video_diff, :resolved)
      expect(diff).to be_resolved
      expect(diff).not_to be_open
    end
  end

  describe "partial unique index" do
    it "allows only one open diff per video" do
      video = create(:video)
      create(:video_diff, video: video)

      expect {
        VideoDiff.create!(video: video, detected_at: Time.current, payload: {})
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows a new open diff after the prior one is resolved" do
      video = create(:video)
      first = create(:video_diff, video: video)
      first.update!(resolved_at: Time.current)

      expect {
        create(:video_diff, video: video)
      }.not_to raise_error
    end
  end
end
