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

  it "registers for the channel_list target in :append mode" do
    expect(described_class.target).to eq("channel_list")
    expect(described_class.mode).to eq(:append)
  end

  it "declares only shinies as an action (visit was removed)" do
    expect(described_class.actions).to eq([ "shinies" ])
    expect(described_class.actions).not_to include("visit")
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
