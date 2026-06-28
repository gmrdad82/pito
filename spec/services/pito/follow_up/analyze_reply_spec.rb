# frozen_string_literal: true

require "rails_helper"

# AR — `analyze` as a follow-up REPLY on list + detail surfaces. Replying
# `#<handle> analyze` to a list analyzes the listed scope; to a detail card,
# that single entity. Each routes through Pito::FollowUp::AnalyzeReply, which
# mirrors the `analyze` chat verb (a :system + :enhanced pending pair).
RSpec.describe "analyze follow-up reply (AR)", type: :service do
  let(:conversation) { Conversation.singleton }
  let!(:channel)     { create(:channel, :on_connection) }
  let!(:video)       { create(:video, channel:) }
  let!(:video2)      { create(:video, channel:) }
  let!(:game)        { create(:game) }

  # The pair build never reaches YouTube here (the job is enqueued by the
  # Finalizer, not the handler) — stub Scaffold defensively like the glance spec.
  before do
    allow(Pito::Analytics::Scaffold).to receive(:for) do |role:, level:, **|
      Pito::Analytics::MetricOrder.for(role:, level:).index_with { true }
    end
  end

  def event_with(target:, kind:, payload:)
    turn = conversation.turns.create!(input_kind: :chat, input_text: "x", position: rand(1..10_000))
    Event.create_with_position!(
      conversation:, turn:, kind:,
      payload: payload.merge("reply_handle" => "h-0001", "reply_target" => target)
    )
  end

  describe Pito::FollowUp::AnalyzeReply do
    it "titles a single-entity scope by the entity's name/handle" do
      # vids/games have no @handle → their title; channels use @handle.
      expect(described_class.scope_title(:vid, [ video.id ])).to eq(video.title)
      expect(described_class.scope_title(:game, [ game.id ])).to eq(game.title)
      expect(described_class.scope_title(:channel, [ channel.id ])).to eq(channel.at_handle)
    end

    it "titles a multi-entity scope as 'N <plural>'" do
      expect(described_class.scope_title(:vid, [ 1, 2, 3 ])).to eq("3 vids")
      expect(described_class.scope_title(:channel, [ 1, 2 ])).to eq("2 channels")
    end

    it "titles an empty scope as 'your <plural>'" do
      expect(described_class.scope_title(:game, [])).to eq("your games")
    end

    it "appends a :system + :enhanced pending pair at the given level" do
      result = described_class.append(level: :vid, ids: [ video.id ], conversation:, period: "28d")
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.map { |e| e[:kind] }).to eq([ :system, :enhanced ])
      expect(result.events).to all(satisfy { |e| e[:payload].dig("analyze", "status") == "pending" })
      expect(result.events.first[:payload].dig("analyze", "level")).to eq("vid")
    end
  end

  shared_examples "an analyze reply" do |level:|
    it "returns a :system + :enhanced analyze pair at level #{level}" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.map { |e| e[:kind] }).to eq([ :system, :enhanced ])
      expect(result.events.first[:payload].dig("analyze", "level")).to eq(level.to_s)
    end

    it "scopes the analysis to the stamped entity ids" do
      expect(result.events.first[:payload].dig("analyze", "entity_ids")).to eq(expected_ids)
    end
  end

  describe "list surfaces" do
    describe "video_list → analyze the listed vids" do
      let(:expected_ids) { [ video.id, video2.id ] }
      let(:event)  { event_with(target: "video_list", kind: :system, payload: { "video_ids" => expected_ids }) }
      let(:result) { Pito::FollowUp::Handlers::VideoList.new.call(event:, rest: "analyze", conversation:, period: "28d") }

      it_behaves_like "an analyze reply", level: :vid
    end

    describe "game_list → analyze the listed games" do
      let(:expected_ids) { [ game.id ] }
      let(:event)  { event_with(target: "game_list", kind: :system, payload: { "game_ids" => expected_ids }) }
      let(:result) { Pito::FollowUp::Handlers::GameList.new.call(event:, rest: "analyze", conversation:, period: "28d") }

      it_behaves_like "an analyze reply", level: :game
    end

    describe "channel_list → analyze the listed channels" do
      let(:expected_ids) { [ channel.id ] }
      let(:event)  { event_with(target: "channel_list", kind: :system, payload: { "channel_ids" => expected_ids }) }
      let(:result) { Pito::FollowUp::Handlers::ChannelList.new.call(event:, rest: "analyze", conversation:, period: "28d") }

      it_behaves_like "an analyze reply", level: :channel
    end
  end

  describe "detail surfaces (single entity)" do
    describe "video_detail → analyze this vid" do
      let(:expected_ids) { [ video.id ] }
      let(:event)  { event_with(target: "video_detail", kind: :system, payload: { "video_id" => video.id }) }
      let(:result) { Pito::FollowUp::Handlers::VideoDetail.new.call(event:, rest: "analyze", conversation:, period: "28d") }

      it_behaves_like "an analyze reply", level: :vid
    end

    describe "game_detail → analyze this game" do
      let(:expected_ids) { [ game.id ] }
      let(:event)  { event_with(target: "game_detail", kind: :system, payload: { "game_id" => game.id }) }
      let(:result) { Pito::FollowUp::Handlers::GameDetail.new.call(event:, rest: "analyze", conversation:, period: "28d") }

      it_behaves_like "an analyze reply", level: :game
    end

    describe "channel_detail → analyze this channel" do
      let(:expected_ids) { [ channel.id ] }
      let(:event)  { event_with(target: "channel_detail", kind: :system, payload: { "channel_id" => channel.id }) }
      let(:result) { Pito::FollowUp::Handlers::ChannelDetail.new.call(event:, rest: "analyze", conversation:, period: "28d") }

      it_behaves_like "an analyze reply", level: :channel
    end
  end
end
