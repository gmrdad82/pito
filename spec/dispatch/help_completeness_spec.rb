# frozen_string_literal: true

require "rails_helper"

# v1.6 unified grammar — the HELP-COMPLETENESS guard (U3/U4). Every chat verb, at
# every noun level `--help` can be typed at, must render a real man page — and the
# `CommandHelp::VERB_NOUNS` routing table must not drift from the actual config
# verbs (a stale entry for a retired verb renders nil, silently breaking that
# verb's `--help`; that is exactly how `linked-game`/`linked-videos` rotted).
#
# The guard is BIDIRECTIONAL — both the copy→config and the config→copy edges are
# pinned, plus the page CONTENT (not just its wrapper):
#   (1) NO ORPHAN — every copy-derived VERB_NOUNS key is a real verb in verbs.yml.
#   (2) NO UNRENDERED DISPATCH VERB (reverse) — every verb that carries a
#       `chat.dispatch` renders a usage-bearing man page, save a maintained,
#       explicit NO_HELP_PAGE exclusion list. This is the edge the old guard
#       missed: a NEW dispatch verb with no `pito.chat_help` copy renders nothing
#       yet used to pass green; likewise deleting a whole page dropped it silently.
#   (3) SHIPPED NOUN FORMS (reverse) — a literal SHIPPED_VERB_NOUNS snapshot,
#       asserted as a SUBSET of the live derived table, so DELETING or RENAMING an
#       existing `pito.chat_help.<verb>.<noun>` sub-hash fails loudly (adding forms
#       stays free).
#   (4) CONTENT — every verb-level and noun-level page's body must carry its own
#       `usage` copy (html-escaped as ManPage renders it), so a blank / wrong /
#       mis-keyed page can't pass as "rendered". The list drill-down
#       (games/vids/channels + index) is anchored the same way.
# So the routing (alias normalisation, ref-skipping) can never silently regress, a
# retired verb can never linger in the table, and a new verb can never ship with a
# dead `--help`.
RSpec.describe "CommandHelp — --help completeness", type: :dispatch do
  CH   = Pito::MessageBuilder::CommandHelp
  VN   = Pito::MessageBuilder::CommandHelp.verb_nouns
  CONF = Pito::Dispatch::Config.data.fetch(:verbs)

  # Verbs that declare a `chat.dispatch` in verbs.yml yet DELIBERATELY render no
  # CommandHelp man page. Maintained by hand — a new dispatch verb that renders
  # nothing must either grow a `pito.chat_help.<verb>` page or be listed here with
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

  # The SHIPPED help surface — the verb→noun forms that render a man page today.
  # An explicit literal snapshot (NOT derived) asserted as a SUBSET of the live
  # `CommandHelp.verb_nouns`: ADDING a form is free, but DELETING or RENAMING an
  # existing `pito.chat_help.<verb>.<noun>` sub-hash drops it out of the derived
  # table and fails here — exactly the silent copy drift (linked-game/linked-videos)
  # this guard exists to catch. Extend this table when you add a noun form; a
  # removal here must be deliberate.
  SHIPPED_VERB_NOUNS = {
    analyze:       %i[channel vid game],
    "at-a-glance": %i[channel vid game],
    breakdowns:    %i[channel vid game],
    channels:      %i[game],
    delete:        %i[game video],
    footage:       %i[game snippet],
    game:          %i[vid],
    games:         %i[channel],
    import:        %i[game videos],
    link:          %i[game video],
    linked:        %i[game vids],
    platform:      %i[game],
    price:         %i[set unset],
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

  # The verb-level usage copy (`pito.chat_help.<verb>.usage`). For single-noun
  # verbs the verb-level page renders the one noun page, whose usage copy equals
  # the verb-level line by construction — so this anchor holds either way.
  def verb_usage(verb)
    Pito::Copy.render_soft("pito.chat_help.#{verb}.usage")
  end

  # The noun-page usage copy (`pito.chat_help.<verb>.<noun>.usage`).
  def noun_usage(verb, noun)
    data = Pito::Copy.subtree("pito.chat_help.#{verb}.#{noun}")
    (data && (data[:usage] || data["usage"])).to_s
  end

  describe "no orphan routing entries" do
    it "every VERB_NOUNS key is a real verb declared in verbs.yml" do
      orphans = VN.keys.reject { |verb| CONF.key?(verb) }
      expect(orphans).to be_empty, "VERB_NOUNS names verbs absent from verbs.yml: #{orphans.inspect}"
    end
  end

  # Reverse edge (F14/F16): every verb with a `chat.dispatch` must render a real
  # man page, save the maintained NO_HELP_PAGE gaps — closes the hole where a new
  # dispatch verb with no help copy, or a whole deleted page, passed green.
  describe "no unrendered dispatch verb (reverse guard)" do
    dispatch_verbs = CONF.select { |_verb, cfg| cfg.is_a?(Hash) && cfg.dig(:chat, :dispatch) }.keys

    it "the exclusion list names only real dispatch verbs (no stale entries)" do
      stale = NO_HELP_PAGE - dispatch_verbs
      expect(stale).to be_empty, "NO_HELP_PAGE names non-dispatch verbs: #{stale.inspect}"
    end

    (dispatch_verbs - NO_HELP_PAGE).each do |verb|
      it "#{verb} (chat.dispatch) renders a man page carrying its usage" do
        expect(renders_usage?(CH.call(verb), verb_usage(verb))).to be(true),
          "#{verb} has a chat.dispatch but `--help` rendered no usage-bearing page"
      end
    end

    NO_HELP_PAGE.each do |verb|
      it "#{verb} is a deliberate no-help-page exclusion (renders nil)" do
        expect(CH.call(verb)).to be_nil, "#{verb} now renders a page — remove it from NO_HELP_PAGE"
      end
    end
  end

  # Reverse edge: the shipped noun forms must survive. The literal snapshot is a
  # subset of the derived table, so a deleted/renamed noun page reddens this.
  describe "shipped noun forms (reverse guard)" do
    it "every shipped verb still exists in the derived table" do
      missing = SHIPPED_VERB_NOUNS.keys - VN.keys
      expect(missing).to be_empty,
        "shipped verbs no longer in CommandHelp.verb_nouns (copy deleted?): #{missing.inspect}"
    end

    SHIPPED_VERB_NOUNS.each do |verb, nouns|
      it "#{verb} still ships its #{nouns.inspect} noun form(s)" do
        dropped = nouns - (VN[verb] || [])
        expect(dropped).to be_empty,
          "#{verb} lost shipped noun form(s) #{dropped.inspect} — a removal must be deliberate"
      end
    end
  end

  VN.each do |verb, nouns|
    describe "#{verb} --help" do
      it "renders a verb-level man page carrying its usage" do
        expect(renders_usage?(CH.call(verb), verb_usage(verb))).to be(true),
          "#{verb} --help rendered no usage-bearing page"
      end

      nouns.each do |noun|
        it "renders the #{verb} #{noun} noun page carrying its usage" do
          expect(renders_usage?(CH.call(verb, noun: noun), noun_usage(verb, noun))).to be(true),
            "#{verb} #{noun} --help rendered no usage-bearing page"
        end
      end
    end
  end

  describe "list drill-down" do
    it "renders the bare `list --help` index carrying its usage" do
      expect(renders_usage?(CH.call(:list), verb_usage(:list))).to be(true)
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

  # Usage-only verbs (a `pito.chat_help.<verb>.usage` line, no noun pages — e.g.
  # search) still render a man page rather than falling through to nil.
  describe "usage-only verbs" do
    subtree = I18n.t("pito.chat_help")
    usage_only = subtree.select do |verb, body|
      verb != :list && body.is_a?(Hash) && body.key?(:usage) &&
        body.keys.none? { |k| k != :usage && body[k].is_a?(Hash) }
    end.keys

    it "there is at least one usage-only verb to guard (search)" do
      expect(usage_only).to include(:search)
    end

    usage_only.each do |verb|
      it "renders `#{verb} --help` carrying its usage" do
        expect(renders_usage?(CH.call(verb), verb_usage(verb))).to be(true)
      end
    end
  end
end
