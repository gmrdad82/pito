# frozen_string_literal: true

require "rails_helper"

# Contract for Pito::Mcp::Executor — the read-only tool runner. Grammar-string
# construction is unit-tested (pure); dispatch is integration-tested through the
# REAL Router with factory records, proving (a) the built string routes to the
# right verb and projects to markdown, and (b) NOTHING is persisted.
RSpec.describe Pito::Mcp::Executor do
  def descriptor(tool) = Pito::Mcp::Registry.tool(tool)

  # ── grammar-string construction (pure) ───────────────────────────────────────
  describe ".build_input" do
    it "interpolates required params inline" do
      expect(described_class.build_input(descriptor("pito_show"), { "noun" => "game", "ref" => "3" }))
        .to eq("show game 3")
    end

    it "appends an input_suffix clause with a comma-joined array" do
      expect(described_class.build_input(descriptor("pito_show"),
                                         { "noun" => "game", "ref" => "3", "segments" => %w[similar videos] }))
        .to eq("show game 3 with similar, videos")
    end

    it "builds the full list grammar: ids, columns (comma), and sort" do
      expect(described_class.build_input(descriptor("pito_list"),
                                         { "noun" => "games", "ids" => [ 2, 4, 5 ],
                                           "columns" => %w[platform genre], "sort" => "price desc" }))
        .to eq("list games 2, 4, 5 with platform, genre sort price desc")
    end

    it "omits absent optional clauses" do
      expect(described_class.build_input(descriptor("pito_list"), { "noun" => "channels" }))
        .to eq("list channels")
    end

    it "does NOT interpolate a Router-forwarded param (period) into the grammar" do
      expect(described_class.build_input(descriptor("pito_analyze"),
                                         { "noun" => "game", "ref" => "3", "period" => "28d" }))
        .to eq("analyze game 3")
    end
  end

  describe ".router_kwargs" do
    it "forwards `period` to Router.call as a keyword" do
      expect(described_class.router_kwargs(descriptor("pito_analyze"),
                                           { "noun" => "game", "ref" => "3", "period" => "28d" }))
        .to eq(period: "28d")
    end

    it "is empty when no forwardable param is present" do
      expect(described_class.router_kwargs(descriptor("pito_show"), { "noun" => "game", "ref" => "3" }))
        .to eq({})
    end
  end

  # ── validation ────────────────────────────────────────────────────────────────
  describe "required-argument validation" do
    it "returns an is_error result naming the missing argument" do
      result = described_class.call(tool: "pito_show", arguments: { "noun" => "game" })
      expect(result.is_error).to be(true)
      expect(result.text).to match(/Missing required argument: ref/)
    end

    it "does not dispatch when a required argument is missing" do
      expect(Pito::Dispatch::Router).not_to receive(:call)
      described_class.call(tool: "pito_show", arguments: { "noun" => "game" })
    end
  end

  describe "unknown tool" do
    it "raises UnknownTool" do
      expect { described_class.call(tool: "pito_nope", arguments: {}) }
        .to raise_error(Pito::Mcp::Executor::UnknownTool, "pito_nope")
    end
  end

  describe "reader tools" do
    it "delegates a reader tool to Pito::Mcp::Readers and returns a Result" do
      result = described_class.call(tool: "pito_conversations", arguments: {})
      expect(result).to be_a(Pito::Mcp::Executor::Result)
      expect(result.is_error).to be(false)
    end
  end

  # ── dispatch through the real Router ─────────────────────────────────────────
  describe "verb dispatch (integration)" do
    it "runs pito_list and projects the library as a markdown table" do
      game = create(:game, title: "Hollow Knight")

      result = described_class.call(tool: "pito_list", arguments: { "noun" => "games" })

      expect(result.is_error).to be(false)
      expect(result.text).to include("| ", "Hollow Knight")
    end

    it "runs pito_show and projects the detail card as de-HTML'd text" do
      game = create(:game, title: "Celeste")

      result = described_class.call(tool: "pito_show", arguments: { "noun" => "game", "ref" => game.id.to_s })

      expect(result.is_error).to be(false)
      expect(result.text).to include("Celeste")
      expect(result.text).not_to include("<")
    end

    it "surfaces a not-found ref as rendered copy (Result::Ok, not an error)" do
      result = described_class.call(tool: "pito_show", arguments: { "noun" => "game", "ref" => "999999" })

      expect(result.is_error).to be(false)          # game_not_found returns Result::Ok
      expect(result.text).to be_present
    end

    it "runs pito_glance and inline-computes the pending scalars (no 'pending' leaks out)" do
      game   = create(:game)
      scalars = Pito::Analytics::Scalars::Result.new(
        metrics: { views: { current: 1234, previous: nil }, likes: { current: 89, previous: nil } },
        label: "lifetime", comparable: false
      )
      allow(Pito::Analytics::Scalars).to receive(:for).and_return(scalars)

      result = described_class.call(tool: "pito_glance", arguments: { "noun" => "game", "ref" => game.id.to_s })

      expect(result.is_error).to be(false)
      expect(result.text).to include("- views: 1234")
      expect(result.text).not_to match(/pending/i)
    end
  end

  # ── the non-persistence invariant ─────────────────────────────────────────────
  describe "READ-ONLY: nothing is persisted" do
    before { create(:game) }

    it "adds no Event when running a tool" do
      expect { described_class.call(tool: "pito_list", arguments: { "noun" => "games" }) }
        .not_to change(Event, :count)
    end

    it "adds no Turn when running a tool" do
      expect { described_class.call(tool: "pito_list", arguments: { "noun" => "games" }) }
        .not_to change(Turn, :count)
    end

    it "dispatches against the mcp anchor and leaves it empty (source-separated)" do
      described_class.call(tool: "pito_list", arguments: { "noun" => "games" })
      anchor = Conversation.mcp_anchor
      expect(anchor.source).to eq("mcp")
      expect(anchor.events).to be_empty
    end
  end
end
