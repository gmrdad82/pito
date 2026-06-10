# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Game::FootageImport do
  let(:game) { create(:game, title: "Returnal") }

  describe ".call" do
    subject(:payload) { described_class.call(game, path: "/clips") }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "sets html: true" do
      expect(payload["html"]).to be(true)
    end

    it "stamps game_id in the payload" do
      expect(payload["game_id"]).to eq(game.id)
    end

    it "body includes the pito-footage-import block" do
      expect(payload["body"]).to include("pito-footage-import")
    end

    it "body includes the pito:tools:probe command for the game" do
      expect(payload["body"]).to include("pito:tools:probe game=#{game.id}")
    end

    it "body includes the probe path glob in the command" do
      expect(payload["body"]).to include("path=&quot;/clips/*&quot;")
    end

    it "body includes the probe prompt intro paragraph" do
      expect(payload["body"]).to include("<p")
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end

    context "when force: true" do
      subject(:payload) { described_class.call(game, path: "/clips", force: true) }

      it "body includes -- --force in the probe command" do
        expect(payload["body"]).to include("-- --force")
      end
    end

    context "when force: false (default)" do
      it "body does not include --force in the probe command" do
        expect(payload["body"]).not_to include("--force")
      end
    end
  end
end
