# frozen_string_literal: true

require "rails_helper"

# ── THE MCP TOOL MATRIX (G130) — the MCP analog of the dispatch matrices ────────
#
# Two guarantees, table-driven:
#   (a) tools/list ≡ the verbs.yml declarations EXACTLY — no phantom tools, none
#       missing. The Registry is the ONLY source; this pins it against the config.
#   (b) for every VERB tool, a representative tool call builds a grammar string
#       that the REAL parser recognizes as the tool's OWN backing verb — proving
#       the executor's template + input_suffixes stay in lockstep with the grammar.
#
# (b) runs against the UNMODIFIED Lex → Parser path (what Router#parse uses). The
# per-tool EXECUTION (dispatch → EventText) is covered by executor_spec /
# analytics_fill_spec / readers_spec; here we pin recognition for all 11 verb tools.
RSpec.describe "the MCP tool matrix (G130)", type: :dispatch do
  let(:conversation) { Conversation.singleton }

  def parse(input)
    tokens = Pito::Lex::KeywordSanitizer.call(Pito::Lex::Lexer.call(input))
    Pito::Chat::Parser.call(tokens, raw: input, conversation:)
  end

  # ── (a) tools/list ≡ the declarations ───────────────────────────────────────
  describe "tools/list is exactly the verbs.yml declarations" do
    it "surfaces every declared tool and no phantoms" do
      data         = Pito::Dispatch::Config.data
      verb_tools   = data[:verbs].filter_map { |_, body| body.dig(:mcp, :tool) }
      reader_tools = (data[:mcp_readers] || {}).values.map { |r| r[:tool] }
      declared     = (verb_tools + reader_tools)

      expect(Pito::Mcp::Registry.tool_names).to match_array(declared)
    end
  end

  # ── (b) every verb tool's built input recognizes as its backing verb ────────
  # Representative params per tool; the EXPECTED verb is the tool's own declared
  # backing verb (Registry descriptor), so this never drifts from the config.
  REPRESENTATIVE_ARGS = {
    "pito_list"             => { "noun" => "games" },
    "pito_show"             => { "noun" => "game", "ref" => "3", "segments" => %w[similar] },
    "pito_analyze"          => { "noun" => "game", "ref" => "3" },
    "pito_glance"           => { "noun" => "vid", "ref" => "5" },
    "pito_breakdowns"       => { "noun" => "channel", "ref" => "@gmrdad82" },
    "pito_videos"           => { "noun" => "channel", "ref" => "@gmrdad82" },
    "pito_game_of_vid"      => { "vid_ref" => "10" },
    "pito_similar"          => { "game_ref" => "3" },
    "pito_channels_of_game" => { "game_ref" => "3" },
    "pito_shinies"          => { "noun" => "game", "ref" => "3" },
    "pito_games"            => { "channel_ref" => "@gmrdad82" }
  }.freeze

  REPRESENTATIVE_ARGS.each do |tool, args|
    it "#{tool}: the built input recognizes as its backing verb" do
      descriptor = Pito::Mcp::Registry.tool(tool)
      input      = Pito::Mcp::Executor.build_input(descriptor, args)

      expect(parse(input).verb.to_s).to eq(descriptor[:verb]),
                                        "built #{input.inspect} → verb #{parse(input).verb.inspect}, expected #{descriptor[:verb]}"
    end
  end

  it "covers every verb-backed tool (no tool left untested)" do
    verb_tools = Pito::Mcp::Registry.tool_names.select { |n| Pito::Mcp::Registry.tool(n)[:kind] == :verb }
    expect(REPRESENTATIVE_ARGS.keys).to match_array(verb_tools)
  end

  # ── (b) execution smoke — a representative tool returns non-empty EventText ──
  describe "execution yields non-empty projections" do
    it "pito_list over a real library renders a table" do
      create(:game, title: "Hollow Knight")
      result = Pito::Mcp::Executor.call(tool: "pito_list", arguments: { "noun" => "games" })
      expect(result.text).to include("Hollow Knight")
    end

    it "pito_conversations renders (readers are covered too)" do
      expect(Pito::Mcp::Executor.call(tool: "pito_conversations", arguments: {}).text).to be_present
    end
  end
end
