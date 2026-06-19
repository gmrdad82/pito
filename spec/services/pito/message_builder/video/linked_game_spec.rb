# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Video::LinkedGame do
  let(:conversation) { Conversation.singleton }
  let(:channel)      { create(:channel) }
  let(:video)        { create(:video, channel: channel, title: "Boss Fight") }

  context "when the video has a linked game" do
    let!(:game) { create(:game, title: "Lies of P") }
    let!(:vgl)  { create(:video_game_link, video: video, game: game) }

    subject(:payload) { described_class.call(video, conversation: conversation) }

    it "renders the linked-game card body" do
      expect(payload["body"]).to include("Lies of P")
      expect(payload["html"]).to be(true)
    end

    it "prepends the witty intro line (game title interpolated) before the card" do
      intro = Pito::Copy.render("pito.copy.videos.linked_game_intro", { game: "Lies of P" })

      expect(payload["body"]).to include(ERB::Util.html_escape(intro))
      # The intro paragraph comes first, the card markup follows it.
      expect(payload["body"].index("pito-video-linked-game-intro"))
        .to be < payload["body"].index("pito-video-linked-game-card")
    end

    it "stamps the linked game's id" do
      expect(payload["game_id"]).to eq(game.id)
    end

    it "is made follow-up-able with the game_detail target" do
      expect(Pito::FollowUp.followupable?(payload)).to be(true)
      expect(payload["reply_target"]).to eq("game_detail")
    end
  end

  context "when the video has no linked game" do
    it "returns nil" do
      expect(described_class.call(video, conversation: conversation)).to be_nil
    end
  end
end
