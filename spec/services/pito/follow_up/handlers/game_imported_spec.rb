# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::GameImported do
  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }
  let!(:game)        { create(:game, title: "Lies of P") }

  # An import-done source event — the imported game's id in the payload.
  let(:event) do
    instance_double(Event, payload: {
      "reply_target" => "game_imported",
      "game_id"      => game.id
    })
  end

  it "registers for the game_imported target" do
    expect(described_class.target).to eq("game_imported")
  end

  it "Matrix serves :append mode for game_imported" do
    expect(Pito::Dispatch::Matrix.mode_for("game_imported")).to eq(:append)
  end

  it "Matrix advertises 'show' for game_imported" do
    expect(Pito::Dispatch::Matrix.actions_for("game_imported")).to include("show")
  end

  describe "#call — show" do
    it "returns a Result::Append for a known game id" do
      result = handler.call(event:, rest: "show", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "routes to the game branch: first event is :system game_detail" do
      result = handler.call(event:, rest: "show", conversation:)
      first  = result.events.first
      expect(first[:kind]).to eq(:system)
      expect(first[:payload]["reply_target"]).to eq("game_detail")
      expect(first[:payload]["game_id"]).to eq(game.id)
    end

    it "uses the game_id from the event payload (not from rest args)" do
      result = handler.call(event:, rest: "show", conversation:)
      first  = result.events.first
      expect(first[:payload]["game_id"]).to eq(game.id)
    end
  end

  describe "#call — invalid action" do
    it "returns a Result::Error for an unrecognised action" do
      result = handler.call(event:, rest: "delete", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.game_imported.errors.invalid_action")
    end

    it "returns a Result::Error for an empty action" do
      result = handler.call(event:, rest: "", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end

    it "returns a Result::Error for any non-show action" do
      result = handler.call(event:, rest: "rm", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end
  end
end
