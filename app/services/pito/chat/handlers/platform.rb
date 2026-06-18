# frozen_string_literal: true

# Handler for the `platform <game> <name>` chat verb — SETS (appends) a game's
# platform from free text, normalising spelling variants to the right logo
# family. Some IGDB games import with NO platform (e.g. Tekken 7); this verb
# lets the operator add one.
#
# Three contexts, one handler (routed via VerbDelegator for the replies):
#   * free chat:           `platform <game-id> ps5`
#   * reply to list games: `#<handle> platform <game-id> ps5`
#   * reply to show game:   `#<handle> platform ps5` (game from the card context)
#
# Resolution is id-only (id_only_resolution!): the leading token of the trailing
# text is the game ref (free-chat / list reply); in a detail reply the game comes
# from the card payload and the WHOLE trailing text is the platform name. The
# platform name is normalised via Pito::Game::PlatformInput and appended to
# `game.platforms` (de-duped). Unknown platforms are still stored (no logo).
module Pito
  module Chat
    module Handlers
      class Platform < Pito::Chat::Handler
        self.verb = :platform
        self.description_key = "pito.chat.platform.descriptions.platform"
        id_only_resolution!

        NOUN_FILLERS = %w[game games].freeze

        def call
          game, name = resolve_game_and_name
          return needs_ref if game == :needs_ref
          return game_not_found if game.nil?
          return missing_name if name.blank?

          set_platform(game, name)
        end

        private

        # ── Mutation ────────────────────────────────────────────────────────────

        def set_platform(game, name)
          normalized = Pito::Game::PlatformInput.normalize(name)
          return missing_name if normalized.blank?

          unless game.platforms.include?(normalized)
            game.update!(platforms: game.platforms + [ normalized ])
          end

          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Game::PlatformSet.call(game, platform: normalized) }
          ])
        end

        # ── Resolution: game + trailing platform name ───────────────────────────

        # @return [[::Game | :needs_ref | nil, String]] the resolved game (or a
        #   sentinel) and the trailing platform name.
        def resolve_game_and_name
          return resolve_from_follow_up if follow_up?

          resolve_from_free_chat
        end

        def resolve_from_follow_up
          payload = follow_up.source_event.payload.with_indifferent_access

          if payload[:game_id].present?
            # Detail reply — game from the card; the whole rest is the platform name.
            @error_ref = payload[:game_id].to_s
            [ ::Game.find_by(id: payload[:game_id]), follow_up.rest.to_s.strip ]
          else
            # List reply — leading id ref, then the platform name, scoped to the list.
            resolve_in_list(payload)
          end
        end

        def resolve_in_list(payload)
          ref, name = split_ref_and_name(strip_noun(follow_up.rest, NOUN_FILLERS))
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
          ref, name = split_ref_and_name(strip_noun(rest, NOUN_FILLERS))
          @error_ref = ref
          return [ :needs_ref, name ] if ref.blank?

          [ find_by_ref(::Game, ref), name ]
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
