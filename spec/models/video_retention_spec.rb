require "rails_helper"

RSpec.describe VideoRetention, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:video) }
  end

  describe "validations" do
    it "is invalid without elapsed_ratio_bucket" do
      record = build(:video_retention, elapsed_ratio_bucket: nil)
      expect(record).not_to be_valid
      expect(record.errors[:elapsed_ratio_bucket]).to be_present
    end

    it "rejects elapsed_ratio_bucket < 0 or > 1" do
      below = build(:video_retention, elapsed_ratio_bucket: -0.01)
      above = build(:video_retention, elapsed_ratio_bucket: 1.5)
      expect(below).not_to be_valid
      expect(above).not_to be_valid
    end

    it "is invalid with a duplicate (video_id, elapsed_ratio_bucket)" do
      existing = create(:video_retention, elapsed_ratio_bucket: 0.10)
      duplicate = build(:video_retention,
                        video: existing.video,
                        elapsed_ratio_bucket: 0.10)
      expect(duplicate).not_to be_valid
    end
  end

  describe "schema" do
    it "uses computed_at, not created_at / updated_at" do
      cols = described_class.column_names
      expect(cols).to include("computed_at")
      expect(cols).not_to include("created_at")
      expect(cols).not_to include("updated_at")
    end
  end

  describe "round-trip precision" do
    it "round-trips audience_watch_ratio at 6 decimal precision" do
      record = create(:video_retention, audience_watch_ratio: 0.123456)
      record.reload
      expect(record.audience_watch_ratio).to eq(BigDecimal("0.123456"))
    end

    it "round-trips relative_retention_performance" do
      record = create(:video_retention, relative_retention_performance: 1.234567)
      record.reload
      expect(record.relative_retention_performance).to eq(BigDecimal("1.234567"))
    end
  end

  describe "defaults" do
    it "defaults started_watching / stopped_watching / total_segment_impressions to 0" do
      record = described_class.create!(
        video: create(:video),
        elapsed_ratio_bucket: 0.42
      )
      expect(record.started_watching).to eq(0)
      expect(record.stopped_watching).to eq(0)
      expect(record.total_segment_impressions).to eq(0)
    end
  end

  describe "cascade" do
    it "is destroyed when its video is destroyed" do
      video = create(:video)
      create(:video_retention, video: video, elapsed_ratio_bucket: 0.50)
      expect { video.destroy }.to change(described_class, :count).by(-1)
    end
  end
end
