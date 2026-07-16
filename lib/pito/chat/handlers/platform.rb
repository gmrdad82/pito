# frozen_string_literal: true

# Handler for the `platform` chat tool — ADD or REMOVE a game's platform from
# free text, normalising spelling variants to the right logo family. Some IGDB
# games import with NO platform (e.g. Tekken 7); this tool lets the operator
# curate the list.
#
# Subcommands (mirrors `price set/unset`):
#   * `platform set <id> <name>`   → ADD <name> (de-duped)
#   * `platform unset <id> <name>` → REMOVE that specific <name>
#   * `platform <id> <name>`       → ADD (bare form, back-compat; default = set)
#
# Three contexts, one handler (routed via ToolDelegator for the replies):
#   * free chat:           `platform [set|unset] <game-id> ps5`
#   * reply to list games: `#<handle> platform [set|unset] <game-id> ps5`
#   * reply to show game:   `#<handle> platform [set|unset] ps5` (game from the card)
#
# Resolution is id-only (id_only_resolution!): an optional leading set/unset token
# is peeled first, then the leading token of the trailing text is the game ref
# (free-chat / list reply); in a detail reply the game comes from the card payload
# and the WHOLE remaining text is the platform name. The name is normalised via
# Pito::Games::PlatformInput and appended to / removed from `game.platforms`.
module Pito
  module Chat
    module Handlers
      class Platform < Pito::Chat::Handler
        self.tool = :platform
        self.description_key = "pito.chat.platform.descriptions.platform"
        id_only_resolution!

        NOUN_FILLERS = %w[game games].freeze
        SUBCOMMANDS  = %w[set unset].freeze

        def call
          # The typed setter moved to the consolidated `update` tool; reply
          # forms (`#g3 platform ps5`, list-scoped) still delegate here through
          # the follow-up pipeline and are unchanged.
          return moved unless follow_up?

          game, name = resolve_game_and_name
          return needs_ref if game == :needs_ref
          return game_not_found if game.nil?
          return missing_name if name.blank?

          @subcommand == :unset ? unset_platform(game, name) : set_platform(game, name)
        end

        private

        def moved
          Pito::Chat::Result::Error.new(
            message_key:  "pito.chat.update.moved",
            message_args: { example: "update game platform 12 ps5" }
          )
        end

        # ── Mutation ────────────────────────────────────────────────────────────

        def set_platform(game, name)
          normalized = Pito::Games::PlatformInput.normalize(name)
          return missing_name if normalized.blank?

          unless game.platforms.include?(normalized)
            game.update!(platforms: game.platforms + [ normalized ])
            GameEmbedIndexJob.perform_later(game.id)
          end

          platform_result(game, normalized, removed: false)
        end

        def unset_platform(game, name)
          normalized = Pito::Games::PlatformInput.normalize(name)
          return missing_name if normalized.blank?

          if game.platforms.include?(normalized)
            game.update!(platforms: game.platforms - [ normalized ])
            GameEmbedIndexJob.perform_later(game.id)
          end

          platform_result(game, normalized, removed: true)
        end

        def platform_result(game, normalized, removed:)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Game::PlatformSet.call(game, platform: normalized, removed:) }
          ])
        end

        # ── Resolution: optional subcommand + game + trailing platform name ──────

        # @return [[::Game | :needs_ref | nil, String]] the resolved game (or a
        #   sentinel) and the trailing platform name. Sets @subcommand as a side
        #   effect (peeled from the trailing text; defaults to :set).
        def resolve_game_and_name
          return resolve_from_follow_up if follow_up?

          resolve_from_free_chat
        end

        def resolve_from_follow_up
          payload = follow_up.source_event.payload.with_indifferent_access
          rest    = peel_subcommand(follow_up.rest.to_s)

          if payload[:game_id].present?
            # Detail reply — game from the card; the whole rest is the platform name.
            @error_ref = payload[:game_id].to_s
            [ ::Game.find_by(id: payload[:game_id]), rest.strip ]
          else
            # List reply — leading id ref, then the platform name, scoped to the list.
            resolve_in_list(payload, rest)
          end
        end

        def resolve_in_list(payload, rest)
          ref, name = split_ref_and_name(strip_noun(rest, NOUN_FILLERS))
          @error_ref = ref
          return [ :needs_ref, name ] if ref.blank?

          game = find_by_ref(::Game, ref)
          return [ nil, name ] if game.nil?

          ids = list_row_ids(payload)
          game = nil unless ids.empty? || ids.include?(game.id)
          [ game, name ]
        end

        def resolve_from_free_chat
          rest = message.raw.to_s.strip.sub(/\A\S+\s*/, "")
          rest = peel_subcommand(rest)
          ref, name = split_ref_and_name(strip_noun(rest, NOUN_FILLERS))
          @error_ref = ref
          return [ :needs_ref, name ] if ref.blank?

          [ find_by_ref(::Game, ref), name ]
        end

        # Peel an optional leading set/unset subcommand, storing it in @subcommand
        # (default :set — bare `platform <id> <name>` still ADDS). Returns the
        # remaining text (the id + name, or just the name in a detail reply).
        def peel_subcommand(text)
          first, rest = text.to_s.strip.split(/\s+/, 2)
          if SUBCOMMANDS.include?(first&.downcase)
            @subcommand = first.downcase.to_sym
            rest.to_s.strip
          else
            @subcommand = :set
            text.to_s.strip
          end
        end

        # First whitespace-delimited token is the game ref; the remainder is the
        # free-text platform name.
        def split_ref_and_name(text)
          stripped = text.to_s.strip
          return [ nil, "" ] if stripped.empty?

          ref, name = stripped.split(/\s+/, 2)
          [ ref, name.to_s.strip ]
        end

        # ── Errors ──────────────────────────────────────────────────────────────

        def needs_ref
          Pito::Chat::Result::Error.new(message_key: "pito.chat.platform.needs_ref", message_args: {})
        end

        def missing_name
          Pito::Chat::Result::Error.new(message_key: "pito.chat.platform.missing_name", message_args: {})
        end

        def game_not_found
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.games.not_found", ref: @error_ref.to_s) }
          ])
        end
      end
    end
  end
end
