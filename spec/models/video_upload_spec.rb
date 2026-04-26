require "rails_helper"

RSpec.describe VideoUpload, type: :model do
  subject { build(:video_upload) }

  describe "associations" do
    it { is_expected.to belong_to(:channel) }
    it { is_expected.to belong_to(:video).optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:file_name) }
    it { is_expected.to validate_presence_of(:file_size) }
    it { is_expected.to validate_numericality_of(:file_size).is_greater_than(0) }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:status).with_values(pending: 0, uploading: 1, processing: 2, completed: 3, failed: 4) }
    it { is_expected.to define_enum_for(:privacy_status).with_values(public_video: 0, unlisted: 1, private_video: 2).with_prefix(:privacy) }
  end

  describe "#progress_percent" do
    it "returns percentage of bytes uploaded" do
      upload = build(:video_upload, file_size: 1000, bytes_sent: 500)
      expect(upload.progress_percent).to eq(50.0)
    end

    it "returns 0 when file_size is zero" do
      upload = build(:video_upload, file_size: 1, bytes_sent: 0)
      upload.file_size = 0
      expect(upload.progress_percent).to eq(0)
    end
  end
end
