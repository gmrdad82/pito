# frozen_string_literal: true

require "rails_helper"

# ── Help/usage derivation-sync guard (plan-0.9.5 T8.12) ─────────────────────
#
# Asserts that pito.chat_help.* and pito.hashtag_help.* stay in sync with the
# config-driven dispatch reality (config/pito/tools.yml + Pito::Dispatch::Matrix).
#
# Design rule: NEVER weaken this guard.  When copy is missing, either author the
# copy entry or add the gap to the explicit pinned-omission table below with a
# comment explaining why it is intentionally absent.  A plain "no copy yet" is
# accepted; a silent gap is not.
#
# Four assertion tiers:
#
#   1. CHAT HELP   — every dispatched chat verb has a pito.chat_help.<verb>.usage
#                    entry; TOOL_GROUPS lists only valid config tools; no dispatched
#                    verb is absent from the main-help listing (unless pinned).
#
#   2. SEGMENTS    — show/analyze Segments sections name EXACTLY the config segment
#                    names for every entity (no phantom names, no omitted names).
#
#   3. HASHTAG HELP— every Matrix reply target has a hashtag_help page (or a pinned
#                    omission); copy actions ⊆ Matrix.actions_for (no phantoms);
#                    every non-universal action has a copy entry (or is pinned).
#                    Failure messages name the verb, target, and key path.
#
#   4. PAGER       — paginated list targets document the configured more_tool name,
#                    not a hardcoded token.

