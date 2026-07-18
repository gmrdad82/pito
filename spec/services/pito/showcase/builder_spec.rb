# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Showcase::Builder do
  let(:conversation) { create(:conversation) }

  def call = described_class.call(conversation:)

  # Helper: create a completed turn and attach event payloads to it.
  def make_turn(payloads)
    turn = create(:turn, conversation:, input_kind: :chat, input_text: "show game #1",
                  completed_at: Time.current)
    payloads.each_with_index do |payload, idx|
      Event.create_with_position!(
        conversation:, turn:, kind: :system,
        payload: payload.stringify_keys
      )
    end
    turn
  end

  # ── Seed set ────────────────────────────────────────────────────────────────

  describe "seed set (no completed turns)" do
    it "returns an array of strings" do
      expect(call).to all(be_a(String))
    end

    it "includes list channels, list games, list vids" do
      result = call
      expect(result).to include("list channels", "list games", "list vids")
    end

    it "includes show last vid and list games upcoming" do
      result = call
      expect(result).to include("show last vid", "list games upcoming")
    end

    it "returns at most 15 suggestions" do
      expect(call.size).to be <= 15
    end

    it "includes sync channels when channels exist" do
      create(:channel)
      expect(call).to include("sync channels")
    end

    it "does not include sync channels when no channels exist" do
      expect(call).not_to include("sync channels")
    end
  end

  # ── Game list context ────────────────────────────────────────────────────────

  describe "after list games (game_ids payload)" do
    let!(:games) { create_list(:game, 4) }

    before do
      make_turn([
        { "game_ids" => games.map(&:id), "reply_target" => "game_list", "html" => true, "body" => "x" }
      ])
    end

    it "includes show game #<id> for up to 3 game ids" do
      result = call
      games.first(3).each do |g|
        expect(result).to include("show game ##{g.id}")
      end
    end

    it "does not include show game #<id> for the 4th game" do
      result = call
      expect(result).not_to include("show game ##{games[3].id}")
    end

    it "also includes navigation commands" do
      result = call
      expect(result).to include("list games upcoming", "list vids")
    end
  end

  # ── Game detail context ──────────────────────────────────────────────────────

  describe "after show game #<id> (game_detail payload)" do
    let!(:game) { create(:game) }

    before do
      make_turn([
        { "game_id" => game.id, "reply_target" => "game_detail", "html" => true, "body" => "x" }
      ])
    end

    it "includes footage update for the game id" do
      result = call
      expect(result).to include("update game footage ##{game.id} 2")
    end

    it "includes analyze games for the game id" do
      result = call
      expect(result).to include("analyze games ##{game.id}")
    end

    it "includes link suggestion when a video exists" do
      video = create(:video)
      result = call
      expect(result).to include("link vid ##{video.id} to game ##{game.id}")
    end

    it "includes navigation commands" do
      result = call
      expect(result).to include("list games", "list vids")
    end

    it "returns at most 15 suggestions" do
      expect(call.size).to be <= 15
    end
  end

  # ── Video list context ───────────────────────────────────────────────────────

  describe "after list vids (video_list payload)" do
    let!(:videos) { create_list(:video, 4) }

    before do
      make_turn([
        { "video_ids" => videos.map(&:id), "reply_target" => "video_list", "html" => true, "body" => "x" }
      ])
    end

    it "includes show vid #<id> for up to 3 video ids" do
      result = call
      videos.first(3).each do |v|
        expect(result).to include("show vid ##{v.id}")
      end
    end

    it "does not include show vid #<id> for the 4th video" do
      result = call
      expect(result).not_to include("show vid ##{videos[3].id}")
    end

    it "includes list games and list channels" do
      result = call
      expect(result).to include("list games", "list channels")
    end
  end

  # ── Video detail context ─────────────────────────────────────────────────────

  describe "after show vid #<id> (video_detail payload)" do
    let!(:video) { create(:video) }

    before do
      make_turn([
        { "video_id" => video.id, "reply_target" => "video_detail", "html" => true, "body" => "x" }
      ])
    end

    it "includes analyze vids for the video id" do
      result = call
      expect(result).to include("analyze vids ##{video.id}")
    end

    it "includes link suggestion when a game exists" do
      game = create(:game)
      result = call
      expect(result).to include("link vid ##{video.id} to game ##{game.id}")
    end

    it "includes navigation commands" do
      result = call
      expect(result).to include("list games", "list vids")
    end
  end

  # ── Channel list context ─────────────────────────────────────────────────────

  describe "after list channels (channel_list payload)" do
    before do
      make_turn([
        { "reply_target" => "channel_list", "html" => true, "body" => "x" }
      ])
    end

    it "includes list vids and list games" do
      result = call
      expect(result).to include("list vids", "list games")
    end

    it "includes show channel @handle for connected channels" do
      ch = create(:channel)
      result = call
      expect(result).to include("show channel #{ch.at_handle}")
    end
  end

  # ── Channel detail context ───────────────────────────────────────────────────

  describe "after show channel @handle (channel_detail payload)" do
    let!(:channel) { create(:channel) }

    before do
      make_turn([
        { "channel_id" => channel.id, "reply_target" => "channel_detail", "html" => true, "body" => "x" }
      ])
    end

    it "includes sync for the channel" do
      result = call
      expect(result).to include("sync #{channel.at_handle}")
    end

    it "includes analyze channel for the channel" do
      result = call
      expect(result).to include("analyze channel #{channel.at_handle}")
    end

    it "includes navigation commands" do
      result = call
      expect(result).to include("list vids", "list games")
    end
  end

  # ── Uniqueness + size invariants ─────────────────────────────────────────────

  describe "output invariants" do
    it "never returns duplicate commands" do
      create(:game)
      make_turn([
        { "game_ids" => ::Game.all.map(&:id), "reply_target" => "game_list", "html" => true, "body" => "x" }
      ])
      result = call
      expect(result.uniq).to eq(result)
    end

    it "always returns at most 15 suggestions" do
      games = create_list(:game, 10)
      make_turn([
        { "game_ids" => games.map(&:id), "reply_target" => "game_list", "html" => true, "body" => "x" }
      ])
      expect(call.size).to be <= 15
    end
  end

  # ── Persistence (turn.suggestions) ──────────────────────────────────────────

  describe "turn.suggestions column" do
    it "defaults to [] on a new turn" do
      turn = create(:turn, conversation:)
      expect(turn.suggestions).to eq([])
    end

    it "can be persisted and reloaded as an array of strings" do
      turn = create(:turn, conversation:)
      cmds = [ "list games", "show game #1" ]
      turn.update!(suggestions: cmds)
      expect(turn.reload.suggestions).to eq(cmds)
    end
  end
end
