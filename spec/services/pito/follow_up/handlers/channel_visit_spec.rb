# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::ChannelVisit do
  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }
  let!(:channel) do
    create(:channel, title: "Alpha Cast", handle: "@alpha", youtube_channel_id: "UCabc")
  end

  # Minimal stand-in for the source event — the handler only reads payload.
  def event_for(channel_id, extra = {})
    Struct.new(:payload).new({ "channel_id" => channel_id }.merge(extra))
  end

  it "registers for the channel_visit target in :mutate mode" do
    expect(described_class.target).to eq("channel_visit")
    expect(described_class.mode).to eq(:mutate)
  end

  it "is internal (must not appear as a user-typeable #hashtag or in #help)" do
    expect(described_class.internal?).to be true
  end

  it "declares the consume action" do
    expect(described_class.actions).to eq([ "consume" ])
  end

  describe "consume" do
    subject(:result) do
      handler.call(event: event_for(channel.id), rest: "consume", conversation:)
    end

    it "returns a Mutation to the system_follow_up surface kind" do
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      expect(result.kind).to eq(:system_follow_up)
    end

    it "rebuilds the :visited payload (visit_state visited, no shimmer)" do
      expect(result.payload["visit_state"]).to eq("visited")
      expect(result.payload["body"]).not_to include("pito-network-shimmer")
    end

    it "is not follow-up-able once consumed (graceful repeat no-op)" do
      expect(Pito::FollowUp.followupable?(result.payload)).to be false
    end

    it "defaults to the :channel destination when visit_destination is absent" do
      expect(result.payload["body"]).to include("www.youtube.com/@alpha")
      expect(result.payload["body"]).not_to include("studio.youtube.com")
    end
  end

  describe "consume preserves the visit_destination from the source event" do
    it "rebuilds the :visited URL as studio when the source was stamped studio" do
      result = handler.call(
        event:        event_for(channel.id, "visit_destination" => "studio"),
        rest:         "consume",
        conversation:
      )
      expect(result.payload["body"]).to include("studio.youtube.com/channel/UCabc")
      expect(result.payload["body"]).not_to include("www.youtube.com/@alpha")
    end

    it "rebuilds the :visited URL as channel when the source was stamped channel" do
      result = handler.call(
        event:        event_for(channel.id, "visit_destination" => "channel"),
        rest:         "consume",
        conversation:
      )
      expect(result.payload["body"]).to include("www.youtube.com/@alpha")
    end
  end

  describe "errors" do
    it "returns an Error for an unknown action" do
      result = handler.call(event: event_for(channel.id), rest: "nope", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end

    it "returns an Error when the channel is gone" do
      result = handler.call(event: event_for(0), rest: "consume", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end
  end
end
