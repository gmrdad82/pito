require "rails_helper"
require_relative "../../../app/mcp/tools/search_content"

# `Mcp::Tools::SearchContent` wraps Meilisearch (`Search.engine`) for
# the MCP `search` tool. The wire shape (consumed by the Rust client)
# is `{ query, videos: [SearchHit<Video>], video_total, took_ms }`.
# Hits whose backing Video row is missing are dropped — `record` is
# non-nullable in the Rust schema. Highlight payloads coerce to
# `HashMap<String, String>`.
RSpec.describe Mcp::Tools::SearchContent do
  let(:fake_engine) do
    instance_double("Search::MeilisearchEngine")
  end

  before { allow(Search).to receive(:engine).and_return(fake_engine) }

  def make_hit(record, highlights = {})
    { record: record, highlights: highlights }
  end

  describe ".call" do
    it "returns the wire shape for an empty result set" do
      allow(fake_engine).to receive(:search)
        .and_return(hits: [], total: 0, took_ms: 0.4)

      result = described_class.call(query: "anything")
      data = JSON.parse(result.content.first[:text])

      expect(data["query"]).to eq("anything")
      expect(data["videos"]).to eq([])
      expect(data["video_total"]).to eq(0)
      expect(data["took_ms"]).to be_a(Float)
    end

    it "decorates each hit's record via VideoDecorator#as_summary_json" do
      v = create(:video, title: "kf2 highlight")
      allow(fake_engine).to receive(:search)
        .and_return(hits: [ make_hit(v, "title" => "kf2 <mark>highlight</mark>") ],
                    total: 1, took_ms: 1.5)

      result = described_class.call(query: "highlight")
      data = JSON.parse(result.content.first[:text])

      expect(data["videos"].size).to eq(1)
      expect(data["videos"].first["record"]["id"]).to eq(v.id)
      expect(data["videos"].first["record"]["title"]).to eq("kf2 highlight")
      expect(data["videos"].first["highlights"]["title"]).to include("<mark>")
    end

    it "drops hits whose record is nil (Rust SearchHit::record is non-nullable)" do
      v = create(:video)
      allow(fake_engine).to receive(:search)
        .and_return(hits: [ make_hit(v), make_hit(nil) ], total: 2, took_ms: 1.0)

      result = described_class.call(query: "x")
      data = JSON.parse(result.content.first[:text])

      expect(data["videos"].size).to eq(1)
      expect(data["video_total"]).to eq(2) # total preserved even after filter
    end

    it "passes per_page = 20 by default and clamps it to [1, 50]" do
      allow(fake_engine).to receive(:search) do |_model, _q, page:, per_page:|
        @captured_per_page = per_page
        { hits: [], total: 0, took_ms: 0.0 }
      end

      described_class.call(query: "x")
      expect(@captured_per_page).to eq(20)
    end

    it "clamps per_page above 50 down to 50" do
      allow(fake_engine).to receive(:search) do |_model, _q, page:, per_page:|
        @captured_per_page = per_page
        { hits: [], total: 0, took_ms: 0.0 }
      end

      described_class.call(query: "x", per_page: 999)
      expect(@captured_per_page).to eq(50)
    end

    it "clamps per_page below 1 up to 1" do
      allow(fake_engine).to receive(:search) do |_model, _q, page:, per_page:|
        @captured_per_page = per_page
        { hits: [], total: 0, took_ms: 0.0 }
      end

      described_class.call(query: "x", per_page: 0)
      expect(@captured_per_page).to eq(1)
    end

    it "clamps page below 1 up to 1" do
      allow(fake_engine).to receive(:search) do |_model, _q, page:, per_page:|
        @captured_page = page
        { hits: [], total: 0, took_ms: 0.0 }
      end

      described_class.call(query: "x", page: 0)
      expect(@captured_page).to eq(1)
    end

    it "passes the query verbatim to the engine" do
      allow(fake_engine).to receive(:search) do |_model, q, **|
        @captured_q = q
        { hits: [], total: 0, took_ms: 0.0 }
      end

      described_class.call(query: "let's go")
      expect(@captured_q).to eq("let's go")
    end

    it "returns a structured error response when the engine raises" do
      allow(fake_engine).to receive(:search).and_raise(StandardError, "search down")

      result = described_class.call(query: "x")
      expect(result.to_h[:isError]).to be(true)
      expect(result.content.first[:text]).to include("search error: search down")
    end

    it "rejects unauthenticated callers (insufficient_scope)" do
      Current.token = nil
      result = described_class.call(query: "x")
      expect(result.to_h[:isError]).to be(true)
      payload = JSON.parse(result.content.first[:text])
      expect(payload["error"]).to eq("insufficient_scope")
      expect(payload["required"]).to eq(Scopes::APP)
    end

    it "rejects dev-only tokens (insufficient_scope: app)" do
      user = User.first || create(:user)
      record, _plaintext = ApiToken.generate!(user: user, name: "dev", scopes: [ Scopes::DEV ])
      Current.token = record

      result = described_class.call(query: "x")
      expect(result.to_h[:isError]).to be(true)
      payload = JSON.parse(result.content.first[:text])
      expect(payload["error"]).to eq("insufficient_scope")
    end
  end

  describe ".stringify_highlights" do
    it "returns {} when raw is nil" do
      expect(described_class.stringify_highlights(nil)).to eq({})
    end

    it "returns {} when raw is not a Hash" do
      expect(described_class.stringify_highlights("oops")).to eq({})
      expect(described_class.stringify_highlights([])).to eq({})
    end

    it "passes string values through unchanged" do
      expect(described_class.stringify_highlights("title" => "hi"))
        .to eq("title" => "hi")
    end

    it "joins array values with ', '" do
      expect(described_class.stringify_highlights("tags" => %w[a b c]))
        .to eq("tags" => "a, b, c")
    end

    it "stringifies non-string scalar values" do
      expect(described_class.stringify_highlights("n" => 42))
        .to eq("n" => "42")
    end

    it "coerces symbol keys to strings" do
      expect(described_class.stringify_highlights(title: "hi"))
        .to eq("title" => "hi")
    end
  end

  describe "input_schema" do
    it "requires a query string" do
      schema = described_class.input_schema.to_h
      required = schema[:required] || schema["required"]
      expect(required.map(&:to_s)).to include("query")
    end

    it "advertises page and per_page as integers" do
      schema = described_class.input_schema.to_h
      props = schema[:properties] || schema["properties"]
      expect((props[:page] || props["page"])[:type] || (props[:page] || props["page"])["type"]).to eq("integer")
      expect((props[:per_page] || props["per_page"])[:type] || (props[:per_page] || props["per_page"])["type"]).to eq("integer")
    end
  end
end
