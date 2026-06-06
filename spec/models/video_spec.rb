# frozen_string_literal: true

require "rails_helper"

RSpec.describe Video, type: :model do
  subject(:video) { build(:video) }

  # ── Associations ─────────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to belong_to(:channel).required }
    it { is_expected.to have_many(:video_game_links).dependent(:destroy) }
    it { is_expected.to have_many(:linked_games).through(:video_game_links).source(:game) }
  end

  # ── Validations ──────────────────────────────────────────────────
  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:youtube_video_id) }

    it "requires uniqueness of youtube_video_id" do
      create(:video, youtube_video_id: "dup_yt_id")
      dup = build(:video, youtube_video_id: "dup_yt_id")
      expect(dup).not_to be_valid
      expect(dup.errors[:youtube_video_id]).to be_present
    end
  end

  # ── Enum: privacy_status ─────────────────────────────────────────
  describe "enum :privacy_status" do
    it "defaults to private (0)" do
      v = Video.new
      expect(v.privacy_status).to eq("private")
    end

    it "defines private, public, unlisted" do
      expect(described_class.privacy_statuses.keys).to contain_exactly("private", "public", "unlisted")
    end

    it "stores public as integer 1 in the database" do
      v = create(:video, privacy_status: :public)
      raw = ActiveRecord::Base.connection.execute(
        "SELECT privacy_status FROM videos WHERE id = #{v.id}"
      ).first["privacy_status"]
      expect(raw).to eq(1)
    end

    it "defines prefix-scoped predicate #privacy_status_public?" do
      v = build(:video, privacy_status: :public)
      expect(v).to be_privacy_status_public
    end

    it "defines #privacy_status_private?" do
      v = build(:video, privacy_status: :private)
      expect(v).to be_privacy_status_private
    end

    it "defines #privacy_status_unlisted?" do
      v = build(:video, privacy_status: :unlisted)
      expect(v).to be_privacy_status_unlisted
    end

    it "transitions privacy_status between values" do
      v = create(:video, :private)
      v.update!(privacy_status: :public)
      expect(v.reload.privacy_status).to eq("public")
    end
  end

  # ── #etag_changed? ───────────────────────────────────────────────
  describe "#etag_changed?" do
    context "when stored etag is nil" do
      it "returns true regardless of new etag" do
        video.etag = nil
        expect(video.etag_changed?("any_etag")).to be(true)
      end
    end

    context "when stored etag is blank" do
      it "returns true for any new etag" do
        video.etag = ""
        expect(video.etag_changed?("W/\"new-etag\"")).to be(true)
      end
    end

    context "when new etag equals stored etag" do
      it "returns false" do
        video.etag = "W/\"abc123\""
        expect(video.etag_changed?("W/\"abc123\"")).to be(false)
      end
    end

    context "when new etag differs from stored etag" do
      it "returns true" do
        video.etag = "W/\"old-etag\""
        expect(video.etag_changed?("W/\"new-etag\"")).to be(true)
      end
    end
  end
end
