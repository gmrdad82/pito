# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::Link do
  def tokens(*words)
    words.each_with_index.map do |w, i|
      Pito::Lex::Token.new(type: :word, value: w, position: i, preceded_by_space: i.positive?)
    end
  end

  def handler_for(*words)
    described_class.new(
      message: Pito::Chat::Message.new(
        tool: :link,
        body_tokens: tokens(*words),
        kind: :new_turn,
        raw: "link #{words.join(' ')}"
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

  it "creates a VideoGameLink when linking game to video by id" do
    expect {
      handler_for("game", game.id.to_s, "to", "video", video.id.to_s).call
    }.to change(VideoGameLink, :count).by(1)
  end

  it "creates a VideoGameLink when linking video to game by id (reversed order)" do
    expect {
      handler_for("video", video.id.to_s, "to", "game", game.id.to_s).call
    }.to change(VideoGameLink, :count).by(1)
  end

  describe "multi-id free chat (comma/space-separated id list per side)" do
    let!(:video2) { create(:video, title: "Lies of P Boss Guide") }

    it "links one game to multiple vids: `link game <id> with vid a,b`" do
      expect {
        handler_for("game", game.id.to_s, "with", "vid", "#{video.id},#{video2.id}").call
      }.to change(VideoGameLink, :count).by(2)
      expect(game.reload.linked_videos).to include(video, video2)
    end

    it "links one vid to multiple games: `link vid <id> with game a,b`" do
      game2 = create(:game, title: "Bloodborne")
      expect {
        handler_for("vid", video.id.to_s, "with", "game", "#{game.id},#{game2.id}").call
      }.to change(VideoGameLink, :count).by(2)
    end

    it "summarises a multi-link listing each target title" do
      payload = handler_for("game", game.id.to_s, "with", "vid", "#{video.id},#{video2.id}").call.events.first[:payload]
      text = payload[:text] || payload["text"]
      expect(text).to include(video.title).and(include(video2.title))
    end

    it "reports a not-found id and links nothing" do
      payload = nil
      expect {
        payload = handler_for("game", game.id.to_s, "with", "vid", "#{video.id},999999").call.events.first[:payload]
      }.not_to change(VideoGameLink, :count)
      expect(payload[:text] || payload["text"]).to include("999999")
    end
  end

  describe "the `with` connector (alias for `to`)" do
    it "links in free chat: `link game <id> with video <id>`" do
      expect {
        handler_for("game", game.id.to_s, "with", "video", video.id.to_s).call
      }.to change(VideoGameLink, :count).by(1)
    end

    it "links in a list reply: `#<h> link <src-id> with <tgt-id>`" do
      payload = { "reply_target" => "video_list", "video_ids" => [ video.id ] }
      expect {
        follow_up_handler(payload: payload, rest: "#{video.id} with #{game.id}").call
      }.to change(VideoGameLink, :count).by(1)
    end
  end

  it "returns Ok with a witty success message" do
    result = handler_for("game", game.id.to_s, "to", "video", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    text = result.events.first[:payload]["text"]
    expect(text).to include("Lies of P")
    expect(text).to include("Lies of P Review")
  end

  it "is idempotent — linking an existing link does not raise" do
    create(:video_game_link, video: video, game: game)
    expect {
      handler_for("game", game.id.to_s, "to", "video", video.id.to_s).call
    }.not_to change(VideoGameLink, :count)
  end

  describe "relink (canonical 1×1 form, vid already linked to a DIFFERENT game)" do
    let!(:old_game) { create(:game, title: "Bloodborne") }

    before { create(:video_game_link, video: video, game: old_game) }

    it "replaces the old link instead of stacking a second one" do
      expect {
        handler_for("game", game.id.to_s, "to", "video", video.id.to_s).call
      }.not_to change(VideoGameLink, :count)

      expect(VideoGameLink.find_by(video: video, game: old_game)).to be_nil
      expect(VideoGameLink.find_by(video: video, game: game)).to be_present
    end

    it "destroys the prior link and creates the new one (video/game order)" do
      expect {
        handler_for("video", video.id.to_s, "to", "game", game.id.to_s).call
      }.not_to change(VideoGameLink, :count)

      expect(video.reload.linked_games).to contain_exactly(game)
    end

    it "returns Ok with honest copy naming both the old and new game" do
      result = handler_for("game", game.id.to_s, "to", "video", video.id.to_s).call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      text = result.events.first[:payload]["text"]
      expect(text).to include("Bloodborne")
      expect(text).to include("Lies of P")
      expect(text).to include(video.title)
    end

    it "does not use the plain 'linked' copy for a relink" do
      result = handler_for("game", game.id.to_s, "to", "video", video.id.to_s).call
      text = result.events.first[:payload]["text"]
      expect(text).to eq(Pito::Copy.render("pito.copy.games.relinked",
                                            video: video.title, old_game: old_game.title, new_game: game.title,
                                            variant: 0))
    end
  end

  describe "relinking to the SAME game the vid already has (still idempotent, plain copy)" do
    before { create(:video_game_link, video: video, game: game) }

    it "does not change the link count" do
      expect {
        handler_for("game", game.id.to_s, "to", "video", video.id.to_s).call
      }.not_to change(VideoGameLink, :count)
    end

    it "keeps the plain 'linked' ack, not the relink copy" do
      result = handler_for("game", game.id.to_s, "to", "video", video.id.to_s).call
      text = result.events.first[:payload]["text"]
      expect(text).to include("Lies of P")
      expect(text).to include(video.title)
    end
  end

  it "returns a not-found result for an unknown game id" do
    result = handler_for("game", "99999", "to", "video", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to include("99999")
  end

  it "returns a not-found result for an unknown video id" do
    result = handler_for("game", game.id.to_s, "to", "video", "99999").call
    expect(result).to be_a(Pito::Chat::Result::Ok)
    expect(result.events.first[:payload]["text"]).to include("99999")
  end

  it "returns a usage hint when a title ref is given instead of an id" do
    result = handler_for("game", "lies", "of", "p", "to", "video", "lies", "of", "p", "review").call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.link.usage")
  end

  it "returns a usage hint when no 'to' separator is given" do
    result = handler_for("game", game.id.to_s, "video", video.id.to_s).call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.link.usage")
  end

  it "returns a usage hint when body is empty" do
    result = handler_for.call
    expect(result).to be_a(Pito::Chat::Result::Error)
    expect(result.message_key).to eq("pito.chat.link.usage")
  end

  it "accepts #N id form for game" do
    expect {
      handler_for("game", "##{game.id}", "to", "video", video.id.to_s).call
    }.to change(VideoGameLink, :count).by(1)
  end

  it "accepts #N id form for video" do
    expect {
      handler_for("game", game.id.to_s, "to", "video", "##{video.id}").call
    }.to change(VideoGameLink, :count).by(1)
  end

  # ── Follow-up branch ─────────────────────────────────────────────────────────

  describe "follow-up from a game_detail card" do
    let(:game_detail_payload) do
      { "reply_target" => "game_detail", "game_id" => game.id }
    end

    it "links game to video by id ref (with leading 'to video')" do
      handler = follow_up_handler(payload: game_detail_payload, rest: "to video ##{video.id}")
      expect { handler.call }.to change(VideoGameLink, :count).by(1)
    end

    it "links game to video without leading noun words" do
      handler = follow_up_handler(payload: game_detail_payload, rest: "##{video.id}")
      expect { handler.call }.to change(VideoGameLink, :count).by(1)
    end

    it "returns a usage hint when a title ref is given instead of an id" do
      handler = follow_up_handler(payload: game_detail_payload, rest: "to video lies of p review")
      result = handler.call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.link.follow_up_usage.detail")
    end

    it "returns Ok with the linked ack" do
      result = follow_up_handler(payload: game_detail_payload, rest: "to video ##{video.id}").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      text = result.events.first[:payload]["text"]
      expect(text).to include("Lies of P")
      expect(text).to include("Lies of P Review")
    end

    it "is idempotent" do
      create(:video_game_link, video: video, game: game)
      expect {
        follow_up_handler(payload: game_detail_payload, rest: "to video ##{video.id}").call
      }.not_to change(VideoGameLink, :count)
    end

    it "returns not-found when the video id is unknown" do
      result = follow_up_handler(payload: game_detail_payload, rest: "to video 99999").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to include("99999")
    end

    it "returns a usage hint when the ref is blank" do
      result = follow_up_handler(payload: game_detail_payload, rest: "to video").call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.link.follow_up_usage.detail")
    end
  end

  describe "follow-up from a video_detail card" do
    let(:video_detail_payload) do
      { "reply_target" => "video_detail", "video_id" => video.id }
    end

    it "links video to game by id ref (with leading 'to game')" do
      handler = follow_up_handler(payload: video_detail_payload, rest: "to game ##{game.id}")
      expect { handler.call }.to change(VideoGameLink, :count).by(1)
    end

    it "links video to game without leading noun words" do
      handler = follow_up_handler(payload: video_detail_payload, rest: "##{game.id}")
      expect { handler.call }.to change(VideoGameLink, :count).by(1)
    end

    it "returns a usage hint when a title ref is given instead of an id" do
      handler = follow_up_handler(payload: video_detail_payload, rest: "to game lies of p")
      result = handler.call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.link.follow_up_usage.detail")
    end

    it "returns Ok with the linked ack" do
      result = follow_up_handler(payload: video_detail_payload, rest: "to game ##{game.id}").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      text = result.events.first[:payload]["text"]
      expect(text).to include("Lies of P")
      expect(text).to include("Lies of P Review")
    end

    it "returns not-found when the game id is unknown" do
      result = follow_up_handler(payload: video_detail_payload, rest: "to game 99999").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to include("99999")
    end

    it "returns a usage hint when the ref is blank" do
      result = follow_up_handler(payload: video_detail_payload, rest: "to game").call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.link.follow_up_usage.detail")
    end

    # Case 4 — detail source + multi-target
    it "links this video to multiple games when targets are comma-separated" do
      g2 = create(:game, title: "Bloodborne")
      expect {
        follow_up_handler(payload: video_detail_payload, rest: "to #{game.id},#{g2.id}").call
      }.to change(VideoGameLink, :count).by(2)
    end

    it "returns Ok whose summary names all linked games for multi-target" do
      g2 = create(:game, title: "Bloodborne")
      result = follow_up_handler(payload: video_detail_payload, rest: "to #{game.id},#{g2.id}").call
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
    it "creates one VideoGameLink given a source video id and a single target game id" do
      handler = follow_up_handler(payload: video_list_payload, rest: "#{video.id} to #{game.id}")
      expect { handler.call }.to change(VideoGameLink, :count).by(1)
    end

    it "returns Ok whose text includes the target game title (single target)" do
      result = follow_up_handler(payload: video_list_payload, rest: "#{video.id} to #{game.id}").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["text"]).to include("Lies of P")
    end

    # Case 2 — list source, multi-target (comma-separated)
    it "creates one link per target for comma-separated game ids" do
      g2 = create(:game, title: "Bloodborne")
      g3 = create(:game, title: "Elden Ring")
      expect {
        follow_up_handler(payload: video_list_payload,
                          rest: "#{video.id} to #{game.id},#{g2.id},#{g3.id}").call
      }.to change(VideoGameLink, :count).by(3)
    end

    it "summary text names all three linked games" do
      g2 = create(:game, title: "Bloodborne")
      g3 = create(:game, title: "Elden Ring")
      result = follow_up_handler(payload: video_list_payload,
                                 rest: "#{video.id} to #{game.id},#{g2.id},#{g3.id}").call
      text = result.events.first[:payload]["text"]
      expect(text).to include("Lies of P")
      expect(text).to include("Bloodborne")
      expect(text).to include("Elden Ring")
    end

    it "creates all links when targets are space-separated instead of comma-separated" do
      g2 = create(:game, title: "Bloodborne")
      expect {
        follow_up_handler(payload: video_list_payload,
                          rest: "#{video.id} to #{game.id} #{g2.id}").call
      }.to change(VideoGameLink, :count).by(2)
    end

    it "is idempotent — re-linking an existing pair does not raise or add a duplicate" do
      create(:video_game_link, video: video, game: game)
      expect {
        follow_up_handler(payload: video_list_payload, rest: "#{video.id} to #{game.id}").call
      }.not_to change(VideoGameLink, :count)
    end

    # Case 3 — not-found target reported
    it "still links valid targets when one target id does not exist" do
      result = follow_up_handler(payload: video_list_payload,
                                 rest: "#{video.id} to #{game.id},99999").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(VideoGameLink.count).to eq(1)
    end

    it "appends a '(not found: ...)' note to the summary for missing target ids" do
      result = follow_up_handler(payload: video_list_payload,
                                 rest: "#{video.id} to #{game.id},99999").call
      text = result.events.first[:payload]["text"]
      expect(text).to include("Lies of P")
      expect(text).to include("(not found: 99999)")
    end

    # Case 5 — list source, missing 'to' connector
    it "returns a usage error when the 'to' connector is absent" do
      result = follow_up_handler(payload: video_list_payload, rest: video.id.to_s).call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.link.follow_up_usage.list")
    end
  end

  # ── Follow-up from a single-row list/search card (implied source) ─────────────

  describe "follow-up from a single-row list/search card (implied source)" do
    let(:other_video) { create(:video, title: "Lies of P Boss Guide") }

    it "links the single displayed game to multiple vids when no source id is typed" do
      payload = { "reply_target" => "game_list", "game_ids" => [ game.id ] }
      expect {
        follow_up_handler(payload: payload, rest: "to ##{video.id},#{other_video.id}").call
      }.to change(VideoGameLink, :count).by(2)
      expect(game.reload.linked_videos).to include(video, other_video)
    end

    it "still returns the usage error when the card shows more than one row" do
      g2 = create(:game, title: "Bloodborne")
      payload = { "reply_target" => "game_list", "game_ids" => [ game.id, g2.id ] }
      result = follow_up_handler(payload: payload, rest: "to #{video.id}").call
      expect(result).to be_a(Pito::Chat::Result::Error)
    end

    it "prefers a typed source id over the card's single implied row" do
      other_game = create(:game, title: "Bloodborne")
      payload = { "reply_target" => "game_list", "game_ids" => [ game.id ] }
      expect {
        follow_up_handler(payload: payload, rest: "#{other_game.id} to #{video.id}").call
      }.to change(VideoGameLink, :count).by(1)
      expect(VideoGameLink.find_by(video: video, game: other_game)).not_to be_nil
      expect(VideoGameLink.find_by(video: video, game: game)).to be_nil
    end

    it "links the other way around from a single-row video_search card" do
      payload = { "reply_target" => "video_search", "video_ids" => [ video.id ] }
      expect {
        follow_up_handler(payload: payload, rest: "to #{game.id}").call
      }.to change(VideoGameLink, :count).by(1)
      expect(video.reload.linked_games).to include(game)
    end
  end
end
