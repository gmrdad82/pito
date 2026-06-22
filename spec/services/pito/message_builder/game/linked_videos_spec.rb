# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Game::LinkedVideos do
  let(:conversation) { Conversation.singleton }
  let(:game)         { create(:game, title: "Lies of P") }
  let(:channel)      { create(:channel, handle: "@bossarena") }
  let!(:video)       { create(:video, channel: channel, title: "Boss Fight") }
  let!(:vgl)         { create(:video_game_link, video: video, game: game) }

  subject(:payload) { described_class.call(game, conversation: conversation) }

  it "marks the body as html so the shimmer markup renders raw" do
    expect(payload["html"]).to be(true)
  end

  it "keeps the video_list follow-up target (inherited from Video::List)" do
    expect(Pito::FollowUp.followupable?(payload)).to be(true)
    expect(payload["reply_target"]).to eq("video_list")
  end

  it "still carries the table rows for the linked videos" do
    expect(payload["table_rows"].size).to eq(1)
    expect(payload["video_ids"]).to eq([ video.id ])
  end

  it "wraps the game title subject in a pito-subject-shimmer span" do
    expect(payload["body"]).to match(%r{<span class="pito-subject-shimmer[^"]*">Lies of P</span>})
  end

  it "renders each channel @handle as a cyan token-shimmer span" do
    expect(payload["body"]).to match(%r{<span class="pito-token-shimmer[^"]*">@bossarena</span>})
  end

  it "escapes HTML-special characters in the game title (no XSS)" do
    game.update!(title: "<b>x</b>")
    expect(payload["body"]).to include("&lt;b&gt;x&lt;/b&gt;")
    expect(payload["body"]).not_to include("<b>x</b>")
  end
end
