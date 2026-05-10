require "rails_helper"

# Phase 20 — friendly URLs. Video uses `youtube_video_id` as the slug.
RSpec.describe Video, type: :model do
  it_behaves_like "an identifier-style friendly resource", Video,
                  factory: :video

  describe "#to_param" do
    it "returns youtube_video_id" do
      video = create(:video, youtube_video_id: "abc123XYZ-_")
      expect(video.to_param).to eq("abc123XYZ-_")
    end

    it "falls back to id when youtube_video_id is unexpectedly blank" do
      video = create(:video)
      video.youtube_video_id = ""
      expect(video.to_param).to eq(video.id.to_s)
    end
  end

  describe "uniqueness on youtube_video_id" do
    it "rejects two videos with the same youtube_video_id" do
      create(:video, youtube_video_id: "duplicate1")
      duplicate = build(:video, youtube_video_id: "duplicate1")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:youtube_video_id]).to include("has already been taken")
    end

    it "is case-sensitive" do
      create(:video, youtube_video_id: "CaseSlug")
      different = build(:video, youtube_video_id: "caseslug")
      expect(different).to be_valid
    end
  end
end
