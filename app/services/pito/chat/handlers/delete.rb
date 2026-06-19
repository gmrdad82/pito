# frozen_string_literal: true

# Handler for the `delete game <id>` / `rm game <id>` and
# `delete video <id>` / `rm video <id>` chat verbs.
#
# Resolves a single game or video by **ID only** (`#123`/`123`) — title
# lookup is intentionally disabled (id_only_resolution!). Emits a
# confirmation event; the destroy happens in
# `Pito::Confirmation::Executor` on `#<handle> confirm`.
# The title is carried in the payload so the outcome text survives the
# row's deletion. Unknown reference → witty not-found; no reference → usage hint.
module Pito
  module Chat
    module Handlers
      class Delete < Pito::Chat::Handler
        self.verb = :delete
        self.description_key = "pito.chat.delete.descriptions.delete"
        id_only_resolution!

        GAME_NOUN_FILLERS  = %w[game games].freeze
        VIDEO_NOUN_FILLERS = %w[vid vids video videos].freeze

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

          video_confirmation_event(video)
        end

        def video_confirmation_event(video)
          payload = Pito::MessageBuilder::Video::DeleteConfirmation.call(video, conversation:)
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

          game_confirmation_event(game)
        end

        def game_confirmation_event(game)
          payload = Pito::MessageBuilder::Game::DeleteConfirmation.call(game, conversation:)
          Pito::Chat::Result::Ok.new(events: [ { kind: :confirmation, payload: payload } ])
        end

        def game_not_found(ref)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.games.not_found", ref: ref) }
          ])
        end

        # ── Shared helpers ──────────────────────────────────────────────────────

        def needs_ref
          Pito::Chat::Result::Error.new(message_key: "pito.chat.delete.needs_ref", message_args: {})
        end
      end
    end
  end
end
