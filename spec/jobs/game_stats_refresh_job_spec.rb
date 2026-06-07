# frozen_string_literal: true

require "rails_helper"

RSpec.describe GameStatsRefreshJob do
  describe "#perform" do
    it "refreshes the game's materialized views stat" do
      game = create(:game)
      video = create(:video)
      Pito::Stats.set(video, :views, 420)
      create(:video_game_link, video: video, game: game)

      described_class.new.perform(game.id)

      expect(Pito::Stats.get(game, :views)).to eq(420)
    end

    it "is a no-op for a missing game" do
      expect { described_class.new.perform(0) }.not_to raise_error
    end
  end

  describe "enqueue triggers" do
    it "is enqueued when a video-game link is created" do
      game = create(:game)
      video = create(:video)

      expect { create(:video_game_link, video: video, game: game) }
        .to have_enqueued_job(GameStatsRefreshJob).with(game.id)
    end

    it "is enqueued when a video-game link is destroyed" do
      link = create(:video_game_link)

      expect { link.destroy }
        .to have_enqueued_job(GameStatsRefreshJob).with(link.game_id)
    end
  end
end
