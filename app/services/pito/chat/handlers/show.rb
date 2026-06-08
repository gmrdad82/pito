# frozen_string_literal: true

# Handler for the `show game <id|title>` / `show video <id|title>` chat verb.
#
# Resolves a single game or video by **ID** (`#123` or `123`) or title (ILIKE)
# and emits the appropriate detail message (follow-up-able).
# Unknown reference → witty not-found via `Pito::Copy`. No reference → a usage
# hint (the no-arg picker fast-path is wired in `ChatController`, T10.10).
module Pito
  module Chat
    module Handlers
      class Show < Pito::Chat::Handler
        self.verb = :show
        self.description_key = "pito.chat.show.descriptions.show"

        # `game`/`games` are noun fillers the user types but that carry no value
        # when resolving a game.
        GAME_NOUN_FILLERS  = %w[game games].freeze

        # `video`/`videos` are noun fillers for the video branch.
        VIDEO_NOUN_FILLERS = %w[video videos].freeze

        def call
          if video_noun_present?
            handle_video
          else
            handle_game
          end
        end

        private

        # ── Video branch ───────────────────────────────────────────────────────

        def video_noun_present?
          message.body_tokens.any? { |t| VIDEO_NOUN_FILLERS.include?(t.value.to_s.downcase) }
        end

        def handle_video
          video = resolve_target(::Video, id_key: :video_id, noun_fillers: VIDEO_NOUN_FILLERS)
          return needs_ref if video == :needs_ref
          return video_not_found(target_ref(VIDEO_NOUN_FILLERS, id_key: :video_id)) if video.nil?

          # Standard detail card (follow-up-able) + an Enhanced message. The video
          # Enhanced is a Pito::Copy intro placeholder for now (Analytics later).
          # Identical events whether typed in free chat or via a `#<handle>` reply.
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system,   payload: Pito::MessageBuilder::Video::Detail.call(video, conversation:) },
            { kind: :enhanced, payload: Pito::MessageBuilder::Video::Enhanced.call(video) }
          ])
        end

        def video_not_found(ref)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.videos.not_found", ref: ref) }
          ])
        end

        # ── Game branch ────────────────────────────────────────────────────────

        def handle_game
          game = resolve_target(::Game, id_key: :game_id, noun_fillers: GAME_NOUN_FILLERS)
          return needs_ref if game == :needs_ref
          return game_not_found(target_ref(GAME_NOUN_FILLERS, id_key: :game_id)) if game.nil?

          # Mirror an import: the Standard detail message (follow-up-able) plus the
          # Enhanced recommendations message (pito chrome, not follow-up-able).
          # Identical events whether typed in free chat or via a `#<handle>` reply.
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system,   payload: Pito::MessageBuilder::Game::Detail.call(game, conversation:) },
            { kind: :enhanced, payload: Pito::MessageBuilder::Game::Enhanced.call(game) }
          ])
        end

        def game_not_found(ref)
          Pito::Chat::Result::Ok.new(events: [
            { kind: :system, payload: Pito::MessageBuilder::Text.call("pito.copy.games.not_found", ref: ref) }
          ])
        end

        # ── Shared helpers ─────────────────────────────────────────────────────

        def needs_ref
          Pito::Chat::Result::Error.new(message_key: "pito.chat.show.needs_ref", message_args: {})
        end
      end
    end
  end
end
