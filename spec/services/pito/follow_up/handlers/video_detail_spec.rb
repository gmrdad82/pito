# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::VideoDetail, type: :service do
  subject(:handler) { described_class.new }

  let(:conversation) { create(:conversation) }
  let!(:channel)     { create(:channel) }
  let!(:video)       { create(:video, channel:, title: "Elden Ring Playthrough") }
  let(:turn) do
    conversation.turns.create!(
      input_kind: :hashtag, input_text: "#vid-1234 reindex", position: 1
    )
  end

  def build_video_detail_event(payload_overrides = {})
    base_payload = {
      "body"         => "<div>video detail</div>",
      "html"         => true,
      "video_id"     => video.id,
      "reply_handle" => "vid-1234",
      "reply_target" => "video_detail"
    }.merge(payload_overrides)
    Event.create_with_position!(
      conversation:, turn:, kind: :system, payload: base_payload
    )
  end

  it "registers for the video_detail target in :append mode" do
    expect(described_class.target).to eq("video_detail")
    expect(described_class.mode).to eq(:append)
  end

  it "declares rm, delete, reindex, link, and unlink actions" do
    expect(described_class.actions).to eq([ "rm", "delete", "reindex", "link", "unlink" ])
  end

  # ── reindex ───────────────────────────────────────────────────────────────────

  describe "#call — reindex" do
    let(:source_event) { build_video_detail_event }

    subject(:result) do
      handler.call(event: source_event, rest: "reindex", conversation:)
    end

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "appends a confirmation with command video_reindex" do
      expect(result.events.first[:payload]["command"]).to eq("video_reindex")
    end

    it "carries video_id and video_title" do
      payload = result.events.first[:payload]
      expect(payload["video_id"]).to eq(video.id)
      expect(payload["video_title"]).to eq("Elden Ring Playthrough")
    end

    it "stamps the confirmation as followupable" do
      expect(result.events.first[:payload]["reply_target"]).to eq("confirmation")
    end

    it "appends one event" do
      expect(result.events.length).to eq(1)
    end

    it "emits a confirmation kind event" do
      expect(result.events.first[:kind]).to eq(:confirmation)
    end
  end

  # ── video_not_found ───────────────────────────────────────────────────────────

  describe "#call — video_id missing from payload" do
    it "returns a Result::Error" do
      event  = build_video_detail_event("video_id" => nil)
      result = handler.call(event: event, rest: "reindex", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.video_detail.errors.video_not_found")
    end
  end

  describe "#call — video no longer in DB" do
    it "returns a Result::Error when video is deleted" do
      event = build_video_detail_event("video_id" => video.id)
      video.destroy!
      result = handler.call(event: event, rest: "reindex", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.video_detail.errors.video_not_found")
    end
  end

  # ── rm / delete ───────────────────────────────────────────────────────────────

  describe "#call — rm" do
    let(:source_event) { build_video_detail_event }

    subject(:result) { handler.call(event: source_event, rest: "rm", conversation:) }

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "appends a confirmation event" do
      expect(result.events.first[:kind].to_s).to eq("confirmation")
    end

    it "uses the video_delete command" do
      expect(result.events.first[:payload]["command"]).to eq("video_delete")
    end

    it "carries video_id and video_title" do
      payload = result.events.first[:payload]
      expect(payload["video_id"]).to eq(video.id)
      expect(payload["video_title"]).to eq("Elden Ring Playthrough")
    end
  end

  describe "#call — delete (alias for rm)" do
    let(:source_event) { build_video_detail_event }

    it "also emits a video_delete confirmation" do
      result = handler.call(event: source_event, rest: "delete", conversation:)
      expect(result.events.first[:payload]["command"]).to eq("video_delete")
    end
  end

  # ── link to game (delegated to Chat::Handlers::Link) ─────────────────────────

  describe "#call — link to game" do
    let(:source_event) { build_video_detail_event }
    let!(:game)        { create(:game, title: "Elden Ring") }

    subject(:result) do
      handler.call(event: source_event, rest: "link to game ##{game.id}", conversation:)
    end

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "creates a VideoGameLink" do
      expect { result }.to change(VideoGameLink, :count).by(1)
    end

    it "appends a witty ack text" do
      text = result.events.first[:payload]["text"]
      expect(text).to be_present
    end

    it "returns not-found when the game ref is unknown" do
      result = handler.call(event: source_event, rest: "link to game 99999", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.first[:payload]["text"]).to be_present
    end

    it "returns a usage hint when the ref is blank" do
      result = handler.call(event: source_event, rest: "link to game", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.chat.link.usage")
    end
  end

  # ── unlink from game (delegated to Chat::Handlers::Unlink) ──────────────────

  describe "#call — unlink from game" do
    let(:source_event) { build_video_detail_event }
    let!(:game)        { create(:game, title: "Elden Ring") }
    let!(:vgl)         { create(:video_game_link, video: video, game: game) }

    it "returns a Result::Append" do
      result = handler.call(event: source_event, rest: "unlink from game ##{game.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "destroys the VideoGameLink" do
      expect {
        handler.call(event: source_event, rest: "unlink from game ##{game.id}", conversation:)
      }.to change(VideoGameLink, :count).by(-1)
    end

    it "appends a witty unlinked ack text" do
      result = handler.call(event: source_event, rest: "unlink from game ##{game.id}", conversation:)
      text = result.events.first[:payload]["text"]
      expect(text).to be_present
    end
  end

  # ── unknown action ────────────────────────────────────────────────────────────

  describe "#call — unknown action" do
    let(:source_event) { build_video_detail_event }

    it "returns a Result::Error" do
      result = handler.call(event: source_event, rest: "bogus", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.video_detail.errors.invalid_action")
    end
  end

  # ── registry ──────────────────────────────────────────────────────────────────

  describe "registry" do
    before { Pito::FollowUp::Registry.register(described_class) }

    it "is registered under 'video_detail'" do
      expect(Pito::FollowUp::Registry.for("video_detail")).to eq(described_class)
    end

    it "has mode :append" do
      expect(Pito::FollowUp::Registry.mode_for("video_detail")).to eq(:append)
    end
  end
end
