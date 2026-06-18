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

    it "is idempotent — missing link still returns Ok with the unlinked summary" do
      link.destroy!
      result = follow_up_handler(payload: game_detail_payload, rest: "from video ##{video.id}").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      text = result.events.first[:payload]["text"]
      expect(text).to include("Lies of P")
      expect(text).to include("Lies of P Review")
      expect(VideoGameLink.find_by(video: video, game: game)).to be_nil
    end

    it "returns not-found when the video id is unknown" do
      result = follow_up_handler(payload: game_detail_payload, rest: "from video 99999").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to include("99999")
    end

    it "returns a usage hint when a title ref is given instead of an id" do
      result = follow_up_handler(payload: game_detail_payload, rest: "from video lies of p review").call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.unlink.follow_up_usage.detail")
    end

    it "returns a usage hint when the ref is blank" do
      result = follow_up_handler(payload: game_detail_payload, rest: "from video").call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.unlink.follow_up_usage.detail")
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

    it "is idempotent — missing link still returns Ok with the unlinked summary" do
      link.destroy!
      result = follow_up_handler(payload: video_detail_payload, rest: "from game ##{game.id}").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      text = result.events.first[:payload]["text"]
      expect(text).to include("Lies of P")
      expect(text).to include("Lies of P Review")
      expect(VideoGameLink.find_by(video: video, game: game)).to be_nil
    end

    it "returns not-found when the game id is unknown" do
      result = follow_up_handler(payload: video_detail_payload, rest: "from game 99999").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to include("99999")
    end

    it "returns a usage hint when a title ref is given instead of an id" do
      result = follow_up_handler(payload: video_detail_payload, rest: "from game lies of p").call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.unlink.follow_up_usage.detail")
    end

    it "returns a usage hint when the ref is blank" do
      result = follow_up_handler(payload: video_detail_payload, rest: "from game").call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.unlink.follow_up_usage.detail")
    end

    # Case 4 — detail source + multi-target
    it "unlinks this video from multiple games when targets are comma-separated" do
      g2    = create(:game,  title: "Bloodborne")
      link2 = create(:video_game_link, video: video, game: g2)
      expect {
        follow_up_handler(payload: video_detail_payload, rest: "from #{game.id},#{g2.id}").call
      }.to change(VideoGameLink, :count).by(-2)
    end

    it "returns Ok whose summary names all unlinked games for multi-target" do
      g2 = create(:game, title: "Bloodborne")
      create(:video_game_link, video: video, game: g2)
      result = follow_up_handler(payload: video_detail_payload, rest: "from #{game.id},#{g2.id}").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      text = result.events.first[:payload]["text"]
      expect(text).to include("Lies of P")
      expect(text).to include("Bloodborne")
    end
  end

  # ── Follow-up from a list card (smart / multi-target) ──────────────────────────

  describe "follow-up from a video_list card (smart / multi-target)" do
    let(:video_list_payload) { { "reply_target" => "video_list" } }

    # Case 1 — list source, single target
    it "destroys the VideoGameLink given a source video id and a single target game id" do
      expect {
        follow_up_handler(payload: video_list_payload, rest: "#{video.id} from #{game.id}").call
      }.to change(VideoGameLink, :count).by(-1)
    end

    it "returns Ok whose text includes the target game title (single target)" do
      result = follow_up_handler(payload: video_list_payload, rest: "#{video.id} from #{game.id}").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to include("Lies of P")
    end

    # Case 2 — list source, multi-target (comma-separated and space-separated)
    it "destroys one link per target for comma-separated game ids" do
      g2    = create(:game, title: "Bloodborne")
      g3    = create(:game, title: "Elden Ring")
      create(:video_game_link, video: video, game: g2)
      create(:video_game_link, video: video, game: g3)
      expect {
        follow_up_handler(payload: video_list_payload,
                          rest: "#{video.id} from #{game.id},#{g2.id},#{g3.id}").call
      }.to change(VideoGameLink, :count).by(-3)
    end

    it "summary text names all three unlinked games" do
      g2 = create(:game, title: "Bloodborne")
      g3 = create(:game, title: "Elden Ring")
      create(:video_game_link, video: video, game: g2)
      create(:video_game_link, video: video, game: g3)
      result = follow_up_handler(payload: video_list_payload,
                                 rest: "#{video.id} from #{game.id},#{g2.id},#{g3.id}").call
      text = result.events.first[:payload]["text"]
      expect(text).to include("Lies of P")
      expect(text).to include("Bloodborne")
      expect(text).to include("Elden Ring")
    end

    it "destroys all links when targets are space-separated instead of comma-separated" do
      g2 = create(:game, title: "Bloodborne")
      create(:video_game_link, video: video, game: g2)
      expect {
        follow_up_handler(payload: video_list_payload,
                          rest: "#{video.id} from #{game.id} #{g2.id}").call
      }.to change(VideoGameLink, :count).by(-2)
    end

    # Case 3 — not-found target reported
    it "still unlinks valid targets when one target id does not exist" do
      result = follow_up_handler(payload: video_list_payload,
                                 rest: "#{video.id} from #{game.id},99999").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(VideoGameLink.find_by(video: video, game: game)).to be_nil
    end

    it "appends a '(not found: ...)' note to the summary for missing target ids" do
      result = follow_up_handler(payload: video_list_payload,
                                 rest: "#{video.id} from #{game.id},99999").call
      text = result.events.first[:payload]["text"]
      expect(text).to include("Lies of P")
      expect(text).to include("(not found: 99999)")
    end

    # Case 5 — list source, missing 'from' connector
    it "returns a usage error when the 'from' connector is absent" do
      result = follow_up_handler(payload: video_list_payload, rest: video.id.to_s).call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.unlink.follow_up_usage.list")
    end
  end
end
