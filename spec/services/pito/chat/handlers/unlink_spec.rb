# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Unlink do
  def tokens(*words)
    words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
  end

  def handler_for(*words)
    described_class.new(
      message: Pito::Chat::Message.new(
        verb: :unlink,
        body_tokens: tokens(*words),
        kind: :new_turn,
        raw: "unlink #{words.join(' ')}"
      ),
      conversation: Conversation.singleton
    )
  end

  let!(:game)  { create(:game,  title: "Lies of P") }
  let!(:video) { create(:video, title: "Lies of P Review") }
  let!(:link)  { create(:video_game_link, video: video, game: game) }

  it "destroys the VideoGameLink when unlinking game from video by id" do
    expect {
      handler_for("game", game.id.to_s, "to", "video", video.id.to_s).call
    }.to change(VideoGameLink, :count).by(-1)
  end

  it "destroys the VideoGameLink when unlinking video from game by id (reversed order)" do
    expect {
      handler_for("video", video.id.to_s, "to", "game", game.id.to_s).call
    }.to change(VideoGameLink, :count).by(-1)
  end

  it "accepts 'from' separator as well as 'to'" do
    expect {
      handler_for("game", game.id.to_s, "from", "video", video.id.to_s).call
    }.to change(VideoGameLink, :count).by(-1)
  end

  it "returns Ok with a witty success message" do
    result = handler_for("game", game.id.to_s, "to", "video", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    text = result.events.first[:payload]["text"]
    expect(text).to include("Lies of P")
    expect(text).to include("Lies of P Review")
  end

  it "is idempotent — unlinking a missing link returns a gentle message" do
    link.destroy!
    result = handler_for("game", game.id.to_s, "to", "video", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    text = result.events.first[:payload]["text"]
    expect(text).to include("already not linked").or include("not linked")
  end

  it "returns a not-found result for an unknown game" do
    result = handler_for("game", "99999", "to", "video", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to include("99999")
  end

  it "returns a not-found result for an unknown video" do
    result = handler_for("game", game.id.to_s, "to", "video", "99999").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to include("99999")
  end

  it "returns a usage hint when no 'to'/'from' separator is given" do
    result = handler_for("game", game.id.to_s, "video", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.unlink.usage")
  end

  it "returns a usage hint when body is empty" do
    result = handler_for.call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.unlink.usage")
  end

  it "unlinks by title (ILIKE) for both game and video" do
    expect {
      handler_for("game", "lies", "of", "p", "to", "video", "lies", "of", "p", "review").call
    }.to change(VideoGameLink, :count).by(-1)
  end

  it "unlinks when video is named first" do
    link2 = create(:video_game_link, video: video, game: create(:game, title: "Sekiro"))
    result = handler_for("video", video.id.to_s, "from", "game", game.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(VideoGameLink.find_by(id: link.id)).to be_nil
    expect(VideoGameLink.find_by(id: link2.id)).not_to be_nil
  end
end
