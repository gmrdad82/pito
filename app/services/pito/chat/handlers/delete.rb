# frozen_string_literal: true

# Handler for the `delete game <id|title>` / `rm game <id|title>` and
# `delete video <id|title>` / `rm video <id|title>` chat verbs.
#
# Resolves a single game or video by **ID** (`#123`/`123`) or title (ILIKE)
# and emits a confirmation event. The destroy happens in
# `Pito::Confirmation::Executor` on `#<handle> confirm`.
# The title is carried in the payload so the outcome text survives the
# row's deletion. Unknown reference → witty not-found; no reference → usage hint.
module Pito
  module Chat
    module Handlers
      class Delete < Pito::Chat::Handler
        self.verb = :delete
        self.description_key = "pito.chat.delete.descriptions.delete"

        GAME_NOUN_FILLERS  = %w[game games].freeze
        VIDEO_NOUN_FILLERS = %w[video videos].freeze

        def call
          if video_noun_present?
            handle_video
          else
            handle_game
          end
        end

        private

        # ── Video branch ────────────────────────────────────────────────────────

        def video_noun_present?
          message.body_tokens.any? { |t| VIDEO_NOUN_FILLERS.include?(t.value.to_s.downcase) }
        end

        def handle_video
          ref = extract_ref(VIDEO_NOUN_FILLERS)
          return needs_ref if ref.blank?

          video = resolve_video(ref)
          return video_not_found(ref) unless video

          video_confirmation_event(video)
        end

        def resolve_video(ref)
          id = ref.sub(/\A#\s*/, "")
          return ::Video.find_by(id: id) if id.match?(/\A\d+\z/)

          ::Video.find_by("title ILIKE ?", ref)
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
          ref = extract_ref(GAME_NOUN_FILLERS)
          return needs_ref if ref.blank?

          game = resolve_game(ref)
          return game_not_found(ref) unless game

          game_confirmation_event(game)
        end

        # Strip a leading `#` + whitespace — the lexer splits `#9` into `# 9`.
        def resolve_game(ref)
          id = ref.sub(/\A#\s*/, "")
          return ::Game.find_by(id: id) if id.match?(/\A\d+\z/)

          ::Game.find_by("title ILIKE ?", ref)
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

        def extract_ref(noun_fillers)
          message.body_tokens
                 .map(&:value)
                 .reject { |w| noun_fillers.include?(w.to_s.downcase) }
                 .join(" ")
                 .strip
        end

        def needs_ref
          Pito::Chat::Result::Error.new(message_key: "pito.chat.delete.needs_ref", message_args: {})
        end
      end
    end
  end
end
