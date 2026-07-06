# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Channel::Games do
  let(:conversation) { Conversation.singleton }
  let(:channel)      { create(:channel, title: "Grid Channel", handle: "@grid") }

  before do
    video = create(:video, channel: channel)
    create(:video_game_link, video: video, game: create(:game, title: "Linked One"))
  end

  it "returns an html payload carrying the games grid component" do
    payload = described_class.call(channel, conversation:)
    expect(payload["html"]).to be(true)
    expect(payload["body"]).to include("pito-channel-games__grid")
  end

  it "stamps the channel id" do
    expect(described_class.call(channel, conversation:)["channel_id"]).to eq(channel.id)
  end

  it "is follow-up-able with reply_target channel_games" do
    payload = described_class.call(channel, conversation:)
    expect(payload["reply_target"]).to eq("channel_games")
    expect(payload["reply_handle"]).to be_present
  end
end
