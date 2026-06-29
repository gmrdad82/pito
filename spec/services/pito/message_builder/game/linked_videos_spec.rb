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

  it "uses the game_linked_videos follow-up target (game-context: show vid / unlink)" do
    expect(Pito::FollowUp.followupable?(payload)).to be(true)
    expect(payload["reply_target"]).to eq("game_linked_videos")
    # game_id is carried so an `unlink #<vid>` reply unlinks from THIS game.
    expect(payload["game_id"]).to eq(game.id)
  end

  it "still carries the table rows for the linked videos" do
    expect(payload["table_rows"].size).to eq(1)
    expect(payload["video_ids"]).to eq([ video.id ])
  end

  it "carries chat-prefill data on the #id cell so a click auto-submits `show vid #id` (J12)" do
    cell = payload["table_rows"].first[:cells][0]
    data = cell[:data]
    expect(cell[:text]).to eq("##{video.id}")
    expect(data[:controller]).to eq("pito--chat-prefill")
    expect(data[:"pito--chat-prefill-text-value"]).to eq("show vid ##{video.id}")
    expect(data[:"pito--chat-prefill-submit-value"]).to eq("true")
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
