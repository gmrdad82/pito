# frozen_string_literal: true

require "rails_helper"

RSpec.describe VideoGameLink, type: :model do
  subject(:link) { build(:video_game_link) }

  # ── Associations ─────────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to belong_to(:video).required }
    it { is_expected.to belong_to(:game).required }
  end

  # ── Validations ──────────────────────────────────────────────────
  describe "validations" do
    it "requires a video" do
      link.video = nil
      expect(link).not_to be_valid
    end

    it "requires a game" do
      link.game = nil
      expect(link).not_to be_valid
    end

    it "enforces uniqueness of video_id scoped to game_id" do
      vgl = create(:video_game_link)
      dup = build(:video_game_link, video: vgl.video, game: vgl.game)
      expect(dup).not_to be_valid
      expect(dup.errors[:video_id]).to be_present
    end

    it "allows same video to link to a different game" do
      vgl = create(:video_game_link)
      other = build(:video_game_link, video: vgl.video, game: create(:game))
      expect(other).to be_valid
    end

    it "allows same game to link to a different video" do
      vgl = create(:video_game_link)
      other = build(:video_game_link, video: create(:video), game: vgl.game)
      expect(other).to be_valid
    end
  end

  # ── Cascade destroy ──────────────────────────────────────────────
  describe "cascade on parent destroy" do
    it "is destroyed when the video is destroyed" do
      vgl = create(:video_game_link)
      expect { vgl.video.destroy! }.to change(VideoGameLink, :count).by(-1)
    end

    it "is destroyed when the game is destroyed" do
      vgl = create(:video_game_link)
      expect { vgl.game.destroy! }.to change(VideoGameLink, :count).by(-1)
    end
  end
end
