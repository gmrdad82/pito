require "rails_helper"

# Phase 34 (2026-05-18) — Meilisearch::BundleIndexer surface coverage.
#
# Coverage priorities (per lane C dispatch):
#   - POSTs to /indexes/games_test/documents with `?primaryKey=id` (DR
#     follow-up #2 — same primary key as Game docs, shared physical index)
#   - Document id is `"bundle_<id>"` (underscore — DR follow-up #2 fix;
#     `bundle:` colon variant was rejected by Meilisearch)
#   - `kind: "bundle"` discriminator
#   - Aggregated summary text built from up to 5 member-game summaries
#   - Optional `_vectors.default` from explicit embedding override or
#     persisted `summary_embedding` column
#   - Swallow + log on network failure
RSpec.describe Meilisearch::BundleIndexer do
  let(:meili_url) { "http://127.0.0.1:7727" }
  let(:index_name) { "games_test" }
  let(:documents_url) { "#{meili_url}/indexes/#{index_name}/documents?primaryKey=id" }

  let(:member1) { double(summary: "Summary one.") }
  let(:member2) { double(summary: "Summary two.") }
  let(:member3) { double(summary: "Summary three.") }
  let(:member4) { double(summary: "Summary four.") }
  let(:member5) { double(summary: "Summary five.") }
  let(:member6) { double(summary: "Summary six (excluded).") }

  let(:bundle) do
    build_stubbed(:bundle, id: 42, name: "Test Bundle").tap do |b|
      allow(b).to receive(:games).and_return([ member1, member2 ])
      # `summary_embedding` is defined on Bundle via `has_neighbors`,
      # but `build_stubbed` returns nil; force the no-vector branch
      # unless an example opts in explicitly.
      allow(b).to receive(:summary_embedding).and_return(nil)
    end
  end

  before do
    stub_request(:post, documents_url).to_return(status: 202, body: "{}")
  end

  describe ".call" do
    it "POSTs to /indexes/games_test/documents with `?primaryKey=id` (matches Game index)" do
      described_class.call(bundle)
      expect(WebMock).to have_requested(:post, documents_url).once
    end

    it "sends the document body as a JSON array of one element" do
      described_class.call(bundle)
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        body = JSON.parse(req.body)
        body.is_a?(Array) && body.size == 1
      }
    end

    it "namespaces the document id as `bundle_<id>` (underscore, not colon)" do
      described_class.call(bundle)
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        doc = JSON.parse(req.body).first
        doc["id"] == "bundle_42"
      }
    end

    it "sets the `kind` discriminator to \"bundle\"" do
      described_class.call(bundle)
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        JSON.parse(req.body).first["kind"] == "bundle"
      }
    end

    it "stores the raw integer bundle id as `bundle_id` for filtering" do
      described_class.call(bundle)
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        JSON.parse(req.body).first["bundle_id"] == 42
      }
    end

    it "uses the bundle name as the searchable title" do
      described_class.call(bundle)
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        JSON.parse(req.body).first["title"] == "Test Bundle"
      }
    end

    it "records the member count as `game_count`" do
      described_class.call(bundle)
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        JSON.parse(req.body).first["game_count"] == 2
      }
    end

    it "aggregates the summary from member games (em-dash joined)" do
      described_class.call(bundle)
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        JSON.parse(req.body).first["summary"] == "Summary one. — Summary two."
      }
    end

    it "caps the aggregated summary at the first 5 member games" do
      allow(bundle).to receive(:games).and_return(
        [ member1, member2, member3, member4, member5, member6 ]
      )
      described_class.call(bundle)
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        summary = JSON.parse(req.body).first["summary"]
        summary.include?("Summary five.") && !summary.include?("Summary six")
      }
    end

    it "drops nil / blank summaries before joining" do
      blank_member = double(summary: "")
      nil_member = double(summary: nil)
      allow(bundle).to receive(:games).and_return([ member1, blank_member, nil_member, member2 ])
      described_class.call(bundle)
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        JSON.parse(req.body).first["summary"] == "Summary one. — Summary two."
      }
    end

    it "omits _vectors when neither explicit embedding nor persisted column is present" do
      described_class.call(bundle)
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        !JSON.parse(req.body).first.key?("_vectors")
      }
    end

    it "attaches _vectors.default from the explicit embedding override" do
      described_class.call(bundle, embedding: [ 0.7, 0.8, 0.9 ])
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        JSON.parse(req.body).first.dig("_vectors", "default") == [ 0.7, 0.8, 0.9 ]
      }
    end

    it "falls back to the persisted summary_embedding column when no override" do
      allow(bundle).to receive(:summary_embedding).and_return([ 0.1, 0.2, 0.3 ])

      described_class.call(bundle)
      expect(WebMock).to have_requested(:post, documents_url).with { |req|
        JSON.parse(req.body).first.dig("_vectors", "default") == [ 0.1, 0.2, 0.3 ]
      }
    end

    it "swallows and logs HTTP failures instead of raising" do
      stub_request(:post, documents_url).to_raise(StandardError.new("net down"))
      expect(Rails.logger).to receive(:warn).with(/BundleIndexer.*upsert failed for bundle 42/)

      expect { described_class.call(bundle) }.not_to raise_error
    end
  end
end
