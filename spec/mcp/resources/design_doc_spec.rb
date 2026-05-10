require "rails_helper"
require Rails.root.join("app/mcp/resources/design_doc")

# `Mcp::Resources::DesignDoc` exposes `docs/design.md` at
# `pito://design`. Unlike `McpDoc`, it has no fallback — if the file
# is missing, `read` raises (the file is checked into the repo).
RSpec.describe Mcp::Resources::DesignDoc do
  describe "URI_PREFIX" do
    it "is pito://design" do
      expect(described_class::URI_PREFIX).to eq("pito://design")
    end
  end

  describe ".definitions" do
    it "returns a single MCP::Resource at the URI prefix" do
      defs = described_class.definitions
      expect(defs.size).to eq(1)
      expect(defs.first.uri).to eq("pito://design")
    end

    it "advertises text/markdown mime type" do
      expect(described_class.definitions.first.mime_type).to eq("text/markdown")
    end

    it "names the resource 'design system'" do
      expect(described_class.definitions.first.name).to eq("design system")
    end
  end

  describe ".handles?" do
    it "matches the exact URI" do
      expect(described_class.handles?("pito://design")).to be(true)
    end

    it "rejects anything else" do
      expect(described_class.handles?("pito://design/v2")).to be(false)
      expect(described_class.handles?("pito://status")).to be(false)
      expect(described_class.handles?("")).to be(false)
    end
  end

  describe ".read" do
    it "returns the on-disk docs/design.md content" do
      out = described_class.read("pito://design")
      expect(out.size).to eq(1)
      expect(out.first[:uri]).to eq("pito://design")
      expect(out.first[:mimeType]).to eq("text/markdown")
      expect(out.first[:text]).to be_a(String)
      expect(out.first[:text].length).to be > 0
    end

    it "stamps the returned URI with the requested URI verbatim" do
      out = described_class.read("pito://design")
      expect(out.first[:uri]).to eq("pito://design")
    end

    it "raises Errno::ENOENT when docs/design.md is missing (no fallback)" do
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read)
        .with(Rails.root.join("docs/design.md"))
        .and_raise(Errno::ENOENT)

      expect {
        described_class.read("pito://design")
      }.to raise_error(Errno::ENOENT)
    end
  end
end
