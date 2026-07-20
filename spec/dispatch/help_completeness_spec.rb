# frozen_string_literal: true

require "rails_helper"

# v1.6 unified grammar — the HELP-COMPLETENESS guard (U3/U4). Every chat tool, at
# every noun level `--help` can be typed at, must render a real man page — and the
# `CommandHelp::tool_nouns` routing table must not drift from the actual config
# tools (a stale entry for a retired tool renders nil, silently breaking that
# tool's `--help`; that is exactly how `linked-game`/`linked-videos` rotted).
#
# The guard is BIDIRECTIONAL — both the copy→config and the config→copy edges are
# pinned, plus the page CONTENT (not just its wrapper):
#   (1) NO ORPHAN — every copy-derived tool_nouns key is a real tool in tools.yml.
#   (2) NO UNRENDERED DISPATCH TOOL (reverse) — every tool that carries a
#       `chat.dispatch` renders a usage-bearing man page, save a maintained,
#       explicit NO_HELP_PAGE exclusion list. This is the edge the old guard
#       missed: a NEW dispatch tool with no `pito.chat_help` copy renders nothing
#       yet used to pass green; likewise deleting a whole page dropped it silently.
#   (3) SHIPPED NOUN FORMS (reverse) — a literal SHIPPED_TOOL_NOUNS snapshot,
#       asserted as a SUBSET of the live derived table, so DELETING or RENAMING an
#       existing `pito.chat_help.<tool>.<noun>` sub-hash fails loudly (adding forms
#       stays free).
#   (4) CONTENT — every tool-level and noun-level page's body must carry its own
#       `usage` copy (html-escaped as ManPage renders it), so a blank / wrong /
#       mis-keyed page can't pass as "rendered". The list drill-down
#       (games/vids/channels + index) is anchored the same way.
# So the routing (alias normalisation, ref-skipping) can never silently regress, a
# retired tool can never linger in the table, and a new tool can never ship with a
# dead `--help`.
RSpec.describe "CommandHelp — --help completeness", type: :dispatch do
  CH   = Pito::MessageBuilder::CommandHelp
  VN   = Pito::MessageBuilder::CommandHelp.tool_nouns
  CONF = Pito::Dispatch::Config.data.fetch(:tools)

  # Tools that declare a `chat.dispatch` in tools.yml yet DELIBERATELY render no
  # CommandHelp man page. Maintained by hand — a new dispatch tool that renders
  # nothing must either grow a `pito.chat_help.<tool>` page or be listed here with
  # a reason (derived factually from Config + CommandHelp, not guessed).
  NO_HELP_PAGE = %i[
    greet
    farewell
    help
  ].freeze
  # greet    — phrase-matched greeting handler; no `--help` surface, no chat_help copy.
  # farewell — phrase-matched farewell handler; ditto.
  # help     — `help --help` is the router's easter-egg nonsense page, not a man page
  #            (lib/pito/dispatch/router.rb#help_page).

  # The SHIPPED help surface — the tool→noun forms that render a man page today.
  # An explicit literal snapshot (NOT derived) asserted as a SUBSET of the live
  # `CommandHelp.tool_nouns`: ADDING a form is free, but DELETING or RENAMING an
  # existing `pito.chat_help.<tool>.<noun>` sub-hash drops it out of the derived
  # table and fails here — exactly the silent copy drift (linked-game/linked-videos)
  # this guard exists to catch. Extend this table when you add a noun form; a
  # removal here must be deliberate.
  SHIPPED_TOOL_NOUNS = {
    analyze:       %i[channel vid game],
    "at-a-glance": %i[channel vid game],
    breakdowns:    %i[channel vid game],
    channels:      %i[game],
    delete:        %i[game video],
    game:          %i[vid],
    games:         %i[channel],
    import:        %i[game videos],
    link:          %i[game video],
    linked:        %i[game vids],
    publish:       %i[video],
    reindex:       %i[game video],
    schedule:      %i[video],
    shinies:       %i[channel video game],
    show:          %i[game video channel],
    similar:       %i[game],
    sync:          %i[videos channels],
    unlink:        %i[game video],
    unlist:        %i[video],
    videos:        %i[channel game]
  }.freeze

  # Wrapper presence — the primitive.
  def renders?(page)
    page.is_a?(Hash) && page["body"].to_s.include?("pito-help-block")
  end

  # Strengthened check: the page must be wrapped AND its rendered body must carry
  # its own `usage` line. ManPage html-escapes the usage before emitting it, so we
  # compare against the escaped form — a blank / wrong / mis-keyed page can't pass.
  def renders_usage?(page, usage)
    renders?(page) && usage.present? &&
      page["body"].to_s.include?(ERB::Util.html_escape(usage))
  end

  # The tool-level usage copy (`pito.chat_help.<tool>.usage`). For single-noun
  # tools the tool-level page renders the one noun page, whose usage copy equals
  # the tool-level line by construction — so this anchor holds either way.
  def tool_usage(tool)
    Pito::Copy.render_soft("pito.chat_help.#{tool}.usage")
  end

  # The noun-page usage copy (`pito.chat_help.<tool>.<noun>.usage`).
  def noun_usage(tool, noun)
    data = Pito::Copy.subtree("pito.chat_help.#{tool}.#{noun}")
    (data && (data[:usage] || data["usage"])).to_s
  end

  describe "no orphan routing entries" do
    it "every tool_nouns key is a real tool declared in tools.yml" do
      orphans = VN.keys.reject { |tool| CONF.key?(tool) }
      expect(orphans).to be_empty, "tool_nouns names tools absent from tools.yml: #{orphans.inspect}"
    end
  end

  # Reverse edge (F14/F16): every tool with a `chat.dispatch` must render a real
  # man page, save the maintained NO_HELP_PAGE gaps — closes the hole where a new
  # dispatch tool with no help copy, or a whole deleted page, passed green.
  describe "no unrendered dispatch tool (reverse guard)" do
    dispatch_tools = CONF.select { |_tool, cfg| cfg.is_a?(Hash) && cfg.dig(:chat, :dispatch) }.keys

    it "the exclusion list names only real dispatch tools (no stale entries)" do
      stale = NO_HELP_PAGE - dispatch_tools
      expect(stale).to be_empty, "NO_HELP_PAGE names non-dispatch tools: #{stale.inspect}"
    end

    (dispatch_tools - NO_HELP_PAGE).each do |tool|
      it "#{tool} (chat.dispatch) renders a man page carrying its usage" do
        expect(renders_usage?(CH.call(tool), tool_usage(tool))).to be(true),
          "#{tool} has a chat.dispatch but `--help` rendered no usage-bearing page"
      end
    end

    NO_HELP_PAGE.each do |tool|
      it "#{tool} is a deliberate no-help-page exclusion (renders nil)" do
        expect(CH.call(tool)).to be_nil, "#{tool} now renders a page — remove it from NO_HELP_PAGE"
      end
    end
  end

  # Reverse edge: the shipped noun forms must survive. The literal snapshot is a
  # subset of the derived table, so a deleted/renamed noun page reddens this.
  describe "shipped noun forms (reverse guard)" do
    it "every shipped tool still exists in the derived table" do
      missing = SHIPPED_TOOL_NOUNS.keys - VN.keys
      expect(missing).to be_empty,
        "shipped tools no longer in CommandHelp.tool_nouns (copy deleted?): #{missing.inspect}"
    end

    SHIPPED_TOOL_NOUNS.each do |tool, nouns|
      it "#{tool} still ships its #{nouns.inspect} noun form(s)" do
        dropped = nouns - (VN[tool] || [])
        expect(dropped).to be_empty,
          "#{tool} lost shipped noun form(s) #{dropped.inspect} — a removal must be deliberate"
      end
    end
  end

  VN.each do |tool, nouns|
    describe "#{tool} --help" do
      it "renders a tool-level man page carrying its usage" do
        expect(renders_usage?(CH.call(tool), tool_usage(tool))).to be(true),
          "#{tool} --help rendered no usage-bearing page"
      end

      nouns.each do |noun|
        it "renders the #{tool} #{noun} noun page carrying its usage" do
          expect(renders_usage?(CH.call(tool, noun: noun), noun_usage(tool, noun))).to be(true),
            "#{tool} #{noun} --help rendered no usage-bearing page"
        end
      end
    end
  end

  describe "list drill-down" do
    it "renders the bare `list --help` index carrying its usage" do
      expect(renders_usage?(CH.call(:list), tool_usage(:list))).to be(true)
    end

    # The per-noun ListHelp builders own their usage copy under `pito.copy.list.*`.
    {
      games:    "pito.copy.list.games_help.usage",
      videos:   "pito.copy.list.videos_help.usage",
      channels: "pito.copy.list.channels_help.usage"
    }.each do |noun, usage_key|
      it "renders `list #{noun} --help` carrying its usage" do
        expect(renders_usage?(CH.call(:list, noun: noun), Pito::Copy.render_soft(usage_key))).to be(true)
      end
    end
  end

  # Usage-only tools (a `pito.chat_help.<tool>.usage` line, no noun pages — e.g.
  # search) still render a man page rather than falling through to nil.
  describe "usage-only tools" do
    subtree = I18n.t("pito.chat_help")
    usage_only = subtree.select do |tool, body|
      tool != :list && body.is_a?(Hash) && body.key?(:usage) &&
        body.keys.none? { |k| k != :usage && body[k].is_a?(Hash) }
    end.keys

    it "there is at least one usage-only tool to guard (search)" do
      expect(usage_only).to include(:search)
    end

    usage_only.each do |tool|
      it "renders `#{tool} --help` carrying its usage" do
        expect(renders_usage?(CH.call(tool), tool_usage(tool))).to be(true)
      end
    end
  end
end
