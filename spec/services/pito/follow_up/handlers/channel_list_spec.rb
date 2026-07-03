# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::ChannelList do
  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }
  let!(:channel) do
    create(:channel,
           title:              "Alpha Cast",
           handle:             "@alpha",
           youtube_channel_id: "UCabc")
  end

  it "registers for the channel_list target" do
    expect(described_class.target).to eq("channel_list")
  end

  it "Matrix serves :append mode for channel_list" do
    expect(Pito::Dispatch::Matrix.mode_for("channel_list")).to eq(:append)
  end

  it "Matrix advertises shinies, analyze, sort/order, and next for channel_list (not visit)" do
    actions = Pito::Dispatch::Matrix.actions_for("channel_list")
    expect(actions).to include("shinies", "analyze", "sort", "order", "next")
    expect(actions).not_to include("visit")
  end

  describe "sort / order replies (mutate — table re-sorts in place)" do
    let(:conversation) { Conversation.singleton }
    let!(:turn)        { create(:turn, conversation:) }
    let!(:small) { create(:channel, title: "Small", handle: "@small", youtube_channel_id: "UCsml") }
    let!(:big)   { create(:channel, title: "Big",   handle: "@big",   youtube_channel_id: "UCbig") }

    let!(:event) do
      create(:event, conversation:, turn:, kind: "system", position: 1,
                     payload: Pito::MessageBuilder::Channel::List.call([ small, big ], conversation:))
    end

    before do
      allow(small).to receive(:subscriber_count).and_return(5)
      allow(big).to receive(:subscriber_count).and_return(500)
      allow(::Channel).to receive(:where).and_call_original
    end

    def handles_of(result)
      result.payload["table_rows"].map { |r| r[:cells][1][:text] }
    end

    it "re-sorts the stamped table by a column (sort by title)" do
      result = handler.call(event:, rest: "sort by title", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      expect(handles_of(result)).to eq([ "@big", "@small" ]) # Big < Small
    end

    it "honors a trailing desc (order title desc)" do
      result = handler.call(event:, rest: "order title desc", conversation:)
      expect(handles_of(result)).to eq([ "@small", "@big" ])
    end

    it "preserves the reply handle/target across the mutation" do
      result = handler.call(event:, rest: "sort by title", conversation:)
      expect(result.payload["reply_handle"]).to eq(event.payload["reply_handle"])
      expect(result.payload["reply_target"]).to eq("channel_list")
    end

    it "is a lenient no-op on an unknown column (stamped order kept)" do
      result = handler.call(event:, rest: "sort by price", conversation:)
      expect(handles_of(result)).to eq([ "@small", "@big" ])
    end
  end

  it "visit is NOT in Registry.actions_for('channel_list')" do
    expect(Pito::FollowUp::Registry.actions_for("channel_list")).not_to include("visit")
  end

  describe "invalid action" do
    it "returns Result::Error for an unknown action" do
      result = handler.call(event: nil, rest: "open @alpha", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.channel_list.errors.invalid_action")
    end

    it "returns Result::Error for 'visit' (visit moved to channel_detail)" do
      source_event = instance_double(Event, payload: { "reply_target" => "channel_list" })
      result = handler.call(event: source_event, rest: "visit @alpha", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.channel_list.errors.invalid_action")
    end
  end

  # ── shinies (delegated to Chat::Handlers::Shinies via VerbDelegator) ───────────

  describe "#call — shinies" do
    let(:source_event) do
      instance_double(Event, payload: { "reply_target" => "channel_list" })
    end

    it "returns a Result::Append with the shinies message for @handle" do
      result = handler.call(event: source_event, rest: "shinies @alpha", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      payload = result.events.first[:payload]
      expect(payload["body"]).to include("pito-achievement-shinies")
      expect(payload["channel_id"]).to eq(channel.id)
    end

    it "does NOT return an invalid_action error (shinies is now a declared action)" do
      result = handler.call(event: source_event, rest: "shinies @alpha", conversation:)
      expect(result).not_to be_a(Pito::FollowUp::Result::Error)
    end
  end
end