RSpec.describe "help/usage derivation-sync", type: :dispatch do
  Pito::Dispatch::Config.reload!
  Pito::Dispatch::Matrix.reload!

  # The full tools.yml document and its verb table.
  HELP_DOC   = Pito::Dispatch::Config.data
  HELP_VERBS = HELP_DOC[:tools]

  before(:all) do
    Pito::FollowUp::Registry.register_all!
    Pito::Chat::Registry.register_all!
  end

  # ── Derived tables ────────────────────────────────────────────────────────────

  # Chat verbs that have a dispatch string (a handler class name).
  # `find` declares no chat: block at all (3.0.1 P6) — it exists purely to
  # feed nl_examples: into the NL corpus, so it never appears here; when it
  # gains a real handler this list will automatically include it.
  HELP_DISPATCH_VERBS = HELP_VERBS.select { |_, body|
    body.dig(:chat, :dispatch).is_a?(String)
  }.keys.map(&:to_s).freeze

  # Ordered flat list of every tool that appears in the main-help TOOL_GROUPS.
  # Referencing Commands first ensures Zeitwerk loads commands.rb, which also
  # defines Pito::MessageBuilder::Help::TOOL_GROUPS (same file, same module).
  Pito::MessageBuilder::Help::Commands
  HELP_GROUP_TOOLS = Pito::MessageBuilder::Help::TOOL_GROUPS.values.flatten.freeze

  # target_id → i18n indicator key (e.g. "game_detail" → "show-game").
  HELP_TARGET_INDICATORS = Pito::MessageBuilder::HashtagHelp::TARGET_INDICATORS.freeze

  # Configured pager tool for `list` (currently "next").
  PAGER_MORE_TOOL = Pito::Dispatch::Config.pager(tool: :list)&.fetch(:more_tool).freeze

  # Targets that expose the pager more_tool as a reply action.
  PAGED_LIST_TARGETS = HELP_VERBS.dig(:next, :reply, :targets)&.keys&.map(&:to_s).to_a.freeze

  # ── Pinned-omission tables ─────────────────────────────────────────────────────
  #
  # Each entry is a KNOWN gap with an explanatory comment.  Filling a gap means
  # removing it from here AND authoring the copy (or adding an ACTION_ALIASES
  # redirect in HashtagHelp).  Adding a new entry documents intent; it is never
  # a license to forget.

  # Dispatched chat verbs that intentionally have no pito.chat_help.<verb> page.
  CHAT_HELP_OMISSIONS = [
    "help",    # help IS the page the user is reading — a usage line would be circular
    "greet",   # whole-input phrase-match in Chat::Parser; not a keyword command
    "farewell" # whole-input phrase-match in Chat::Parser; not a keyword command
  ].freeze

  # Dispatched chat verbs intentionally absent from the TOOL_GROUPS main-help listing.
  TOOL_GROUPS_OMISSIONS = [
    "help",    # the page itself — listing it would be self-referential
    "greet",   # phrase-matched greeting; suppressed from keyword command listing
    "farewell" # phrase-matched farewell; suppressed from keyword command listing
  ].freeze

  # Reply targets that intentionally have no hashtag_help indicator or page.
  # These are specialized, internal, or early-stage targets not yet wired into
  # the hashtag help system.
  HASHTAG_TARGET_OMISSIONS = [
    "analytics_glance",   # at-a-glance panel; reply-only, no hashtag_help page yet
    "analyze_message",    # analyze result card; reply-only, no hashtag_help page yet
    "channel_visit",      # visit card; only the internal `consume` verb applies here
    "game_channels",      # channels-for-game segment; no hashtag_help page yet
    "game_imported",      # freshly-imported game card; no hashtag_help page yet
    "game_linked_videos", # game linked-videos segment; no hashtag_help page yet
    "game_similar",       # similar-games segment; no hashtag_help page yet
    "resume_missing"      # "conversation not found" card; no hashtag_help page yet
  ].freeze

  # Per-target non-universal actions available in the Matrix that have no copy
  # entry in the hashtag_help page.  Each gap is acknowledged with a comment.
  # Fix a gap: (a) author the copy entry, or (b) add an ACTION_ALIASES redirect
  # in Pito::MessageBuilder::HashtagHelp.  Then remove it from this table.
  #
  # Note: "order" is absent from every target below because it is already handled
  # by HashtagHelp::ACTION_ALIASES ("order" → renders the "sort" page).
  HASHTAG_ACTION_OMISSIONS = {
    # game_detail (show-game indicator)
    "game_detail" => [
      "sync",     # sync re-syncs game metadata; pito.hashtag_help.show-game.actions.sync not yet authored
      "shinies",  # thumbnail breakdown for a game; help entry not yet authored
      "del"       # per-target alias of delete (alias: rm IS documented separately)
    ],
    # game_list (list-games indicator)
    "game_list" => [
      "shinies",  # thumbnail breakdown from game list; help entry not yet authored
      "del"       # per-target alias of delete (rm IS documented)
    ],
    # video_detail (show-video indicator)
    "video_detail" => [
      "sync",     # sync re-syncs video metadata; help entry not yet authored
      "publish",  # publish from video card; help entry not yet authored
      "pub",      # per-target alias of publish on video_detail
      "unlist",   # unlist from video card; help entry not yet authored
      "schedule", # schedule from video card; help entry not yet authored
      "del",      # per-target alias of delete (rm IS documented)
      "shinies"   # thumbnail breakdown for a video; help entry not yet authored
    ],
    # video_list (list-videos indicator)
    "video_list" => [
      "publish", # publish from video list; help entry not yet authored
      "pub",     # per-target alias of publish on video_list
      "unlist",  # unlist from video list; help entry not yet authored
      "del",     # per-target alias of delete (rm IS documented)
      "shinies"  # thumbnail breakdown from video list; help entry not yet authored
    ],
    # video_search (search-videos indicator)
    "video_search" => [
      "publish", # publish from search results; help entry not yet authored
      "pub",     # per-target alias of publish on video_search
      "unlist",  # unlist from search results; help entry not yet authored
      "del",     # per-target alias of delete (rm IS documented)
      "shinies"  # thumbnail breakdown from search results; help entry not yet authored
    ],
    # channel_list (list-channels indicator)
    "channel_list" => [
      "sort" # sort on channel list; help entry not yet authored
    ],
    # channel_detail (show-channel indicator)
    "channel_detail" => [
      "sync" # sync re-syncs channel metadata from YouTube; help entry not yet authored
    ]
    # confirmation: confirm and cancel are both documented; no omissions.
  }.transform_values(&:freeze).freeze

  # Maps config entity symbol → i18n copy subkey within pito.chat_help.<verb>.
  # show uses "video" for the `vid` entity (VERB_NOUNS convention in CommandHelp);
  # analyze uses "vid" (matching the actual i18n key in the help YAML).
  SEGMENT_COPY_ENTITY = {
    show:    { channel: "channel", vid: "video", game: "game" },
    analyze: { channel: "channel", vid: "vid",   game: "game" }
  }.freeze

  # ══ TIER 1 — Chat verb ↔ chat_help coverage ════════════════════════════════
  describe "CHAT HELP — dispatched verb coverage and TOOL_GROUPS sync" do
    describe "every dispatched chat verb (modulo pinned omissions) has a pito.chat_help.<verb>.usage entry" do
      HELP_DISPATCH_VERBS.each do |verb|
        next if CHAT_HELP_OMISSIONS.include?(verb)

        it "pito.chat_help.#{verb}.usage exists" do
          expect(I18n.exists?("pito.chat_help.#{verb}.usage")).to(
            be(true),
            "pito.chat_help.#{verb}.usage is missing — " \
            "add a usage entry to config/locales/pito/help/en.yml, " \
            "or pin #{verb.inspect} in CHAT_HELP_OMISSIONS with an explanation"
          )
        end
      end
    end

    it "every tool in TOOL_GROUPS is a valid dispatched chat verb in config" do
      bad = HELP_GROUP_TOOLS.reject do |verb|
        HELP_VERBS[verb.to_sym]&.dig(:chat, :dispatch).is_a?(String)
      end
      expect(bad).to(
        be_empty,
        "TOOL_GROUPS lists tools absent from config or lacking a chat dispatch:\n" +
          bad.map { |v|
            "  #{v} — either remove from TOOL_GROUPS or add chat.dispatch to tools.yml"
          }.join("\n")
      )
    end

    it "no dispatched chat verb is absent from TOOL_GROUPS (modulo pinned omissions)" do
      ungrouped = HELP_DISPATCH_VERBS - HELP_GROUP_TOOLS - TOOL_GROUPS_OMISSIONS
      expect(ungrouped).to(
        be_empty,
        "dispatched chat verbs absent from TOOL_GROUPS and not in TOOL_GROUPS_OMISSIONS:\n" +
          ungrouped.map { |v|
            "  #{v} — add to a Pito::MessageBuilder::Help::TOOL_GROUPS entry " \
            "or pin in TOOL_GROUPS_OMISSIONS with an explanation"
          }.join("\n")
      )
    end
  end

  # ══ TIER 2 — Segment section coverage ═════════════════════════════════════
  describe "SEGMENTS — help copy Segments section matches config exactly for show/analyze" do
    SEGMENT_COPY_ENTITY.each do |verb, entity_map|
      segments_by_entity = HELP_VERBS.dig(verb, :segments) || {}

      entity_map.each do |config_entity, copy_key|
        next unless segments_by_entity.key?(config_entity)

        config_names = segments_by_entity[config_entity].keys.map(&:to_s).sort

        it "#{verb}/#{config_entity}: Segments section names match config (expected #{config_names.inspect})" do
          data = Pito::Copy.subtree("pito.chat_help.#{verb}.#{copy_key}")
          expect(data).to(
            be_a(Hash),
            "pito.chat_help.#{verb}.#{copy_key} is missing or is not a Hash — " \
            "add the noun page to config/locales/pito/help/en.yml"
          )

          sections    = data[:sections] || data["sections"] || {}
          seg_section = sections[:Segments] || sections["Segments"] || {}
          copy_names  = seg_section.keys.map(&:to_s).sort

          expect(copy_names).to(
            eq(config_names),
            "pito.chat_help.#{verb}.#{copy_key}.sections.Segments " \
            "lists #{copy_names.inspect} but config/pito/tools.yml declares " \
            "#{config_names.inspect} — update the copy to match the config"
          )
        end
      end
    end
  end

  # ══ TIER 3 — Hashtag help coverage ════════════════════════════════════════
  describe "HASHTAG HELP — Matrix targets have pages; action entries are consistent" do
    it "every Matrix reply target is mapped in TARGET_INDICATORS or pinned as omitted" do
      unmapped = Pito::Dispatch::Matrix.targets - HELP_TARGET_INDICATORS.keys - HASHTAG_TARGET_OMISSIONS
      expect(unmapped).to(
        be_empty,
        "Matrix reply targets without a TARGET_INDICATORS mapping or pinned omission " \
        "(add to Pito::MessageBuilder::HashtagHelp::TARGET_INDICATORS + " \
        "config/locales/pito/help/en.yml, or pin in HASHTAG_TARGET_OMISSIONS):\n" +
          unmapped.map { |t| "  #{t}" }.join("\n")
      )
    end

    describe "copy actions ⊆ Matrix.actions_for(target) — no phantom entries in copy" do
      HELP_TARGET_INDICATORS.each do |target, indicator|
        it "#{target} (pito.hashtag_help.#{indicator}): no phantom actions" do
          actions_tree = Pito::Copy.subtree("pito.hashtag_help.#{indicator}.actions") || {}
          copy_actions  = actions_tree.keys.map(&:to_s)
          matrix_actions = Pito::Dispatch::Matrix.actions_for(target)

          phantoms = copy_actions - matrix_actions
          expect(phantoms).to(
            be_empty,
            "pito.hashtag_help.#{indicator}.actions has entries that are NOT in " \
            "Matrix.actions_for(#{target.inspect}): #{phantoms.inspect}\n" \
            "  Cause: the copy references a verb that was removed or was never wired " \
            "as a reply.targets.#{target} entry in config/pito/tools.yml"
          )
        end
      end
    end

    describe "every non-universal action is covered by copy or is pinned" do
      HELP_TARGET_INDICATORS.each do |target, indicator|
        it "#{target} (pito.hashtag_help.#{indicator}): non-universal actions covered" do
          non_universal  = Pito::Dispatch::Matrix.actions_for(target) -
                           Pito::Dispatch::Matrix.universal_tokens
          actions_tree   = Pito::Copy.subtree("pito.hashtag_help.#{indicator}.actions") || {}
          copy_actions   = actions_tree.keys.map(&:to_s)
          pinned         = HASHTAG_ACTION_OMISSIONS.fetch(target, [])
          # ACTION_ALIASES keys are alias tokens that redirect to another action's page
          # (e.g. "order" → "sort"); they count as covered without needing their own entry.
          alias_covered  = Pito::MessageBuilder::HashtagHelp::ACTION_ALIASES.keys

          uncovered = non_universal - copy_actions - pinned - alias_covered
          expect(uncovered).to(
            be_empty,
            "#{target}: non-universal Matrix actions missing from " \
            "pito.hashtag_help.#{indicator}.actions and not pinned:\n" +
              uncovered.map { |a|
                "  #{a} — add pito.hashtag_help.#{indicator}.actions.#{a} to en.yml, " \
                "add an ACTION_ALIASES redirect in HashtagHelp, " \
                "or pin in HASHTAG_ACTION_OMISSIONS[#{target.inspect}]"
              }.join("\n")
          )
        end
      end
    end
  end

  # ══ TIER 4 — Pager more_tool ═════════════════════════════════════════════
  describe "PAGER — paginated list targets document the configured more_tool name" do
    it "list pager has a more_tool configured in tools.yml" do
      expect(PAGER_MORE_TOOL).to(
        be_present,
        "tools.list.concerns.pager.more_tool is missing — " \
        "the pager tool cannot be cross-checked against hashtag help copy"
      )
    end

    PAGED_LIST_TARGETS.each do |target|
      indicator = Pito::MessageBuilder::HashtagHelp::TARGET_INDICATORS[target]
      next unless indicator

      it "#{target} (pito.hashtag_help.#{indicator}): actions includes the pager tool #{PAGER_MORE_TOOL.inspect}" do
        actions_tree = Pito::Copy.subtree("pito.hashtag_help.#{indicator}.actions") || {}
        copy_actions  = actions_tree.keys.map(&:to_s)
        expect(copy_actions).to(
          include(PAGER_MORE_TOOL),
          "pito.hashtag_help.#{indicator}.actions is missing the configured pager " \
          "more_tool #{PAGER_MORE_TOOL.inspect} — if more_tool is renamed in " \
          "tools.yml, rename the action key in pito.hashtag_help.#{indicator}.actions too"
        )
      end
    end
  end
end
