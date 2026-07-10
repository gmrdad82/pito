# frozen_string_literal: true

require "rails_helper"

# Contract for Pito::Mcp::Registry — the projection of verbs.yml `mcp:` blocks +
# the top-level `mcp_readers:` into the MCP `tools/list` payload. Runs against the
# REAL config (no injection): the add-a-tool proof (T1.4) covers the config-only
# extensibility; this pins the shape of what the shipped ontology surfaces.
RSpec.describe Pito::Mcp::Registry do
  # The 11 verb-backed tools + 2 readers the plan declares (G130).
  VERB_TOOLS   = %w[
    pito_list pito_show pito_analyze pito_glance pito_videos pito_game_of_vid
    pito_similar pito_channels_of_game pito_breakdowns pito_shinies pito_games
  ].freeze
  READER_TOOLS = %w[pito_conversations pito_messages].freeze
  ALL_TOOLS    = (VERB_TOOLS + READER_TOOLS).sort.freeze

  describe ".tool_names" do
    it "is exactly the declared tools, name-sorted" do
      expect(Pito::Mcp::Registry.tool_names).to eq(ALL_TOOLS)
    end

    it "has no duplicate tool names" do
      names = Pito::Mcp::Registry.tool_names
      expect(names).to eq(names.uniq)
    end
  end

  describe ".tools" do
    subject(:tools) { Pito::Mcp::Registry.tools }

    it "returns one entry per declared tool" do
      expect(tools.map { |t| t[:name] }).to match_array(ALL_TOOLS)
    end

    it "gives every tool a non-empty description" do
      expect(tools).to all(include(description: a_string_matching(/\S/)))
    end

    it "gives every tool an object inputSchema with additionalProperties disabled" do
      tools.each do |tool|
        expect(tool[:inputSchema]).to include("type" => "object", "additionalProperties" => false)
        expect(tool[:inputSchema]["properties"]).to be_a(Hash)
      end
    end
  end

  describe "inputSchema derivation" do
    def schema_for(name)
      Pito::Mcp::Registry.tools.find { |t| t[:name] == name }[:inputSchema]
    end

    it "marks required params and omits optional ones from `required`" do
      schema = schema_for("pito_show")
      expect(schema["required"]).to contain_exactly("noun", "ref")
      expect(schema["properties"]).to have_key("segments") # optional → present in properties
    end

    it "omits `required` entirely when a tool has no required params" do
      # pito_analyze — every param optional (bare analyze = all channels).
      expect(schema_for("pito_analyze")).not_to have_key("required")
    end

    it "carries an enum through to the property schema" do
      expect(schema_for("pito_list")["properties"]["noun"])
        .to include("type" => "string", "enum" => %w[games vids channels])
    end

    it "nests `items` for an array param" do
      expect(schema_for("pito_list")["properties"]["ids"])
        .to include("type" => "array", "items" => { "type" => "integer" })
    end

    it "defaults an array param's items to string when unspecified" do
      expect(schema_for("pito_show")["properties"]["segments"])
        .to include("type" => "array", "items" => { "type" => "string" })
    end

    it "maps a param `hint` to the schema `description`" do
      expect(schema_for("pito_show")["properties"]["ref"]["description"])
        .to match(/numeric id/)
    end

    it "produces a valid no-arg object for a param-less reader" do
      expect(schema_for("pito_conversations"))
        .to eq("type" => "object", "properties" => {}, "additionalProperties" => false)
    end

    # U5 — a `capability:` param's description is enriched with the per-noun valid
    # tokens read live from Pito::Grammar::Capability (so the client can list-with-
    # columns instead of N pito_show calls, and never drifts from the grammar).
    describe "capability-derived param descriptions" do
      subject(:columns_desc) { schema_for("pito_list")["properties"]["columns"]["description"] }

      it "enumerates the valid columns per noun" do
        expect(columns_desc).to match(/games: platform, genre/)
        expect(columns_desc).to match(/vids: channel, visibility.*publish_at/)
        expect(columns_desc).to match(/channels: subs, views, vids, likes/)
      end

      it "enumerates the toggle filters per noun on the filter param" do
        filter_desc = schema_for("pito_list")["properties"]["filter"]["description"]
        expect(filter_desc).to match(/games: upcoming/)
        expect(filter_desc).to match(/vids: published, unlisted, scheduled/)
        # vids filters carry no `vocabulary:` — their tokens are already literal,
        # so nothing to expand; pin the noun's list is exactly this and no more.
        expect(filter_desc).to end_with("vids: published, unlisted, scheduled.")
      end

      # capability_tokens' `filters` branch now expands each filter through
      # Pito::Grammar::Capability.filter_tokens — a vocabulary-backed filter
      # (games genre/platform) enumerates the REAL values a client can pass
      # (vocabulary members + synonyms, downcased), not the bare category name,
      # which the chat grammar never accepts as a filter value on its own.
      it "expands vocabulary-backed games filters to real passable tokens, not bare category names" do
        filter_desc = schema_for("pito_list")["properties"]["filter"]["description"]
        games_desc  = filter_desc[/games: (.*?); vids:/m, 1]

        expect(games_desc).to start_with("upcoming, ")
        expect(games_desc).to match(/\brpg\b/)   # genre vocabulary member
        expect(games_desc).to match(/\bfps\b/)   # genre vocabulary synonym
        expect(games_desc).to match(/\bps5\b/)   # platform vocabulary synonym
        expect(games_desc).to match(/\bxsx\b/)   # platform vocabulary synonym

        # `genre` the bare category label is gone entirely — anchored with \b so
        # it can't false-positive against a token that merely contains it.
        expect(games_desc).not_to match(/\bgenre\b/)

        # Before this change, filters were listed by NAME, so games advertised
        # exactly "upcoming, genre, platform" — none of which (bar `upcoming`)
        # a client could actually pass. That exact bare triple is gone. Note:
        # the STRING "platform" does still legitimately reappear further down
        # the (now much longer) list — it's also a `genres` vocabulary synonym
        # for the "Platformer" genre (config/pito/verbs.yml
        # vocabularies.genres.synonyms), a real, independently passable token —
        # so we pin absence of the old bare triple rather than a blanket
        # "platform" match, which would false-positive against that token.
        expect(games_desc).not_to include("upcoming, genre, platform")
      end

      it "reflects a newly added capability column automatically (publish_at → sort)" do
        expect(schema_for("pito_list")["properties"]["sort"]["description"]).to match(/vids:.*publish_at/)
      end
    end
  end

  # U5 — readOnlyHint mirrors each tool's REQUIRED config `read_only:` flag
  # (owner 2026-07-10: strict over flexible). The four analytics tools warm a
  # persistent cache / may call the YouTube Analytics API on a cold read, so
  # they declare false; every other tool is a pure read and declares true.
  describe "tool annotations" do
    NOT_READ_ONLY = %w[pito_analyze pito_glance pito_breakdowns pito_channels_of_game].freeze

    it "annotates readOnlyHint per tool from the config read_only flag" do
      described_class.tools.each do |tool|
        expected = !NOT_READ_ONLY.include?(tool[:name])
        expect(tool[:annotations]).to eq("readOnlyHint" => expected),
                                      "#{tool[:name]} expected readOnlyHint #{expected}"
      end
    end

    it "declares the analytics four read_only: false explicitly (not defaulted)" do
      NOT_READ_ONLY.each do |name|
        expect(described_class.tool(name)[:read_only]).to be(false)
      end
    end
  end

  describe ".tool" do
    it "returns the full descriptor for a verb-backed tool" do
      d = Pito::Mcp::Registry.tool("pito_show")
      expect(d).to include(
        name:  "pito_show",
        kind:  :verb,
        verb:  "show",
        input: "show %{noun} %{ref}"
      )
      expect(d[:input_suffixes]).to eq(segments: " with %{values}")
    end

    it "returns a reader descriptor with kind :reader and no backing verb" do
      d = Pito::Mcp::Registry.tool("pito_messages")
      expect(d).to include(name: "pito_messages", kind: :reader, verb: nil, input: nil)
      expect(d[:params]).to have_key(:limit)
    end

    it "exposes a param declared but absent from the input template (Router-forwarded)" do
      # `period` is NOT in pito_analyze's `input`/`input_suffixes` — the Executor
      # forwards it to Router.call(period:). It must still be a declared param.
      d = Pito::Mcp::Registry.tool("pito_analyze")
      expect(d[:params]).to have_key(:period)
      expect(d[:input]).to eq("analyze")
      expect(d[:input_suffixes].keys).to contain_exactly(:noun, :ref)
    end

    it "returns nil for an unknown tool name" do
      expect(Pito::Mcp::Registry.tool("pito_nonexistent")).to be_nil
    end

    it "accepts a symbol name" do
      expect(Pito::Mcp::Registry.tool(:pito_list)).to include(name: "pito_list")
    end
  end
end
