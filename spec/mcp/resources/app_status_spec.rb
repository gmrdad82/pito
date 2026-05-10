require "rails_helper"
require Rails.root.join("app/mcp/resources/app_status")

# `Mcp::Resources::AppStatus` aggregates pito-wide health into the
# `pito://status` resource: counts (channels / videos / saved views),
# search engine health (with rescue → false / {}), and the live
# AppSetting trio (max_panes, pane_title_length, theme).
RSpec.describe Mcp::Resources::AppStatus do
  describe "URI_PREFIX" do
    it "is pito://status" do
      expect(described_class::URI_PREFIX).to eq("pito://status")
    end
  end

  describe ".definitions" do
    it "returns a single MCP::Resource pointing at the URI prefix" do
      defs = described_class.definitions
      expect(defs.size).to eq(1)
      expect(defs.first.uri).to eq("pito://status")
    end

    it "advertises application/json mime type" do
      mime = described_class.definitions.first.mime_type
      expect(mime).to eq("application/json")
    end
  end

  describe ".handles?" do
    it "returns true for the canonical URI" do
      expect(described_class.handles?("pito://status")).to be(true)
    end

    it "returns false for any other URI" do
      expect(described_class.handles?("pito://design")).to be(false)
      expect(described_class.handles?("pito://status/extra")).to be(false)
      expect(described_class.handles?("")).to be(false)
    end
  end

  describe ".read" do
    let(:fake_engine) do
      Class.new do
        def healthy?; true; end
        def index_stats; { "videos" => 5 }; end
      end.new
    end

    before { allow(Search).to receive(:engine).and_return(fake_engine) }

    it "returns one entry stamped with the request URI" do
      out = described_class.read("pito://status")
      expect(out.size).to eq(1)
      expect(out.first[:uri]).to eq("pito://status")
      expect(out.first[:mimeType]).to eq("application/json")
    end

    it "encodes a JSON payload with version + counts + search health" do
      create(:channel)
      create(:channel, :connected)
      out = described_class.read("pito://status")
      payload = JSON.parse(out.first[:text])

      expect(payload["channels"]).to eq(2)
      expect(payload["connected_channels"]).to eq(1)
      expect(payload).to have_key("videos")
      expect(payload).to have_key("video_stats_entries")
      expect(payload).to have_key("saved_views")
      expect(payload["search_healthy"]).to eq("yes")
      expect(payload["search_stats"]).to eq("videos" => 5)
      expect(payload["version"]).to be_a(String)
    end

    it "serializes search_healthy as 'no' when the engine reports unhealthy" do
      bad = Class.new do
        def healthy?; false; end
        def index_stats; {}; end
      end.new
      allow(Search).to receive(:engine).and_return(bad)

      out = described_class.read("pito://status")
      payload = JSON.parse(out.first[:text])
      expect(payload["search_healthy"]).to eq("no")
    end

    it "rescues a search-health raise to 'no' (defense-in-depth)" do
      raiser = Class.new do
        def healthy?; raise "search down"; end
        def index_stats; raise "search down"; end
      end.new
      allow(Search).to receive(:engine).and_return(raiser)

      out = described_class.read("pito://status")
      payload = JSON.parse(out.first[:text])
      expect(payload["search_healthy"]).to eq("no")
      expect(payload["search_stats"]).to eq({})
    end

    it "uses '(default: ...)' placeholders when AppSetting rows are absent" do
      AppSetting.where(key: %w[max_panes pane_title_length theme]).destroy_all

      out = described_class.read("pito://status")
      payload = JSON.parse(out.first[:text])

      expect(payload["settings"]["max_panes"]).to eq("(default: 3)")
      expect(payload["settings"]["pane_title_length"]).to eq("(default: 14)")
      expect(payload["settings"]["theme"]).to eq("auto")
    end

    it "surfaces concrete AppSetting values when present" do
      AppSetting.set("max_panes", "5")
      AppSetting.set("pane_title_length", "20")
      AppSetting.set("theme", "dark")

      out = described_class.read("pito://status")
      payload = JSON.parse(out.first[:text])

      expect(payload["settings"]["max_panes"]).to eq("5")
      expect(payload["settings"]["pane_title_length"]).to eq("20")
      expect(payload["settings"]["theme"]).to eq("dark")
    end

    it "returns a text/plain error payload when the read fundamentally fails" do
      allow(Channel).to receive(:count).and_raise(StandardError, "db down")

      out = described_class.read("pito://status")
      expect(out.first[:mimeType]).to eq("text/plain")
      expect(out.first[:text]).to include("error reading status")
      expect(out.first[:text]).to include("db down")
    end
  end
end
