# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::GameList do
  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }
  let!(:game)        { create(:game, title: "Lies of P") }

  # A game_list source event whose only row is `game` (#id in the first cell).
  let(:event) do
    instance_double(Event, payload: {
      "reply_target" => "game_list",
      "table_rows"   => [ { cells: [ { text: "##{game.id}" }, { text: game.title } ] } ]
    })
  end

  it "registers for the game_list target in :append mode" do
    expect(described_class.target).to eq("game_list")
    expect(described_class.mode).to eq(:append)
  end

  it "delegates `show <id>` to the verb handler: detail card + enhanced message" do
    result = handler.call(event:, rest: "show ##{game.id}", conversation:)
    expect(result).to be_a(Pito::FollowUp::Result::Append)

    expect(result.events.map { |e| e[:kind] }).to eq([ :system, :enhanced ])
    detail = result.events.find { |e| e[:kind] == :system }[:payload]
    expect(detail["body"]).to include("Lies of P")
    expect(detail["reply_target"]).to eq("game_detail")
    enhanced = result.events.find { |e| e[:kind] == :enhanced }[:payload]
    expect(enhanced["body"]).to include("pito-game-enhanced-message")
  end

  it "resolves `show <id>` by GAME id (not video) — reply_target fixes entity type" do
    # Even without the 'game' noun in rest, the entity type is GAME
    # because reply_target = 'game_list' does not start with 'video', so
    # video_target? returns false and the Show handler takes the game branch.
    result = handler.call(event:, rest: "show ##{game.id}", conversation:)
    detail = result.events.find { |e| e[:kind] == :system }[:payload]
    expect(detail["game_id"]).to eq(game.id)
    expect(detail["reply_target"]).to eq("game_detail")
  end

  it "returns not-found for a title ref (show is id-only — no title lookup)" do
    result = handler.call(event:, rest: "show lies of p", conversation:)
    expect(result.events.first[:payload]["text"]).to be_present
    expect(result.events.first[:payload]["game_id"]).to be_nil
  end

  it "appends a witty not-found for an unknown reference" do
    result = handler.call(event:, rest: "show 9999", conversation:)
    expect(result.events.first[:payload]["text"]).to include("9999")
  end

  it "rejects an invalid action (not in the game_list matrix)" do
    result = handler.call(event:, rest: "destroy 5", conversation:)
    expect(result).to be_a(Pito::FollowUp::Result::Error)
  end

  it "delegates `delete <id>` to the same delete confirmation" do
    result = handler.call(event:, rest: "delete ##{game.id}", conversation:)
    expect(result).to be_a(Pito::FollowUp::Result::Append)
    ev = result.events.first
    expect(ev[:kind].to_s).to eq("confirmation")
    expect(ev[:payload]["command"]).to eq("game_delete")
    expect(ev[:payload]["game_id"]).to eq(game.id)
  end

  it "accepts `rm <id>` as an alias for delete" do
    result = handler.call(event:, rest: "rm ##{game.id}", conversation:)
    expect(result.events.first[:kind].to_s).to eq("confirmation")
  end

  it "stamps game_id in the delete confirmation payload" do
    result = handler.call(event:, rest: "rm ##{game.id}", conversation:)
    expect(result.events.first[:payload]["game_id"]).to eq(game.id)
  end

  it "stamps game_id in the appended detail event payload" do
    result = handler.call(event:, rest: "show ##{game.id}", conversation:)
    expect(result.events.first[:payload]["game_id"]).to eq(game.id)
  end
end
