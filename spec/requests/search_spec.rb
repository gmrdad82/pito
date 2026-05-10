require "rails_helper"

# Phase 7 Path A2 (literal full retract). Video search is stubbed:
# Video declares no `searchable :*` / `filterable :*` lines, so the
# Meilisearch index for videos contains only `id` and the surface
# returns zero matches until Phase 8+ rebuilds metadata caching.
# These specs assert the surface remains functional (renders the page,
# returns JSON in the post-A2 shape) — they do NOT exercise actual
# match/highlight rendering, since there is no metadata to match on.
RSpec.describe "Search", type: :request do
  let(:engine) { double("search_engine") }
  let(:empty_results) { { hits: [], total: 0, took_ms: 0.1 } }

  before do
    Search.reset_engine!
    allow(Search).to receive(:engine).and_return(engine)
  end

  after do
    Search.reset_engine!
  end

  describe "GET /search" do
    context "without a query" do
      it "returns 200" do
        get search_path
        expect(response).to have_http_status(:ok)
      end

      it "shows empty state" do
        get search_path
        expect(response.body).to include("enter a search query")
      end

      it "does not call the search engine" do
        expect(engine).not_to receive(:search)
        get search_path
      end
    end

    context "with a query" do
      it "renders the page and shows the post-A2 disabled-search caption" do
        allow(engine).to receive(:search).and_return(empty_results)

        get search_path, params: { q: "anything" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("video search is currently disabled")
      end

      # Phase 14 §1 polish (2026-05-10) — the navbar `<input value=…>`
      # was retired in favor of the `/`-keyed search modal, so this
      # spec now asserts the query string echoes back in the results
      # paragraph (`results for "<query>"`) instead of an input value.
      it "echoes the query back in the results paragraph" do
        allow(engine).to receive(:search).and_return(empty_results)

        get search_path, params: { q: "test query" }
        expect(response.body).to include('results for "test query"')
      end

      it "supports pagination" do
        allow(engine).to receive(:search).and_return(empty_results)

        get search_path, params: { q: "test", page: 2 }
        expect(response).to have_http_status(:ok)
      end

      it "shows timing info" do
        allow(engine).to receive(:search).and_return(empty_results)

        get search_path, params: { q: "test" }
        expect(response.body).to include("ms)")
      end
    end

    context "JSON format" do
      it "returns JSON in the flat shape pito-sh expects" do
        allow(engine).to receive(:search).and_return(empty_results)

        get search_path, params: { q: "test" }, as: :json
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["query"]).to eq("test")
        expect(json).to have_key("videos")
        expect(json["videos"]).to be_an(Array)
        expect(json).to have_key("video_total")
        expect(json).to have_key("took_ms")
        expect(json["video_total"]).to be_a(Integer)
        expect(json["took_ms"]).to be_a(Numeric)
      end

      it "does not include channels key" do
        allow(engine).to receive(:search).and_return(empty_results)

        get search_path, params: { q: "test" }, as: :json
        json = response.parsed_body
        expect(json).not_to have_key("channels")
      end

      it "drops hits whose backing Video row is missing (Rust record field is non-nullable)" do
        hits = {
          hits: [ { id: 99_999, record: nil, highlights: {}, score: nil } ],
          total: 1, took_ms: 0.5
        }
        allow(engine).to receive(:search).and_return(hits)

        get search_path, params: { q: "stale" }, as: :json
        json = response.parsed_body
        expect(json["videos"]).to eq([])
      end
    end
  end
end
