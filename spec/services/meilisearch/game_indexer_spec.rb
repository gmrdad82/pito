require "rails_helper"

# Phase 34 (2026-05-18) — Meilisearch::GameIndexer surface coverage.
#
# This spec lives in lane C of the consolidation pass. It covers:
#   - the `?primaryKey=id` query param on the POST (DR follow-up #2 fix)
#   - the document payload (searchable + filterable fields, `kind: "game"`,
#     numeric id as primary key, optional `_vectors.default`)
#   - the configure-index PATCH path (idempotent attribute updates)
#   - the swallow-and-log behavior on HTTP failure
#
# All HTTP traffic is intercepted via WebMock. We use stubbed Game-shaped
# objects to avoid AR machinery and to keep `developers` / `publishers` /
# `genres` easily controllable without hitting the DB.
RSpec.describe Meilisearch::GameIndexer do
  let(:meili_url) { "http://127.0.0.1:7727" }
  let(:index_name) { "games_test" }
  let(:documents_url) { "#{meili_url}/indexes/#{index_name}/documents?primaryKey=id" }
  let(:settings_base) { "#{meili_url}/indexes/#{index_name}/settings" }

  let(:dev1) { double(id: 11, name: "Dev One") }
  let(:dev2) { double(id: 12, name: "Dev Two") }
  let(:pub1) { double(id: 21, name: "Pub One") }
  let(:genre1) { double(id: 31, name: "RPG") }
  let(:genre2) { double(id: 32, name: "Adventure") }

  let(:game) do
    build_stubbed(
      :game,
      id: 7,
      title: "Test Game",
      summary: "A test game.",
      igdb_id: 9001,
      igdb_slug: "test-game",
      release_year: 2017,
      primary_genre_id: 31
    ).tap do |g|
      allow(g).to receive(:developers).and_return([ dev1, dev2 ])
      allow(g).to receive(:publishers).and_return([ pub1 ])
      allow(g).to receive(:genres).and_return([ genre1, genre2 ])
      # `summary_embedding` is defined on Game via `has_neighbors`, but
      # `build_stubbed` returns nil for it by default. Force the indexer
      # down the no-vector branch unless an individual example opts in.
      allow(g).to receive(:summary_embedding).and_return(nil)
    end
  end

  before do
    stub_request(:put, %r{#{Regexp.escape(settings_base)}/.+}).to_return(status: 202, body: "{}")
    stub_request(:post, documents_url).to_return(status: 202, body: "{}")
  end

  describe ".call" do
    it "POSTs to /indexes/games_test/documents with `?primaryKey=id` query param" do
      described_class.call(game)
      expect(WebMock).to have_requested(:post, documents_url).once
    end

    it "sends the document body as a JSON array of one element" do
      described_class.call(game)
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        body = JSON.parse(req.body)
        body.is_a?(Array) && body.size == 1
      }
    end

    it "includes the game id as the document primary key" do
      described_class.call(game)
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        JSON.parse(req.body).first["id"] == 7
      }
    end

    it "sets the `kind` discriminator to \"game\"" do
      described_class.call(game)
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        JSON.parse(req.body).first["kind"] == "game"
      }
    end

    it "includes searchable text fields (title, summary, developer_name, publisher_name, genre_names)" do
      described_class.call(game)
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        doc = JSON.parse(req.body).first
        doc["title"] == "Test Game" &&
          doc["summary"] == "A test game." &&
          doc["developer_name"] == "Dev One Dev Two" &&
          doc["publisher_name"] == "Pub One" &&
          doc["genre_names"] == [ "RPG", "Adventure" ]
      }
    end

    it "includes filterable id fields (developer_id, publisher_id, genre_ids, primary_genre_id)" do
      described_class.call(game)
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        doc = JSON.parse(req.body).first
        doc["developer_id"] == [ 11, 12 ] &&
          doc["publisher_id"] == [ 21 ] &&
          doc["genre_ids"] == [ 31, 32 ] &&
          doc["primary_genre_id"] == 31
      }
    end

    it "includes IGDB metadata fields (igdb_id, igdb_slug, release_year)" do
      described_class.call(game)
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        doc = JSON.parse(req.body).first
        doc["igdb_id"] == 9001 &&
          doc["igdb_slug"] == "test-game" &&
          doc["release_year"] == 2017
      }
    end

    it "omits the _vectors payload when no summary_embedding is present" do
      described_class.call(game)
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        !JSON.parse(req.body).first.key?("_vectors")
      }
    end

    it "attaches _vectors.default when the Game exposes a summary_embedding" do
      allow(game).to receive(:summary_embedding).and_return([ 0.1, 0.2, 0.3 ])

      described_class.call(game)
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        JSON.parse(req.body).first.dig("_vectors", "default") == [ 0.1, 0.2, 0.3 ]
      }
    end

    it "issues PUT settings calls for searchable-attributes, filterable-attributes, sortable-attributes" do
      described_class.call(game)
      expect(WebMock).to have_requested(:put, "#{settings_base}/searchable-attributes").once
      expect(WebMock).to have_requested(:put, "#{settings_base}/filterable-attributes").once
      expect(WebMock).to have_requested(:put, "#{settings_base}/sortable-attributes").once
    end

    it "configures filterable attributes to include `kind` and `bundle_id`" do
      described_class.call(game)
      expect(WebMock).to have_requested(:put, "#{settings_base}/filterable-attributes").with { |req|
        body = JSON.parse(req.body)
        body.include?("kind") && body.include?("bundle_id")
      }
    end

    it "swallows and logs HTTP failures instead of raising" do
      stub_request(:post, documents_url).to_return(status: 500, body: "boom")
      stub_request(:post, documents_url).to_raise(StandardError.new("net down"))
      stub_request(:put, %r{#{Regexp.escape(settings_base)}/.+}).to_raise(StandardError.new("net down"))
      expect(Rails.logger).to receive(:warn).with(/GameIndexer.*upsert failed for game 7/)

      expect { described_class.call(game) }.not_to raise_error
    end
  end
end
