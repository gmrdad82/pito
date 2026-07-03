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

      # Known noun tokens for each verb.  Determines rendering strategy and
      # the order in which nouns are listed on the verb-level page.
      VERB_NOUNS = {
        show:     %i[game video channel],
        delete:   %i[game video],
        reindex:  %i[game video],
        footage:  %i[update snippet],
        price:    %i[set unset],
        link:     %i[game video],
        unlink:   %i[game video],
        publish:  %i[video],
        unlist:   %i[video],
        schedule: %i[video],
        platform: %i[game],
        # `import` is canonically the IGDB game import; `import videos` is a
        # de-emphasized alias of `sync videos`, listed last as an alias note.
        import:   %i[game videos],
        sync:     %i[videos channels],
        shinies:  %i[channel video game],
        analyze:  %i[channel vid game],
        # Segment verbs (D20/D21): the noun forms each accepts (its parent
        # segment's entity availability). Single-noun verbs render that one page.
        "at-a-glance": %i[channel vid game],
        videos:        %i[channel],
        "linked-game": %i[vid],
        similar:       %i[game],
        "linked-videos": %i[game],
        channels:      %i[game],
        breakdowns:    %i[channel vid game],
        # The `linked` two-word forms (E14) — two noun pages: `linked game` (a
        # vid's game) and `linked vids` (a game's vids). Multi-noun verb.
        linked:        %i[game vids]
      }.freeze

      # Canonical display token per (verb, noun). The verb-level page labels and
      # the list index lead with the short canonical noun (`vid`/`vids`) for the
      # verbs whose handlers accept it; the I18n copy KEYS stay `video`/`videos`.
      # `video`/`videos` remain valid aliases at the parser.
      NOUN_DISPLAY = {
        show:   { video: "vid" },
        import: { videos: "vids" },
        sync:   { videos: "vids" }
      }.freeze

      # @param verb [Symbol]
      # @param noun [Symbol, nil]
      # @return [Hash, nil]
      def call(verb, noun: nil)
        if verb == :list
          case noun
          when :games    then return Pito::MessageBuilder::Game::ListHelp.call
          when :videos   then return Pito::MessageBuilder::Video::ListHelp.call
          when :channels then return Pito::MessageBuilder::Channel::ListHelp.call
          when nil       then return render_list_index
          end
        end

        nouns = VERB_NOUNS[verb]
        return nil unless nouns # unknown verb

        if noun
          render_noun_page(verb, noun)
        else
          render_verb_page(verb, nouns)
        end
      end

      # ── Private ──────────────────────────────────────────────────────────────

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
