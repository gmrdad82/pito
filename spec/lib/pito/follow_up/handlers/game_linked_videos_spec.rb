# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::GameLinkedVideos do
  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }
  let!(:game)        { create(:game, title: "Lies of P") }
  let(:channel)      { create(:channel, handle: "@bossarena") }
  let!(:video)       { create(:video, :public, title: "Boss Fight", channel:) }
  let!(:vgl)         { create(:video_game_link, video:, game:) }

  # A game_linked_videos source event — carries both game_id (the game whose
  # linked videos are listed) and video_ids (list scope for further replies).
  let(:event) do
    instance_double(Event, kind: "enhanced", payload: {
      "reply_target" => "game_linked_videos",
      "game_id"      => game.id,
      "video_ids"    => [ video.id ],
      "list_columns" => [],
      "table_rows"   => [ { cells: [ { text: "##{video.id}" }, { text: video.title } ] } ]
    })
  end

  it "registers for the game_linked_videos target" do
    expect(described_class.target).to eq("game_linked_videos")
  end

  it "Matrix serves :append base mode for game_linked_videos" do
    expect(Pito::Dispatch::Matrix.mode_for("game_linked_videos")).to eq(:append)
  end

  it "Matrix advertises show, unlink, with, without, sort, order, analyze for game_linked_videos" do
    actions = Pito::Dispatch::Matrix.actions_for("game_linked_videos")
    expect(actions).to include("show", "unlink", "with", "without", "sort", "order", "analyze")
  end

  it "Matrix serves :mutate for with, without, sort, order on game_linked_videos" do
    %w[with without sort order].each do |a|
      expect(Pito::Dispatch::Matrix.mode_for("game_linked_videos", action: a)).to eq(:mutate)
    end
  end

  describe "`@ai <text>` — anchored reply (owner-scoped roster)" do
    let(:ai_event) { instance_double(Event, id: 4249, kind: "enhanced", payload: event.payload) }

    it "delegates to Chat::Handlers::Ai via ToolDelegator: a pending :ai event anchored on this list" do
      result = handler.call(event: ai_event, rest: "@ai which of these needs a better title", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to be(false)
      pending = result.events.first
      expect(pending[:kind]).to eq(:ai)
      expect(pending[:payload]["status"]).to eq("pending")
      expect(pending[:payload]["prompt"]).to eq("which of these needs a better title")
      expect(pending[:payload]["anchor_event_id"]).to eq(4249)
    end
  end

  # ── show ─────────────────────────────────────────────────────────────────────

  describe "#call — show <id>" do
    it "returns a Result::Append for a known video id" do
      result = handler.call(event:, rest: "show #{video.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "routes to the video branch: first event is :system video_detail" do
      result = handler.call(event:, rest: "show #{video.id}", conversation:)
      first  = result.events.first
      expect(first[:kind]).to eq(:system)
      expect(first[:payload]["reply_target"]).to eq("video_detail")
      expect(first[:payload]["video_id"]).to eq(video.id)
    end

    it "accepts a hash-prefixed id (#N)" do
      result = handler.call(event:, rest: "show ##{video.id}", conversation:)
      expect(result.events.first[:payload]["video_id"]).to eq(video.id)
    end

    it "dispatches as free-chat: NOT scoped to list rows (any video id resolves)" do
      other_channel = create(:channel)
      other_video   = create(:video, :public, title: "Other Vid", channel: other_channel)
      result = handler.call(event:, rest: "show #{other_video.id}", conversation:)
      expect(result.events.first[:payload]["video_id"]).to eq(other_video.id)
    end

    it "returns a not-found Ok (consume: false) for an unknown id" do
      result = handler.call(event:, rest: "show 999999", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to be(false)
    end

    # 3.0.1 reconciliation fix: this free-chat re-dispatch has no follow_up
    # context (so title resolution still runs), but a ref matching neither an
    # id nor a title must stay the crisp not-found (consume: false) — never
    # leak into the NL gate (mirrors GameSimilar's equivalent example).
    it "returns a not-found Ok (consume: false) for a ref matching no id and no title" do
      result = handler.call(event:, rest: "show no such video anywhere", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to be(false)
    end
  end

  # ── unlink ────────────────────────────────────────────────────────────────────

  describe "#call — unlink <vid_id>" do
    it "returns a Result::Append when the VideoGameLink exists" do
      result = handler.call(event:, rest: "unlink #{video.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "destroys the VideoGameLink (game context from payload, vid from rest)" do
      expect {
        handler.call(event:, rest: "unlink #{video.id}", conversation:)
      }.to change(VideoGameLink, :count).by(-1)
      expect(VideoGameLink.exists?(video:, game:)).to be(false)
    end

    it "accepts a hash-prefixed vid id" do
      expect {
        handler.call(event:, rest: "unlink ##{video.id}", conversation:)
      }.to change(VideoGameLink, :count).by(-1)
    end

    it "has consume: false — the card stays reusable for subsequent unlinks" do
      result = handler.call(event:, rest: "unlink #{video.id}", conversation:)
      expect(result.consume).to be(false)
    end

    it "returns a not-found-style Ok for an unknown video id" do
      result = handler.call(event:, rest: "unlink 999999", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end
  end

  # ── invalid action ────────────────────────────────────────────────────────────

  describe "#call — invalid action" do
    it "returns a Result::Error for an unrecognised action" do
      result = handler.call(event:, rest: "delete #{video.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.game_linked_videos.errors.invalid_action")
    end

    it "returns a Result::Error for an empty action" do
      result = handler.call(event:, rest: "", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end
  end
end
