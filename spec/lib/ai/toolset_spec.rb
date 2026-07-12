# frozen_string_literal: true

require "rails_helper"

# Ai::Toolset is a pure projection over Pito::Mcp::Registry.tools (renaming
# inputSchema → input_schema, dropping annotations — the AI wires don't take
# them) PLUS the two terminal tools (pito_render_command / pito_respond) that
# end the orchestrator's loop. Nothing here is memoized — every call re-reads
# the Registry, which itself mirrors config/pito/tools.yml.
RSpec.describe Ai::Toolset do
  describe ".tools" do
    subject(:tools) { described_class.tools }

    it "includes every Pito::Mcp::Registry tool with name/description passed through" do
      registry_tools = Pito::Mcp::Registry.tools

      registry_tools.each do |registry_tool|
        wire_tool = tools.find { |t| t[:name] == registry_tool[:name] }

        expect(wire_tool).not_to be_nil
        expect(wire_tool[:description]).to eq(registry_tool[:description])
      end
    end

    it "renames inputSchema to input_schema for every Registry tool" do
      registry_tools = Pito::Mcp::Registry.tools

      registry_tools.each do |registry_tool|
        wire_tool = tools.find { |t| t[:name] == registry_tool[:name] }

        expect(wire_tool[:input_schema]).to eq(registry_tool[:inputSchema])
      end
    end

    it "drops the annotations key from every Registry-derived tool" do
      registry_names = Pito::Mcp::Registry.tools.map { |t| t[:name] }

      tools.each do |tool|
        next unless registry_names.include?(tool[:name])

        expect(tool).not_to have_key(:annotations)
      end
    end

    it "ends with the two terminal tools, in order: pito_render_command then pito_respond" do
      expect(tools.last(2).map { |t| t[:name] }).to eq(%w[pito_render_command pito_respond])
    end

    describe "the pito_render_command terminal" do
      subject(:tool) { tools.find { |t| t[:name] == "pito_render_command" } }

      it "requires a string command with additionalProperties disabled" do
        expect(tool[:input_schema]).to include(
          "type" => "object",
          "additionalProperties" => false,
          "required" => [ "command" ]
        )
        expect(tool[:input_schema]["properties"]["command"]).to include("type" => "string")
      end
    end

    describe "the pito_respond terminal" do
      subject(:tool) { tools.find { |t| t[:name] == "pito_respond" } }

      it "requires a blocks array of 1..12 items" do
        schema = tool[:input_schema]

        expect(schema).to include("type" => "object", "additionalProperties" => false, "required" => [ "blocks" ])
        expect(schema["properties"]["blocks"]).to include(
          "type" => "array",
          "minItems" => 1,
          "maxItems" => 12
        )
      end

      it "enumerates the nine block kinds on the blocks item type" do
        item_type_enum = tool[:input_schema]["properties"]["blocks"]["items"]["properties"]["type"]["enum"]

        expect(item_type_enum).to contain_exactly(
          "text", "kv_table", "table", "media", "sparkline", "chart", "score", "ttb", "suggestion"
        )
      end

      it "embeds the per-type key documentation in the description" do
        expect(tool[:description]).to include("kv_table")
        expect(tool[:description]).to include("suggestion")
        expect(tool[:description]).to include("sparkline")
      end
    end
  end

  describe "the web tool pair (P14 — per-message opt-in, never MCP)" do
    it "is absent from the default toolset even when search is configured" do
      allow(Ai::Web::Search).to receive(:configured?).and_return(true)

      names = described_class.tools.map { |t| t[:name] }

      expect(names).not_to include("web_search", "web_fetch")
    end

    it "carries both tools on tools(web: true) when search is configured, ahead of the terminals" do
      allow(Ai::Web::Search).to receive(:configured?).and_return(true)

      tools = described_class.tools(web: true)
      search = tools.find { |t| t[:name] == "web_search" }
      fetch  = tools.find { |t| t[:name] == "web_fetch" }

      expect(search[:input_schema]["required"]).to eq([ "query" ])
      expect(fetch[:input_schema]["required"]).to eq([ "url" ])
      expect(tools.last(2).map { |t| t[:name] }).to eq(%w[pito_render_command pito_respond])
    end

    it "carries neither tool on tools(web: true) when search is unconfigured" do
      allow(Ai::Web::Search).to receive(:configured?).and_return(false)

      names = described_class.tools(web: true).map { |t| t[:name] }

      expect(names).not_to include("web_search", "web_fetch")
    end

    it "never registers the web tools in Pito::Mcp::Registry" do
      expect(Pito::Mcp::Registry.tool_names).not_to include("web_search", "web_fetch")
    end
  end

  describe ".terminal?" do
    it "is true for pito_render_command" do
      expect(described_class.terminal?("pito_render_command")).to be(true)
    end

    it "is true for pito_respond" do
      expect(described_class.terminal?("pito_respond")).to be(true)
    end

    it "accepts a symbol name" do
      expect(described_class.terminal?(:pito_render_command)).to be(true)
      expect(described_class.terminal?(:pito_respond)).to be(true)
    end

    it "is false for a real Registry tool name" do
      expect(described_class.terminal?("pito_show")).to be(false)
    end

    it "is false for an unknown tool name" do
      expect(described_class.terminal?("pito_bogus")).to be(false)
    end
  end

  describe ".tool_names" do
    it "equals the names of .tools, in order" do
      expect(described_class.tool_names).to eq(described_class.tools.map { |t| t[:name] })
    end

    it "ends with the two terminal names" do
      expect(described_class.tool_names.last(2)).to eq(%w[pito_render_command pito_respond])
    end
  end

  describe "no memoization" do
    it "reflects an immediate Pito::Mcp::Registry.tools change with no restart" do
      fake_tools = [
        { name: "pito_fake", description: "A fake tool for the memoization proof.",
         inputSchema: { "type" => "object", "properties" => {}, "additionalProperties" => false },
         annotations: { "readOnlyHint" => true } }
      ]

      allow(Pito::Mcp::Registry).to receive(:tools).and_return(fake_tools)

      expect(described_class.tool_names).to eq(%w[pito_fake pito_render_command pito_respond])
      expect(described_class.tools.first).to eq(
        name: "pito_fake",
        description: "A fake tool for the memoization proof.",
        input_schema: { "type" => "object", "properties" => {}, "additionalProperties" => false }
      )

      allow(Pito::Mcp::Registry).to receive(:tools).and_call_original

      expect(described_class.tool_names).not_to include("pito_fake")
    end
  end

  describe "constants" do
    it "RENDER_COMMAND is the render-command terminal tool name" do
      expect(described_class::RENDER_COMMAND).to eq("pito_render_command")
    end

    it "RESPOND is the respond terminal tool name" do
      expect(described_class::RESPOND).to eq("pito_respond")
    end
  end
end
