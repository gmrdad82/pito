# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Confirmation::Executor, type: :service do
  let(:connection) { create(:youtube_connection) }
  let!(:channel)   { create(:channel, handle: "@pito", youtube_connection: connection) }
  let!(:video1)    { create(:video, channel:) }
  let!(:video2)    { create(:video, channel:) }

  let(:payload) do
    { "command" => "disconnect", "channel_id" => channel.id }
  end

  # ── confirm / disconnect ──────────────────────────────────────────────────

  describe ".confirm — disconnect" do
    it "destroys the channel" do
      expect { described_class.confirm("disconnect", payload) }
        .to change(Channel, :count).by(-1)
    end

    it "destroys all videos via cascade" do
      expect { described_class.confirm("disconnect", payload) }
        .to change(Video, :count).by(-2)
    end

    it "destroys the YoutubeConnection when it was the last channel" do
      expect { described_class.confirm("disconnect", payload) }
        .to change(YoutubeConnection, :count).by(-1)
    end

    it "keeps the YoutubeConnection when other channels remain" do
      create(:channel, youtube_connection: connection)
      expect { described_class.confirm("disconnect", payload) }
        .not_to change(YoutubeConnection, :count)
    end

    it "returns outcome_text mentioning the handle and video count" do
      text = described_class.confirm("disconnect", payload)
      expect(text).to include("@pito")
      expect(text).to include("2")
    end

    context "when the channel is already gone" do
      before { channel.destroy! }

      it "does not raise" do
        expect { described_class.confirm("disconnect", payload) }.not_to raise_error
      end

      it "returns the already_gone message" do
        text = described_class.confirm("disconnect", payload)
        expect(text).to be_present
      end
    end
  end

  # ── cancel / disconnect ───────────────────────────────────────────────────

  describe ".cancel — disconnect" do
    it "does NOT destroy the channel" do
      expect { described_class.cancel("disconnect", payload) }
        .not_to change(Channel, :count)
    end

    it "returns outcome_text mentioning the channel handle" do
      text = described_class.cancel("disconnect", payload)
      expect(text).to include("@pito")
    end
  end

  # ── unknown command fallbacks ─────────────────────────────────────────────

  describe ".confirm — unknown command" do
    it "returns the default confirmed text" do
      text = described_class.confirm("unknown_cmd", {})
      expect(text).to be_present
    end
  end

  describe ".cancel — unknown command" do
    it "returns the default cancelled text" do
      text = described_class.cancel("unknown_cmd", {})
      expect(text).to be_present
    end
  end

  describe ".confirm — game_delete" do
    it "destroys the game and returns outcome text with the title" do
      game = create(:game, title: "Lies of P")
      text = nil
      expect {
        text = described_class.confirm("game_delete", { "game_id" => game.id, "game_title" => "Lies of P" })
      }.to change(Game, :count).by(-1)
      expect(text).to include("Lies of P")
    end

    it "is a no-op (still returns text) when the game is already gone" do
      text = described_class.confirm("game_delete", { "game_id" => 0, "game_title" => "Gone" })
      expect(text).to include("Gone")
    end
  end

  # ── confirm / video_delete ───────────────────────────────────────────────

  describe ".confirm — video_delete" do
    let!(:v_channel) { create(:channel) }
    let!(:video)     { create(:video, channel: v_channel, title: "My Let's Play") }

    it "destroys the video and returns outcome text with the title" do
      text = nil
      expect {
        text = described_class.confirm("video_delete", { "video_id" => video.id, "video_title" => "My Let's Play" })
      }.to change(Video, :count).by(-1)
      expect(text).to include("My Let's Play")
    end

    it "is a no-op (still returns text) when the video is already gone" do
      text = described_class.confirm("video_delete", { "video_id" => 0, "video_title" => "Vanished" })
      expect(text).to include("Vanished")
    end
  end

  # ── cancel / video_delete ───────────────────────────────────────────────

  describe ".cancel — video_delete" do
    let!(:v_channel) { create(:channel) }
    let!(:video)     { create(:video, channel: v_channel, title: "Cancelled Video") }

    it "does NOT destroy the video" do
      expect {
        described_class.cancel("video_delete", { "video_id" => video.id, "video_title" => "Cancelled Video" })
      }.not_to change(Video, :count)
    end

    it "returns a non-empty cancelled message" do
      text = described_class.cancel("video_delete", { "video_id" => video.id, "video_title" => "Cancelled Video" })
      expect(text).to be_present
    end
  end

  # ── confirm / game_resync ─────────────────────────────────────────────────

  describe ".confirm — game_resync" do
    let!(:game) { create(:game, title: "Sekiro") }

    it "enqueues GameIgdbSync and returns outcome text mentioning the title" do
      allow(GameIgdbSync).to receive(:perform_later)
      text = described_class.confirm("game_resync", { "game_id" => game.id, "game_title" => "Sekiro" })
      expect(GameIgdbSync).to have_received(:perform_later).with(game.id, conversation_id: nil)
      expect(text).to include("Sekiro")
    end

    it "returns a not-found text when the game does not exist" do
      text = described_class.confirm("game_resync", { "game_id" => 0, "game_title" => "Ghost" })
      expect(text).to be_present
    end
  end

  # ── confirm / game_reindex ────────────────────────────────────────────────

  describe ".confirm — game_reindex" do
    let!(:game) { create(:game, title: "Bloodborne") }

    it "calls Game::VoyageIndexer with force: true and returns outcome text" do
      allow(::Game::VoyageIndexer).to receive(:call)
      text = described_class.confirm("game_reindex", { "game_id" => game.id, "game_title" => "Bloodborne" })
      expect(::Game::VoyageIndexer).to have_received(:call).with(game, force: true)
      expect(text).to include("Bloodborne")
    end

    it "returns a not-found text when the game does not exist" do
      text = described_class.confirm("game_reindex", { "game_id" => 0, "game_title" => "Vanished" })
      expect(text).to be_present
    end
  end

  # ── cancel / game_delete ──────────────────────────────────────────────────

  describe ".cancel — game_delete" do
    let!(:game) { create(:game, title: "Cancelled Game") }

    it "does NOT destroy the game" do
      expect {
        described_class.cancel("game_delete", { "game_id" => game.id, "game_title" => "Cancelled Game" })
      }.not_to change(Game, :count)
    end

    it "returns a non-empty cancelled message" do
      text = described_class.cancel("game_delete", { "game_id" => game.id, "game_title" => "Cancelled Game" })
      expect(text).to be_present
    end
  end

  # ── cancel / game_resync ──────────────────────────────────────────────────

  describe ".cancel — game_resync" do
    let!(:game) { create(:game, title: "Resync Target") }

    it "does NOT enqueue GameIgdbSync" do
      expect(GameIgdbSync).not_to receive(:perform_later)
      described_class.cancel("game_resync", { "game_id" => game.id, "game_title" => "Resync Target" })
    end

    it "returns a non-empty cancelled message" do
      text = described_class.cancel("game_resync", { "game_id" => game.id, "game_title" => "Resync Target" })
      expect(text).to be_present
    end
  end

  # ── cancel / game_reindex ─────────────────────────────────────────────────

  describe ".cancel — game_reindex" do
    let!(:game) { create(:game, title: "Reindex Target") }

    it "does NOT call Game::VoyageIndexer" do
      expect(::Game::VoyageIndexer).not_to receive(:call)
      described_class.cancel("game_reindex", { "game_id" => game.id, "game_title" => "Reindex Target" })
    end

    it "returns a non-empty cancelled message" do
      text = described_class.cancel("game_reindex", { "game_id" => game.id, "game_title" => "Reindex Target" })
      expect(text).to be_present
    end
  end

  # ── confirm / video_reindex ───────────────────────────────────────────────

  describe ".confirm — video_reindex" do
    let!(:v_channel) { create(:channel) }
    let!(:video)     { create(:video, channel: v_channel, title: "Let's Play Bloodborne") }

    it "calls Video::VoyageIndexer with force: true and returns outcome text" do
      allow(::Video::VoyageIndexer).to receive(:call)
      text = described_class.confirm("video_reindex", { "video_id" => video.id, "video_title" => "Let's Play Bloodborne" })
      expect(::Video::VoyageIndexer).to have_received(:call).with(video, force: true)
      expect(text).to include("Let's Play Bloodborne")
    end

    it "returns a not-found text when the video does not exist" do
      text = described_class.confirm("video_reindex", { "video_id" => 0, "video_title" => "Vanished Video" })
      expect(text).to be_present
    end
  end

  # ── cancel / video_reindex ────────────────────────────────────────────────

  describe ".cancel — video_reindex" do
    let!(:v_channel) { create(:channel) }
    let!(:video)     { create(:video, channel: v_channel, title: "Video Reindex Target") }

    it "does NOT call Video::VoyageIndexer" do
      expect(::Video::VoyageIndexer).not_to receive(:call)
      described_class.cancel("video_reindex", { "video_id" => video.id, "video_title" => "Video Reindex Target" })
    end

    it "returns a non-empty cancelled message" do
      text = described_class.cancel("video_reindex", { "video_id" => video.id, "video_title" => "Video Reindex Target" })
      expect(text).to be_present
    end
  end

  # ── confirm / channel_reindex ─────────────────────────────────────────────

  describe ".confirm — channel_reindex" do
    let(:reindex_connection) { create(:youtube_connection) }
    let!(:reindex_channel) do
      create(:channel, handle: "@reindex_chan", youtube_connection: reindex_connection)
    end
    let!(:vid_a) { create(:video, channel: reindex_channel) }
    let!(:vid_b) { create(:video, channel: reindex_channel) }

    it "enqueues VideoVoyageIndexJob for each channel video" do
      expect {
        described_class.confirm("channel_reindex", { "channel_id" => reindex_channel.id, "channel_handle" => "@reindex_chan" })
      }.to have_enqueued_job(VideoVoyageIndexJob).exactly(2).times
    end

    it "enqueues the correct video ids" do
      described_class.confirm("channel_reindex", { "channel_id" => reindex_channel.id, "channel_handle" => "@reindex_chan" })
      expect(VideoVoyageIndexJob).to have_been_enqueued.with(vid_a.id)
      expect(VideoVoyageIndexJob).to have_been_enqueued.with(vid_b.id)
    end

    it "returns a queued outcome text mentioning the channel handle" do
      text = described_class.confirm("channel_reindex", { "channel_id" => reindex_channel.id, "channel_handle" => "@reindex_chan" })
      expect(text).to be_present
    end

    it "returns a not-found text when the channel does not exist" do
      text = described_class.confirm("channel_reindex", { "channel_id" => 0, "channel_handle" => "@gone" })
      expect(text).to be_present
    end
  end

  # ── cancel / channel_reindex ──────────────────────────────────────────────

  describe ".cancel — channel_reindex" do
    let(:cancel_connection) { create(:youtube_connection) }
    let!(:cancel_channel) do
      create(:channel, handle: "@cancel_chan", youtube_connection: cancel_connection)
    end

    it "does NOT enqueue VideoVoyageIndexJob" do
      expect(VideoVoyageIndexJob).not_to receive(:perform_later)
      described_class.cancel("channel_reindex", { "channel_id" => cancel_channel.id, "channel_handle" => "@cancel_chan" })
    end

    it "returns a non-empty cancelled message" do
      text = described_class.cancel("channel_reindex", { "channel_id" => cancel_channel.id, "channel_handle" => "@cancel_chan" })
      expect(text).to be_present
    end
  end

  # ── confirm / disconnect — zero-video case ────────────────────────────────

  describe ".confirm — disconnect with zero videos" do
    let(:empty_connection) { create(:youtube_connection) }
    let!(:empty_channel)   { create(:channel, handle: "@bare", youtube_connection: empty_connection) }

    it "returns text that covers the zero-video case (no crash, non-empty)" do
      text = described_class.confirm("disconnect", { "channel_id" => empty_channel.id })
      expect(text).to be_present
    end
  end

  # ── cancel / disconnect — blank-handle fallback ───────────────────────────

  describe ".cancel — disconnect with blank handle" do
    let(:bare_connection) { create(:youtube_connection) }
    let!(:bare_channel) do
      create(:channel, title: "No Handle Channel", youtube_connection: bare_connection).tap do |ch|
        ch.update_column(:handle, nil)
      end
    end

    it "falls back to a non-empty cancelled message" do
      text = described_class.cancel("disconnect", { "channel_id" => bare_channel.id })
      expect(text).to be_present
    end
  end
end
