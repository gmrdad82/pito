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

  def follow_up_handler(payload:, rest:)
    ctx = Pito::Chat::FollowUpContext.new(
      source_event: instance_double(Event, payload: payload),
      rest:         rest
    )
    described_class.new(
      message:      instance_double(Pito::Chat::Message),
      conversation: Conversation.singleton,
      follow_up:    ctx
    )
  end

  let!(:game)  { create(:game,  title: "Lies of P") }
  let!(:video) { create(:video, title: "Lies of P Review") }
  let!(:link)  { create(:video_game_link, video: video, game: game) }

  it "destroys the VideoGameLink when unlinking game from video by id" do
    expect {
      handler_for("game", game.id.to_s, "from", "video", video.id.to_s).call
    }.to change(VideoGameLink, :count).by(-1)
  end

  it "destroys the VideoGameLink when unlinking video from game by id (reversed order)" do
    expect {
      handler_for("video", video.id.to_s, "from", "game", game.id.to_s).call
    }.to change(VideoGameLink, :count).by(-1)
  end

  it "returns a usage hint when 'to' is used as separator (only 'from' is valid)" do
    result = handler_for("game", game.id.to_s, "to", "video", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.unlink.usage")
  end

  it "returns Ok with a witty success message" do
    result = handler_for("game", game.id.to_s, "from", "video", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    text = result.events.first[:payload]["text"]
    expect(text).to include("Lies of P")
    expect(text).to include("Lies of P Review")
  end

  it "is idempotent — unlinking a missing link returns a gentle message" do
    link.destroy!
    result = handler_for("game", game.id.to_s, "from", "video", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    text = result.events.first[:payload]["text"]
    expect(text).to include("already not linked").or include("not linked")
  end

  it "returns a not-found result for an unknown game id" do
    result = handler_for("game", "99999", "from", "video", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to include("99999")
  end

  it "returns a not-found result for an unknown video id" do
    result = handler_for("game", game.id.to_s, "from", "video", "99999").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to include("99999")
  end

  it "returns a usage hint when no 'from' separator is given" do
    result = handler_for("game", game.id.to_s, "video", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.unlink.usage")
  end

  it "returns a usage hint when body is empty" do
    result = handler_for.call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.unlink.usage")
  end

  it "returns a usage hint when a title ref is given instead of an id" do
    result = handler_for("game", "lies", "of", "p", "from", "video", "lies", "of", "p", "review").call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.unlink.usage")
  end

  it "unlinks when video is named first (from separator)" do
    link2 = create(:video_game_link, video: video, game: create(:game, title: "Sekiro"))
    result = handler_for("video", video.id.to_s, "from", "game", game.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(VideoGameLink.find_by(id: link.id)).to be_nil
    expect(VideoGameLink.find_by(id: link2.id)).not_to be_nil
  end

  # ── Follow-up branch ─────────────────────────────────────────────────────────

  describe "follow-up from a game_detail card" do
    let(:game_detail_payload) do
      { "reply_target" => "game_detail", "game_id" => game.id }
    end

    it "destroys the link by video id ref (with leading 'from video')" do
      handler = follow_up_handler(payload: game_detail_payload, rest: "from video ##{video.id}")
      expect { handler.call }.to change(VideoGameLink, :count).by(-1)
    end

    it "destroys the link by video id ref (with leading 'to video')" do
      handler = follow_up_handler(payload: game_detail_payload, rest: "to video ##{video.id}")
      expect { handler.call }.to change(VideoGameLink, :count).by(-1)
    end

    it "returns Ok with the unlinked ack" do
      result = follow_up_handler(payload: game_detail_payload, rest: "from video ##{video.id}").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      text = result.events.first[:payload]["text"]
      expect(text).to include("Lies of P")
      expect(text).to include("Lies of P Review")
    end

    it "returns a gentle 'not linked' message when link is already absent" do
      link.destroy!
      result = follow_up_handler(payload: game_detail_payload, rest: "from video ##{video.id}").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      text = result.events.first[:payload]["text"]
      expect(text).to include("not linked").or include("already")
    end

    it "returns not-found when the video id is unknown" do
      result = follow_up_handler(payload: game_detail_payload, rest: "from video 99999").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to include("99999")
    end

    it "returns a usage hint when a title ref is given instead of an id" do
      result = follow_up_handler(payload: game_detail_payload, rest: "from video lies of p review").call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.unlink.usage")
    end

    it "returns a usage hint when the ref is blank" do
      result = follow_up_handler(payload: game_detail_payload, rest: "from video").call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.unlink.usage")
    end
  end

  describe "follow-up from a video_detail card" do
    let(:video_detail_payload) do
      { "reply_target" => "video_detail", "video_id" => video.id }
    end

    it "destroys the link by game id ref (with leading 'from game')" do
      handler = follow_up_handler(payload: video_detail_payload, rest: "from game ##{game.id}")
      expect { handler.call }.to change(VideoGameLink, :count).by(-1)
    end

    it "destroys the link by game id ref (with leading 'to game')" do
      handler = follow_up_handler(payload: video_detail_payload, rest: "to game ##{game.id}")
      expect { handler.call }.to change(VideoGameLink, :count).by(-1)
    end

    it "returns Ok with the unlinked ack" do
      result = follow_up_handler(payload: video_detail_payload, rest: "from game ##{game.id}").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      text = result.events.first[:payload]["text"]
      expect(text).to include("Lies of P")
      expect(text).to include("Lies of P Review")
    end

    it "returns a gentle 'not linked' message when link is already absent" do
      link.destroy!
      result = follow_up_handler(payload: video_detail_payload, rest: "from game ##{game.id}").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      text = result.events.first[:payload]["text"]
      expect(text).to include("not linked").or include("already")
    end

    it "returns not-found when the game id is unknown" do
      result = follow_up_handler(payload: video_detail_payload, rest: "from game 99999").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to include("99999")
    end

    it "returns a usage hint when a title ref is given instead of an id" do
      result = follow_up_handler(payload: video_detail_payload, rest: "from game lies of p").call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.unlink.usage")
    end

    it "returns a usage hint when the ref is blank" do
      result = follow_up_handler(payload: video_detail_payload, rest: "from game").call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.unlink.usage")
    end
  end
end
