# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::GameDetail, type: :service do
  subject(:handler) { described_class.new }

  let(:conversation) { create(:conversation) }
  let!(:game) { create(:game, title: "Lies of P") }
  let(:turn)  do
    conversation.turns.create!(
      input_kind: :hashtag, input_text: "#test-1234 rm", position: 1
    )
  end

  # Build a stub detail-event with game_id stamped (as DetailMessage now does).
  def build_detail_event(payload_overrides = {})
    base_payload = {
      "body"         => "<div>card html</div>",
      "html"         => true,
      "game_id"      => game.id,
      "reply_handle" => "detail-1234",
      "reply_target" => "game_detail"
    }.merge(payload_overrides)
    Event.create_with_position!(
      conversation:, turn:, kind: :system, payload: base_payload
    )
  end

  it "registers for the game_detail target in :append mode" do
    expect(described_class.target).to eq("game_detail")
    expect(described_class.mode).to eq(:append)
  end

  # ── rm / delete ─────────────────────────────────────────────────────────────

  describe "#call — rm" do
    let(:source_event) { build_detail_event }

    subject(:result) { handler.call(event: source_event, rest: "rm", conversation:) }

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "appends a confirmation event" do
      expect(result.events.first[:kind].to_s).to eq("confirmation")
    end

    it "uses the game_delete command" do
      expect(result.events.first[:payload]["command"]).to eq("game_delete")
    end

    it "carries game_id and game_title" do
      payload = result.events.first[:payload]
      expect(payload["game_id"]).to eq(game.id)
      expect(payload["game_title"]).to eq("Lies of P")
    end

    it "stamps the confirmation as followupable (confirmation target)" do
      payload = result.events.first[:payload]
      expect(payload["reply_target"]).to eq("confirmation")
    end
  end

  describe "#call — delete (alias for rm)" do
    let(:source_event) { build_detail_event }

    it "also emits a game_delete confirmation" do
      result = handler.call(event: source_event, rest: "delete", conversation:)
      expect(result.events.first[:payload]["command"]).to eq("game_delete")
    end
  end

  describe "#call — rm when game is missing/deleted" do
    let(:source_event) { build_detail_event("game_id" => 0) }

    it "returns a Result::Append with a not-found message (delegated path)" do
      result = handler.call(event: source_event, rest: "rm", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "does not raise" do
      expect { handler.call(event: source_event, rest: "rm", conversation:) }.not_to raise_error
    end
  end

  # ── resync ───────────────────────────────────────────────────────────────────

  describe "#call — resync" do
    let(:source_event) { build_detail_event }

    subject(:result) { handler.call(event: source_event, rest: "resync", conversation:) }

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "appends a confirmation with command game_resync" do
      expect(result.events.first[:payload]["command"]).to eq("game_resync")
    end

    it "carries game_id and game_title" do
      payload = result.events.first[:payload]
      expect(payload["game_id"]).to eq(game.id)
      expect(payload["game_title"]).to eq("Lies of P")
    end
  end

  describe "#call — resync when game is missing/deleted" do
    let(:source_event) { build_detail_event("game_id" => 0) }

    it "returns a Result::Error (not-found)" do
      result = handler.call(event: source_event, rest: "resync", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end

    it "does not raise" do
      expect { handler.call(event: source_event, rest: "resync", conversation:) }.not_to raise_error
    end
  end

  # ── link to video (delegated to Chat::Handlers::Link) ───────────────────────

  describe "#call — link to video" do
    let(:source_event)  { build_detail_event }
    let(:connection)    { create(:youtube_connection) }
    let(:channel)       { create(:channel, youtube_connection: connection) }
    let!(:video)        { create(:video, channel: channel, title: "Let's Play Lies of P") }

    context "with a valid video id" do
      subject(:result) do
        handler.call(event: source_event, rest: "link to video ##{video.id}", conversation:)
      end

      it "returns a Result::Append" do
        expect(result).to be_a(Pito::FollowUp::Result::Append)
      end

      it "creates a VideoGameLink" do
        expect { result }.to change(VideoGameLink, :count).by(1)
      end

      it "is idempotent (no duplicate link on repeat)" do
        handler.call(event: source_event, rest: "link to video ##{video.id}", conversation:)
        expect { handler.call(event: source_event, rest: "link to video ##{video.id}", conversation:) }
          .not_to change(VideoGameLink, :count)
      end

      it "appends a witty ack text" do
        text = result.events.first[:payload]["text"]
        expect(text).to be_present
      end
    end

    context "with a video title reference" do
      it "resolves by ILIKE title" do
        result = handler.call(event: source_event, rest: "link to video let's play lies of p", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Append)
        expect(VideoGameLink.where(video:, game:).exists?).to be true
      end
    end

    context "with an unknown video" do
      it "returns a not-found append with witty text" do
        result = handler.call(event: source_event, rest: "link to video 99999", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Append)
        text = result.events.first[:payload]["text"]
        expect(text).to be_present
      end
    end

    context "with missing video ref" do
      it "returns a Result::Error (usage hint from Link handler)" do
        result = handler.call(event: source_event, rest: "link to video", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Error)
        expect(result.message_key).to eq("pito.chat.link.usage")
      end
    end
  end

  # ── unknown action ───────────────────────────────────────────────────────────

  describe "#call — import <path>" do
    let(:source_event) { build_detail_event }

    subject(:result) { handler.call(event: source_event, rest: "import /mnt/clips", conversation:) }

    it "returns a Result::Append with a system event" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "emits the copyable probe command for the segment's game and path" do
      body = result.events.first[:payload]["body"]
      expect(body).to include("pito:tools:probe game=#{game.id}")
      expect(body).to include("path=&quot;/mnt/clips/*&quot;")
    end

    it "keeps a multi-word folder path whole" do
      result = handler.call(event: source_event, rest: "import /mnt/Ghosts n Goblins", conversation:)
      expect(result.events.first[:payload]["body"]).to include("path=&quot;/mnt/Ghosts n Goblins/*&quot;")
    end

    it "errors with missing_path when no path is given" do
      result = handler.call(event: source_event, rest: "import", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.game_detail.errors.missing_path")
    end

    it "errors when the segment's game no longer exists" do
      event = build_detail_event("game_id" => game.id)
      game.destroy
      result = handler.call(event: event, rest: "import /mnt/clips", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end
  end

  describe "#call — unknown action" do
    let(:source_event) { build_detail_event }

    it "returns a Result::Error" do
      result = handler.call(event: source_event, rest: "frobnicate", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.game_detail.errors.invalid_action")
    end
  end

  # ── registry ─────────────────────────────────────────────────────────────────

  describe "registry" do
    before { Pito::FollowUp::Registry.register(described_class) }

    it "is registered under 'game_detail'" do
      expect(Pito::FollowUp::Registry.for("game_detail")).to eq(described_class)
    end

    it "has mode :append" do
      expect(Pito::FollowUp::Registry.mode_for("game_detail")).to eq(:append)
    end
  end
end
