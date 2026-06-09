# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("spec/support/recommendation_fixture")

# Golden, hand-validated game→channel numbers (Recommendation v2). Built from the
# frozen 7-game corpus seeded onto genre-personality channels as published-video
# links. These numbers were confirmed by the user; do not change them without
# warrant — they are the contract for the channel-personality model.
RSpec.describe "Golden game→channel recommendations", type: :service do
  let(:games) { RecommendationFixture.load!.index_by(&:title) }

  let(:scenario) do
    {
      "good games"     => [ "Elden Ring", "Pragmata" ],
      "survival"       => [ "Dead Space", "Mad Max" ],
      "hard games"     => [ "Ghosts 'n Goblins Resurrection", "Super Meat Boy" ],
      "sci-fi shooter" => [ "Dead Space", "Pragmata", "Scars Above" ]
    }
  end

  before do
    games # force-load the corpus
    scenario.each do |name, titles|
      channel = create(:channel, title: name)
      titles.each do |title|
        video = create(:video, :public, channel: channel)
        create(:video_game_link, video: video, game: games.fetch(title))
      end
    end
  end

  def scores_for(title)
    Game::ChannelRecommendation.call(games.fetch(title), include_all: true)
      .to_h { |r| [ r.channel.title, r.score ] }
  end

  it "routes Dead Space to its sci-fi home, then survival, then good, then hard" do
    expect(scores_for("Dead Space")).to eq(
      "sci-fi shooter" => 95, "survival" => 84, "good games" => 62, "hard games" => 32
    )
  end

  it "routes Elden Ring to good games (high score), low on the platformer 'hard' channel" do
    s = scores_for("Elden Ring")
    expect(s["good games"]).to eq(89)
    expect(s["good games"]).to be > s["hard games"]
  end

  it "routes Ghosts 'n Goblins to the hard (platformer) channel" do
    expect(scores_for("Ghosts 'n Goblins Resurrection")["hard games"]).to eq(90)
  end

  it "routes Mad Max to survival" do
    expect(scores_for("Mad Max")["survival"]).to eq(88)
  end

  it "gives the SAME game different scores per channel (personality fit)" do
    s = scores_for("Pragmata")
    expect(s.values.uniq.size).to be > 1
    expect(s["sci-fi shooter"]).to be > s["hard games"]
  end
end
