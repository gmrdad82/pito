# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Help
      # Builder for the chat `help` verb — a simple, always-visible system message
      # listing every available chat command grouped by category.
      #
      # == Output shape
      #
      # Returns a Hash with:
      #   body  — raw HTML fragment (html: true); yellow-bold group headings each
      #           followed by a two-column .pito-data-grid[data-cols="2"] listing
      #           the verb and a hint pointing to --help.
      #   html  — true (so the body renders instantly without typewriter)
      #
      # The `sections` and `table_rows` keys are intentionally absent so the full
      # content is always visible (sections are hidden behind the ctrl+| expand
      # toggle; table_rows would limit output to a single kv section).
      #
      # == Grouping
      #
      # VERB_GROUPS is the authoritative ordered map of group → verbs.
      # Each verb appears in exactly one group; the `help` verb itself is not
      # listed (it IS the page the user is reading).
      VERB_GROUPS = {
        # platform (platform set/unset) and price (price set/unset) manage game
        # metadata and belong alongside the other game commands.  shinies shows
        # the thumbnail breakdown and is applicable to game, vid, and channel.
        # All three were dispatched with chat_help copy but missing from this
        # listing (found during a help-sync guard audit).
        # Segment verbs are grouped by the entity their card is ABOUT:
        # similar/game → games, videos → videos, games/channels → channels,
        # at-a-glance/breakdowns → analytics. `linked` is the
        # relationship verb — grouped with link/unlink beside the game
        # commands. (linked-game → game, linked-videos folded into
        # videos, games = the channel games grid.)
        "pito.copy.help.games_group_title"     => %w[list search show import update delete reindex link unlink linked footage price platform shinies similar game],
        "pito.copy.help.videos_group_title"    => %w[publish unlist schedule videos],
        "pito.copy.help.channels_group_title"  => %w[sync channels games],
        # analyze spans channel/vid/game — its own group (was missing from the
        # main help entirely; found during a help audit).
        "pito.copy.help.analytics_group_title" => %w[analyze at-a-glance breakdowns],
        # The AI assistant spans the whole library — its own group.
        "pito.copy.help.ai_group_title"        => %w[@ai]
      }.freeze

      module Commands
        class << self
          # @return [Hash] system payload with html body (always visible)
          def call
            {
              "body" => full_body_html,
              "html" => true
            }
          end

          private

          # Concatenates one section per group: a title div + a data-grid of verbs.
          def full_body_html
            hint = ERB::Util.html_escape(Pito::Copy.render("pito.copy.help.command_hint"))

            VERB_GROUPS.each_with_index.map do |(title_key, verbs), index|
              title = ERB::Util.html_escape(Pito::Copy.render(title_key))

              # Omit `mt-3` on the first group so it sits flush at the top,
              # matching the original single-group spacing.
              margin = index.zero? ? "" : " mt-3"
              title_div = %(<div class="text-purple font-bold#{margin}">#{title}</div>)

              # Alphabetical within the group — the arrays
              # above stay membership-only; display order is derived.
              rows = verbs.sort.map do |verb|
                verb_escaped = ERB::Util.html_escape(verb)
                %(<span class="text-fg">#{verb_escaped}</span>) \
                  "<span class=\"text-fg-dim\">#{hint}</span>"
              end.join

              %(#{title_div}<div class="pito-data-grid" data-cols="2">#{rows}</div>)
            end.join
          end
        end
      end
    end
  end
end
