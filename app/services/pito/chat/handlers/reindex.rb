# frozen_string_literal: true

# Handler for the `reindex game <id|title>` / `reindex video <id|title>` chat verb.
#
# Resolves a single game or video by **ID** (`#123` or `123`) or title (ILIKE)
# and emits a Voyage re-embed confirmation event. The actual re-index happens in
# `Pito::Confirmation::Executor` on `#<handle> confirm`.
# Unknown reference → witty not-found; no reference → usage hint.
module Pito
  module Chat
    module Handlers
      class Reindex < Pito::Chat::Handler
        self.verb = :reindex
        self.description_key = "pito.chat.reindex.descriptions.reindex"

        GAME_NOUN_FILLERS  = %w[game games].freeze
        VIDEO_NOUN_FILLERS = %w[video videos].freeze

        def call
          if video_target?(VIDEO_NOUN_FILLERS)
            handle_video
          else
            handle_game
          end
        end

        private

        # ── Video branch ────────────────────────────────────────────────────────

        def handle_video
          video = resolve_target(::Video, id_key: :video_id, noun_fillers: VIDEO_NOUN_FILLERS)
          return needs_ref if video == :needs_ref
          return video_not_found(target_ref(VIDEO_NOUN_FILLERS, id_key: :video_id)) if video.nil?

          payload = Pito::MessageBuilder::Video::ReindexConfirmation.call(video, conversation:)
          Pito::Chat::Result::Ok.new(events: [ { kind: :confirmation, payload: payload } ])
        end

        def video_not_found(ref)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.videos.not_found", ref: ref) }
          ])
        end

        # ── Game branch ─────────────────────────────────────────────────────────

        def handle_game
          game = resolve_target(::Game, id_key: :game_id, noun_fillers: GAME_NOUN_FILLERS)
          return needs_ref if game == :needs_ref
          return game_not_found(target_ref(GAME_NOUN_FILLERS, id_key: :game_id)) if game.nil?

          payload = Pito::MessageBuilder::Game::ReindexConfirmation.call(game, conversation:)
          Pito::Chat::Result::Ok.new(events: [ { kind: :confirmation, payload: payload } ])
        end

        def game_not_found(ref)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.games.not_found", ref: ref) }
          ])
        end

        # ── Shared helpers ──────────────────────────────────────────────────────

        def needs_ref
          Pito::Chat::Result::Error.new(message_key: "pito.chat.reindex.needs_ref", message_args: {})
        end
      end
    end
  end
end
