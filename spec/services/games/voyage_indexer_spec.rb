require "rails_helper"

RSpec.describe Games::VoyageIndexer do
  describe ".call" do
    let(:vector) { Array.new(1024) { 0.42 } }
    let(:game) { create(:game, title: "Hollow Knight", summary: "Indie metroidvania.") }

    before do
      allow(AppSetting).to receive(:voyage_configured?).and_return(true)
      allow(Meilisearch::GameIndexer).to receive(:call)
    end

    it "no-ops (no Voyage call, no Meilisearch push) when title AND summary are both blank" do
      blank_game = build_stubbed(:game, title: "", summary: nil)

      expect(Voyage::Client).not_to receive(:new)
      expect(Meilisearch::GameIndexer).not_to receive(:call)

      described_class.call(blank_game)
    end

    it "skips the Voyage embed step but still pushes to Meilisearch when voyage is NOT configured" do
      allow(AppSetting).to receive(:voyage_configured?).and_return(false)
      expect(Voyage::Client).not_to receive(:new)
      expect(Meilisearch::GameIndexer).to receive(:call)

      described_class.call(game)
    end

    it "writes the embedding into games.summary_embedding via update_column (no callbacks)" do
      voyage_client = instance_double(Voyage::Client, embed: [ vector ])
      allow(Voyage::Client).to receive(:new).and_return(voyage_client)

      described_class.call(game)
      game.reload

      expect(game.summary_embedding).not_to be_nil
      expect(game.summary_embedding.length).to eq(1024)
    end

    it "passes the combined `title — summary` text to Voyage" do
      voyage_client = instance_double(Voyage::Client)
      allow(Voyage::Client).to receive(:new).and_return(voyage_client)
      expect(voyage_client).to receive(:embed).with([ "Hollow Knight — Indie metroidvania." ]).and_return([ vector ])

      described_class.call(game)
    end

    it "calls Meilisearch::GameIndexer with the reloaded game (vector freshly written)" do
      voyage_client = instance_double(Voyage::Client, embed: [ vector ])
      allow(Voyage::Client).to receive(:new).and_return(voyage_client)
      expect(Meilisearch::GameIndexer).to receive(:call) do |reloaded|
        expect(reloaded.id).to eq(game.id)
        expect(reloaded.summary_embedding.length).to eq(1024)
      end

      described_class.call(game)
    end

    it "raises when Voyage is configured but the embed call returns nil" do
      voyage_client = instance_double(Voyage::Client, embed: [ nil ])
      allow(Voyage::Client).to receive(:new).and_return(voyage_client)

      expect {
        described_class.call(game)
      }.to raise_error(/Voyage embedding returned nil/)
    end

    it "uses just the title when summary is blank (single-part combined text)" do
      title_only = create(:game, title: "Tetris", summary: nil)
      voyage_client = instance_double(Voyage::Client)
      allow(Voyage::Client).to receive(:new).and_return(voyage_client)
      expect(voyage_client).to receive(:embed).with([ "Tetris" ]).and_return([ vector ])

      described_class.call(title_only)
    end
  end
end
