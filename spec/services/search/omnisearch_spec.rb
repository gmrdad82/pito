require "rails_helper"

# 2026-05-18 — Search::Omnisearch dispatcher coverage.
#
# The dispatcher is a thin routing layer: given an `area:`, look up the
# registered implementation in `AREAS` and forward `query` + extra kwargs.
# Coverage:
#   - happy path: `:games` delegates to `Meilisearch::SearchGames.call`
#   - kwargs (e.g. `exclude_bundle:`, `include_bundles:`) pass through
#   - unknown area raises ArgumentError naming the bad area
#   - the `AREAS` table is frozen (constant guarded against runtime mutation)
RSpec.describe Search::Omnisearch do
  describe ".call" do
    context "with a known area" do
      it "delegates `:games` to `Meilisearch::SearchGames.call` with the query positional" do
        expect(Meilisearch::SearchGames).to receive(:call).with("street").and_return(games: [], bundles: [])

        result = described_class.call(area: :games, query: "street")
        expect(result).to eq(games: [], bundles: [])
      end

      it "passes extra kwargs (e.g. `exclude_bundle:`) through to the implementation" do
        excluded = double("Bundle")
        expect(Meilisearch::SearchGames).to receive(:call)
          .with("street", exclude_bundle: excluded)
          .and_return(games: [], bundles: [])

        described_class.call(area: :games, query: "street", exclude_bundle: excluded)
      end

      it "passes `include_bundles: true` through to the implementation" do
        expect(Meilisearch::SearchGames).to receive(:call)
          .with("street", include_bundles: true)
          .and_return(games: [], bundles: [])

        described_class.call(area: :games, query: "street", include_bundles: true)
      end

      it "passes multiple kwargs together" do
        excluded = double("Bundle")
        expect(Meilisearch::SearchGames).to receive(:call)
          .with("street", exclude_bundle: excluded, limit: 5)
          .and_return(games: [], bundles: [])

        described_class.call(area: :games, query: "street", exclude_bundle: excluded, limit: 5)
      end

      it "returns whatever the implementation returns (envelope is not rewrapped)" do
        envelope = { games: [ :g1, :g2 ], bundles: [ :b1 ] }
        allow(Meilisearch::SearchGames).to receive(:call).and_return(envelope)

        expect(described_class.call(area: :games, query: "any")).to equal(envelope)
      end
    end

    context "with an unknown area" do
      it "raises ArgumentError naming the bad area" do
        expect {
          described_class.call(area: :unknown, query: "anything")
        }.to raise_error(ArgumentError, /unknown omnisearch area:\s*:unknown/)
      end

      it "does NOT touch any implementation when the area is unknown" do
        expect(Meilisearch::SearchGames).not_to receive(:call)

        expect {
          described_class.call(area: :nope, query: "x")
        }.to raise_error(ArgumentError)
      end
    end
  end

  describe "AREAS constant" do
    it "is frozen so callers cannot mutate the registry at runtime" do
      expect(described_class::AREAS).to be_frozen
    end

    it "registers `:games` to `Meilisearch::SearchGames`" do
      expect(described_class::AREAS[:games]).to eq(Meilisearch::SearchGames)
    end
  end
end
