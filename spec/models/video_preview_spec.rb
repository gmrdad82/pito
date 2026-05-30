# frozen_string_literal: true

require "rails_helper"

RSpec.describe VideoPreview, type: :model do
  subject(:preview) { build(:video_preview) }

  describe "associations" do
    it { is_expected.to belong_to(:video).required }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:status) }
  end

  describe "enums" do
    it "defines expected status values" do
      expect(described_class.statuses).to eq(
        { "draft" => 0, "publishing" => 1, "published" => 2, "failed" => 3 }
      )
    end

    it "defines expected shorts_remixing values" do
      expect(described_class.shorts_remixings).to eq(
        { "video_audio" => 0, "audio_only" => 1, "none" => 2 }
      )
    end

    it "generates prefixed predicate methods" do
      preview = build(:video_preview, shorts_remixing: :video_audio)
      expect(preview).to respond_to(:shorts_remixing_video_audio?)
      expect(preview.shorts_remixing_video_audio?).to be(true)
    end
  end

  describe "thumbnail attachment" do
    it "responds to thumbnail" do
      expect(preview).to respond_to(:thumbnail)
    end
  end
end
