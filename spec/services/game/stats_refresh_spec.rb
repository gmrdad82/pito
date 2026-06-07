# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game::StatsRefresh do
  let(:game) { create(:game) }

  def link_video(views:)
    video = create(:video)
    Pito::Stats.set(video, :views, views) unless views.nil?
    create(:video_game_link, video: video, game: game)
    video
  end

  describe ".call" do
    it "materializes game views as the sum of linked videos' views" do
      link_video(views: 100)
      link_video(views: 250)

      described_class.call(game)

      expect(Pito::Stats.get(game, :views)).to eq(350)
    end

    it "stores 0 when the game has no linked videos" do
      described_class.call(game)
      expect(Pito::Stats.get(game, :views)).to eq(0)
    end

    it "ignores linked videos that carry no view stat" do
      link_video(views: 100)
      link_video(views: nil)

      described_class.call(game)

      expect(Pito::Stats.get(game, :views)).to eq(100)
    end

    it "excludes views of videos linked to other games" do
      other_game = create(:game)
      other_video = create(:video)
      Pito::Stats.set(other_video, :views, 9_999)
      create(:video_game_link, video: other_video, game: other_game)

      link_video(views: 50)
      described_class.call(game)

      expect(Pito::Stats.get(game, :views)).to eq(50)
    end

    it "recomputes on a subsequent call" do
      video = link_video(views: 100)
      described_class.call(game)
      expect(Pito::Stats.get(game, :views)).to eq(100)

      Pito::Stats.set(video, :views, 500)
      described_class.call(game)
      expect(Pito::Stats.get(game, :views)).to eq(500)
    end
  end
end
