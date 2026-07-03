# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::GameChannels do
  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }
  let!(:game)        { create(:game, title: "Lies of P") }
  let!(:channel)     { create(:channel, handle: "@gmrdad82", title: "GMR Dad", description: "Stories.") }

  # A game_channels source event — the shown game's id in the payload.
  let(:event) do
    instance_double(Event, payload: {
      "reply_target" => "game_channels",
      "game_id"      => game.id
    })
  end

  it "registers for the game_channels target" do
    expect(described_class.target).to eq("game_channels")
  end

  it "Matrix serves :append mode for game_channels" do
    expect(Pito::Dispatch::Matrix.mode_for("game_channels")).to eq(:append)
  end

  it "Matrix advertises 'show' for game_channels" do
    expect(Pito::Dispatch::Matrix.actions_for("game_channels")).to include("show")
  end

  describe "#call — show @handle" do
    it "returns a Result::Append for a known channel handle" do
      result = handler.call(event:, rest: "show @gmrdad82", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "routes to the channel branch: first event is :system channel_detail" do
      result = handler.call(event:, rest: "show @gmrdad82", conversation:)
      first  = result.events.first
      expect(first[:kind]).to eq(:system)
      expect(first[:payload]["reply_target"]).to eq("channel_detail")
      expect(first[:payload]["channel_id"]).to eq(channel.id)
    end

    it "resolves @-agnostic (without the @-prefix)" do
      result = handler.call(event:, rest: "show gmrdad82", conversation:)
      expect(result.events.first[:payload]["channel_id"]).to eq(channel.id)
    end

    it "resolves case-insensitively" do
      result = handler.call(event:, rest: "show @GMRDAD82", conversation:)
      expect(result.events.first[:payload]["channel_id"]).to eq(channel.id)
    end

    it "dispatches free-chat so the source game_id does NOT pollute channel resolution" do
      # Even though the source event has game_id, the channel branch is reached
      # because free-chat dispatch includes the 'channel' noun in the input.
      result = handler.call(event:, rest: "show @gmrdad82", conversation:)
      expect(result.events.first[:payload]["reply_target"]).to eq("channel_detail")
    end

    it "returns a not-found Ok (consume: false) for an unknown handle" do
      result = handler.call(event:, rest: "show @nope", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to be(false)
    end
  end

  describe "#call — invalid action" do
    it "returns a Result::Error for an unrecognised action" do
      result = handler.call(event:, rest: "rm @gmrdad82", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.game_channels.errors.invalid_action")
    end

    it "returns a Result::Error for an empty action" do
      result = handler.call(event:, rest: "", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end
  end
end
