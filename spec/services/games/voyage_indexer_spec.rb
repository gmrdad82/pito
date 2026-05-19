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

    # 2026-05-19 — alternative_names joins the Voyage embedding input
    # so similar-games + recommended-bundles clustering picks up alt-
    # name signal (series identifiers, localized names, marketing
    # aliases). Three cases pin the contract.
    context "with alternative_names" do
      it "includes alt_names between title and summary (all three slots)" do
        game = create(
          :game,
          title: "Hollow Knight",
          summary: "Indie metroidvania.",
          alternative_names: [ "HK", "ホロウナイト" ]
        )
        voyage_client = instance_double(Voyage::Client)
        allow(Voyage::Client).to receive(:new).and_return(voyage_client)
        expect(voyage_client).to receive(:embed)
          .with([ "Hollow Knight — HK ホロウナイト — Indie metroidvania." ])
          .and_return([ vector ])

        described_class.call(game)
      end

      it "omits the alt_names slot when alternative_names is empty (no leading em-dash, no blank slot)" do
        game = create(
          :game,
          title: "Hollow Knight",
          summary: "Indie metroidvania.",
          alternative_names: []
        )
        voyage_client = instance_double(Voyage::Client)
        allow(Voyage::Client).to receive(:new).and_return(voyage_client)
        expect(voyage_client).to receive(:embed)
          .with([ "Hollow Knight — Indie metroidvania." ])
          .and_return([ vector ])

        described_class.call(game)
      end

      it "uses title + alt_names when summary is blank (alt slot still wired in)" do
        game = create(
          :game,
          title: "Tetris",
          summary: nil,
          alternative_names: [ "テトリス" ]
        )
        voyage_client = instance_double(Voyage::Client)
        allow(Voyage::Client).to receive(:new).and_return(voyage_client)
        expect(voyage_client).to receive(:embed)
          .with([ "Tetris — テトリス" ])
          .and_return([ vector ])

        described_class.call(game)
      end

      it "strips blank entries inside alternative_names before joining" do
        game = create(
          :game,
          title: "Game",
          summary: "Sum.",
          alternative_names: [ "Alt1", "  ", "", "Alt2" ]
        )
        voyage_client = instance_double(Voyage::Client)
        allow(Voyage::Client).to receive(:new).and_return(voyage_client)
        expect(voyage_client).to receive(:embed)
          .with([ "Game — Alt1 Alt2 — Sum." ])
          .and_return([ vector ])

        described_class.call(game)
      end
    end
  end
end
