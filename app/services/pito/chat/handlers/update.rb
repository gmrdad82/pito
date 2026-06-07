# frozen_string_literal: true

# Handler for `update game ownership <id> <platforms…>` chat verb.
#
# Parses the body for an ownership sub-command: drops noun fillers
# (`game`/`games`) and the literal word `ownership`, then expects:
#   - First token group = the game **id** (`#N` or `N`). Title refs are
#     rejected with a plain usage hint — IDs are required for mutation.
#   - Remaining tokens = the platform list (tolerant: split on `,`, `.`,
#     `*`, whitespace; synonym expansion; dedup).
#
# The ownership set is **replaced exactly** to the parsed list:
#   - Missing tokens → create GamePlatformOwnership records.
#   - Extra tokens → destroy obsolete GamePlatformOwnership records.
#
# Empty / unrecognisable platform list → usage hint (no silent wipe).
module Pito
  module Chat
    module Handlers
      class Update < Pito::Chat::Handler
        self.verb = :update
        self.description_key = "pito.chat.update.descriptions.update"

        NOUN_FILLERS    = %w[game games].freeze
        SUBCOMMAND_WORD = "ownership"

        # Maps user input synonyms to canonical PLATFORM_TOKENS.
        PLATFORM_SYNONYMS = {
          "ps"          => "ps",
          "ps4"         => "ps",
          "ps5"         => "ps",
          "playstation" => "ps",
          "sony"        => "ps",
          "switch"      => "switch",
          "switch1"     => "switch",
          "switch2"     => "switch",
          "nintendo"    => "switch",
          "steam"       => "steam",
          "gog"         => "steam",
          "epic"        => "steam",
          "pc"          => "steam"
        }.freeze

        def call
          words = message.body_tokens.map(&:value)

          # Drop noun fillers and the literal subcommand word.
          words = words.reject { |w| NOUN_FILLERS.include?(w.downcase) }
          words = words.reject { |w| w.downcase == SUBCOMMAND_WORD }

          return needs_id if words.empty?

          # First token must be a numeric id (`#N` or `N`).
          id_token = words.first
          id = id_token.to_s.delete_prefix("#")
          return needs_id unless id.match?(/\A\d+\z/)

          game = ::Game.find_by(id: id)
          return not_found(id_token) unless game

          # Remaining tokens = platform list.
          platform_words = words.drop(1)
          tokens = parse_platforms(platform_words)

          return needs_platforms if tokens.empty?

          apply_ownership(game, tokens)

          display = tokens.map { |t| I18n.t("pito.game.detail.platform_label.#{t}") }.join(", ")
          text    = Pito::Copy.render("pito.copy.games.ownership_set", { title: game.title, platforms: display })

          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: Pito::MessageBuilder::Text.call(text) } ])
        end

        private

        # Tolerant parser: join all words, split on any combination of
        # commas, dots, asterisks, and whitespace, then map synonyms.
        def parse_platforms(words)
          raw = words.join(" ")
          raw.split(/[,.*\s]+/)
             .map { |tok| PLATFORM_SYNONYMS[tok.downcase] }
             .compact
             .uniq
        end

        def apply_ownership(game, wanted_tokens)
          existing = game.game_platform_ownerships.pluck(:platform_token)
          to_add   = wanted_tokens - existing
          to_remove = existing - wanted_tokens

          to_add.each    { |tok| game.game_platform_ownerships.create!(platform_token: tok) }
          to_remove.each { |tok| game.game_platform_ownerships.where(platform_token: tok).destroy_all }
        end

        def needs_id
          Pito::Chat::Result::Error.new(
            message_key:  "pito.chat.update.needs_id",
            message_args: {}
          )
        end

        def needs_platforms
          Pito::Chat::Result::Error.new(
            message_key:  "pito.chat.update.needs_platforms",
            message_args: {}
          )
        end

        def not_found(ref)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.games.not_found", ref: ref) }
          ])
        end
      end
    end
  end
end
