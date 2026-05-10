require "rails_helper"
require Rails.root.join("app/mcp/resources/mcp_doc")

# `Mcp::Resources::McpDoc` exposes `docs/mcp.md` at `pito://mcp`. Unlike
# `DesignDoc`, this resource has a graceful fallback when the file is
# missing — it returns a text/plain "mcp.md not found" entry.
RSpec.describe Mcp::Resources::McpDoc do
  describe "URI_PREFIX" do
    it "is pito://mcp" do
      expect(described_class::URI_PREFIX).to eq("pito://mcp")
    end
  end

  describe ".definitions" do
    it "returns a single MCP::Resource at the URI prefix" do
      defs = described_class.definitions
      expect(defs.size).to eq(1)
      expect(defs.first.uri).to eq("pito://mcp")
    end

    it "advertises text/markdown mime type" do
      expect(described_class.definitions.first.mime_type).to eq("text/markdown")
    end
  end

  describe ".handles?" do
    it "matches the exact URI" do
      expect(described_class.handles?("pito://mcp")).to be(true)
    end

    it "rejects unrelated URIs" do
      expect(described_class.handles?("pito://design")).to be(false)
      expect(described_class.handles?("pito://mcp/extra")).to be(false)
    end
  end

  describe ".read" do
    context "when docs/mcp.md exists" do
      it "returns the file contents as text/markdown" do
        out = described_class.read("pito://mcp")
        expect(out.size).to eq(1)
        expect(out.first[:uri]).to eq("pito://mcp")
        expect(out.first[:mimeType]).to eq("text/markdown")
        expect(out.first[:text]).to be_a(String)
        expect(out.first[:text].length).to be > 0
      end
    end

    context "when docs/mcp.md is missing" do
      it "returns a text/plain 'not found' fallback (no raise)" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?)
          .with(Rails.root.join("docs/mcp.md"))
          .and_return(false)

        out = described_class.read("pito://mcp")
        expect(out.first[:mimeType]).to eq("text/plain")
        expect(out.first[:text]).to eq("mcp.md not found")
        expect(out.first[:uri]).to eq("pito://mcp")
      end
    end
  end
end
