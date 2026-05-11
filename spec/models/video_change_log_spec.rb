require "rails_helper"

RSpec.describe VideoChangeLog, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:video) }
    it { is_expected.to belong_to(:changed_by_user).class_name("User").optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:field) }
    it { is_expected.to validate_presence_of(:changed_at) }

    it "rejects an unknown field name" do
      log = build(:video_change_log, field: "notafield")
      expect(log).not_to be_valid
      expect(log.errors[:field]).to be_present
    end

    it "accepts every field in DIFF_RESOLVABLE_FIELDS" do
      Youtube::DiffComputer::DIFF_RESOLVABLE_FIELDS.each do |f|
        log = build(:video_change_log, field: f)
        expect(log).to be_valid, "expected `#{f}` to validate"
      end
    end
  end

  describe "enum :source" do
    it "exposes the three source kinds" do
      expect(described_class.sources.keys).to match_array(%w[pito_apply youtube_pull initial_sync])
    end
  end

  describe "append-only enforcement" do
    let(:log) { create(:video_change_log) }

    it "is read-only once persisted" do
      expect(log).to be_readonly
    end

    it "raises ReadOnlyRecord on update" do
      expect {
        log.update!(new_value: "tampered")
      }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "raises ReadOnlyRecord on destroy" do
      expect {
        log.destroy
      }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "allows fresh inserts" do
      expect {
        create(:video_change_log)
      }.to change(described_class, :count).by(1)
    end
  end

  describe "scopes" do
    let(:video) { create(:video) }
    let!(:older) { create(:video_change_log, video: video, changed_at: 2.days.ago) }
    let!(:newer) { create(:video_change_log, video: video, changed_at: 1.hour.ago) }

    it ".recent orders by changed_at desc" do
      expect(described_class.recent.first).to eq(newer)
    end

    it ".for_field filters by field name" do
      desc_log = create(:video_change_log, video: video, field: "description")
      expect(described_class.for_field("description")).to contain_exactly(desc_log)
    end
  end
end
