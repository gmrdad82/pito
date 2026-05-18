require "rails_helper"

# Phase 34 (2026-05-18) — Meilisearch::SearchGames surface coverage.
#
# Coverage priorities (per lane C dispatch):
#   - Mixed games + bundles returned in Meilisearch hit order
#   - `kind` discriminator filtering (game vs bundle hits)
#   - `include_bundles: false` mode (search service / `:bundle_add`)
#   - `exclude_bundle` filter (drops already-in-bundle games)
#   - `resolve_bundles` accepts both new `bundle_` and legacy `bundle:` id
#     prefixes (FG defensive parser)
#   - Empty / blank query short-circuit
#   - Network failure swallow + log
RSpec.describe Meilisearch::SearchGames do
  let(:meili_url) { "http://127.0.0.1:7727" }
  let(:index_name) { "games_test" }
  let(:search_url) { "#{meili_url}/indexes/#{index_name}/search" }

  let(:game_a) { build_stubbed(:game, id: 101, title: "Alpha") }
  let(:game_b) { build_stubbed(:game, id: 102, title: "Bravo") }
  let(:game_c) { build_stubbed(:game, id: 103, title: "Charlie") }
  let(:bundle_x) { build_stubbed(:bundle, id: 201, name: "X") }
  let(:bundle_y) { build_stubbed(:bundle, id: 202, name: "Y") }

  def stub_meili_hits(hits)
    stub_request(:post, search_url).to_return(
      status: 200,
      body: JSON.generate(hits: hits),
      headers: { "Content-Type" => "application/json" }
    )
  end

  describe ".call" do
    context "with a blank query" do
      it "short-circuits and returns empty result sets without hitting Meilisearch" do
        result = described_class.call("   ")
        expect(result).to eq(games: [], bundles: [])
        expect(WebMock).not_to have_requested(:post, search_url)
      end
    end

    context "with a query and `include_bundles: false` (default)" do
      it "returns only games, in Meilisearch hit order, no bundles" do
        stub_meili_hits(
          [
            { "id" => 102, "kind" => "game" },
            { "id" => "bundle_201", "kind" => "bundle" },
            { "id" => 101, "kind" => "game" }
          ]
        )
        allow(Game).to receive(:where).with(id: [ 102, 101 ]).and_return([ game_a, game_b ])

        result = described_class.call("any")
        expect(result[:games].map(&:id)).to eq([ 102, 101 ])
        expect(result[:bundles]).to eq([])
      end

      it "filters by kind == 'game' even when bundle hits are present" do
        stub_meili_hits(
          [
            { "id" => "bundle_201", "kind" => "bundle" },
            { "id" => "bundle_202", "kind" => "bundle" }
          ]
        )
        result = described_class.call("any")
        expect(result[:games]).to eq([])
        expect(result[:bundles]).to eq([])
      end
    end

    context "with `include_bundles: true`" do
      it "returns mixed games + bundles, each in hit order" do
        stub_meili_hits(
          [
            { "id" => 102, "kind" => "game" },
            { "id" => "bundle_201", "kind" => "bundle" },
            { "id" => 101, "kind" => "game" },
            { "id" => "bundle_202", "kind" => "bundle" }
          ]
        )
        allow(Game).to receive(:where).with(id: [ 102, 101 ]).and_return([ game_a, game_b ])
        allow(Bundle).to receive(:where).with(id: [ 201, 202 ]).and_return([ bundle_x, bundle_y ])

        result = described_class.call("any", include_bundles: true)
        expect(result[:games].map(&:id)).to eq([ 102, 101 ])
        expect(result[:bundles].map(&:id)).to eq([ 201, 202 ])
      end

      it "strips the new `bundle_` prefix to recover the bundle AR id" do
        stub_meili_hits([ { "id" => "bundle_201", "kind" => "bundle" } ])
        allow(Bundle).to receive(:where).with(id: [ 201 ]).and_return([ bundle_x ])

        result = described_class.call("any", include_bundles: true)
        expect(result[:bundles].map(&:id)).to eq([ 201 ])
      end

      it "defensively accepts the legacy `bundle:` colon prefix as well" do
        stub_meili_hits([ { "id" => "bundle:201", "kind" => "bundle" } ])
        allow(Bundle).to receive(:where).with(id: [ 201 ]).and_return([ bundle_x ])

        result = described_class.call("any", include_bundles: true)
        expect(result[:bundles].map(&:id)).to eq([ 201 ])
      end
    end

    context "with `exclude_bundle`" do
      it "filters out games that are already members of the given bundle" do
        members_relation = double(pluck: [ 102 ])
        excluded_bundle = double(bundle_members: members_relation)
        stub_meili_hits(
          [
            { "id" => 101, "kind" => "game" },
            { "id" => 102, "kind" => "game" },
            { "id" => 103, "kind" => "game" }
          ]
        )
        allow(Game).to receive(:where).with(id: [ 101, 103 ]).and_return([ game_a, game_c ])

        result = described_class.call("any", exclude_bundle: excluded_bundle)
        expect(result[:games].map(&:id)).to eq([ 101, 103 ])
      end

      it "returns an empty games array when every hit is excluded" do
        members_relation = double(pluck: [ 101, 102, 103 ])
        excluded_bundle = double(bundle_members: members_relation)
        stub_meili_hits(
          [
            { "id" => 101, "kind" => "game" },
            { "id" => 102, "kind" => "game" }
          ]
        )
        result = described_class.call("any", exclude_bundle: excluded_bundle)
        expect(result[:games]).to eq([])
      end
    end

    context "with a non-2xx Meilisearch response" do
      it "returns empty result sets (no raise)" do
        stub_request(:post, search_url).to_return(status: 500, body: "boom")
        expect { described_class.call("any") }.not_to raise_error
        expect(described_class.call("any")).to eq(games: [], bundles: [])
      end
    end

    context "when the network call raises" do
      it "logs and returns empty result sets" do
        stub_request(:post, search_url).to_raise(StandardError.new("net down"))
        expect(Rails.logger).to receive(:warn).with(/SearchGames.*query failed.*\"any\".*net down/)

        expect(described_class.call("any")).to eq(games: [], bundles: [])
      end
    end

    context "limit handling" do
      it "asks Meilisearch for 2x the per-kind limit (headroom for skewed results)" do
        stub_meili_hits([])
        described_class.call("any", limit: 7)
        expect(WebMock).to have_requested(:post, search_url).with { |req|
          JSON.parse(req.body)["limit"] == 14
        }
      end

      it "caps each per-kind array at the limit value" do
        hits = (1..50).map { |i| { "id" => i, "kind" => "game" } }
        stub_meili_hits(hits)
        all_games = (1..50).map { |i| build_stubbed(:game, id: i) }
        allow(Game).to receive(:where).and_return(all_games)

        result = described_class.call("any", limit: 5)
        expect(result[:games].size).to eq(5)
      end
    end

    # 2026-05-18 — Postgres ILIKE fallback. When Meilisearch returns no
    # game / bundle hits (the index is empty / stale / unreachable), the
    # service falls back to `LOWER(title) ILIKE %q%` so local-typed
    # title substrings stay findable. Reproduces the user-reported bug
    # where "street" returned zero local rows for a library that
    # contained Street Fighter 6 because the Meilisearch index had not
    # been (re)populated after a fresh sync.
    context "Postgres ILIKE fallback when Meilisearch returns no game hits" do
      it "returns matching local games via ILIKE on Game#title" do
        create(:game, title: "Street Fighter 6")
        create(:game, title: "Hollow Knight")
        stub_meili_hits([])

        result = described_class.call("street")
        expect(result[:games].map(&:title)).to eq([ "Street Fighter 6" ])
      end

      it "is case-insensitive" do
        create(:game, title: "Pragmata")
        stub_meili_hits([])

        result = described_class.call("PRAG")
        expect(result[:games].map(&:title)).to eq([ "Pragmata" ])
      end

      it "honors `exclude_bundle` and drops games already in the bundle" do
        in_bundle = create(:game, title: "Street Fighter 6")
        free = create(:game, title: "Street Fighter 4")
        bundle = create(:bundle, name: "Fighters")
        bundle.bundle_members.create!(game_id: in_bundle.id)
        stub_meili_hits([])

        result = described_class.call("street", exclude_bundle: bundle)
        expect(result[:games].map(&:id)).to eq([ free.id ])
      end

      it "does NOT fire the fallback when Meilisearch returns at least one game hit" do
        create(:game, title: "Street Fighter 6")
        meili_game = create(:game, title: "Stardew Valley")
        stub_meili_hits([ { "id" => meili_game.id, "kind" => "game" } ])

        result = described_class.call("st")
        # Only the Meilisearch-ranked hit should appear; ILIKE fallback skipped.
        expect(result[:games].map(&:id)).to eq([ meili_game.id ])
      end

      it "returns local bundles via ILIKE on Bundle#name when include_bundles is true" do
        create(:bundle, name: "Street Fighter Series")
        create(:bundle, name: "Roguelikes")
        stub_meili_hits([])

        result = described_class.call("street", include_bundles: true)
        expect(result[:bundles].map(&:name)).to eq([ "Street Fighter Series" ])
      end

      it "still runs the fallback when the Meilisearch network call raises" do
        create(:game, title: "Street Fighter 6")
        stub_request(:post, search_url).to_raise(StandardError.new("net down"))
        allow(Rails.logger).to receive(:warn)

        result = described_class.call("street")
        expect(result[:games].map(&:title)).to eq([ "Street Fighter 6" ])
      end

      it "escapes LIKE metacharacters in the query" do
        create(:game, title: "Plain Title")
        stub_meili_hits([])

        result = described_class.call("%plain%")
        # `%` is sanitized so the LIKE pattern is `%\%plain\%%` — matches
        # only a literal `%plain%` substring (none in the fixture).
        expect(result[:games]).to eq([])
      end
    end
  end
end
