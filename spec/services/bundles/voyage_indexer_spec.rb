require "rails_helper"

RSpec.describe Bundles::VoyageIndexer do
  describe ".call" do
    let(:vector) { Array.new(1024) { 0.11 } }

    before do
      allow(AppSetting).to receive(:voyage_configured?).and_return(true)
      allow(Meilisearch::BundleIndexer).to receive(:call)
    end

    it "no-ops when combined_text is blank (no name, no member summaries)" do
      blank_bundle = build_stubbed(:bundle, name: "")
      allow(blank_bundle).to receive(:games).and_return([])

      expect(Voyage::Client).not_to receive(:new)
      expect(Meilisearch::BundleIndexer).not_to receive(:call)

      described_class.call(blank_bundle)
    end

    it "skips the Voyage embed step but still pushes to Meilisearch when voyage is NOT configured" do
      allow(AppSetting).to receive(:voyage_configured?).and_return(false)
      bundle = create(:bundle, name: "PS Classics")

      expect(Voyage::Client).not_to receive(:new)
      expect(Meilisearch::BundleIndexer).to receive(:call).with(an_instance_of(Bundle), embedding: nil)

      described_class.call(bundle)
    end

    it "writes the embedding into bundles.summary_embedding via update_column (no callbacks)" do
      bundle = create(:bundle, name: "Sony first-party")
      voyage_client = instance_double(Voyage::Client, embed: [ vector ])
      allow(Voyage::Client).to receive(:new).and_return(voyage_client)

      described_class.call(bundle)
      bundle.reload

      expect(bundle.summary_embedding).not_to be_nil
      expect(bundle.summary_embedding.length).to eq(1024)
    end

    it "passes the combined `name — agg(member summaries)` text to Voyage" do
      bundle = create(:bundle, name: "Action 2025")
      g1 = create(:game, title: "Game A", summary: "First action game.")
      g2 = create(:game, title: "Game B", summary: "Second action game.")
      bundle.games << g1
      bundle.games << g2

      voyage_client = instance_double(Voyage::Client)
      allow(Voyage::Client).to receive(:new).and_return(voyage_client)
      expect(voyage_client).to receive(:embed).with([ "Action 2025 — First action game. — Second action game." ]).and_return([ vector ])

      described_class.call(bundle.reload)
    end

    it "passes the freshly-written embedding to Meilisearch::BundleIndexer" do
      bundle = create(:bundle, name: "Test")
      voyage_client = instance_double(Voyage::Client, embed: [ vector ])
      allow(Voyage::Client).to receive(:new).and_return(voyage_client)

      expect(Meilisearch::BundleIndexer).to receive(:call) do |reloaded, embedding:|
        expect(reloaded.id).to eq(bundle.id)
        expect(embedding).to eq(vector)
      end

      described_class.call(bundle)
    end

    it "passes nil embedding to Meilisearch when Voyage returns nil (silent skip)" do
      bundle = create(:bundle, name: "Test")
      voyage_client = instance_double(Voyage::Client, embed: [ nil ])
      allow(Voyage::Client).to receive(:new).and_return(voyage_client)

      expect(Meilisearch::BundleIndexer).to receive(:call).with(an_instance_of(Bundle), embedding: nil)

      described_class.call(bundle)
      bundle.reload
      expect(bundle.summary_embedding).to be_nil
    end

    it "caps aggregated member summaries at MAX_MEMBER_SUMMARIES (5)" do
      bundle = create(:bundle, name: "Bundle")
      7.times { |i| bundle.games << create(:game, title: "G#{i}", summary: "Summary #{i}") }

      voyage_client = instance_double(Voyage::Client)
      allow(Voyage::Client).to receive(:new).and_return(voyage_client)

      expect(voyage_client).to receive(:embed) do |inputs|
        # 5 summaries em-dash joined, NOT 7
        body = inputs.first
        expect(body.scan(/Summary \d/).length).to eq(described_class::MAX_MEMBER_SUMMARIES)
        [ vector ]
      end

      described_class.call(bundle.reload)
    end
  end
end
