# frozen_string_literal: true

require "rails_helper"

RSpec.describe GameVoyageIndexJob, type: :job do
  let(:game) { create(:game, title: "Elden Ring") }

  it "is a no-op when the game id is missing" do
    expect(Game::VoyageIndexer).not_to receive(:call)
    described_class.new.perform(0)
  end

  it "delegates to Game::VoyageIndexer.call with the resolved game" do
    expect(Game::VoyageIndexer).to receive(:call).with(game)
    described_class.new.perform(game.id)
  end
end
