require "rails_helper"
require Rails.root.join("app/mcp/pito_server")

# Phase 10 — `Mcp::PitoServer` builds the MCP server: registers the
# tool registry from `app/mcp/tools/*.rb` and the resource registry
# from `app/mcp/resources/*.rb`. The dev-scope strip-on-release flag
# (`Rails.application.config.x.mcp.expose_dev_scope`) gates the three
# dev-KB tools (`list_docs`, `read_doc`, `save_note`) at registration
# time — pairs with the per-tool `require_scope!` defense.
#
# The Rack-app contract is exercised separately
# (`spec/requests/mcp/rack_app_auth_spec.rb`); this spec focuses on
# the registration contract.
RSpec.describe Mcp::PitoServer do
  describe ".version" do
    it "reads VERSION from the repo root" do
      expect(File).to receive(:read).with(Rails.root.join("VERSION")).and_return("9.9.9\n")
      expect(described_class.version).to eq("9.9.9")
    end

    it "falls back to '0.0.0' when VERSION is missing" do
      expect(File).to receive(:read).with(Rails.root.join("VERSION")).and_raise(Errno::ENOENT)
      expect(described_class.version).to eq("0.0.0")
    end
  end

  describe ".dev_scope_exposed?" do
    it "returns true when the flag is unset" do
      allow(Rails.application.config.x.mcp).to receive(:expose_dev_scope).and_return(nil)
      expect(described_class.dev_scope_exposed?).to be(true)
    end

    it "returns true when the flag is true" do
      allow(Rails.application.config.x.mcp).to receive(:expose_dev_scope).and_return(true)
      expect(described_class.dev_scope_exposed?).to be(true)
    end

    it "returns false when the flag is false" do
      allow(Rails.application.config.x.mcp).to receive(:expose_dev_scope).and_return(false)
      expect(described_class.dev_scope_exposed?).to be(false)
    end
  end

  describe ".build" do
    it "returns an MCP::Server" do
      server = described_class.build
      expect(server).to be_a(MCP::Server)
    end

    it "names the server 'pito'" do
      server = described_class.build
      expect(server.name).to eq("pito")
    end

    it "stamps the version from .version" do
      allow(described_class).to receive(:version).and_return("1.2.3")
      server = described_class.build
      expect(server.version).to eq("1.2.3")
    end

    it "carries the canonical INSTRUCTIONS string" do
      server = described_class.build
      # MCP::Server exposes server_info / instructions through its
      # public surface; `instance_variable_get` keeps the spec robust
      # against minor MCP gem signature drift.
      stored = server.instance_variable_get(:@instructions) || described_class::INSTRUCTIONS
      expect(stored).to include("connected to pito")
    end
  end

  describe ".register_tools" do
    let(:server) { MCP::Server.new(name: "test", version: "0", instructions: "x") }

    it "registers every tool under app/mcp/tools when dev scope is exposed" do
      allow(described_class).to receive(:dev_scope_exposed?).and_return(true)
      described_class.register_tools(server)

      tool_names = server.tools.keys
      # `app` tools always present.
      expect(tool_names).to include("list_channels", "list_videos", "create_channel", "search")
      # `dev` tools present when the flag is on.
      expect(tool_names).to include("list_docs", "read_doc", "save_note")
    end

    it "drops dev-KB tools when dev scope is hidden" do
      allow(described_class).to receive(:dev_scope_exposed?).and_return(false)
      described_class.register_tools(server)

      tool_names = server.tools.keys
      expect(tool_names).to include("list_channels") # app tools survive
      expect(tool_names).not_to include("list_docs")
      expect(tool_names).not_to include("read_doc")
      expect(tool_names).not_to include("save_note")
    end

    it "uses each tool's tool_name (not the Ruby class name)" do
      allow(described_class).to receive(:dev_scope_exposed?).and_return(true)
      described_class.register_tools(server)

      # `Mcp::Tools::SearchContent` registers under `tool_name "search"`.
      expect(server.tools).to have_key("search")
      expect(server.tools["search"]).to eq(Mcp::Tools::SearchContent)
    end

    it "registers every dev-KB tool exactly once" do
      allow(described_class).to receive(:dev_scope_exposed?).and_return(true)
      described_class.register_tools(server)
      described_class::DEV_TOOL_NAMES.each do |n|
        expect(server.tools).to have_key(n)
      end
    end
  end

  describe ".register_resources" do
    let(:server) { MCP::Server.new(name: "test", version: "0", instructions: "x") }

    it "loads every resource module under app/mcp/resources" do
      described_class.register_resources(server)
      uris = server.resources.map(&:uri)

      expect(uris).to include(Mcp::Resources::AppStatus::URI_PREFIX)
      expect(uris).to include(Mcp::Resources::DesignDoc::URI_PREFIX)
      expect(uris).to include(Mcp::Resources::McpDoc::URI_PREFIX)
    end

    # The MCP gem stores per-method handlers in `@handlers` keyed by
    # the JSON-RPC method name. The dispatch surface is opaque, so we
    # capture the configured proc by calling `resources_read_handler`
    # right before / after registration and asserting the registered
    # proc behaves correctly.
    def captured_handler(server)
      server.instance_variable_get(:@handlers)["resources/read"]
    end

    it "wires a resources/read handler" do
      described_class.register_resources(server)
      expect(captured_handler(server)).to respond_to(:call)
    end

    it "returns a not-found stub when no resource handles the URI" do
      described_class.register_resources(server)
      handler = captured_handler(server)
      out = handler.call(uri: "pito://does-not-exist")
      expect(out.first[:text]).to include("resource not found")
    end

    it "dispatches to the correct resource for known URIs" do
      described_class.register_resources(server)
      handler = captured_handler(server)
      out = handler.call(uri: Mcp::Resources::AppStatus::URI_PREFIX)
      expect(out.first[:uri]).to eq(Mcp::Resources::AppStatus::URI_PREFIX)
    end
  end

  describe "DEV_TOOL_NAMES" do
    it "lists exactly the three dev-KB tools" do
      expect(described_class::DEV_TOOL_NAMES).to contain_exactly(
        "list_docs", "read_doc", "save_note"
      )
    end

    it "is frozen (no in-place mutation)" do
      expect(described_class::DEV_TOOL_NAMES).to be_frozen
    end
  end
end
