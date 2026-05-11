require "rails_helper"

# Phase 22 §4.2 — RejectedVideoImport tombstone.
RSpec.describe RejectedVideoImport, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:channel) }
    it { is_expected.to belong_to(:rejected_by).class_name("User") }
  end

  describe "validations" do
    let(:channel) { create(:channel) }
    let(:user)    { create(:user) }

    it "requires a youtube_video_id" do
      record = described_class.new(channel: channel, rejected_by: user, rejected_at: Time.current)
      expect(record).not_to be_valid
      expect(record.errors[:youtube_video_id]).to be_present
    end

    it "requires a rejected_at" do
      record = described_class.new(channel: channel, rejected_by: user,
                                   youtube_video_id: "dQw4w9WgXcQ")
      record.valid?
      expect(record.errors[:rejected_at]).to be_present
    end

    it "rejects malformed youtube_video_id values" do
      record = build(:rejected_video_import, channel: channel, rejected_by: user,
                                              youtube_video_id: "not-a-youtube-id")
      expect(record).not_to be_valid
      expect(record.errors[:youtube_video_id]).to be_present
    end

    it "accepts the canonical 11-char shape" do
      record = build(:rejected_video_import, channel: channel, rejected_by: user,
                                              youtube_video_id: "dQw4w9WgXcQ")
      expect(record).to be_valid
    end

    it "enforces uniqueness within a channel" do
      create(:rejected_video_import, channel: channel, rejected_by: user,
                                     youtube_video_id: "dQw4w9WgXcQ")
      dup = build(:rejected_video_import, channel: channel, rejected_by: user,
                                          youtube_video_id: "dQw4w9WgXcQ")
      expect(dup).not_to be_valid
      expect(dup.errors[:youtube_video_id]).to be_present
    end

    it "allows the same youtube_video_id across channels" do
      other_channel = create(:channel)
      create(:rejected_video_import, channel: channel, rejected_by: user,
                                     youtube_video_id: "dQw4w9WgXcQ")
      twin = build(:rejected_video_import, channel: other_channel, rejected_by: user,
                                           youtube_video_id: "dQw4w9WgXcQ")
      expect(twin).to be_valid
    end
  end

  describe "DB-level uniqueness" do
    it "raises ActiveRecord::RecordNotUnique on a duplicate (channel, youtube_video_id)" do
      channel = create(:channel)
      user = create(:user)
      create(:rejected_video_import, channel: channel, rejected_by: user,
                                     youtube_video_id: "dQw4w9WgXcQ")

      expect {
        described_class.new(
          channel: channel,
          rejected_by: user,
          youtube_video_id: "dQw4w9WgXcQ",
          rejected_at: Time.current
        ).save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
