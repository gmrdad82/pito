require "rails_helper"

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
      let(:channel) { create(:channel, title: "code kitchen") }
      let(:video) { create(:video, channel: channel, title: "rails tutorial") }

      before { channel; video }

      it "returns channel results" do
        channel_hits = {
          hits: [ { id: channel.id, record: channel, highlights: { "title" => "<mark>code</mark> kitchen" }, score: nil } ],
          total: 1, took_ms: 2.5
        }
        allow(engine).to receive(:search).and_return(channel_hits, empty_results)

        get search_path, params: { q: "code" }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("<mark>code</mark> kitchen")
        expect(response.body).to include("1 channel")
      end

      it "returns video results" do
        video_hits = {
          hits: [ { id: video.id, record: video, highlights: { "title" => "<mark>rails</mark> tutorial" }, score: nil } ],
          total: 1, took_ms: 1.3
        }
        allow(engine).to receive(:search).and_return(empty_results, video_hits)

        get search_path, params: { q: "rails" }
        expect(response.body).to include("<mark>rails</mark> tutorial")
        expect(response.body).to include("1 video")
      end

      it "shows no results message" do
        allow(engine).to receive(:search).and_return(empty_results)

        get search_path, params: { q: "nonexistent" }
        expect(response.body).to include("no results found")
      end

      it "preserves query in search input" do
        allow(engine).to receive(:search).and_return(empty_results)

        get search_path, params: { q: "test query" }
        expect(response.body).to include('value="test query"')
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
      it "returns JSON" do
        allow(engine).to receive(:search).and_return(empty_results)

        get search_path, params: { q: "test" }, as: :json
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json["query"]).to eq("test")
        expect(json).to have_key("channels")
        expect(json).to have_key("videos")
        expect(json["channels"]).to have_key("total")
        expect(json["videos"]).to have_key("total")
      end
    end
  end
end
