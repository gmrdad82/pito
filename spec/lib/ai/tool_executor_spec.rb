# frozen_string_literal: true

require "rails_helper"

# Ai::ToolExecutor is the raise-safe boundary around ONE Pito::Mcp::Executor
# call mid-loop: unknown names (including the two terminal tool names, which
# are intercepted upstream and never reach the Registry) short-circuit before
# the Executor is ever invoked, a real call's Result is projected to the plain
# { content:, error: } shape the orchestrator wants, and ANY raise from the
# Executor is rescued + logged rather than bubbling into the orchestrator loop.
RSpec.describe Ai::ToolExecutor do
  describe "unknown tool" do
    it "names the tool and lists the registry's tool names, without calling the Executor" do
      expect(Pito::Mcp::Executor).not_to receive(:call)

      result = described_class.call(name: "pito_bogus", arguments: {})

      expect(result[:error]).to be(true)
      expect(result[:content]).to include("pito_bogus")
      Pito::Mcp::Registry.tool_names.each { |name| expect(result[:content]).to include(name) }
    end

    it "falls through the unknown-tool branch for the two terminal names (not MCP Registry tools)" do
      expect(Pito::Mcp::Executor).not_to receive(:call)

      %w[pito_render_command pito_respond].each do |name|
        result = described_class.call(name: name, arguments: {})
        expect(result[:error]).to be(true)
        expect(result[:content]).to include(name)
      end
    end
  end

  describe "known tool happy path" do
    it "returns the Result's text uninverted as content: with error: false" do
      allow(Pito::Mcp::Executor).to receive(:call)
        .and_return(Pito::Mcp::Executor::Result.new(text: "some markdown", is_error: false))

      result = described_class.call(name: "pito_show", arguments: { "noun" => "vids" })

      expect(result).to eq({ content: "some markdown", error: false })
      expect(Pito::Mcp::Executor).to have_received(:call).with(tool: "pito_show", arguments: { "noun" => "vids" })
    end

    it "passes nil arguments through to the Executor as {}" do
      allow(Pito::Mcp::Executor).to receive(:call)
        .and_return(Pito::Mcp::Executor::Result.new(text: "ok", is_error: false))

      described_class.call(name: "pito_show", arguments: nil)

      expect(Pito::Mcp::Executor).to have_received(:call).with(tool: "pito_show", arguments: {})
    end
  end

  describe "error result from the executor" do
    it "returns error: true with the Result's text as content" do
      allow(Pito::Mcp::Executor).to receive(:call)
        .and_return(Pito::Mcp::Executor::Result.new(text: "Missing required argument: ref.", is_error: true))

      result = described_class.call(name: "pito_show", arguments: { "noun" => "vids" })

      expect(result).to eq({ content: "Missing required argument: ref.", error: true })
    end
  end

  describe "web tools (P14 — routed to Ai::Web, never the MCP Executor)" do
    it "routes web_search to Ai::Web::Search and returns its result as JSON with error: false" do
      expect(Pito::Mcp::Executor).not_to receive(:call)
      allow(Ai::Web::Search).to receive(:call).and_return({ results: [] })

      result = described_class.call(name: "web_search", arguments: { "query" => "elden ring dlc date" })

      expect(Ai::Web::Search).to have_received(:call).with(query: "elden ring dlc date")
      expect(JSON.parse(result[:content])).to eq({ "results" => [] })
      expect(result[:error]).to be(false)
    end

    it "routes web_fetch to Ai::Web::Fetch and returns its result as JSON with error: false" do
      expect(Pito::Mcp::Executor).not_to receive(:call)
      allow(Ai::Web::Fetch).to receive(:call)
        .and_return({ title: "Some page", url: "https://example.com/page", text: "readable text" })

      result = described_class.call(name: "web_fetch", arguments: { "url" => "https://example.com/page" })

      expect(Ai::Web::Fetch).to have_received(:call).with(url: "https://example.com/page")
      expect(JSON.parse(result[:content]))
        .to eq({ "title" => "Some page", "url" => "https://example.com/page", "text" => "readable text" })
      expect(result[:error]).to be(false)
    end

    it "marks a web result carrying error: as error: true, still as JSON content" do
      expect(Pito::Mcp::Executor).not_to receive(:call)
      allow(Ai::Web::Search).to receive(:call).and_return({ error: "search failed (HTTP 500)" })

      result = described_class.call(name: "web_search", arguments: { "query" => "anything" })

      expect(result[:error]).to be(true)
      expect(JSON.parse(result[:content])).to eq({ "error" => "search failed (HTTP 500)" })
    end
  end

  describe "the executor raising" do
    it "rescues ANY StandardError, warns once, and never raises to the caller" do
      allow(Pito::Mcp::Executor).to receive(:call).and_raise(RuntimeError, "kaboom")
      allow(Rails.logger).to receive(:warn)

      result = nil
      expect { result = described_class.call(name: "pito_show", arguments: { "noun" => "vids" }) }.not_to raise_error

      expect(Rails.logger).to have_received(:warn).once
      expect(result[:error]).to be(true)
      expect(result[:content]).to include("pito_show", "kaboom")
    end
  end

  describe "REAL-collaborator sanity (no stubs)" do
    it "runs pito_conversations end to end without persisting any Event" do
      result = nil
      expect { result = described_class.call(name: "pito_conversations", arguments: {}) }
        .not_to change(Event, :count)

      expect(result[:error]).to be(false)
    end
  end
end
