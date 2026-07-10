# frozen_string_literal: true

module Pito
  module MessageBuilder
    # Two-level `--help` dispatcher for chat verbs.
    #
    # CommandHelp.call(:show)                 → verb-level page (lists all noun forms)
    # CommandHelp.call(:show, noun: :game)    → noun-level page for show game
    # CommandHelp.call(:list)                 → noun-index page (Forms: games/videos/channels)
    # CommandHelp.call(:list, noun: :games)   → delegates to Game::ListHelp
    # CommandHelp.call(:list, noun: :videos)  → delegates to Video::ListHelp
    # CommandHelp.call(:list, noun: :channels)→ delegates to Channel::ListHelp (witty)
    #
    # Copy lives at pito.chat_help.<verb>:
    #   verb-level usage  → pito.chat_help.<verb>.usage  (String)
    #   noun page         → pito.chat_help.<verb>.<noun> = { usage:, sections: }
    #
    # Verb-level rendering:
    #   - Shows the verb-level usage line.
    #   - Single-noun verbs: renders the one noun page directly (same output).
    #   - Multi-noun verbs: lists noun forms with a one-liner Options: --help row.
    #
    # Returns nil for unknown verb/noun (no copy exists).
    module CommandHelp
      module_function

      # The per-verb noun forms are DERIVED from the `pito.chat_help` copy subtree
      # (see `verb_nouns`) — the noun pages authored there ARE the source of truth,
      # so the routing table can never drift from the copy (a stale entry for a
      # retired verb, or a missing form for a real one, is impossible by
      # construction). Rendering strategy + verb-level noun order follow the copy's
      # declaration order.

      # Canonical display token per (verb, noun). The verb-level page labels and
      # the list index lead with the short canonical noun (`vid`/`vids`) for the
      # verbs whose handlers accept it; the I18n copy KEYS stay `video`/`videos`.
      # `video`/`videos` remain valid aliases at the parser.
      NOUN_DISPLAY = {
        show:   { video: "vid" },
        import: { videos: "vids" },
        sync:   { videos: "vids" }
      }.freeze

      # The `list` noun forms (canonical, plural). Not in VERB_NOUNS because list
      # is rendered via the per-noun ListHelp builders below.
      LIST_NOUNS = %i[games videos channels].freeze

      # @param verb [Symbol]
      # @param noun [Symbol, nil]
      # @return [Hash, nil]
      def call(verb, noun: nil)
        valid = valid_nouns(verb)
        # A verb with no noun pages but a `usage:` (e.g. search) renders a
        # usage-only page; a verb with neither is unknown → nil.
        return render_usage_only(verb) if valid.nil?

        # Normalise a typed alias to THIS verb's canonical noun (vid/vids/videos →
        # the verb's video form; singular/plural folded) so `show vid --help` and
        # `list vids --help` render the same page `show video`/`list videos` do.
        noun = canonical_noun(valid, noun) if noun

        if verb == :list
          case noun
          when :games    then Pito::MessageBuilder::Game::ListHelp.call
          when :videos   then Pito::MessageBuilder::Video::ListHelp.call
          when :channels then Pito::MessageBuilder::Channel::ListHelp.call
          when nil       then render_list_index
          end # unknown list noun → nil
        elsif noun
          render_noun_page(verb, noun)
        else
          render_verb_page(verb, valid)
        end
      end

      # ── Private ──────────────────────────────────────────────────────────────

      # Valid noun set for a verb (LIST_NOUNS for list; the copy-derived forms
      # otherwise). nil ⇒ unknown verb (no noun pages in the copy).
      def valid_nouns(verb)
        verb == :list ? LIST_NOUNS : verb_nouns[verb]
      end
      private_class_method :valid_nouns

      # verb(Symbol) → [noun Symbols], derived from the `pito.chat_help.<verb>`
      # copy: a verb's noun forms are its sub-keys whose value is a Hash (a noun
      # page with usage/sections), in declaration order. `usage`-only verbs (no
      # noun pages, e.g. search) and `list` (rendered via the ListHelp builders)
      # are excluded. Deliberately NOT memoised: help renders are rare and a
      # cached table would survive locale reloads (dev) and stubbed translations
      # (specs) with no reset hook.
      def verb_nouns
        subtree = I18n.t("pito.chat_help")
        return {}.freeze unless subtree.is_a?(Hash)

        subtree.each_with_object({}) do |(verb, body), out|
          next if verb == :list || !body.is_a?(Hash)

          nouns = body.keys.reject { |k| k == :usage }.select { |k| body[k].is_a?(Hash) }
          out[verb] = nouns.freeze if nouns.any?
        end.freeze
      end

      # Fold a typed noun to the verb's canonical member by comparing stems, so
      # aliases and singular/plural resolve without a per-verb alias table:
      #   stem: drop a trailing "s", then map "vid" → "video".
      # Returns +noun+ unchanged when it is already valid or has no stem match.
      def canonical_noun(valid, noun)
        return noun if valid.include?(noun)

        target = noun_stem(noun)
        valid.find { |member| noun_stem(member) == target } || noun
      end
      private_class_method :canonical_noun

      def noun_stem(token)
        stem = token.to_s.downcase.sub(/s\z/, "")
        stem == "vid" ? "video" : stem
      end
      private_class_method :noun_stem

      # Render a specific noun page.
      def render_noun_page(verb, noun)
        data = Pito::Copy.subtree("pito.chat_help.#{verb}.#{noun}")
        return nil unless data

        usage    = (data[:usage] || data["usage"]).to_s
        sections = data[:sections] || data["sections"]
        return nil unless sections.is_a?(Hash)

        groups = build_groups(sections)
        return nil if groups.empty?

        body = Pito::MessageBuilder::ManPage.render(usage:, groups:)
        { "html" => true, "body" => body }
      end
      private_class_method :render_noun_page

      # Render a verb-level page.
      # Single-noun verb: delegates straight to the one noun page.
      # Multi-noun verb: usage line + one row per noun form + Options: --help.
      def render_verb_page(verb, nouns)
        if nouns.size == 1
          render_noun_page(verb, nouns.first)
        else
          render_multi_noun_verb_page(verb, nouns)
        end
      end
      private_class_method :render_verb_page

      # Build a verb-level man page listing noun form usages.
      def render_multi_noun_verb_page(verb, nouns)
        verb_usage = Pito::Copy.render_soft("pito.chat_help.#{verb}.usage")
        return nil if verb_usage.blank?

        # Collect per-noun usage lines.
        noun_rows = nouns.filter_map do |n|
          data = Pito::Copy.subtree("pito.chat_help.#{verb}.#{n}")
          next unless data

          usage = (data[:usage] || data["usage"]).to_s
          next if usage.blank?

          display = NOUN_DISPLAY.dig(verb, n) || n
          [ "#{verb} #{display}", usage ]
        end

        return nil if noun_rows.empty?

        groups = [
          [ "Forms", noun_rows ],
          [ "Options", [ [ "--help", "Print this help message" ] ] ]
        ]

        body = Pito::MessageBuilder::ManPage.render(usage: verb_usage, groups:)
        { "html" => true, "body" => body }
      end
      private_class_method :render_multi_noun_verb_page

      # Build the bare `list --help` noun-index page.
      # Lists all three noun forms (games / videos / channels) with their usage lines,
      # followed by an Options group with --help.  Mirrors render_multi_noun_verb_page.
      def render_list_index
        usage = Pito::Copy.render_soft("pito.chat_help.list.usage")
        return nil if usage.blank?

        games_usage    = Pito::Copy.render("pito.copy.list.games_help.usage")
        videos_usage   = Pito::Copy.render("pito.copy.list.videos_help.usage")

        noun_rows = [
          [ "list games",    games_usage ],
          [ "list vids",     videos_usage ],
          [ "list channels", "list channels" ]
        ]

        groups = [
          [ "Forms", noun_rows ],
          [ "Options", [ [ "--help", "Print this help message" ] ] ]
        ]

        body = Pito::MessageBuilder::ManPage.render(usage:, groups:)
        { "html" => true, "body" => body }
      end
      private_class_method :render_list_index

      # Usage-only page for a verb that has a `pito.chat_help.<verb>.usage` line but
      # no noun sub-pages (a query verb like `search`): the usage line + an Options
      # group with `--help`. nil when the verb has no help copy at all (truly
      # unknown verb).
      def render_usage_only(verb)
        usage = Pito::Copy.render_soft("pito.chat_help.#{verb}.usage")
        return nil if usage.blank?

        groups = [ [ "Options", [ [ "--help", "Print this help message" ] ] ] ]
        body   = Pito::MessageBuilder::ManPage.render(usage:, groups:)
        { "html" => true, "body" => body }
      end
      private_class_method :render_usage_only

      # Convert I18n sections hash into ManPage groups array.
      def build_groups(sections)
        sections.filter_map do |title, rows|
          next unless rows.is_a?(Hash)

          [ title.to_s, rows.map { |tok, desc| [ tok.to_s, desc.to_s ] } ]
        end
      end
      private_class_method :build_groups
    end
  end
end
